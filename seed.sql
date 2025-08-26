-- ============================================================
-- Seed data for Farm Equipment Maintenance Scheduling DB
-- ============================================================

-- -------------------------
-- 1) Companies
-- -------------------------
INSERT INTO company (name)
SELECT 'Acme Farms'
WHERE NOT EXISTS (SELECT 1 FROM company WHERE name = 'Acme Farms');

INSERT INTO company (name)
SELECT 'GreenFields Co.'
WHERE NOT EXISTS (SELECT 1 FROM company WHERE name = 'GreenFields Co.');

-- -------------------------
-- 2) Farms
-- -------------------------
INSERT INTO farm (name, location, company_id)
SELECT 'North Farm', 'Iowa', c.id
FROM company c
WHERE c.name = 'Acme Farms'
  AND NOT EXISTS (SELECT 1 FROM farm f WHERE f.name='North Farm' AND f.company_id=c.id);

INSERT INTO farm (name, location, company_id)
SELECT 'South Farm', 'Nebraska', c.id
FROM company c
WHERE c.name = 'Acme Farms'
  AND NOT EXISTS (SELECT 1 FROM farm f WHERE f.name='South Farm' AND f.company_id=c.id);

INSERT INTO farm (name, location, company_id)
SELECT 'Valley Farm', 'Kansas', c.id
FROM company c
WHERE c.name = 'GreenFields Co.'
  AND NOT EXISTS (SELECT 1 FROM farm f WHERE f.name='Valley Farm' AND f.company_id=c.id);

-- -------------------------
-- 3) Equipment models
-- -------------------------
INSERT INTO equipment_model (manufacturer, model_name, equipment_type, description)
SELECT 'John Deere','6110','Tractor','Mid-size tractor'
WHERE NOT EXISTS (SELECT 1 FROM equipment_model WHERE manufacturer='John Deere' AND model_name='6110');

INSERT INTO equipment_model (manufacturer, model_name, equipment_type, description)
SELECT 'Case IH','Axial-Flow 8250','Combine','High capacity combine'
WHERE NOT EXISTS (SELECT 1 FROM equipment_model WHERE manufacturer='Case IH' AND model_name='Axial-Flow 8250');

INSERT INTO equipment_model (manufacturer, model_name, equipment_type, description)
SELECT 'Ford','F-250','Truck','Farm pickup'
WHERE NOT EXISTS (SELECT 1 FROM equipment_model WHERE manufacturer='Ford' AND model_name='F-250');

-- -------------------------
-- 4) Part types
-- -------------------------
INSERT INTO part_type (name, category, manufacturer, model_code, description)
SELECT 'Oil Filter Type A','Oil Filter','FleetGuard','OF-A','Standard oil filter'
WHERE NOT EXISTS (SELECT 1 FROM part_type WHERE name='Oil Filter Type A');

INSERT INTO part_type (name, category, manufacturer, model_code, description)
SELECT 'Oil Filter Type B','Oil Filter','FleetGuard','OF-B','Higher performance oil filter'
WHERE NOT EXISTS (SELECT 1 FROM part_type WHERE name='Oil Filter Type B');

INSERT INTO part_type (name, category, manufacturer, model_code, description)
SELECT 'Hydraulic Filter H100','Hydraulic Filter','Parker','HF-100','Hydraulic system filter'
WHERE NOT EXISTS (SELECT 1 FROM part_type WHERE name='Hydraulic Filter H100');

INSERT INTO part_type (name, category, manufacturer, model_code, description)
SELECT 'Front Tire 18"','Tire','Firestone','FT18','Front tire 18 inch'
WHERE NOT EXISTS (SELECT 1 FROM part_type WHERE name='Front Tire 18"');

INSERT INTO part_type (name, category, manufacturer, model_code, description)
SELECT 'Engine Oil 15W-40','Oil','Shell','ROTELLA-1540','Engine oil'
WHERE NOT EXISTS (SELECT 1 FROM part_type WHERE name='Engine Oil 15W-40');

