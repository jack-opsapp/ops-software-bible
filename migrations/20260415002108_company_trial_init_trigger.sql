CREATE OR REPLACE FUNCTION initialize_company_trial()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.subscription_status IS NULL AND NEW.trial_end_date IS NULL THEN
    NEW.subscription_status := 'trial';
    NEW.subscription_plan   := COALESCE(NEW.subscription_plan, 'trial');
    NEW.trial_start_date    := COALESCE(NEW.trial_start_date, NOW());
    NEW.trial_end_date      := NOW() + INTERVAL '30 days';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS initialize_company_trial_trigger ON companies;

CREATE TRIGGER initialize_company_trial_trigger
BEFORE INSERT ON companies
FOR EACH ROW
EXECUTE FUNCTION initialize_company_trial();
