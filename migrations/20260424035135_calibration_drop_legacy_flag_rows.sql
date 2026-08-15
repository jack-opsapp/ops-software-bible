-- Single-tenant cleanup: delete the superseded ai_email_review rows now that
-- phase_c rows are authoritative.
DELETE FROM admin_feature_overrides
WHERE feature_key = 'ai_email_review';
