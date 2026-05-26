-- 2026-05-26-01-spec-phase1-email-templates.sql
--
-- SPEC Phase 1 email templates — initial registration in
-- public.email_template_versions. Mirrors the migration applied to ops-app
-- (project ref: ijeekuhbatykdomumfjx) on 2026-05-26 from Stage H.
--
-- Hashes are sha256 over each template TSX source byte stream at Stage H
-- commit time. The OPS-Web `email:sync-versions` build script will treat
-- these as 'unchanged' on its next run as long as the source files have
-- not been touched. Any source-content change without a corresponding
-- @template-version bump triggers a CI hash-mismatch failure (this is the
-- gate that keeps the rendered output byte-stable per version).
--
-- Template surface and send-time wiring:
--   • TSX files                  OPS-Web/src/lib/email/react/templates/Spec*.tsx
--   • TEMPLATE_REGISTRY entries  OPS-Web/src/lib/email/template-registry.ts
--   • KIND_TO_LIST (all global)  OPS-Web/src/lib/email/constants.ts
--   • Typed sendSpec*() senders  OPS-Web/src/lib/email/sendgrid.tsx
--
-- Send-triggers (cron + webhook + intake submit) are wired in Stage C/D —
-- this migration only registers the templates so the build can validate
-- them and the admin email-template UI can render the version timeline.

insert into public.email_template_versions (template_id, version, content_hash, notes)
values
  ('spec.owner_approval_required',           '1.0.0', '110cd6db5ed1bfd414282e6a5f44ef0a09296412d5ea324cce1a1c1721cf3cc3', 'Phase 1 initial registration — Stage H. Sent to account_holder when buyer != account_holder.'),
  ('spec.owner_approval_granted',            '1.0.0', '7378faf9bc2d23f0bb743e2c6941b2fc000fbfb6dcd0190538d68fa45de52b38', 'Phase 1 initial registration — Stage H. Sent to buyer after account_holder approves; checkout link expires in 24h.'),
  ('spec.owner_approval_declined',           '1.0.0', '3b12560f0cfadad85addced2596d571de8e15031cec7722b8ea66ffb7bda69c3', 'Phase 1 initial registration — Stage H. Sent to buyer after account_holder declines; no charge ever made.'),
  ('spec.deposit_confirmed',                 '1.0.0', 'e03a4fc17690f043627ba3972c671beed8110afa8d9d4f2c0ab93bfcefe44901', 'Phase 1 initial registration — Stage H. Sent to buyer after Stripe deposit clears.'),
  ('spec.quebec_rejected_post_stripe',       '1.0.0', '324756913c1aa3dfcb196323c39fc16d6826ef4b27c95ed65a9606ea862ed9fb', 'Phase 1 initial registration — Stage H. Sent when Stripe webhook catches a QC billing-address leak post-checkout.'),
  ('spec.intake_reminder_1',                 '1.0.0', '39f251594d5b41f876380a167f0cd56dd6fa04d175516c683db8875004e93e61', 'Phase 1 initial registration — Stage H. D14 post-deposit nudge — SPEC INTAKE WAITING.'),
  ('spec.intake_reminder_2',                 '1.0.0', 'c055fc90ade622e006ff56d024fe438c74ed5484eaab2520ce3903ef939546e0', 'Phase 1 initial registration — Stage H. D30 post-deposit — SPEC PAUSED.'),
  ('spec.intake_reminder_3',                 '1.0.0', '68ae9519392ad24b6f488e122532151697afdba3faeae1270f4b2ff3154183ce', 'Phase 1 initial registration — Stage H. D60 post-deposit final — SPEC FINAL CHECK-IN.'),
  ('spec.intake_completed_customer',         '1.0.0', 'f24d67ed7d41889768a9b087c7cff1a50f1261d6b23889ca8d206f482ef95526', 'Phase 1 initial registration — Stage H. Sent to buyer immediately after intake submission with Calendly discovery link.'),
  ('spec.intake_completed_no_discovery_1',   '1.0.0', '23fda5178d69d7bb545443ceec1b6c6624688e769bf85e675d8d3a45b31ce0c6', 'Phase 1 initial registration — Stage H. D7 post-intake if no discovery scheduled.'),
  ('spec.intake_completed_no_discovery_2',   '1.0.0', '73a0d54603561ee4e49a6c2f2d118f87e2c293415e82d4c0046a20cc7f506b90', 'Phase 1 initial registration — Stage H. D21 post-intake if no discovery scheduled — SPEC PAUSED.'),
  ('spec.intake_completed_no_discovery_3',   '1.0.0', '286ee3e0ea3e019af962bffdc26fcdaad642ff239ce084676bb37a3e8da6acfe', 'Phase 1 initial registration — Stage H. D60 post-intake final.'),
  ('spec.scope_doc_ready',                   '1.0.0', '4c470ebea6df00893ebdd2b87bb47291121c18a6d516ab267cbb3dd72f6d493f', 'Phase 1 initial registration — Stage H. Sent to buyer when scope document is drafted and ready for countersignature.'),
  ('spec.scope_doc_signed_customer',         '1.0.0', '5f04b422403c11d412f2575366758d323bcc053e9799b21927de656152106499', 'Phase 1 initial registration — Stage H. Sent to buyer after scope countersignature — build kicks off, P2 invoice incoming.'),
  ('spec.p2_invoice',                        '1.0.0', '49cb87ec552a4efc6b032beef639a533c29f17b852895d4b397bf9537c589444', 'Phase 1 initial registration — Stage H. P2 milestone invoice (scope sign-off).'),
  ('spec.p3_invoice',                        '1.0.0', 'fb7c514533b4b50763f3858f653061818999ccaaaf55fd16844c3c50f4ec1a86', 'Phase 1 initial registration — Stage H. P3 milestone invoice (midpoint accepted).'),
  ('spec.p4_invoice',                        '1.0.0', 'eb83fb5b6b1714036bfad3a32637e5182fdc031538bbd62dad9bc1beb1757b2d', 'Phase 1 initial registration — Stage H. P4 milestone invoice (post-walkthrough, includes 30-day Guarantee anchor).'),
  ('spec.support_window_open',               '1.0.0', '23b25485d602a720e861ced80f58789210e8f8fb4d65eedf0fae540c2f7e4fe5', 'Phase 1 initial registration — Stage H. Sent the day after walkthrough; Support Window + Guarantee Period both running.'),
  ('spec.refund_processed',                  '1.0.0', '5e6132209e824be59451d5f56efae7e8e5596746a6f1469e0919bdbf14a1d3c8', 'Phase 1 initial registration — Stage H. Per-milestone refund breakdown rendered inline as a table.'),
  ('spec.refund_denied',                     '1.0.0', 'f993e24e5b4a4b690881f51e980e2415d6e291ea9de5a64d8c79a0b97e76558d', 'Phase 1 initial registration — Stage H. Reason text + appeal path to founder.')
on conflict (template_id, version) do nothing;
