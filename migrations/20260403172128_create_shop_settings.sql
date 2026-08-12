
-- Shop settings — single-row config table
CREATE TABLE shop_settings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  store_live boolean NOT NULL DEFAULT false,
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- Insert the single config row (store starts OFF)
INSERT INTO shop_settings (store_live) VALUES (false);

-- RLS
ALTER TABLE shop_settings ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Public read settings" ON shop_settings FOR SELECT TO anon USING (true);
CREATE POLICY "Service role settings" ON shop_settings FOR ALL TO service_role USING (true) WITH CHECK (true);

