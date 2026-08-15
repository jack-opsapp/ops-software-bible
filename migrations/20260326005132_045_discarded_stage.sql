ALTER TABLE opportunities DROP CONSTRAINT IF EXISTS opportunities_stage_check;
ALTER TABLE opportunities ADD CONSTRAINT opportunities_stage_check
  CHECK (stage IN ('new_lead','qualifying','quoting','quoted','follow_up','negotiation','won','lost','discarded'));
