-- ============================================================================
-- Farm Equipment Maintenance Scheduling DB (PostgreSQL 15 / Supabase)
-- Final schema with equipment_component, automation triggers, and due_soon
-- ============================================================================

BEGIN;

-- =========================
-- 1) Organization (multi-tenant)
-- =========================
CREATE TABLE IF NOT EXISTS company (
  id          serial PRIMARY KEY,
  name        varchar(100) NOT NULL,
  created_at  timestamp NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS farm (
  id          serial PRIMARY KEY,
  name        varchar(100) NOT NULL,
  location    text,
  company_id  int NOT NULL REFERENCES company(id),
  created_at  timestamp NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_farm_company ON farm(company_id);

-- =========================
-- 2) Equipment & Models
-- =========================
CREATE TABLE IF NOT EXISTS equipment_model (
  id              serial PRIMARY KEY,
  manufacturer    varchar(100) NOT NULL,
  model_name      varchar(100) NOT NULL,
  equipment_type  varchar(50)  NOT NULL, -- e.g. Tractor, Combine, Truck
  description     text,
  UNIQUE (manufacturer, model_name)
);

CREATE TABLE IF NOT EXISTS equipment (
  id                 serial PRIMARY KEY,
  display_name       varchar(100) NOT NULL,   -- e.g. "Tractor #5"
  serial_number      varchar(100),
  equipment_model_id int NOT NULL REFERENCES equipment_model(id),
  farm_id            int NOT NULL REFERENCES farm(id),
  acquired_on        date,
  active             boolean NOT NULL DEFAULT true,
  engine_hours       numeric(10,2),  -- nullable if N/A
  odometer_km        numeric(10,2),  -- nullable if N/A
  created_at         timestamp NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_equipment_farm  ON equipment(farm_id);
CREATE INDEX IF NOT EXISTS idx_equipment_model ON equipment(equipment_model_id);

-- =========================
-- 3) Parts & Installed Equipment Components (state + history)
-- =========================
CREATE TABLE IF NOT EXISTS part_type (
  id           serial PRIMARY KEY,
  name         varchar(100) NOT NULL,  -- e.g. "Oil Filter Type B"
  category     varchar(100) NOT NULL,  -- e.g. "Oil Filter", "Tire"
  manufacturer varchar(100),
  model_code   varchar(100),
  description  text
);

CREATE TABLE IF NOT EXISTS equipment_component (
  id             bigserial PRIMARY KEY,
  equipment_id   int NOT NULL REFERENCES equipment(id),
  part_type_id   int NOT NULL REFERENCES part_type(id),
  slot_label     varchar(50),         -- e.g. "FRONT-LEFT", "FILTER_OIL"
  serial_number  varchar(100),
  installed_at   timestamp NOT NULL DEFAULT now(),
  removed_at     timestamp,           -- NULL = still active
  notes          text
);
CREATE INDEX IF NOT EXISTS idx_ec_equipment      ON equipment_component(equipment_id);
CREATE INDEX IF NOT EXISTS idx_ec_part_type      ON equipment_component(part_type_id);
CREATE INDEX IF NOT EXISTS idx_ec_equipment_slot ON equipment_component(equipment_id, slot_label);
-- Fast lookup of "current" components
CREATE INDEX IF NOT EXISTS idx_ec_active_partial ON equipment_component(equipment_id, slot_label)
  WHERE removed_at IS NULL;

-- Optional trigger: ensure only one active component per (equipment, slot_label)
CREATE OR REPLACE FUNCTION fn_close_previous_equipment_component()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.slot_label IS NOT NULL THEN
    UPDATE equipment_component
       SET removed_at = COALESCE(NEW.installed_at, now())
     WHERE equipment_id = NEW.equipment_id
       AND slot_label   = NEW.slot_label
       AND removed_at IS NULL;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_close_previous_component ON equipment_component;
CREATE TRIGGER trg_close_previous_component
BEFORE INSERT ON equipment_component
FOR EACH ROW
EXECUTE FUNCTION fn_close_previous_equipment_component();

-- =========================
-- 4) Maintenance Catalog & Rules
-- =========================
CREATE TABLE IF NOT EXISTS maintenance_task (
  id                   serial PRIMARY KEY,
  name                 varchar(100) NOT NULL,  -- e.g. "Change Engine Oil Filter"
  description          text,
  default_part_type_id int REFERENCES part_type(id)
);
CREATE INDEX IF NOT EXISTS idx_task_name ON maintenance_task(name);

