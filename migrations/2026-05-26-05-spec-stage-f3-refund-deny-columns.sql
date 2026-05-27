-- Stage F.3 (P1-2-14) — additive columns for the refund queue.
--
-- The Phase 1 base migration `spec_phase1_money_tables.sql` created
-- `spec_refund_requests` without an explicit denial path or internal-note
-- field. Stage F.3 (`/admin/spec/refunds`) needs:
--   - denied_at / denial_reason_text / denied_by_user_id — set when Jackson
--     clicks Deny on a pending request (sends `spec.refund_denied` email).
--   - internal_note — operator-only context attached at process- or deny-time.
--
-- Additive only. Every existing row carries NULL for the new columns. Customer
-- inserts (via /api/account/spec/[id]/request-refund) never populate them —
-- they remain operator-only.
--
-- Bible: SPEC/02_DATA_MODEL.md § spec_refund_requests + SPEC/05_ADMIN_UX.md
-- § /admin/spec/refunds.

alter table public.spec_refund_requests
  add column if not exists denied_at timestamptz,
  add column if not exists denial_reason_text text,
  add column if not exists denied_by_user_id uuid references public.users(id) on delete set null,
  add column if not exists internal_note text;

-- Index to speed the processed-refund detail rail in the operator UI.
create index if not exists spec_refund_requests_status_processed_at_idx
  on public.spec_refund_requests (status, processed_at desc)
  where status in ('processed', 'partial', 'denied', 'failed');
