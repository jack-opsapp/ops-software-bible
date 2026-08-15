
-- ============================================
-- OPS Merch Store Schema
-- ============================================

-- 1. Categories
CREATE TABLE shop_categories (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  slug text NOT NULL UNIQUE,
  sort_order int NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- 2. Products
CREATE TABLE shop_products (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  category_id uuid NOT NULL REFERENCES shop_categories(id),
  name text NOT NULL,
  slug text NOT NULL UNIQUE,
  description text,
  price_cents int NOT NULL,
  images jsonb NOT NULL DEFAULT '[]'::jsonb,
  is_featured boolean NOT NULL DEFAULT false,
  is_active boolean NOT NULL DEFAULT true,
  archived_at timestamptz,
  tax_code text NOT NULL DEFAULT 'txcd_99999999',
  sort_order int NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- 3. Product Options (e.g., "Size", "Color")
CREATE TABLE shop_product_options (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id uuid NOT NULL REFERENCES shop_products(id) ON DELETE CASCADE,
  name text NOT NULL,
  sort_order int NOT NULL DEFAULT 0
);

-- 4. Option Values (e.g., "M", "L", "Matte Black")
CREATE TABLE shop_product_option_values (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  option_id uuid NOT NULL REFERENCES shop_product_options(id) ON DELETE CASCADE,
  value text NOT NULL,
  sort_order int NOT NULL DEFAULT 0
);

-- 5. Variants (one per purchasable combination)
CREATE TABLE shop_variants (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id uuid NOT NULL REFERENCES shop_products(id) ON DELETE CASCADE,
  sku text NOT NULL UNIQUE,
  price_cents int NOT NULL,
  stock_quantity int NOT NULL DEFAULT 0,
  reserved_quantity int NOT NULL DEFAULT 0,
  is_active boolean NOT NULL DEFAULT true,
  sort_order int NOT NULL DEFAULT 0
);

-- 6. Variant - Option Value pivot
CREATE TABLE shop_variant_option_values (
  variant_id uuid NOT NULL REFERENCES shop_variants(id) ON DELETE CASCADE,
  option_value_id uuid NOT NULL REFERENCES shop_product_option_values(id) ON DELETE CASCADE,
  PRIMARY KEY (variant_id, option_value_id)
);

-- 7. Shipping Methods
CREATE TABLE shop_shipping_methods (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  description text,
  price_cents int NOT NULL,
  min_order_cents int,
  is_active boolean NOT NULL DEFAULT true,
  sort_order int NOT NULL DEFAULT 0
);

-- 8. Orders
CREATE TABLE shop_orders (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_number text NOT NULL UNIQUE,
  email text NOT NULL,
  shipping_address jsonb NOT NULL,
  shipping_method_id uuid REFERENCES shop_shipping_methods(id),
  subtotal_cents int NOT NULL,
  shipping_cents int NOT NULL,
  tax_cents int NOT NULL,
  total_cents int NOT NULL,
  stripe_payment_intent_id text NOT NULL,
  stripe_tax_calculation_id text,
  status text NOT NULL DEFAULT 'pending',
  paid_at timestamptz,
  shipped_at timestamptz,
  tracking_number text,
  tracking_url text,
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- 9. Order Items (denormalized snapshots)
CREATE TABLE shop_order_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id uuid NOT NULL REFERENCES shop_orders(id) ON DELETE CASCADE,
  product_id uuid REFERENCES shop_products(id) ON DELETE SET NULL,
  variant_id uuid REFERENCES shop_variants(id) ON DELETE SET NULL,
  product_name text NOT NULL,
  variant_label text NOT NULL,
  sku text NOT NULL,
  image_url text,
  unit_price_cents int NOT NULL,
  quantity int NOT NULL,
  option_values jsonb
);

-- 10. Inventory Reservations (15-min TTL)
CREATE TABLE shop_inventory_reservations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  variant_id uuid NOT NULL REFERENCES shop_variants(id) ON DELETE CASCADE,
  quantity int NOT NULL,
  stripe_payment_intent_id text NOT NULL,
  expires_at timestamptz NOT NULL DEFAULT (now() + interval '15 minutes'),
  created_at timestamptz NOT NULL DEFAULT now()
);

-- Indexes
CREATE INDEX idx_shop_products_category ON shop_products(category_id);
CREATE INDEX idx_shop_products_active ON shop_products(is_active, archived_at);
CREATE INDEX idx_shop_variants_product ON shop_variants(product_id);
CREATE INDEX idx_shop_orders_status ON shop_orders(status);
CREATE INDEX idx_shop_orders_email ON shop_orders(email);
CREATE INDEX idx_shop_order_items_order ON shop_order_items(order_id);
CREATE INDEX idx_shop_reservations_expires ON shop_inventory_reservations(expires_at);

-- Auto-update updated_at trigger for shop_products
CREATE OR REPLACE FUNCTION update_shop_products_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER shop_products_updated_at
  BEFORE UPDATE ON shop_products
  FOR EACH ROW EXECUTE FUNCTION update_shop_products_updated_at();

-- Auto-update updated_at trigger for shop_orders
CREATE OR REPLACE FUNCTION update_shop_orders_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER shop_orders_updated_at
  BEFORE UPDATE ON shop_orders
  FOR EACH ROW EXECUTE FUNCTION update_shop_orders_updated_at();

-- RLS: Enable on all tables
ALTER TABLE shop_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE shop_products ENABLE ROW LEVEL SECURITY;
ALTER TABLE shop_product_options ENABLE ROW LEVEL SECURITY;
ALTER TABLE shop_product_option_values ENABLE ROW LEVEL SECURITY;
ALTER TABLE shop_variants ENABLE ROW LEVEL SECURITY;
ALTER TABLE shop_variant_option_values ENABLE ROW LEVEL SECURITY;
ALTER TABLE shop_shipping_methods ENABLE ROW LEVEL SECURITY;
ALTER TABLE shop_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE shop_order_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE shop_inventory_reservations ENABLE ROW LEVEL SECURITY;

-- RLS: Public read for catalog tables (anon role)
CREATE POLICY "Public read categories" ON shop_categories FOR SELECT TO anon USING (true);
CREATE POLICY "Public read products" ON shop_products FOR SELECT TO anon USING (is_active = true AND archived_at IS NULL);
CREATE POLICY "Public read options" ON shop_product_options FOR SELECT TO anon USING (true);
CREATE POLICY "Public read option values" ON shop_product_option_values FOR SELECT TO anon USING (true);
CREATE POLICY "Public read variants" ON shop_variants FOR SELECT TO anon USING (is_active = true);
CREATE POLICY "Public read variant options" ON shop_variant_option_values FOR SELECT TO anon USING (true);
CREATE POLICY "Public read shipping" ON shop_shipping_methods FOR SELECT TO anon USING (is_active = true);

-- RLS: Service role has full access (implicit via bypass), no anon writes on orders
CREATE POLICY "Service role orders" ON shop_orders FOR ALL TO service_role USING (true) WITH CHECK (true);
CREATE POLICY "Service role order items" ON shop_order_items FOR ALL TO service_role USING (true) WITH CHECK (true);
CREATE POLICY "Service role reservations" ON shop_inventory_reservations FOR ALL TO service_role USING (true) WITH CHECK (true);

