-- Workstream C (iOS) realtime enablement — applied to prod ijeekuhbatykdomumfjx 2026-06-02.
--
-- The iOS app subscribes to expense_batches (and already to expenses) over Supabase
-- Realtime so envelope status flips (filling → with the office, auto-approved) and
-- line-state / total changes render live in the review hub + crew list. Neither table
-- was in the supabase_realtime publication, so those subscriptions delivered nothing
-- (the existing expenses subscription was silently dead). Realtime-filtered tables
-- also need REPLICA IDENTITY FULL so company_id is present on UPDATE/DELETE WAL records
-- for the company_id=eq filter — matching how projects/notifications are configured.
--
-- Additive + reversible; no data change. Negligible cost (realtime messages only).

alter table public.expenses        replica identity full;
alter table public.expense_batches replica identity full;
alter publication supabase_realtime add table public.expenses;
alter publication supabase_realtime add table public.expense_batches;
