CREATE OR REPLACE FUNCTION initialize_company_trial()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.trial_end_date IS NULL THEN
    NEW.subscription_status := COALESCE(NEW.subscription_status, 'trial');
    NEW.subscription_plan   := COALESCE(NEW.subscription_plan, 'trial');
    NEW.trial_start_date    := COALESCE(NEW.trial_start_date, NOW());
    NEW.trial_end_date      := NOW() + INTERVAL '30 days';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