CREATE TABLE IF NOT EXISTS maintenance_rule (
  id                 serial PRIMARY KEY,
  task_id            int NOT NULL REFERENCES maintenance_task(id),
  -- Scope (priority: equipment > model > part-type global)
  equipment_model_id int REFERENCES equipment_model(id),
  equipment_id       int REFERENCES equipment(id),
  part_type_id       int REFERENCES part_type(id),
  -- Frequency definition
  frequency_type     varchar(20) NOT NULL,     -- HOURS|KM|DAYS|WEEKS|MONTHS|YEARS|CRON|RRULE
  value_numeric      numeric(10,2),            -- numeric value when applicable
  interval_text      varchar(50),              -- optional textual interval (redundant but handy)
  pattern            varchar(200),             -- CRON/RRULE text
  condition_note     text,                     -- "whichever comes first", etc.
  active             boolean NOT NULL DEFAULT true,
  is_default         boolean NOT NULL DEFAULT false,
  CHECK (
    equipment_model_id IS NOT NULL OR
    equipment_id       IS NOT NULL OR
    part_type_id       IS NOT NULL
  )
);
-- Helpful indexes (partial indexes useful in Postgres; these are full for simplicity)
CREATE INDEX IF NOT EXISTS idx_rule_task_model ON maintenance_rule(task_id, equipment_model_id);
CREATE INDEX IF NOT EXISTS idx_rule_equipment  ON maintenance_rule(equipment_id);
CREATE INDEX IF NOT EXISTS idx_rule_part_type  ON maintenance_rule(part_type_id);

-- =========================
-- 5) Maintenance Logs (header) & Details (line-items per component)
-- =========================
CREATE TABLE IF NOT EXISTS maintenance_log (
  id                       bigserial PRIMARY KEY,
  equipment_id             int NOT NULL REFERENCES equipment(id),
  task_id                  int NOT NULL REFERENCES maintenance_task(id),
  performed_on             date NOT NULL DEFAULT current_date,
  engine_hours             numeric(10,2),
  odometer_km              numeric(10,2),
  notes                    text,
  equipment_component_id   bigint REFERENCES equipment_component(id), -- optional single-component shortcut
  part_type_id             int REFERENCES part_type(id),              -- optional consumable summary
  performed_by             varchar(100)
);
CREATE INDEX IF NOT EXISTS idx_log_equipment            ON maintenance_log(equipment_id);
CREATE INDEX IF NOT EXISTS idx_log_task                 ON maintenance_log(task_id);
CREATE INDEX IF NOT EXISTS idx_log_date                 ON maintenance_log(performed_on);
CREATE INDEX IF NOT EXISTS idx_log_equipment_component  ON maintenance_log(equipment_component_id);

CREATE TABLE IF NOT EXISTS maintenance_log_detail (
  id                       bigserial PRIMARY KEY,
  maintenance_log_id       bigint NOT NULL REFERENCES maintenance_log(id) ON DELETE CASCADE,
  equipment_component_id   bigint REFERENCES equipment_component(id),
  action                   varchar(20) NOT NULL,   -- REPLACE|REPAIR|INSPECT|CLEAN|...
  old_part_type_id         int REFERENCES part_type(id),
  new_part_type_id         int REFERENCES part_type(id),
  qty_used                 numeric(10,2),
  notes                    text
);
CREATE INDEX IF NOT EXISTS idx_mld_log        ON maintenance_log_detail(maintenance_log_id);
CREATE INDEX IF NOT EXISTS idx_mld_component  ON maintenance_log_detail(equipment_component_id);

