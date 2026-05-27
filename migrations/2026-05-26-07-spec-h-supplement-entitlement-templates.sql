-- 2026-05-26-07-spec-h-supplement-entitlement-templates.sql
--
-- SPEC Phase 1 — Stage H supplement: register the two entitlement-toggle
-- email templates that F.2.b's toggle-entitlement.ts queues to
-- spec_email_outbox but Stage H's initial batch of 20 (per
-- SPEC/07_ROLLOUT.md § 11) did not include. Mirror of the migration applied
-- to ops-app (project ref: ijeekuhbatykdomumfjx) on 2026-05-27.
--
-- Without these rows, the outbox row queues correctly + the in-app rail
-- notification fires, but the customer-facing email never dispatches because
-- the renderer rejects unregistered template_ids — customers don't learn
-- that their delivered-module access was paused or restored.
--
-- Hashes are sha256 over each template TSX source byte stream at supplement
-- commit time. Same byte-stability contract as
-- 2026-05-26-02-spec-phase1-email-templates.sql — the OPS-Web
-- email:sync-versions build script treats these as unchanged unless the
-- source files are touched.
--
-- Template surface and send-time wiring:
--   • TSX files                  OPS-Web/src/lib/email/react/templates/SpecEntitlement{Disabled,Enabled}.tsx
--   • TEMPLATE_REGISTRY entries  OPS-Web/src/lib/email/template-registry.ts
--   • KIND_TO_LIST (both global) OPS-Web/src/lib/email/constants.ts
--   • Typed sendSpec* senders    OPS-Web/src/lib/email/sendgrid.tsx
--   • Outbox writer (queues row) OPS-Web/src/app/admin/spec/[id]/_actions/toggle-entitlement.ts (F.2.b)
--
-- The disabled-reason branch in spec.entitlement_disabled mirrors the CHECK
-- enum on spec_module_entitlements.disabled_reason — see
-- SPEC/02_DATA_MODEL.md § spec_module_entitlements. The refunded branch is
-- legally sensitive: it explicitly references SPEC ToS § 9 and points the
-- customer at the separate spec.refund_processed notice for the refund
-- itself (so a single email never carries both the disable confirmation and
-- the refund-processed receipt — they remain distinct legal communications).

insert into public.email_template_versions (template_id, version, content_hash, preview_props, notes)
values
  (
    'spec.entitlement_disabled',
    '1.0.0',
    'ca3b38e0b7bd96cdc83fad2629f562fe4f8f6ceebab6eeaa8ded822ea815b904',
    jsonb_build_object(
      'customerName', 'Marcus',
      'moduleKey', 'ai_estimator',
      'moduleLabel', 'Ai Estimator',
      'disabledReason', 'non_payment',
      'tier', 'Build',
      'restoreInstructionsUrl', 'https://opsapp.co/billing/invoices',
      'contactEmail', 'support@opsapp.co'
    ),
    'Phase 1 H-supplement registration. Sent when /admin/spec/[id] Tab 10 toggle disables a delivered module. Body branches on disabled_reason; refund case explicitly references SPEC ToS § 9 and the separate spec.refund_processed notice.'
  ),
  (
    'spec.entitlement_enabled',
    '1.0.0',
    '471329c4c6c496e4629c65c66c348d9774fec002ce0de029a1e495ce818119e2',
    jsonb_build_object(
      'customerName', 'Marcus',
      'moduleKey', 'ai_estimator',
      'moduleLabel', 'Ai Estimator',
      'previousDisabledReason', 'non_payment',
      'tier', 'Build',
      'loginUrl', 'https://opsapp.co/dashboard',
      'contactEmail', 'support@opsapp.co'
    ),
    'Phase 1 H-supplement registration. Sent when /admin/spec/[id] Tab 10 toggle re-enables a previously-disabled module with a CLEARABLE reason. previousDisabledReason is optional — toggle outbox payload sets new disabled_reason=null but does not carry the prior value; dispatcher can enrich from audit_log.old_data.'
  )
on conflict (template_id, version) do nothing;
