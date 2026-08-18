-- Out-of-ledger change (executed via execute_sql, no ledger row) 2026-08-18
-- ~05:21 UTC, immediately after the agent-wave Vercel deploy verified Ready.
-- Restores the last deliberately-held outbound revoke from the 2026-08-17
-- deploy pause: EXECUTE on the send-claim RPC returns to service_role,
-- matching the July 20260715162000 grant state. Auto-send remains OFF via the
-- unset INBOX_AUTO_SEND_ENABLED env gate, which is the policy lock.
grant execute on function public.claim_email_send_provider_delivery(uuid) to service_role;