-- Optional trigger: when a log targets a single component but no detail is provided,
-- auto-create a minimal detail row to keep header and details in sync.
CREATE OR REPLACE FUNCTION fn_log_autodetail()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.equipment_component_id IS NOT NULL THEN
    INSERT INTO maintenance_log_detail
      (maintenance_log_id, equipment_component_id, action, notes)
    VALUES
      (NEW.id, NEW.equipment_component_id, 'INSPECT', 'Auto-created detail for single-component log');
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_log_autodetail ON maintenance_log;
CREATE TRIGGER trg_log_autodetail
AFTER INSERT ON maintenance_log
FOR EACH ROW
WHEN (NEW.equipment_component_id IS NOT NULL)
EXECUTE FUNCTION fn_log_autodetail();

-- =========================
-- 6) due_soon snapshot (FKs + unique key) and UPSERT refresh function
-- =========================
CREATE TABLE IF NOT EXISTS due_soon (
  id                 bigserial PRIMARY KEY,
  computed_at        timestamptz NOT NULL DEFAULT now(),
  company_id         int REFERENCES company(id) ON DELETE SET NULL,
  farm_id            int REFERENCES farm(id) ON DELETE SET NULL,
  equipment_id       int NOT NULL REFERENCES equipment(id) ON DELETE CASCADE,
  task_id            int NOT NULL REFERENCES maintenance_task(id) ON DELETE CASCADE,
  rule_id            int NOT NULL REFERENCES maintenance_rule(id) ON DELETE CASCADE,
  -- Time-based
  next_due_date      date,
  days_until_due     int,
  -- Usage-based (engine hours)
  next_due_at_hours  numeric(12,2),
  hours_remaining    numeric(12,2),
  -- Usage-based (vehicle kilometers)
  next_due_at_km     numeric(12,2),
  km_remaining       numeric(12,2),
  -- OVERDUE | DUE_SOON | INFO
  severity           text,
  CONSTRAINT uq_due_soon UNIQUE (equipment_id, task_id, rule_id)
);
CREATE INDEX IF NOT EXISTS idx_due_soon_computed_at ON due_soon(computed_at);
CREATE INDEX IF NOT EXISTS idx_due_soon_company     ON due_soon(company_id);
CREATE INDEX IF NOT EXISTS idx_due_soon_farm        ON due_soon(farm_id);
CREATE INDEX IF NOT EXISTS idx_due_soon_equipment   ON due_soon(equipment_id);
CREATE INDEX IF NOT EXISTS idx_due_soon_task        ON due_soon(task_id);
CREATE INDEX IF NOT EXISTS idx_due_soon_rule        ON due_soon(rule_id);
CREATE INDEX IF NOT EXISTS idx_due_soon_severity    ON due_soon(severity);
CREATE INDEX IF NOT EXISTS idx_due_soon_next_date   ON due_soon(next_due_date);

