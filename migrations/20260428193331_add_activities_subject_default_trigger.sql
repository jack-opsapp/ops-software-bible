-- Auto-populate activities.subject when client omits it.
-- Strategy:
--   1. First non-empty line of content (truncated to 100 chars)
--   2. Fall back to a human-readable label derived from type
--   3. Fall back to 'Activity' as last resort
--
-- Defense in depth — subject is NOT NULL with no default. iOS Log Activity flow
-- did not historically send it, and any future client could miss it too.

CREATE OR REPLACE FUNCTION public.activities_default_subject()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  candidate text;
BEGIN
  IF NEW.subject IS NOT NULL AND btrim(NEW.subject) <> '' THEN
    RETURN NEW;
  END IF;

  -- 1. First non-empty line of content
  IF NEW.content IS NOT NULL AND btrim(NEW.content) <> '' THEN
    candidate := btrim(split_part(NEW.content, E'\n', 1));
    IF candidate <> '' THEN
      NEW.subject := substring(candidate FROM 1 FOR 100);
      RETURN NEW;
    END IF;
  END IF;

  -- 2. Type-derived label
  NEW.subject := CASE NEW.type
    WHEN 'note'                 THEN 'Note'
    WHEN 'email'                THEN 'Email'
    WHEN 'call'                 THEN 'Call'
    WHEN 'meeting'              THEN 'Meeting'
    WHEN 'site_visit'           THEN 'Site visit'
    WHEN 'site_visit_scheduled' THEN 'Site visit scheduled'
    WHEN 'estimate_sent'        THEN 'Estimate sent'
    WHEN 'estimate_accepted'    THEN 'Estimate accepted'
    WHEN 'estimate_declined'    THEN 'Estimate declined'
    WHEN 'invoice_sent'         THEN 'Invoice sent'
    WHEN 'payment_received'     THEN 'Payment received'
    WHEN 'stage_change'         THEN 'Stage change'
    WHEN 'created'              THEN 'Created'
    WHEN 'won'                  THEN 'Won'
    WHEN 'lost'                 THEN 'Lost'
    WHEN 'system'               THEN 'System'
    ELSE 'Activity'
  END;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_activities_default_subject ON public.activities;

CREATE TRIGGER trg_activities_default_subject
BEFORE INSERT ON public.activities
FOR EACH ROW EXECUTE FUNCTION public.activities_default_subject();
