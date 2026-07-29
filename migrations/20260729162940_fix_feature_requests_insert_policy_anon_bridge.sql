-- Applied to prod ijeekuhbatykdomumfjx 2026-07-29 (SYSTEMS REPAIR W1-3): revive iOS feedback.
-- Old INSERT policy required auth.role()='authenticated'; the Firebase bridge runs as anon,
-- so both iOS flows (ReportIssueView.swift:166-177, WhatsNewView.swift:254-264) were dead —
-- zero "iOS mobile" rows ever. Mirror bug_reports tenancy (company_id = private.get_user_company_id()).
-- iOS payloads omit user_id/company_id entirely, so a BEFORE INSERT trigger stamps both from
-- the resolved bridge identity; RLS WITH CHECK evaluates the post-trigger row, so the
-- tenancy check passes exactly when the requester resolves to a real user with a company.
-- Service-role inserts (submit-feature-request edge fn) bypass RLS and keep explicit values
-- (COALESCE never overwrites; absent JWT stamps NULL).

CREATE OR REPLACE FUNCTION public.feature_requests_stamp_identity()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public', 'pg_temp'
AS $$
BEGIN
  NEW.user_id := COALESCE(NEW.user_id, private.resolve_uid()::text);
  NEW.company_id := COALESCE(NEW.company_id, (private.get_user_company_id())::text);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_feature_requests_00_stamp_identity ON public.feature_requests;
CREATE TRIGGER trg_feature_requests_00_stamp_identity
  BEFORE INSERT ON public.feature_requests
  FOR EACH ROW EXECUTE FUNCTION public.feature_requests_stamp_identity();

DROP POLICY "Users can submit feature requests" ON public.feature_requests;

CREATE POLICY "Users can insert feature requests for their company"
  ON public.feature_requests
  FOR INSERT
  TO anon, authenticated
  WITH CHECK (company_id = (private.get_user_company_id())::text);
