ALTER TABLE products
  ADD COLUMN IF NOT EXISTS thumbnail_url text;

COMMENT ON COLUMN products.thumbnail_url IS
  'Optional product thumbnail. Stored as a Supabase Storage public URL pointing into the product-thumbnails bucket. NULL = no image.';
