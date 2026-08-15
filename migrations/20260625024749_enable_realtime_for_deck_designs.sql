-- Enable Supabase Realtime postgres_changes for deck_designs so crew see a
-- teammate's deck edits live. REPLICA IDENTITY FULL is required for the
-- company_id=eq filter to match on UPDATE/DELETE (default = PK only would drop
-- filtered delete/old-value events). Table is small (~528 kB / 71 rows), so the
-- extra WAL per change is negligible.
ALTER TABLE public.deck_designs REPLICA IDENTITY FULL;
ALTER PUBLICATION supabase_realtime ADD TABLE public.deck_designs;