-- Compute and UPSERT due items (OVERDUE or DUE_SOON) into due_soon.
CREATE OR REPLACE FUNCTION refresh_due_soon_upsert(
  p_days_ahead  int     DEFAULT 30,
  p_hours_ahead numeric DEFAULT 25,
  p_km_ahead    numeric DEFAULT 500,
  p_purge       boolean DEFAULT true
)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  CREATE TEMP TABLE due_soon_stage (
    computed_at        timestamptz NOT NULL,
    company_id         int,
    farm_id            int,
    equipment_id       int NOT NULL,
    task_id            int NOT NULL,
    rule_id            int NOT NULL,
    next_due_date      date,
    days_until_due     int,
    next_due_at_hours  numeric(12,2),
    hours_remaining    numeric(12,2),
    next_due_at_km     numeric(12,2),
    km_remaining       numeric(12,2),
    severity           text,
    UNIQUE (equipment_id, task_id, rule_id)
  ) ON COMMIT DROP;

  WITH
  last_log AS (
    SELECT
      ml.equipment_id,
      ml.task_id,
      MAX(ml.performed_on) AS last_date,
      MAX(ml.engine_hours) FILTER (WHERE ml.engine_hours IS NOT NULL) AS last_hours,
      MAX(ml.odometer_km)  FILTER (WHERE ml.odometer_km  IS NOT NULL) AS last_km
    FROM maintenance_log ml
    GROUP BY ml.equipment_id, ml.task_id
  ),
  equipment_rules AS (
    -- precedence 1: equipment-specific
    SELECT e.id AS equipment_id, r.id AS rule_id, r.task_id,
           r.frequency_type, r.value_numeric, r.interval_text, r.pattern, r.condition_note,
           1 AS precedence
    FROM equipment e
    JOIN maintenance_rule r ON r.active AND r.equipment_id = e.id

    UNION ALL
    -- precedence 2: model-level
    SELECT e.id, r.id, r.task_id, r.frequency_type, r.value_numeric, r.interval_text, r.pattern, r.condition_note,
           2 AS precedence
    FROM equipment e
    JOIN maintenance_rule r ON r.active
                            AND r.equipment_id IS NULL
                            AND r.equipment_model_id = e.equipment_model_id

    UNION ALL
    -- precedence 3: part_type-global (must be installed & active)
    SELECT DISTINCT e.id, r.id, r.task_id, r.frequency_type, r.value_numeric, r.interval_text, r.pattern, r.condition_note,
           3 AS precedence
    FROM equipment e
    JOIN maintenance_rule r ON r.active
                            AND r.equipment_id IS NULL
                            AND r.equipment_model_id IS NULL
                            AND r.part_type_id IS NOT NULL
    JOIN equipment_component ec ON ec.equipment_id = e.id
                               AND ec.removed_at IS NULL
                               AND ec.part_type_id = r.part_type_id
  ),
  picked_rules AS (
    -- one rule per (equipment, task, frequency_type) by precedence
    SELECT DISTINCT ON (er.equipment_id, er.task_id, er.frequency_type)
      er.*
    FROM equipment_rules er
    ORDER BY er.equipment_id, er.task_id, er.frequency_type, er.precedence
  ),
  base AS (
    SELECT e.id AS equipment_id, e.farm_id, f.company_id,
           e.created_at::date AS equip_created,
           e.engine_hours, e.odometer_km
    FROM equipment e
    JOIN farm f ON f.id = e.farm_id
  ),
  time_due AS (
    SELECT
      pr.equipment_id, pr.rule_id, pr.task_id,
      CASE pr.frequency_type
        WHEN 'DAYS'   THEN (COALESCE(ll.last_date, b.equip_created) + (pr.value_numeric || ' days')::interval)::date
        WHEN 'WEEKS'  THEN (COALESCE(ll.last_date, b.equip_created) + (pr.value_numeric || ' weeks')::interval)::date
        WHEN 'MONTHS' THEN (COALESCE(ll.last_date, b.equip_created) + (pr.value_numeric || ' months')::interval)::date
        WHEN 'YEARS'  THEN (COALESCE(ll.last_date, b.equip_created) + (pr.value_numeric || ' years')::interval)::date
        ELSE NULL
      END AS next_due_date
    FROM picked_rules pr
    JOIN base b  ON b.equipment_id = pr.equipment_id
    LEFT JOIN last_log ll ON ll.equipment_id = pr.equipment_id
                         AND ll.task_id      = pr.task_id
    WHERE pr.frequency_type IN ('DAYS','WEEKS','MONTHS','YEARS')
  ),
  hours_due AS (
    SELECT
      pr.equipment_id, pr.rule_id, pr.task_id,
      CASE WHEN b.engine_hours IS NULL OR pr.value_numeric IS NULL THEN NULL
           ELSE COALESCE(ll.last_hours, 0) + pr.value_numeric END AS next_due_at_hours,
      CASE WHEN b.engine_hours IS NULL OR pr.value_numeric IS NULL THEN NULL
           ELSE GREATEST((COALESCE(ll.last_hours, 0) + pr.value_numeric) - b.engine_hours, 0) END AS hours_remaining
    FROM picked_rules pr
    JOIN base b  ON b.equipment_id = pr.equipment_id
    LEFT JOIN last_log ll ON ll.equipment_id = pr.equipment_id
                         AND ll.task_id      = pr.task_id
    WHERE pr.frequency_type = 'HOURS'
  ),
  km_due AS (
    SELECT
      pr.equipment_id, pr.rule_id, pr.task_id,
      CASE WHEN b.odometer_km IS NULL OR pr.value_numeric IS NULL THEN NULL
           ELSE COALESCE(ll.last_km, 0) + pr.value_numeric END AS next_due_at_km,
      CASE WHEN b.odometer_km IS NULL OR pr.value_numeric IS NULL THEN NULL
           ELSE GREATEST((COALESCE(ll.last_km, 0) + pr.value_numeric) - b.odometer_km, 0) END AS km_remaining
    FROM picked_rules pr
    JOIN base b  ON b.equipment_id = pr.equipment_id
    LEFT JOIN last_log ll ON ll.equipment_id = pr.equipment_id
                         AND ll.task_id      = pr.task_id
    WHERE pr.frequency_type = 'KM'
  )

  INSERT INTO due_soon_stage (
    computed_at, company_id, farm_id, equipment_id, task_id, rule_id,
    next_due_date, days_until_due,
    next_due_at_hours, hours_remaining,
    next_due_at_km, km_remaining, severity
  )
  -- Time-based
  SELECT
    now(), b.company_id, b.farm_id, td.equipment_id, td.task_id, td.rule_id,
    td.next_due_date,
    CASE WHEN td.next_due_date IS NULL THEN NULL
         ELSE (td.next_due_date - current_date) END::int AS days_until_due,
    NULL::numeric, NULL::numeric,
    NULL::numeric, NULL::numeric,
    CASE
      WHEN td.next_due_date < current_date THEN 'OVERDUE'
      WHEN td.next_due_date <= current_date + (p_days_ahead || ' days')::interval THEN 'DUE_SOON'
      ELSE 'INFO'
    END
  FROM time_due td
  JOIN base b ON b.equipment_id = td.equipment_id
  WHERE td.next_due_date IS NOT NULL
    AND td.next_due_date <= current_date + (p_days_ahead || ' days')::interval

  UNION ALL
  -- Hours-based
  SELECT
    now(), b.company_id, b.farm_id, hd.equipment_id, hd.task_id, hd.rule_id,
    NULL::date, NULL::int,
    hd.next_due_at_hours, hd.hours_remaining,
    NULL::numeric, NULL::numeric,
    CASE
      WHEN hd.hours_remaining IS NULL THEN 'INFO'
      WHEN hd.hours_remaining <= 0 THEN 'OVERDUE'
      WHEN hd.hours_remaining <= COALESCE(p_hours_ahead, 25) THEN 'DUE_SOON'
      ELSE 'INFO'
    END
  FROM hours_due hd
  JOIN base b ON b.equipment_id = hd.equipment_id
  WHERE hd.next_due_at_hours IS NOT NULL
    AND (hd.hours_remaining <= COALESCE(p_hours_ahead, 25) OR hd.hours_remaining <= 0)

  UNION ALL
  -- KM-based
  SELECT
    now(), b.company_id, b.farm_id, kd.equipment_id, kd.task_id, kd.rule_id,
    NULL::date, NULL::int,
    NULL::numeric, NULL::numeric,
    kd.next_due_at_km, kd.km_remaining,
    CASE
      WHEN kd.km_remaining IS NULL THEN 'INFO'
      WHEN kd.km_remaining <= 0 THEN 'OVERDUE'
      WHEN kd.km_remaining <= COALESCE(p_km_ahead, 500) THEN 'DUE_SOON'
      ELSE 'INFO'
    END
  FROM km_due kd
  JOIN base b ON b.equipment_id = kd.equipment_id
  WHERE kd.next_due_at_km IS NOT NULL
    AND (kd.km_remaining <= COALESCE(p_km_ahead, 500) OR kd.km_remaining <= 0);

  -- Keep only actionable severities
  DELETE FROM due_soon_stage WHERE severity NOT IN ('OVERDUE','DUE_SOON');

  -- UPSERT into target snapshot
  INSERT INTO due_soon AS dst (
    computed_at, company_id, farm_id, equipment_id, task_id, rule_id,
    next_due_date, days_until_due,
    next_due_at_hours, hours_remaining,
    next_due_at_km, km_remaining, severity
  )
  SELECT
    computed_at, company_id, farm_id, equipment_id, task_id, rule_id,
    next_due_date, days_until_due,
    next_due_at_hours, hours_remaining,
    next_due_at_km, km_remaining, severity
  FROM due_soon_stage
  ON CONFLICT (equipment_id, task_id, rule_id)
  DO UPDATE SET
    computed_at       = EXCLUDED.computed_at,
    company_id        = EXCLUDED.company_id,
    farm_id           = EXCLUDED.farm_id,
    next_due_date     = EXCLUDED.next_due_date,
    days_until_due    = EXCLUDED.days_until_due,
    next_due_at_hours = EXCLUDED.next_due_at_hours,
    hours_remaining   = EXCLUDED.hours_remaining,
    next_due_at_km    = EXCLUDED.next_due_at_km,
    km_remaining      = EXCLUDED.km_remaining,
    severity          = EXCLUDED.severity;

  -- Remove items that are no longer due
  IF p_purge THEN
    DELETE FROM due_soon d
    WHERE NOT EXISTS (
      SELECT 1
      FROM due_soon_stage s
      WHERE s.equipment_id = d.equipment_id
        AND s.task_id      = d.task_id
        AND s.rule_id      = d.rule_id
    );
  END IF;

