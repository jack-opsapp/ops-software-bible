# Phase16 production release — 2026-09-08

Software and both database migrations are released. Financial authority remains disabled.

- [Release verification](release-verification.json): exact production source/deployment, final database checks, live HTTP boundaries, focused test/build proof and authority exclusions.
- [Preflight](production-preflight.json): unchanged baseline data and exact function prerequisite checks.
- [Migration readback](production-postflight.json): actual ledger versions and SQL hashes, RLS/privileges, zero activation state and intentionally stale effect approval.
- [Contract](../../../../specs/2026-09-08-ops-mcp-financial-readiness.md): business behavior and separate host-trial gates.

Actual production migration mirrors are `20260908054740_financial_policy_readiness.sql` and `20260908054759_financial_trial_oauth.sql`; their bytes match the corresponding source-named mirrors.

The 670 regression tests, nine real local protocol scenarios, eight focused owner-policy tests and 160 SQL assertions are overlapping validation groups, not a combined count. All local fixtures were fictional and removed. No authenticated Claude or ChatGPT financial trial has occurred.

Normal OAuth usage can update `last_used_at`. The final grant authority digest excludes only that usage field and matches the preflight; grants were not upgraded or activated by this release.