-- -------------------------
-- 5) Equipment (3 units)
-- -------------------------
-- Tractor at North Farm (Acme)
INSERT INTO equipment (display_name, serial_number, equipment_model_id, farm_id, acquired_on, active, engine_hours, odometer_km, created_at)
SELECT 'Tractor T-100', 'JD6110-0001',
       (SELECT id FROM equipment_model WHERE manufacturer='John Deere' AND model_name='6110'),
       (SELECT f.id FROM farm f JOIN company c ON c.id=f.company_id WHERE f.name='North Farm' AND c.name='Acme Farms'),
       current_date - INTERVAL '400 days', TRUE, 495, NULL, now() - INTERVAL '400 days'
WHERE NOT EXISTS (SELECT 1 FROM equipment WHERE display_name='Tractor T-100');

-- Combine at North Farm (Acme)
INSERT INTO equipment (display_name, serial_number, equipment_model_id, farm_id, acquired_on, active, engine_hours, odometer_km, created_at)
SELECT 'Combine C-200', 'CASE8250-0009',
       (SELECT id FROM equipment_model WHERE manufacturer='Case IH' AND model_name='Axial-Flow 8250'),
       (SELECT f.id FROM farm f JOIN company c ON c.id=f.company_id WHERE f.name='North Farm' AND c.name='Acme Farms'),
       current_date - INTERVAL '300 days', TRUE, 520, NULL, now() - INTERVAL '300 days'
WHERE NOT EXISTS (SELECT 1 FROM equipment WHERE display_name='Combine C-200');

-- Truck at South Farm (Acme)
INSERT INTO equipment (display_name, serial_number, equipment_model_id, farm_id, acquired_on, active, engine_hours, odometer_km, created_at)
SELECT 'Truck TR-9', 'F250-77TR9',
       (SELECT id FROM equipment_model WHERE manufacturer='Ford' AND model_name='F-250'),
       (SELECT f.id FROM farm f JOIN company c ON c.id=f.company_id WHERE f.name='South Farm' AND c.name='Acme Farms'),
       current_date - INTERVAL '500 days', TRUE, NULL, 148500, now() - INTERVAL '500 days'
WHERE NOT EXISTS (SELECT 1 FROM equipment WHERE display_name='Truck TR-9');

-- -------------------------
-- 6) Installed equipment components
-- -------------------------
-- Tractor: Oil filter in FILTER_OIL slot (Type B)
INSERT INTO equipment_component (equipment_id, part_type_id, slot_label, serial_number, installed_at, removed_at, notes)
SELECT e.id,
       (SELECT id FROM part_type WHERE name='Oil Filter Type B'),
       'FILTER_OIL', 'OF-B-TRAC-001', current_timestamp - INTERVAL '240 days', NULL, 'Upgraded filter'
FROM equipment e
WHERE e.display_name='Tractor T-100'
  AND NOT EXISTS (
    SELECT 1 FROM equipment_component ec
    WHERE ec.equipment_id=e.id AND ec.slot_label='FILTER_OIL' AND ec.removed_at IS NULL
  );

-- Tractor: Front tires
INSERT INTO equipment_component (equipment_id, part_type_id, slot_label, serial_number, installed_at, removed_at, notes)
SELECT e.id, (SELECT id FROM part_type WHERE name='Front Tire 18"'),
       'FRONT-LEFT', 'TIRE18-FL-001', current_timestamp - INTERVAL '7 months', NULL, NULL
FROM equipment e
WHERE e.display_name='Tractor T-100'
  AND NOT EXISTS (
    SELECT 1 FROM equipment_component ec
    WHERE ec.equipment_id=e.id AND ec.slot_label='FRONT-LEFT' AND ec.removed_at IS NULL
  );

INSERT INTO equipment_component (equipment_id, part_type_id, slot_label, serial_number, installed_at, removed_at, notes)
SELECT e.id, (SELECT id FROM part_type WHERE name='Front Tire 18"'),
       'FRONT-RIGHT', 'TIRE18-FR-001', current_timestamp - INTERVAL '7 months', NULL, NULL
