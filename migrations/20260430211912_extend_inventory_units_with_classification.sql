-- 1. Add columns
ALTER TABLE inventory_units ADD COLUMN IF NOT EXISTS abbreviation TEXT;
ALTER TABLE inventory_units ADD COLUMN IF NOT EXISTS dimension TEXT NOT NULL DEFAULT 'count'
  CHECK (dimension IN ('count', 'time', 'length', 'area', 'volume', 'weight'));

-- 2. Backfill abbreviation + dimension for existing seeded defaults
UPDATE inventory_units SET abbreviation = 'ea',     dimension = 'count'  WHERE display = 'ea'     AND abbreviation IS NULL;
UPDATE inventory_units SET abbreviation = 'box',    dimension = 'count'  WHERE display = 'box'    AND abbreviation IS NULL;
UPDATE inventory_units SET abbreviation = 'ft',     dimension = 'length' WHERE display = 'ft'     AND abbreviation IS NULL;
UPDATE inventory_units SET abbreviation = 'm',      dimension = 'length' WHERE display = 'm'      AND abbreviation IS NULL;
UPDATE inventory_units SET abbreviation = 'kg',     dimension = 'weight' WHERE display = 'kg'     AND abbreviation IS NULL;
UPDATE inventory_units SET abbreviation = 'lb',     dimension = 'weight' WHERE display = 'lb'     AND abbreviation IS NULL;
UPDATE inventory_units SET abbreviation = 'gal',    dimension = 'volume' WHERE display = 'gal'    AND abbreviation IS NULL;
UPDATE inventory_units SET abbreviation = 'L',      dimension = 'volume' WHERE display = 'L'      AND abbreviation IS NULL;
UPDATE inventory_units SET abbreviation = 'roll',   dimension = 'count'  WHERE display = 'roll'   AND abbreviation IS NULL;
UPDATE inventory_units SET abbreviation = 'sheet',  dimension = 'count'  WHERE display = 'sheet'  AND abbreviation IS NULL;
UPDATE inventory_units SET abbreviation = 'bag',    dimension = 'count'  WHERE display = 'bag'    AND abbreviation IS NULL;
UPDATE inventory_units SET abbreviation = 'pallet', dimension = 'count'  WHERE display = 'pallet' AND abbreviation IS NULL;

-- 3. Insert NEW defaults for every existing company (idempotent via WHERE NOT EXISTS)
DO $$
DECLARE c RECORD;
BEGIN
  FOR c IN SELECT DISTINCT company_id FROM inventory_units WHERE deleted_at IS NULL LOOP
    INSERT INTO inventory_units (company_id, display, abbreviation, dimension, is_default, sort_order)
    SELECT c.company_id, 'hour', 'hr', 'time', true, 12
    WHERE NOT EXISTS (SELECT 1 FROM inventory_units WHERE company_id = c.company_id AND display = 'hour' AND deleted_at IS NULL);

    INSERT INTO inventory_units (company_id, display, abbreviation, dimension, is_default, sort_order)
    SELECT c.company_id, 'day', 'd', 'time', true, 13
    WHERE NOT EXISTS (SELECT 1 FROM inventory_units WHERE company_id = c.company_id AND display = 'day' AND deleted_at IS NULL);

    INSERT INTO inventory_units (company_id, display, abbreviation, dimension, is_default, sort_order)
    SELECT c.company_id, 'linear ft', 'LF', 'length', true, 14
    WHERE NOT EXISTS (SELECT 1 FROM inventory_units WHERE company_id = c.company_id AND display = 'linear ft' AND deleted_at IS NULL);

    INSERT INTO inventory_units (company_id, display, abbreviation, dimension, is_default, sort_order)
    SELECT c.company_id, 'linear m', 'LM', 'length', true, 15
    WHERE NOT EXISTS (SELECT 1 FROM inventory_units WHERE company_id = c.company_id AND display = 'linear m' AND deleted_at IS NULL);

    INSERT INTO inventory_units (company_id, display, abbreviation, dimension, is_default, sort_order)
    SELECT c.company_id, 'sq ft', 'sqft', 'area', true, 16
    WHERE NOT EXISTS (SELECT 1 FROM inventory_units WHERE company_id = c.company_id AND display = 'sq ft' AND deleted_at IS NULL);

    INSERT INTO inventory_units (company_id, display, abbreviation, dimension, is_default, sort_order)
    SELECT c.company_id, 'sq m', 'sqm', 'area', true, 17
    WHERE NOT EXISTS (SELECT 1 FROM inventory_units WHERE company_id = c.company_id AND display = 'sq m' AND deleted_at IS NULL);

    INSERT INTO inventory_units (company_id, display, abbreviation, dimension, is_default, sort_order)
    SELECT c.company_id, 'cu yd', 'cu yd', 'volume', true, 18
    WHERE NOT EXISTS (SELECT 1 FROM inventory_units WHERE company_id = c.company_id AND display = 'cu yd' AND deleted_at IS NULL);

    INSERT INTO inventory_units (company_id, display, abbreviation, dimension, is_default, sort_order)
    SELECT c.company_id, 'cu m', 'cu m', 'volume', true, 19
    WHERE NOT EXISTS (SELECT 1 FROM inventory_units WHERE company_id = c.company_id AND display = 'cu m' AND deleted_at IS NULL);
  END LOOP;
