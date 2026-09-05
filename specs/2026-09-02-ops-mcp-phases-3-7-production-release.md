# OPS MCP Phases 3–7 Production Release

- **Release date:** 2026-09-02
- **OPS-Web release commit:** `a763f1a0e4cc431abd4e9e7bc873a69470c0379f`
- **Current production descendant:** `dd187ba32d1c0e8dcee21f0ea1434eb948357393`
- **Current Vercel deployment:** `dpl_AQfJGzTsQ6XS65RWptFBgD4isQXR` (`READY`)
- **Production alias:** `app.opsapp.co`

## Outcome

Invisible Office Phases 3–7 are production-released as dormant capability code and database contracts:

1. `analyze_hiring_break_even` — read-only hiring what-if;
2. `check_customer_reply` — read-only promise recovery;
3. `analyze_sales_truth` — read-only sales truth;
4. `check_payroll_readiness` — read-only payroll readiness; and
5. `prepare_recurring_service_price_change` — ephemeral high-risk preparation with no commit or send sibling.

Release is not activation. Production OAuth metadata remains immutable read-only exposure `2026-08-29.mcp-exposure.v2`. Exposures v5–v9 have zero clients and zero grants. No outside host has accepted these capabilities, and no customer has received their authority.

## Applied database ledger

| Ledger | SHA-256 |
|---|---|
| `20260902194603_agent_hiring_what_if_read` | `7577174090a66ccfac3279b578740bc7cb2239efcb1c4266c206a20eb06d65a5` |
| `20260902194631_agent_promise_recovery_read` | `6d98e07d67eda2cf4e8e350ba80bdc1d6b62eb04512ee9d8318e0233a244e538` |
| `20260902194703_agent_sales_truth_read` | `88eb84718a015b7c5428fffafa087692b8890e8dc8fabd022d0069f6b09badab` |
| `20260902194727_agent_payroll_readiness` | `77a355c27dd5f4ddeadd2e5cd82009be90a7d3a470c268c573f294307b83d7b7` |
| `20260902194758_agent_recurring_service_price_change` | `e93302dbb1fae57ce61e8a0f63cb2c2e9f72b76f5bd6b5e8ae1b9f925af69f24` |
| `20260902195149_agent_recurring_service_price_index_dedupe` | `c0b508d63053e4f05fe6bdde368678d20488d892346760d136adf090825ad20a` |
| `20260902195335_agent_recurring_service_price_fk_indexes` | `7c3d48c88fc576e175c6a48dca17e857a14259f068962a0327b066c09e106344` |

Every archive in `migrations/` is byte-identical to its corresponding committed source in `supabase/migrations/` and to the SQL submitted to the production migration API.

The first hiring migration attempt failed closed before commit because the live company source uses `currency_code`, not obsolete `currency`. The source guard made no production change. The candidate and its fixture/hash proof were corrected to the live schema, retested, committed, and then applied successfully.

The post-apply performance advisor found one redundant provider-delivery index and four policy foreign keys without their own leading indexes. The two final migrations removed only the definition-equivalent duplicate and added the four exact B-tree indexes. Follow-up advisor output contains no release-related duplicate-index or unindexed-foreign-key finding. Newly created indexes are reported as unused immediately after creation, which is expected while the exposures remain dormant.

## Authority and data proof

Production catalog readback found six Phase 3–7 public RPCs, including the separate final Phase 7 authority assertion. Every RPC is owned by `postgres`, is `SECURITY DEFINER`, has a pinned search path, denies execute to `anon` and `authenticated`, and grants execute only to `service_role` and the database owner. Direct `anon` and `authenticated` reads of `private.mcp_oauth_clients` and `private.mcp_oauth_grants` remain denied.

After deployment:

- active v1: seven clients and two grants;
- active v2: one client and one grant;
- v5–v9: zero clients and zero grants;
- recurring-service price policies: zero rows;
- users: 217, companies: 64, recurring expenses: 0, OAuth clients: 11, OAuth grants: 3 — unchanged from preflight; and
- the four nullable payroll-evidence columns exist with no defaults, preserving every existing row.

Supabase security advice contains one release-related informational notice: the private recurring-price policy table has RLS enabled with no policy. This is deliberate deny-by-default design; direct app-role table privileges are revoked and independently read back as false. Remediation reference: https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy.

## Application and live proof

The combined changed-file release suite passed 426 tests across 39 files, with 12 intentionally skipped disposable-database cases. TypeScript, changed-file ESLint, `git diff --check`, the focused Phase 3/7 repair regressions, and the complete Next.js production build passed. Earlier broad-suite runs retained machine-contention timeouts in unrelated fixed-timeout tests; focused reruns and the release suite passed.

Vercel built the exact release commit successfully in deployment `dpl_8F3LWncCSY2b8WEBoXuYPoXV87Ev`. A concurrent, unrelated mainline integration then advanced production to descendant `dd187ba32d1c0e8dcee21f0ea1434eb948357393`; ancestry verification proves that descendant contains the complete release. Vercel built the descendant successfully in deployment `dpl_AQfJGzTsQ6XS65RWptFBgD4isQXR`, marked it `READY`, and attached `app.opsapp.co`. Fresh live probes against that current production deployment verified:

- OAuth authorization-server metadata: HTTP 200 with only the established 20 read scopes;
- OAuth protected-resource metadata: HTTP 200 with the same read ceiling;
- unauthenticated `POST /api/mcp`: HTTP 401, standards-compliant Bearer challenge, and body `{"error":"unauthorized"}`; and
- no `/api/mcp` runtime error cluster in the release window.

The exact deployment also observed concurrent pre-existing failures on `/api/calibration/deck` and `/api/cron/email-sync`. They are outside this MCP release and are not evidence of an MCP regression; this release does not claim whole-application production health.

## Cost and next gate

The release adds no subscription, model call, scheduled job, provider request, or fixed vendor cost. It uses ordinary existing Vercel build/runtime allocation and Supabase storage, compute, and index maintenance. Since the new exposures remain dormant, they generate no capability traffic.

The next gate is a separately controlled host-acceptance and activation decision. It must create only the exact intended client/grant, run an authenticated host matrix, and independently prove revocation and dormant-to-active authority. That gate is not part of this release.