FROM equipment e
WHERE e.display_name='Tractor T-100'
  AND NOT EXISTS (
    SELECT 1 FROM equipment_component ec
    WHERE ec.equipment_id=e.id AND ec.slot_label='FRONT-RIGHT' AND ec.removed_at IS NULL
  );

-- Combine: Hydraulic filter (H100)
INSERT INTO equipment_component (equipment_id, part_type_id, slot_label, serial_number, installed_at, removed_at, notes)
SELECT e.id,
       (SELECT id FROM part_type WHERE name='Hydraulic Filter H100'),
       'FILTER_HYD', 'HF-100-COMB-01', current_timestamp - INTERVAL '200 days', NULL, NULL
FROM equipment e
WHERE e.display_name='Combine C-200'
  AND NOT EXISTS (
    SELECT 1 FROM equipment_component ec
    WHERE ec.equipment_id=e.id AND ec.slot_label='FILTER_HYD' AND ec.removed_at IS NULL
  );

-- Truck: Front-Left tire (for tire inspections)
INSERT INTO equipment_component (equipment_id, part_type_id, slot_label, serial_number, installed_at, removed_at, notes)
SELECT e.id, (SELECT id FROM part_type WHERE name='Front Tire 18"'),
       'FRONT-LEFT', 'TIRE18-FL-TR9', current_timestamp - INTERVAL '5 months', NULL, NULL
FROM equipment e
WHERE e.display_name='Truck TR-9'
  AND NOT EXISTS (
    SELECT 1 FROM equipment_component ec
    WHERE ec.equipment_id=e.id AND ec.slot_label='FRONT-LEFT' AND ec.removed_at IS NULL
  );

-- -------------------------
-- 7) Maintenance tasks
-- -------------------------
INSERT INTO maintenance_task (name, description, default_part_type_id)
SELECT 'Change Engine Oil','Replace engine oil',
       (SELECT id FROM part_type WHERE name='Engine Oil 15W-40')
WHERE NOT EXISTS (SELECT 1 FROM maintenance_task WHERE name='Change Engine Oil');

INSERT INTO maintenance_task (name, description, default_part_type_id)
SELECT 'Replace Oil Filter','Replace engine oil filter',
       (SELECT id FROM part_type WHERE name='Oil Filter Type A')
WHERE NOT EXISTS (SELECT 1 FROM maintenance_task WHERE name='Replace Oil Filter');

INSERT INTO maintenance_task (name, description)
SELECT 'Grease Fittings','Lubricate grease points'
WHERE NOT EXISTS (SELECT 1 FROM maintenance_task WHERE name='Grease Fittings');

INSERT INTO maintenance_task (name, description)
SELECT 'Inspect Tires','Check wear & pressure'
WHERE NOT EXISTS (SELECT 1 FROM maintenance_task WHERE name='Inspect Tires');

INSERT INTO maintenance_task (name, description)
SELECT 'Replace Hydraulic Filter','Replace hydraulic filter'
WHERE NOT EXISTS (SELECT 1 FROM maintenance_task WHERE name='Replace Hydraulic Filter');

-- -------------------------
-- 8) Maintenance rules (mix time & usage)
-- -------------------------
-- Tractor model: Change Engine Oil every 250 HOURS
INSERT INTO maintenance_rule (task_id, equipment_model_id, frequency_type, value_numeric, active, is_default, condition_note)
SELECT
  (SELECT id FROM maintenance_task WHERE name='Change Engine Oil'),
  (SELECT id FROM equipment_model WHERE manufacturer='John Deere' AND model_name='6110'),
  'HOURS', 250, TRUE, TRUE, 'Every 250 engine hours'
WHERE NOT EXISTS (
  SELECT 1 FROM maintenance_rule r
  WHERE r.task_id = (SELECT id FROM maintenance_task WHERE name='Change Engine Oil')
    AND r.equipment_model_id = (SELECT id FROM equipment_model WHERE manufacturer='John Deere' AND model_name='6110')
    AND r.frequency_type='HOURS'
);

