INSERT INTO storage.buckets (id, name, public)
VALUES ('product-thumbnails', 'product-thumbnails', true)
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS "Anyone can view product thumbnails" ON storage.objects;
CREATE POLICY "Anyone can view product thumbnails"
  ON storage.objects
  FOR SELECT
  USING (bucket_id = 'product-thumbnails');

DROP POLICY IF EXISTS "Company members can upload product thumbnails" ON storage.objects;
CREATE POLICY "Company members can upload product thumbnails"
  ON storage.objects
  FOR INSERT
  WITH CHECK (
    bucket_id = 'product-thumbnails'
    AND auth.role() = 'authenticated'
  );

DROP POLICY IF EXISTS "Company members can update product thumbnails" ON storage.objects;
CREATE POLICY "Company members can update product thumbnails"
  ON storage.objects
  FOR UPDATE
  USING (
    bucket_id = 'product-thumbnails'
    AND auth.role() = 'authenticated'
  )
  WITH CHECK (
    bucket_id = 'product-thumbnails'
    AND auth.role() = 'authenticated'
  );

DROP POLICY IF EXISTS "Company members can delete product thumbnails" ON storage.objects;
CREATE POLICY "Company members can delete product thumbnails"
  ON storage.objects
  FOR DELETE
  USING (
    bucket_id = 'product-thumbnails'
    AND auth.role() = 'authenticated'
  );
