
-- RPC function to get cron job statuses
CREATE OR REPLACE FUNCTION get_email_cron_status()
RETURNS TABLE(jobname text, schedule text, active boolean)
LANGUAGE sql
SECURITY DEFINER
AS $$
  SELECT j.jobname, j.schedule, j.active
  FROM cron.job j
  WHERE j.jobname IN (
    'lifecycle-emails-daily',
    'bubble-reauth-emails-daily',
    'unverified-emails-daily',
    'newsletter-monthly'
  )
  ORDER BY j.jobname;
$$;

-- RPC function to toggle a cron job
CREATE OR REPLACE FUNCTION toggle_email_cron(p_jobname text, p_active boolean)
RETURNS TABLE(jobname text, active boolean)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  IF p_jobname NOT IN (
    'lifecycle-emails-daily',
    'bubble-reauth-emails-daily',
    'unverified-emails-daily',
    'newsletter-monthly'
  ) THEN
    RAISE EXCEPTION 'Invalid job name: %', p_jobname;
  END IF;

  UPDATE cron.job SET active = p_active WHERE cron.job.jobname = p_jobname;

  RETURN QUERY SELECT j.jobname, j.active FROM cron.job j WHERE j.jobname = p_jobname;
END;
$$;

