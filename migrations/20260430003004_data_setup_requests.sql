CREATE TABLE data_setup_requests (
  id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id                  UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  requested_by                UUID NOT NULL REFERENCES users(id),
  status                      TEXT NOT NULL DEFAULT 'pending'
                                CHECK (status IN ('pending','scheduled','in_progress','completed','cancelled')),
  scheduled_at                TIMESTAMPTZ,
  completed_at                TIMESTAMPTZ,
  notes                       TEXT,
  stripe_payment_intent_id    TEXT,
  amount_paid_cents           INTEGER,
  source_software             TEXT,
  contact_email               TEXT,
  contact_phone               TEXT,
  created_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_data_setup_requests_company ON data_setup_requests(company_id);
CREATE INDEX idx_data_setup_requests_status  ON data_setup_requests(status);

CREATE UNIQUE INDEX idx_data_setup_requests_stripe_pi
  ON data_setup_requests(stripe_payment_intent_id)
  WHERE stripe_payment_intent_id IS NOT NULL;

CREATE OR REPLACE FUNCTION data_setup_requests_set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at := NOW();
  RETURN NEW;
END;
$$;

CREATE TRIGGER data_setup_requests_updated_at
  BEFORE UPDATE ON data_setup_requests
  FOR EACH ROW EXECUTE FUNCTION data_setup_requests_set_updated_at();

ALTER TABLE data_setup_requests ENABLE ROW LEVEL SECURITY;

CREATE POLICY "data_setup_requests_select_company"
  ON data_setup_requests
  FOR SELECT
  USING (company_id = (SELECT private.get_user_company_id()));

CREATE POLICY "data_setup_requests_insert_company"
  ON data_setup_requests
  FOR INSERT
  WITH CHECK (
    company_id = (SELECT private.get_user_company_id())
    AND requested_by IN (
      SELECT id FROM users
      WHERE auth_id = auth.uid()::text
         OR firebase_uid = auth.uid()::text
    )
  );

CREATE POLICY "data_setup_requests_update_admin"
  ON data_setup_requests
  FOR UPDATE
  USING (
    company_id = (SELECT private.get_user_company_id())
    AND EXISTS (
      SELECT 1 FROM users u
      WHERE (u.auth_id = auth.uid()::text OR u.firebase_uid = auth.uid()::text)
        AND u.company_id = data_setup_requests.company_id
        AND u.is_company_admin = TRUE
    )
  )
  WITH CHECK (
    company_id = (SELECT private.get_user_company_id())
    AND EXISTS (
      SELECT 1 FROM users u
      WHERE (u.auth_id = auth.uid()::text OR u.firebase_uid = auth.uid()::text)
        AND u.company_id = data_setup_requests.company_id
        AND u.is_company_admin = TRUE
    )
  );
