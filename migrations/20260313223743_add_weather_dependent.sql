ALTER TABLE companies
  ADD COLUMN IF NOT EXISTS weather_dependent BOOLEAN DEFAULT NULL;

COMMENT ON COLUMN companies.weather_dependent
  IS 'Whether the company work is weather-dependent (set during onboarding)';
