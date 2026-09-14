# Site-visit choice release and jPhone installation

**Both approved steps are complete.** The two database migrations are production-installed; the signed choice-compatible test app is installed on jPhone. Production readback was refreshed on 2026-09-14 UTC, and phone installation was independently verified at 04:12:38 UTC / September 13 local. Company/host MCP write activation remains disabled; no physical-workflow acceptance or App Store release is claimed.

## Exact production ledger

| Approved source | Actual ledger | Bytes | Verified MD5 |
|---|---|---:|---|
| `20260912004121_site_visit_single_choice_v2.sql` | [20260912213224](../../migrations/20260912213224_site_visit_single_choice_v2.sql) | 41,531 | `0b720c6c9d2f77e5d9d74b336e68334e` |
| `20260912203552_site_visit_mcp_choice_coexistence.sql` | [20260912213347](../../migrations/20260912213347_site_visit_mcp_choice_coexistence.sql) | 24,328 | `d96bf1cc1924161b4e0cc364f3e33579` |

The installed ledger statement sizes and MD5s match the reviewed local files. Ledger-named archives are byte-identical to the preserved preparation aliases. Their SHA-256 values remain `0a88823d2bbe0aef8dee75398056de2ed243ad5487140609f1df4a9df8b87b8f` and `bdeb62a50eb1b5ccf9a3a166a43d34a6c534b664dc5c896082bdcdfa203d8fc9`.

Verification independently confirmed twelve installed function-body fingerprints, execute permissions and security settings; nullable/no-default `choice_snapshot jsonb`; the owner-only RLS-enabled private token table; and both enabled choice triggers. Existing checklist RLS fingerprints and stored catalog/financial effect-policy fingerprints remain unchanged. Site-visit compatibility/effect rows remain zero.

The exact 31-assertion coexistence regression suite was rerun successfully before release, including the existing workflow boundary/timezone/discovery and writer-contention checks. In production, all three new phone v2 endpoints rejected unauthenticated calls with SQLSTATE `42501` within a READ ONLY transaction. No test business record was created or changed. Public MCP schemas, scope/consent pins and named-operator review requirements are unchanged.

A broad preflight snapshot was blocked by the safety reviewer. Verification was narrowed to code hashes, permitted schema metadata, counts and security fingerprints; full production function bodies and authority rows were not exported by the rejected check. No attempt was made to bypass it.

## Security-advisor review

The scoped new findings are intentional and reviewed: one private token table with RLS and no runtime grants/policies, plus the three current-actor-guarded phone RPCs executable by the existing `anon`/`authenticated` Firebase-bridge lanes. Role-level execute is not anonymous business authority; the production denial check above proves the unauthenticated entry path fails closed. No new mutable-search-path or extension warning was introduced. Existing unrelated findings remain baseline, not a clean whole-database audit.

References: [private RLS/no-policy advisory](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy), [anonymous executable definer advisory](https://supabase.com/docs/guides/database/database-linter?lint=0028_anon_security_definer_function_executable), [authenticated executable definer advisory](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable). The exact scoped delta is in [the JSON evidence](2026-09-14-site-visit-choice-release.json).

## jPhone installation

Exact signed source `2e46d7285170b7520ee73a7a12be0751b0713c9e`, bundle `co.opsapp.ops.OPS`, version/build 3.0.5, was installed in place on jPhone (iPhone 16 Pro). Signature verification was repeated using normal macOS trust services; the binary SHA-256 remained `99ae6e98834bf5cda03dd92057fc6c5269654a3263da07f7a099c9a536496d38`. The installer exited 0. A separate device app inventory exited 0 and matched the new bundle location from the install receipt, distinct from the prior installation.

The initial permission-review timeout never started installation; a later device connection failed before transfer. A bounded retry succeeded once the phone was reachable. OPS was not uninstalled or automatically launched, and no direct local-store/outbox edits were made. This does not prove offline/reconnect/conflict/media or complete signed-in workflow behavior.

iOS evidence commit `b34a142b2365cf44fee491f9304b7826a4658310` records sanitized installation proof in `docs/artifacts/phase19/choice-device-install-20260914.{md,json}`. Raw device receipts remain in the session's private temporary build directory. The older signed app and all original test artifacts are preserved.

## Still separate

The subsequent [native-host readiness check](2026-09-14-site-visit-host-readiness.md) confirms that the restricted site-visit OAuth trial path still needs implementation. The native connector is bound to Canpro while the independent OPS web session is signed into MAVERICK; reconnecting alone does not activate V22. Company compatibility/effect tables remain empty at the fresh September 14 check.

Exact company compatibility/effect and host actor/client/grant activation; signed-in native-host prepare → OPS review → save → independent readback/revocation; physical-device offline/reconnect/conflict/media acceptance; and App Store distribution remain separate. Expense migrations, provider messages, effect resealing and web push/deploy were not performed. No subscription or paid API setting changed; this record does not claim measured zero infrastructure cost. The detailed cross-task handoff was not sent after a privacy review rejected it.
