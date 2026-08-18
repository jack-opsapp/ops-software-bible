-- Additive enum value for email-pipeline photo attribution.
-- Safe for every deployed client: web narrows unknown sources out of
-- gallery groups; iOS decodes source as a plain string.
alter type public.photo_source add value if not exists 'email';