-- Tractor model: Replace Oil Filter every 200 HOURS
INSERT INTO maintenance_rule (task_id, equipment_model_id, frequency_type, value_numeric, active, is_default, condition_note)
SELECT
  (SELECT id FROM maintenance_task WHERE name='Replace Oil Filter'),
  (SELECT id FROM equipment_model WHERE manufacturer='John Deere' AND model_name='6110'),
  'HOURS', 200, TRUE, TRUE, 'Every 200 engine hours'
WHERE NOT EXISTS (
  SELECT 1 FROM maintenance_rule r
  WHERE r.task_id = (SELECT id FROM maintenance_task WHERE name='Replace Oil Filter')
    AND r.equipment_model_id = (SELECT id FROM equipment_model WHERE manufacturer='John Deere' AND model_name='6110')
    AND r.frequency_type='HOURS'
);

-- Combine model: Replace Hydraulic Filter every 500 HOURS
INSERT INTO maintenance_rule (task_id, equipment_model_id, frequency_type, value_numeric, active, is_default, condition_note)
SELECT
  (SELECT id FROM maintenance_task WHERE name='Replace Hydraulic Filter'),
  (SELECT id FROM equipment_model WHERE manufacturer='Case IH' AND model_name='Axial-Flow 8250'),
  'HOURS', 500, TRUE, TRUE, 'Every 500 engine hours'
WHERE NOT EXISTS (
  SELECT 1 FROM maintenance_rule r
  WHERE r.task_id = (SELECT id FROM maintenance_task WHERE name='Replace Hydraulic Filter')
    AND r.equipment_model_id = (SELECT id FROM equipment_model WHERE manufacturer='Case IH' AND model_name='Axial-Flow 8250')
    AND r.frequency_type='HOURS'
);

-- Global by part-type: Inspect Tires every 6 MONTHS when a Front Tire 18" is installed (any equipment)
INSERT INTO maintenance_rule (task_id, part_type_id, frequency_type, value_numeric, active, is_default, condition_note)
SELECT
  (SELECT id FROM maintenance_task WHERE name='Inspect Tires'),
  (SELECT id FROM part_type WHERE name='Front Tire 18"'),
  'MONTHS', 6, TRUE, TRUE, 'Every 6 months while tire is installed'
WHERE NOT EXISTS (
  SELECT 1 FROM maintenance_rule r
  WHERE r.task_id = (SELECT id FROM maintenance_task WHERE name='Inspect Tires')
    AND r.part_type_id = (SELECT id FROM part_type WHERE name='Front Tire 18"')
    AND r.frequency_type='MONTHS'
);

-- Truck model: Change Engine Oil every 10,000 KM
INSERT INTO maintenance_rule (task_id, equipment_model_id, frequency_type, value_numeric, active, is_default, condition_note)
SELECT
  (SELECT id FROM maintenance_task WHERE name='Change Engine Oil'),
  (SELECT id FROM equipment_model WHERE manufacturer='Ford' AND model_name='F-250'),
  'KM', 10000, TRUE, TRUE, 'Every 10,000 km'
WHERE NOT EXISTS (
  SELECT 1 FROM maintenance_rule r
  WHERE r.task_id = (SELECT id FROM maintenance_task WHERE name='Change Engine Oil')
    AND r.equipment_model_id = (SELECT id FROM equipment_model WHERE manufacturer='Ford' AND model_name='F-250')
    AND r.frequency_type='KM'
);

-- -------------------------
-- 9) Maintenance logs (make some due soon / overdue)
-- -------------------------
-- For Tractor T-100:
-- Last oil change was at 260 hours, so next due at 510; current engine_hours=495 (15h remaining -> DUE_SOON with default 25h threshold)
INSERT INTO maintenance_log (equipment_id, task_id, performed_on, engine_hours, notes, part_type_id)
SELECT e.id,
       (SELECT id FROM maintenance_task WHERE name='Change Engine Oil'),
       current_date - INTERVAL '200 days',
       260,
       'Oil changed using 15W-40',
       (SELECT id FROM part_type WHERE name='Engine Oil 15W-40')
FROM equipment e
WHERE e.display_name='Tractor T-100'
  AND NOT EXISTS (
     SELECT 1 FROM maintenance_log ml
     WHERE ml.equipment_id=e.id AND ml.task_id=(SELECT id FROM maintenance_task WHERE name='Change Engine Oil')
  );

