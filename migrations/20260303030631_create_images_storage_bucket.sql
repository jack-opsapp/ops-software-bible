INSERT INTO storage.buckets (id, name, public, file_size_limit)
VALUES ('images', 'images', true, 10485760)
ON CONFLICT (id) DO NOTHING;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Public read images' AND tablename = 'objects') THEN
    CREATE POLICY "Public read images" ON storage.objects FOR SELECT USING (bucket_id = 'images');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Service upload images' AND tablename = 'objects') THEN
    CREATE POLICY "Service upload images" ON storage.objects FOR INSERT WITH CHECK (bucket_id = 'images');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Service delete images' AND tablename = 'objects') THEN
    CREATE POLICY "Service delete images" ON storage.objects FOR DELETE USING (bucket_id = 'images');
  END IF;
END $$;
