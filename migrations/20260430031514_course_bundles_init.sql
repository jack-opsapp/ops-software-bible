
-- Course bundles schema (Option B): supports both fixed bundles and pick_n bundles.
-- Fixed bundles ship a curated set of courses at a flat price.
-- Pick_n bundles let the user pick N courses from the eligible catalog and apply a percentage discount.

DO $$ BEGIN
  CREATE TYPE bundle_type AS ENUM ('fixed', 'pick_n');
EXCEPTION
  WHEN duplicate_object THEN null;
END $$;

CREATE TABLE IF NOT EXISTS course_bundles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  slug TEXT UNIQUE NOT NULL,
  type bundle_type NOT NULL,
  title TEXT NOT NULL,
  description TEXT,
  -- Fixed bundles use price_cents directly. Pick_n leaves it NULL and applies discount_pct at checkout.
  price_cents INTEGER,
  discount_pct INTEGER, -- only for pick_n bundles, e.g. 26 for Party Pack
  pick_count INTEGER, -- only for pick_n bundles, e.g. 6 for Party Pack
  status TEXT NOT NULL DEFAULT 'draft',
  sort_order INTEGER,
  stripe_price_id TEXT, -- fixed bundles have one; pick_n uses dynamic Checkout Sessions
  stripe_coupon_id TEXT, -- pick_n uses a coupon for the discount
  thumbnail_url TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT bundle_pricing_shape CHECK (
    (type = 'fixed' AND price_cents IS NOT NULL AND discount_pct IS NULL AND pick_count IS NULL) OR
    (type = 'pick_n' AND price_cents IS NULL AND discount_pct IS NOT NULL AND pick_count IS NOT NULL AND pick_count >= 2)
  )
);

CREATE TABLE IF NOT EXISTS bundle_courses (
  bundle_id UUID NOT NULL REFERENCES course_bundles(id) ON DELETE CASCADE,
  course_id UUID NOT NULL REFERENCES courses(id) ON DELETE CASCADE,
  sort_order INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (bundle_id, course_id)
);

CREATE INDEX IF NOT EXISTS bundle_courses_course_idx ON bundle_courses(course_id);
CREATE INDEX IF NOT EXISTS course_bundles_status_idx ON course_bundles(status);
CREATE INDEX IF NOT EXISTS course_bundles_sort_order_idx ON course_bundles(sort_order);

-- updated_at trigger
CREATE OR REPLACE FUNCTION course_bundles_set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS course_bundles_updated_at ON course_bundles;
CREATE TRIGGER course_bundles_updated_at
  BEFORE UPDATE ON course_bundles
  FOR EACH ROW EXECUTE FUNCTION course_bundles_set_updated_at();

-- RLS: published bundles readable to anon/auth, writes restricted to service role
ALTER TABLE course_bundles ENABLE ROW LEVEL SECURITY;
ALTER TABLE bundle_courses ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "course_bundles_read_published" ON course_bundles;
CREATE POLICY "course_bundles_read_published" ON course_bundles
  FOR SELECT USING (status = 'published');

DROP POLICY IF EXISTS "bundle_courses_read_published" ON bundle_courses;
CREATE POLICY "bundle_courses_read_published" ON bundle_courses
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM course_bundles cb
      WHERE cb.id = bundle_courses.bundle_id AND cb.status = 'published'
    )
  );