-- Last oil filter replacement at 300 hours, so next due at 500; current=495 (5h remaining -> DUE_SOON)
-- Also attach the component in header for 1:1 shortcut and create detail with REPLACE
WITH t AS (
  SELECT e.id AS equipment_id,
         (SELECT id FROM maintenance_task WHERE name='Replace Oil Filter') AS task_id,
         (SELECT ec.id FROM equipment_component ec WHERE ec.equipment_id=e.id AND ec.slot_label='FILTER_OIL' AND ec.removed_at IS NULL) AS ec_id
  FROM equipment e
  WHERE e.display_name='Tractor T-100'
)
INSERT INTO maintenance_log (equipment_id, task_id, performed_on, engine_hours, notes, equipment_component_id, part_type_id)
SELECT t.equipment_id, t.task_id, current_date - INTERVAL '150 days', 300,
       'Oil filter replaced (Type B)',
       t.ec_id,
       (SELECT id FROM part_type WHERE name='Oil Filter Type B')
FROM t
WHERE NOT EXISTS (
  SELECT 1 FROM maintenance_log ml
  WHERE ml.equipment_id=t.equipment_id AND ml.task_id=t.task_id
);

-- Add a matching detail for the previous filter replacement
INSERT INTO maintenance_log_detail (maintenance_log_id, equipment_component_id, action, old_part_type_id, new_part_type_id, qty_used, notes)
SELECT ml.id,
       (SELECT ec.id FROM equipment_component ec WHERE ec.equipment_id=ml.equipment_id AND ec.slot_label='FILTER_OIL' AND ec.removed_at IS NULL),
       'REPLACE',
       (SELECT id FROM part_type WHERE name='Oil Filter Type A'),
       (SELECT id FROM part_type WHERE name='Oil Filter Type B'),
       1,
       'Upgraded to Type B'
FROM maintenance_log ml
JOIN equipment e ON e.id=ml.equipment_id
JOIN maintenance_task t ON t.id=ml.task_id
WHERE e.display_name='Tractor T-100' AND t.name='Replace Oil Filter'
  AND NOT EXISTS (SELECT 1 FROM maintenance_log_detail d WHERE d.maintenance_log_id=ml.id);

-- Tires inspection on Truck 5 months ago => next due at 6 months; due within next ~30 days
INSERT INTO maintenance_log (equipment_id, task_id, performed_on, odometer_km, notes)
SELECT e.id,
       (SELECT id FROM maintenance_task WHERE name='Inspect Tires'),
       current_date - INTERVAL '5 months',
       e.odometer_km,
       'Routine tire inspection'
FROM equipment e
WHERE e.display_name='Truck TR-9'
  AND NOT EXISTS (
    SELECT 1 FROM maintenance_log ml WHERE ml.equipment_id=e.id AND ml.task_id=(SELECT id FROM maintenance_task WHERE name='Inspect Tires')
  );

-- Combine C-200: hydraulic filter replaced at 100 hours, now engine_hours=520 -> next due 600 -> not due soon (kept as background)
INSERT INTO maintenance_log (equipment_id, task_id, performed_on, engine_hours, notes)
SELECT e.id,
       (SELECT id FROM maintenance_task WHERE name='Replace Hydraulic Filter'),
       current_date - INTERVAL '250 days',
       100,
       'Initial hydraulic filter replacement'
FROM equipment e
WHERE e.display_name='Combine C-200'
  AND NOT EXISTS (
    SELECT 1 FROM maintenance_log ml WHERE ml.equipment_id=e.id AND ml.task_id=(SELECT id FROM maintenance_task WHERE name='Replace Hydraulic Filter')
  );

-- -------------------------
-- 10) Kick the due_soon computation
-- -------------------------
-- Default thresholds: 30 days, 25 hours, 500 km, purge=true
SELECT refresh_due_soon_upsert();

-- Quick check
SELECT * FROM vw_due_soon ORDER BY severity, next_due_date NULLS LAST, hours_remaining NULLS LAST, km_remaining NULLS LAST;