END $$;

-- 4. Update initialize_company_defaults() for new companies
CREATE OR REPLACE FUNCTION initialize_company_defaults(p_company_id UUID)
RETURNS void AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM task_types WHERE company_id = p_company_id AND deleted_at IS NULL) THEN
    INSERT INTO task_types (company_id, display, color, is_default, display_order) VALUES
      (p_company_id, 'Quote',        '#B5A381', true, 0),
      (p_company_id, 'Installation', '#8195B5', true, 1),
      (p_company_id, 'Repair',       '#B58289', true, 2),
      (p_company_id, 'Inspection',   '#9DB582', true, 3),
      (p_company_id, 'Consultation', '#A182B5', true, 4),
      (p_company_id, 'Follow-up',    '#C4A868', true, 5);
  END IF;

  IF NOT EXISTS (SELECT 1 FROM inventory_units WHERE company_id = p_company_id AND deleted_at IS NULL) THEN
    INSERT INTO inventory_units (company_id, display, abbreviation, dimension, is_default, sort_order) VALUES
      (p_company_id, 'ea',         'ea',     'count',  true, 0),
      (p_company_id, 'box',        'box',    'count',  true, 1),
      (p_company_id, 'ft',         'ft',     'length', true, 2),
      (p_company_id, 'm',          'm',      'length', true, 3),
      (p_company_id, 'kg',         'kg',     'weight', true, 4),
      (p_company_id, 'lb',         'lb',     'weight', true, 5),
      (p_company_id, 'gal',        'gal',    'volume', true, 6),
      (p_company_id, 'L',          'L',      'volume', true, 7),
      (p_company_id, 'roll',       'roll',   'count',  true, 8),
      (p_company_id, 'sheet',      'sheet',  'count',  true, 9),
      (p_company_id, 'bag',        'bag',    'count',  true, 10),
      (p_company_id, 'pallet',     'pallet', 'count',  true, 11),
      (p_company_id, 'hour',       'hr',     'time',   true, 12),
      (p_company_id, 'day',        'd',      'time',   true, 13),
      (p_company_id, 'linear ft',  'LF',     'length', true, 14),
      (p_company_id, 'linear m',   'LM',     'length', true, 15),
      (p_company_id, 'sq ft',      'sqft',   'area',   true, 16),
      (p_company_id, 'sq m',       'sqm',    'area',   true, 17),
      (p_company_id, 'cu yd',      'cu yd',  'volume', true, 18),
      (p_company_id, 'cu m',       'cu m',   'volume', true, 19);
  END IF;

  INSERT INTO company_settings (company_id) VALUES (p_company_id::TEXT) ON CONFLICT (company_id) DO NOTHING;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;
