# Phase 19 site visits — local integration handoff

Date: 2026-09-10. Owner: parent task `01a0551f-df19-7942-a6d9-7e6e33f1bc9e`. Implementation task: `01a08ca5-857a-7323-a221-bf68a1bf4d80`.

Status: local implementation complete. Final independent web and phone reviews accepted with no remaining actionable findings in scope. All three local repositories have committed code or documentation for parent integration. No release, production migration, live enrollment, consent/exposure change, provider write or customer message has been performed.

## Integrate the complete phase

| Repository | Isolated branch | Exact base | Integration scope |
|---|---|---|---|
| OPS-Web | `feat/ops-mcp-site-visits-p19` | `c44cf655e733b257beaef8c7f37498ac057c8cb0` | Ten phase commits through `33af1aaf686af928fe52480cd55fef3fb10e0f1f`, including the supported-candidate correction and final evidence. |
| OPS iOS | `feat/ops-mcp-site-visits-p19` | `8553b1b435a286c344e2050898f6fb558453612a` | Seven phase commits through `b028aa553f52a1fb8c0ee123c95e937a2a4bd98a`, including V28 migration `b15bf20f` and final proof. |
| Software Bible | `docs/ops-mcp-site-visits-p19` | `5da52c90a7e6602438132416156983d34924ee7a` | Approved brief, implementation contract, persona matrix, this handoff, chapters 03/04/07 and six byte-identical unapplied migration mirrors. |

Private checkouts are `/Users/jacksonsweet/Projects/OPS/.worktrees/ops-mcp-site-visits-{web,ios,bible}-p19`. Parent integration must include every phase commit after each base. The first phone commit alone does not contain the release-compatible frozen schema, later recovery corrections or final verification.

The web commits in order are `392676346`, `eec1b7573`, `0c3ae18ef`, `ea5ca1b71`, `9aeb87915`, `eb929129a`, `195107fa4`, `9ea332d25`, `69a8c08cd` and `33af1aaf6`. Core workflow commit `195107fa4` contains the shared facade, strict contracts, canonical appointment migration, proposal/commit migration, candidate factories, approval backend/UI and root proof. Phone commits are `32d67ce9`, `c1e70272`, `83f5a6b0`, `3005b50e`, `6b7096f7`, `b15bf20f` and `b028aa55`.

Shared integration points: capability/exposure/scope registries, MCP OAuth scope catalogs, runtime/domain dispatch/server factory, durable rate adapter, capability service, approval queue service/types, action detail/queue row, English/Spanish queue dictionaries. Reconcile with P17/P18 and the separately owned P19 deck phase; do not replace siblings' shared registry edits wholesale. P19 site-visit candidates reserve manifest v27, exposure v22 and consent v17. The site-visit candidate is limited to ten necessary existing discovery reads plus eleven site-visit operations, with their exact read/prepare scope union. Other phases' prepares are excluded rather than broadening their pinned SQL grant authority. Existing active/default exposure remains unchanged.

SwiftData V28 is separately reserved by the parent and iOS Bugs coordinator. Preserve the frozen released V1–V27 models/checksums, adjacent V27→V28 migration and `OPSSchemaCurrent` alias update together. CalendarMirror payload/service/resolver and its tests are released to the iOS Bugs calendar-address task and are outside P19 ownership.

## Local proof

The web [verification report](../../ops-mcp-site-visits-web-p19/docs/artifacts/phase19/verification.md) records 115 form/civil/service/approval/read tests, 146 protocol/runtime/limiter/UI tests, focused production and protocol TypeScript success, 24 PostgreSQL workflow groups, 37 actual SQL outputs validated by Node 22, 69 phone SQL checks and 26 dedicated rate checks. SQL fixtures use captured production catalog definitions with synthetic local business records. All seven operation families have exact proposal/receipt binding coverage.

The [phone verification report](../../ops-mcp-site-visits-ios-p19/docs/artifacts/phase19/phone-verification.md) retains test summaries and 390/320 point populated conflict-review PNGs. All27 released checksum entries remain unchanged and match runtime measurement. The newV28 fingerprint is `nKgJeuKrTdQESe0YctzHunky4wMIqOpHYSoPkjdozIk=`. Populated V27 migration and independent reopen preserve every original template/answer/outbox scalar and leave all seven new nullable properties nil. Final checksum/Deck/adjacency verification passes7/7. Earlier hosted field-workflow subsets and corrected failures remain individually identified; two optional private-device-copy fixtures were skipped.

