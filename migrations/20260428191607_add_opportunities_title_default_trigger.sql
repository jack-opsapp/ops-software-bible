-- Auto-populate opportunities.title from contact_name when title is null/empty.
-- Defense in depth: title is NOT NULL, but clients sometimes forget to send it.
-- Falls back to 'New Lead' if both title and contact_name are empty.

CREATE OR REPLACE FUNCTION public.opportunities_default_title()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.title IS NULL OR btrim(NEW.title) = '' THEN
    NEW.title := COALESCE(NULLIF(btrim(NEW.contact_name), ''), 'New Lead');
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_opportunities_default_title ON public.opportunities;

CREATE TRIGGER trg_opportunities_default_title
BEFORE INSERT ON public.opportunities
FOR EACH ROW EXECUTE FUNCTION public.opportunities_default_title();
