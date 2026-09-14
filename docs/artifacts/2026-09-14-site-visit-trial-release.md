# Restricted site-visit trial release — 2026-09-14

Jackson approved finishing and activating the MAVERICK-only trial while preserving exact OPS save approval and leaving Canpro untouched. Implementation and release proceed separately from company compatibility enrollment, host consent, and physical-device acceptance.

## Implementation and bounded proof

Web implementation `75b9faf46`, current callback fixture `85ab0867f`. Independent Astra review found one approval-queue regression; the reproduced failure was fixed by preserving the proposal's original OAuth identity while refreshing current permissions. Both visibility helper assertions pass; the reviewer closed the finding. Bearer validation also retains the existing secondary exact-subject check for V22.

The exact release was based on current remote production `61cc787f9`, not the shared local main's unrelated unreleased commits. Release commits are `5fb5d844f`, `517a2bad9`, and `0086cd591` (archives the two already-applied choice dependencies without applying them again). The MCP/application dependency paths match the tested implementation. Exact release verification passed 802 tests across 20 files, both focused TypeScript configurations, and 53 actual PostgreSQL assertions using synthetic local records.

SQL coverage includes actual consent preview, authorization-code consumption and grant minting, current subject binding, exact review/save, queue visibility, idempotent replay, cross-actor/company denial, no internal/API write escape, immutable two-hour bindings, separate OAuth and workflow seals, permission/compatibility loss, real wall-clock expiry, refresh/revocation, and byte-identical unrelated public V14/V23 client/grant/token preservation. These are not native Claude/ChatGPT/Codex acceptance claims.

## Production database

- Applied at **2026-09-14 20:34 UTC** under ledger version **20260914203418**, name `site_visit_oauth_trial`.
- Source alias: web `supabase/migrations/20260914200524_site_visit_oauth_trial.sql`.
- Archive: [`../../migrations/20260914203418_site_visit_oauth_trial.sql`](../../migrations/20260914203418_site_visit_oauth_trial.sql).
- SHA-256: `849d7b420c530d78f9092bf333aee893e50d007e788203cb92b61a0a103d764a`.
- Nine existing function fingerprints matched immediately before application. The migration succeeded atomically and its actual history entry was independently read back.
- Independent history readback confirmed one statement and 22,061 bytes with the exact source/archive SHA-256. All nine changed functions retain their original SECURITY DEFINER/INVOKER setting, search-path/configuration and EXECUTE ACLs.
- At **20:34:47 UTC**, bindings, compatibility enrollments, workflow effect policies, V22 clients and V22 grants were all zero. Binding RLS is enabled and forced; direct service-role insertion and authenticated provisioning are denied; service-only provisioning is granted. Frozen OAuth/workflow labels agree.

No business record, company activation, existing client/grant pin, other-domain effect seal, provider message, paid subscription/API fallback, or App Store release was changed.

The post-migration security advisor reports the new private binding only as INFO “RLS Enabled No Policy,” which is intentional for owner-only storage with all API-role table privileges revoked. No trial-related warning is reported. This is not a claim that the project's pre-existing unrelated warnings are resolved. [Supabase's advisory explanation](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy).

Foreign-key coverage follow-up: migration `20260914204329_site_visit_trial_subject_indexes`, source alias `20260914204207`, adds the actor/company indexes without changing rows or authority. The existing unique client index covers the third FK. A new regression failed before the fix; the complete local SQL suite now passes **54 assertions**. Independent production readback confirms all three leading indexes. Ledger/source/archive are 420 bytes and SHA-256 `bb75e739b1a3e7a48d199aecd071ee863cbcfcf89ae4c45b93fbeed06558efd7`. Web source `1749ecf77` is released as database-only commit `efdf1822a`; its application source, package files and runtime configuration are byte-identical to the already-live `0086cd591` release.

## Application and remaining acceptance

Production deployment `dpl_95Q9Fb2nKViBnPqrUmRqDcjY9VZH` reached **READY** with `app.opsapp.co` assigned, exact commit `0086cd591cb9642fe5f262249cd7db00447c16f8`. Its hosted compile and TypeScript check passed. At 20:43:57 UTC, a real authenticated native Codex company-context call returned **Canpro Deck and Rail**, confirming existing connection compatibility only. At 20:44 UTC, public OAuth metadata retained the exact 21 public scopes and S256; anonymous MCP and userinfo requests both returned HTTP401 with `Cache-Control: no-store`.

The database-only source/archive follow-up `efdf1822a3f47fbfb6b6d300512fdcf93da75736` reached **READY** at **20:50:38 UTC** in production deployment `dpl_2Kd176gWdFAq1tgCM8gKRUQgLsai`, with `app.opsapp.co` assigned and no alias error. Application bytes are unchanged from the first verified release. At **20:52:26 UTC**, a fresh native Codex company-context call again returned Canpro successfully; an anonymous MCP request at **20:52:27 UTC** remained HTTP401 with `Cache-Control: no-store` and the same 21 public scopes. This verifies the final deployment's existing read boundary, not MAVERICK trial acceptance.

The final production activation readback at **20:48:05 UTC** still showed zero restricted trial bindings, company compatibility enrollments, workflow effect policies, V22 clients and V22 grants. Neither application deployment activates those rows.

MAVERICK company compatibility/effect enrollment remains gated on the installed phone's pending-work recovery. A separate fresh, exact MAVERICK host consent is still required; the existing native Codex connection is Canpro and cannot be repinned or treated as MAVERICK. The requested phone check was presented to Jackson while deployment continued. After these prerequisites, verify real host preparation → visible exact OPS review/save → independent business readback and revocation. Physical-device offline/reconnect/conflict/media acceptance remains independently recorded, not inferred from synthetic SQL or installation.
