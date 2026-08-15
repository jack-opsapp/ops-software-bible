-- Inbox data cleanup — Sweep 2: threads bound to soft-deleted clients
--
-- Sets email_threads.client_id = NULL when the linked client has
-- deleted_at != NULL. The next sync pass through resolveClientIdFromEmails
-- (which now filters deleted_at IS NULL) will re-resolve from current data,
-- or the user will see the "no client linked" toast and quick-create one.
--
-- This intentionally does NOT touch threads bound to active clients via
-- soft-deleted sub_clients (a more nuanced case requiring participant
-- re-evaluation). That case is rarer and resolves itself on next inbound
-- via the resolver's deleted_at filter (added in P1.3).

UPDATE email_threads t
SET client_id = NULL, updated_at = NOW()
FROM clients c
WHERE t.client_id = c.id
  AND c.deleted_at IS NOT NULL;
