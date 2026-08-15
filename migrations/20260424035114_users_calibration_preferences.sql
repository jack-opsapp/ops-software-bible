-- Ensure users.preferences JSONB column exists for per-user preference flags.
-- Calibration uses preferences.calibrationFirstRunDismissed to track explicit
-- "skip all three sources" dismissal, distinct from "not yet completed."

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'users'
      AND column_name = 'preferences'
  ) THEN
    ALTER TABLE public.users ADD COLUMN preferences JSONB NOT NULL DEFAULT '{}'::jsonb;
    COMMENT ON COLUMN public.users.preferences IS
      'Per-user preferences. Keys include calibrationFirstRunDismissed (bool) for the CALIBRATION first-run wizard dismissal state.';
  END IF;
END $$;
