-- 2026-05-27-01-spec-h-supplement-cron-templates.sql
--
-- SPEC Phase 1 — Stage H supplement (round 2): register the three email
-- templates that C.5's owner-approval-expiry + customer_requested
-- hold-expiry crons queue to spec_email_outbox but Stage H's initial
-- batch of 20 (per SPEC/07_ROLLOUT.md § 11) and the P1-2-19 batch
-- (entitlement toggles, mirrored at
-- 2026-05-26-07-spec-h-supplement-entitlement-templates.sql) did not
-- include. Closes the gap flagged by Stage I verification report
-- § P1-2-18-3 before the SPEC_LIVE_DEPOSITS_ENABLED flag flip. Mirror
-- of the migration applied to ops-app (project ref: ijeekuhbatykdomumfjx)
-- on 2026-05-27.
--
-- Without these rows, the outbox row queues correctly + the in-app rail
-- notification fires, but the customer-facing email never dispatches
-- because the renderer rejects unregistered template_ids. The buyer
-- never learns their owner-approval request timed out; the
-- account_holder never learns the buyer request was cancelled; the
-- customer never learns their 90-day pause hit stalled state.
--
-- Hashes are sha256 over each template TSX source byte stream at
-- supplement commit time. Same byte-stability contract as
-- 2026-05-26-02-spec-phase1-email-templates.sql — the OPS-Web
-- email:sync-versions build script treats these as unchanged unless the
-- source files are touched.
--
-- Template surface and send-time wiring:
--   • TSX files                  OPS-Web/src/lib/email/react/templates/
--                                  SpecOwnerApprovalExpiredBuyer.tsx
--                                  SpecOwnerApprovalExpiredOwner.tsx
--                                  SpecHoldExpiredCustomerRequested.tsx
--   • TEMPLATE_REGISTRY entries  OPS-Web/src/lib/email/template-registry.ts
--   • KIND_TO_LIST (all global)  OPS-Web/src/lib/email/constants.ts
--   • Typed sendSpec* senders    OPS-Web/src/lib/email/sendgrid.tsx
--   • Outbox writers (queue rows)
--       ops-site/src/lib/spec/cron/owner-approval-expiry.ts (buyer + owner)
--       ops-site/src/lib/spec/cron/hold-expiry.ts (customer_requested)
--
-- All three templates carry no-emoji, no-exclamation OPS tactical voice.
-- The hold-expiry template stays neutral between resume and Guarantee
-- Refund (operator-side action remains manual). The owner-expired
-- template tells the account_holder they can self-initiate at /spec
-- without waiting for a new team-member request.
--
-- Voice notes (see SPEC/03_WORKFLOW.md § Owner approval token expires
-- and § Customer-requested pause for the underlying state-machine
-- semantics these templates announce):
--   • spec.owner_approval_expired_buyer — restart path is the active
--     CTA. 7-day window is communicated as a hard rule.
--   • spec.owner_approval_expired_owner — purely informational. Sign-in
--     mention is inline text only (no primary button). Mirrors the
--     SpecOwnerApprovalDeclined pattern.
--   • spec.hold_expired_customer_requested — no primary button by
--     design. Two paths (resume / Guarantee Refund) are named
--     neutrally. References SPEC ToS § 9 for refund terms.

insert into public.email_template_versions (template_id, version, content_hash, preview_props, notes)
values
  (
    'spec.owner_approval_expired_buyer',
    '1.0.0',
    '9444d4c18182d74a4aba790bb0801d111b8c708acd6b7d7c05a1876f3268cd1c',
    jsonb_build_object(
      'buyerName', 'Sam Reyes',
      'accountHolderName', 'Marcus',
      'companyName', 'CanPro Deck and Rail',
      'tier', 'Build',
      'originalRequestedAt', 'May 20, 2026',
      'retryUrl', 'https://opsapp.co/spec'
    ),
    'Phase 1 H-supplement (round 2). Sent to a Path B team-member buyer when the 7-day owner-approval window closes without a decision. No charge fired; offers a restart path. Queued by ops-site/src/lib/spec/cron/owner-approval-expiry.ts with payload { spec_project_id, tier } — dispatcher hydrates buyerName/accountHolderName/companyName/originalRequestedAt/retryUrl from spec_projects + spec_owner_approval_requests + users.'
  ),
  (
    'spec.owner_approval_expired_owner',
    '1.0.0',
    '1ee7d83fa28c5547db08e8d9c24734ffdb1b52387860d12bc341964669a969bd',
    jsonb_build_object(
      'accountHolderName', 'Marcus',
      'buyerName', 'Sam Reyes',
      'companyName', 'CanPro Deck and Rail',
      'tier', 'Build',
      'originalRequestedAt', 'May 20, 2026'
    ),
    'Phase 1 H-supplement (round 2). Sent to the account_holder whose team-member SPEC purchase request expired without their decision. Informational only — no charge fired, buyer was notified separately, and the account_holder can self-initiate at /spec. Queued by ops-site/src/lib/spec/cron/owner-approval-expiry.ts with payload { spec_project_id, tier, buyer_name } — dispatcher hydrates accountHolderName/companyName/originalRequestedAt from spec_projects + users.'
  ),
  (
    'spec.hold_expired_customer_requested',
    '1.0.0',
    'bba1e4c0f1e4bc3730d0288441ec981c8035f535a5904fe5147072daf548d60d',
    jsonb_build_object(
      'customerName', 'Marcus',
      'tier', 'Build',
      'holdEnteredAt', 'Feb 25, 2026',
      'priorStatus', 'Building',
      'contactEmail', 'jack@opsapp.co'
    ),
    'Phase 1 H-supplement (round 2). Sent when a customer_requested SPEC hold reaches the 90-day cap and the project flips to stalled_on_hold. Voice posture: neutral state-of-affairs — names BOTH resume and Guarantee Refund paths without pushing either. Operator-side action stays manual. Queued by ops-site/src/lib/spec/cron/hold-expiry.ts with payload { spec_project_id, tier } — dispatcher hydrates customerName/holdEnteredAt/priorStatus/contactEmail from spec_projects.'
  )
on conflict (template_id, version) do nothing;
