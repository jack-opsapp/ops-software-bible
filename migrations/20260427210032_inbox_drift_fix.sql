-- Inbox data cleanup — Sweep 1: thread/opp client_id drift
--
-- When a thread has an opportunity_id pointing to an opp whose client_id
-- differs from the thread's stamped client_id, the opportunity wins. This
-- matches the long-term reconciliation rule applied by attributeOpportunity.
--
-- Counts pre-apply (informational only):
--   SELECT COUNT(*) FROM email_threads t
--   JOIN opportunities o ON o.id = t.opportunity_id
--   WHERE t.client_id IS DISTINCT FROM o.client_id AND o.client_id IS NOT NULL;

UPDATE email_threads t
SET client_id = o.client_id, updated_at = NOW()
FROM opportunities o
WHERE t.opportunity_id = o.id
  AND t.client_id IS DISTINCT FROM o.client_id
  AND o.client_id IS NOT NULL
  AND o.deleted_at IS NULL;