Final independent [web integration review](../../ops-mcp-site-visits-web-p19/docs/artifacts/phase19/reviews/final-web-integration-review.md) and [phone integration review](../../ops-mcp-site-visits-web-p19/docs/artifacts/phase19/reviews/final-phone-integration-review.md) are accepted with no remaining scoped findings.

The [30-persona matrix](2026-09-10-ops-mcp-site-visits-p19-personas.md) maps real persona needs to deterministic scenarios. It is not thirty live customer or native-host trials. Browser/static-component proof, simulator app-hosted tests, local protocol transport and local SQL receipts establish their named layers only.

## Release sequence and exact boundaries

### Parent integration progress — 2026-09-11

Web local main now includes implementation merge `ce49225089f745c060e0400dbc7c85279bbdcfe6` and evidence `b0e8d89c771d3bfc2a58b9fc766bc0e3b5c6a518`, combining all phase commits with exact main `cabebb8caf9e8c19b5e2ee8f315391dd89af5ff7`. Fresh verification: 115 workflow/read tests, 146 candidate/runtime/limiter/UI tests, and 410 deck/OAuth tests (671 distinct tests); focused production, P19 protocol and deck/OAuth TypeScript pass. Independent merge-seam review found no actionable issues. V22 now selects corrected deck geometry v2 while remaining unpublished; V23/V9 and historical public pins retain their authority. All six SQL hashes/mirrors and all27 historical phone fingerprint entries are unchanged. The primary web checkout's 43 pre-existing tracked edits retain their original hashes.

Phone integration commit `187a36d631a7413ced22d631c3cc153c62eb195f` merges exact main `b08de1042bed5d272d52daa83ef1bc30a501fa86` without overlapping source conflicts. The reviewed model/migration files are byte-identical to the accepted phone head. The app-hosted migration/site-visit/calendar regression is running in the private P19 simulator after the earlier external build exited; phone main has not yet been advanced. The Bible merge retains both the site-visit candidate and deployed deck/Canpro documentation. No release or activation action is authorized by this progress record.

### Remaining release order

1. Integrate all three repositories and reconcile shared registries plus SwiftData registration with current main. Preserve unrelated work and the separately owned calendar-address change. Run verification justified by integration differences.
2. Under separate explicit authorization, refresh deployed schema/function/ACL state and apply the six reviewed SQL migrations in filename order. Their byte-identical mirrors, sizes and SHA-256 hashes are in [the unapplied migration index](../migrations/README.md#phase-19-site-visits--unapplied-local-candidates-2026-09-10). These are source filenames, not production ledger versions. A changed deployed effect graph requires fresh review; do not silently reseal other phases.
3. Under iOS release authority, distribute and verify the compatible V28 phone client and pending-work recovery before company shared-write activation. Legacy clients are rejected safely for enrolled companies. Older queued operations without an originating actor remain recoverable but unbound; migration must not invent actor authority or rewrite attempted payloads.
4. Under separate exact authority, establish reviewed compatibility/effect policy and candidate exposure/consent for the named actor/company/client/grant. Both compatibility and effect policy are empty in the migrations. Enrollment, a readable connection and an exact operator approval are separate authorities.
5. Conduct the full signed-in native-host workflow for every host claimed: discovery, preparation, OPS review, exact save, independent readback and revocation. Then conduct signed-device offline/reconnect/conflict/media/recovery canaries with exact authorized records. No such live writes were authorized or performed by this implementation task.
6. Verify provider processing and customer-live behavior separately. A queued calendar intent reports `calendar_reconciled:false`; it is not an external event-delivery receipt. Saving answers never starts/completes the physical visit and never sends an implicit customer message. An iOS archive/upload is not an App Store release.

No purchase, subscription change or paid API fallback was used. Activation uses existing infrastructure; production invocation cost has not been measured by these local tests.

Contract details: [implementation](2026-09-10-ops-mcp-site-visits-p19-implementation.md). Authorized scope and release limits: [approved brief](2026-09-10-ops-mcp-site-visits-p19-brief.md).
