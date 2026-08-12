-- Auto-bump gmail_scan_jobs.updated_at on every row update.
-- Prior to this trigger, the app only wrote `progress` and `status` fields,
-- leaving updated_at pinned to the insert time. That broke staleness checks
-- and made it impossible to filter jobs by recent activity.
CREATE OR REPLACE FUNCTION public.bump_gmail_scan_jobs_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_gmail_scan_jobs_updated_at ON public.gmail_scan_jobs;

CREATE TRIGGER trg_gmail_scan_jobs_updated_at
BEFORE UPDATE ON public.gmail_scan_jobs
FOR EACH ROW
EXECUTE FUNCTION public.bump_gmail_scan_jobs_updated_at();