END;
$$;

COMMIT;

-- =========================
-- 7) Optional: schedule daily refresh with pg_cron
-- =========================
-- Enable once
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- Run every day at 02:05 (tune thresholds as needed)
SELECT cron.schedule(
  'due_soon_daily',
  '5 2 * * *',
  $$SELECT refresh_due_soon_upsert(30, 25, 500, true);$$
);

-- =========================
-- 8) Manual run (for first-time test)
-- =========================
-- SELECT refresh_due_soon_upsert();  -- defaults: 30d / 25h / 500km / purge=true

-- =========================
-- 9) Optional views for dashboards
-- =========================
CREATE OR REPLACE VIEW vw_due_soon AS
SELECT
  ds.computed_at,
  c.name  AS company,
  f.name  AS farm,
  e.display_name AS equipment,
  t.name  AS task,
  ds.severity,
  ds.next_due_date,
  ds.days_until_due,
  ds.next_due_at_hours,
  ds.hours_remaining,
  ds.next_due_at_km,
  ds.km_remaining,
  ds.rule_id,
  ds.equipment_id,
  ds.task_id
FROM due_soon ds
JOIN equipment e     ON e.id = ds.equipment_id
JOIN farm f          ON f.id = e.farm_id
JOIN company c       ON c.id = f.company_id
JOIN maintenance_task t ON t.id = ds.task_id;

CREATE OR REPLACE VIEW vw_due_soon_summary AS
SELECT c.name AS company,
       ds.severity,
       COUNT(*) AS total
FROM due_soon ds
JOIN equipment e ON e.id = ds.equipment_id
JOIN farm f ON f.id = e.farm_id
JOIN company c ON c.id = f.company_id
GROUP BY c.name, ds.severity
ORDER BY c.name, ds.severity;
