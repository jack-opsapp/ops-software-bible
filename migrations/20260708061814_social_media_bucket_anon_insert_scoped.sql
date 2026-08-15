-- Allow anon (and authenticated) clients to upload images into the public
-- social-media marketing bucket. Scoped to the known content prefixes and
-- INSERT-only (no overwrite/delete). The bucket itself already enforces
-- image/* mime types and a 10 MB size limit. This restores the automated
-- social scheduled-task upload pipeline, which previously depended on the
-- service-role key that scheduled runs do not carry.
create policy "social-media anon image upload (scoped, insert-only)"
on storage.objects
for insert
to anon, authenticated
with check (
  bucket_id = 'social-media'
  and (storage.foldername(name))[1] = any (array[
    'stories',
    'blog-carousel',
    'opp',
    'feature-release',
    'photos',
    'custom',
    'feature-spotlight',
    'insight'
  ])
);
