-- Inbox data cleanup — Sweep 3: backfill single-open-opp auto-link
--
-- For threads with a client_id but no opportunity_id, if the client has
-- EXACTLY ONE open opportunity (stage not in won/lost/discarded, not archived,
-- not deleted), stamp it. Same rule as the live upsertFromEmail auto-link.

UPDATE email_threads t
SET opportunity_id = o.id, updated_at = NOW()
FROM opportunities o
WHERE t.client_id IS NOT NULL
  AND t.opportunity_id IS NULL
  AND o.client_id = t.client_id
  AND o.company_id = t.company_id
  AND o.stage NOT IN ('won', 'lost', 'discarded')
  AND o.deleted_at IS NULL
  AND o.archived_at IS NULL
  AND (
    SELECT COUNT(*) FROM opportunities o2
    WHERE o2.client_id = t.client_id
      AND o2.company_id = t.company_id
      AND o2.stage NOT IN ('won', 'lost', 'discarded')
      AND o2.deleted_at IS NULL
      AND o2.archived_at IS NULL
  ) = 1;
