-- SYNC RECOVERY T1 · M2 grant hardening
-- Supabase ALTER DEFAULT PRIVILEGES auto-grants EXECUTE on new public.* functions
-- to anon, authenticated, service_role. create_opportunity_guarded (the sibling this
-- RPC mirrors) is authenticated + owner only, because prior *_acl_hardening migrations
-- revoked anon/service_role from it. Mirror that exactly so a fresh migration-ledger
-- replay reproduces the same restricted ACL. iOS calls guarded lead/deck RPCs with a
-- Firebase-bridged JWT carrying role=authenticated, so authenticated-only is correct
-- and the function additionally self-authorizes via private.get_current_user_id().

revoke execute on function public.link_deck_design_to_opportunity_guarded(uuid, uuid) from anon;
revoke execute on function public.link_deck_design_to_opportunity_guarded(uuid, uuid) from service_role;
revoke execute on function public.link_deck_design_to_opportunity_guarded(uuid, uuid) from public;
