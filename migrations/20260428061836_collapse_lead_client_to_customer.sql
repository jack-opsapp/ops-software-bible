
-- Collapse LEAD + CLIENT primary_category values to CUSTOMER.
--
-- Rationale: the lead-vs-client distinction was double-encoded — once at the
-- thread category level (LEAD/CLIENT) and once at the linked opportunity stage.
-- The inbox bucket layer (JOBS vs LEADS) handles the user-facing distinction;
-- the category becomes a unified CUSTOMER tag.
--
-- Also updates the CHECK constraint on email_threads.primary_category to
-- replace LEAD/CLIENT with CUSTOMER in the valid-values list.
--
-- Idempotent: running multiple times leaves CUSTOMER values untouched; the
-- constraint drop/add is safe because the name is deterministic.

-- Step 1 — Relax the CHECK constraint so the UPDATE can proceed.
ALTER TABLE email_threads
  DROP CONSTRAINT IF EXISTS email_threads_primary_category_check;

-- Step 2 — Migrate existing rows.
UPDATE email_threads
SET primary_category = 'CUSTOMER'
WHERE primary_category IN ('LEAD', 'CLIENT');

-- Step 3 — Add the new constraint with CUSTOMER replacing LEAD/CLIENT.
ALTER TABLE email_threads
  ADD CONSTRAINT email_threads_primary_category_check
  CHECK (primary_category = ANY (ARRAY[
    'CUSTOMER',
    'VENDOR',
    'SUBTRADE',
    'PLATFORM_BID',
    'LEGAL',
    'JOB_SEEKER',
    'COLLECTIONS',
    'MARKETING',
    'RECEIPT',
    'PERSONAL',
    'INTERNAL',
    'OTHER'
  ]));

-- Step 4 — Backfill the corrections history table (no constraint to worry about).
UPDATE email_thread_category_corrections
SET from_category = 'CUSTOMER'
WHERE from_category IN ('LEAD', 'CLIENT');

UPDATE email_thread_category_corrections
SET to_category = 'CUSTOMER'
WHERE to_category IN ('LEAD', 'CLIENT');

