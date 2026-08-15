-- Add 'voice_log' as a valid opportunity source. Used by iOS Log Activity quick-capture flow
-- when the user creates a new lead inline while logging a voice-driven activity.

ALTER TABLE public.opportunities
  DROP CONSTRAINT IF EXISTS opportunities_source_check;

ALTER TABLE public.opportunities
  ADD CONSTRAINT opportunities_source_check
  CHECK (source = ANY (ARRAY[
    'referral'::text,
    'website'::text,
    'email'::text,
    'phone'::text,
    'walk_in'::text,
    'social_media'::text,
    'repeat_client'::text,
    'voice_log'::text,
    'other'::text
  ]));
