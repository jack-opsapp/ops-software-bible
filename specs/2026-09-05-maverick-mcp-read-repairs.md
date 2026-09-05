# Maverick MCP read and preparation-boundary repairs

Status: implemented and verified locally on September 5, 2026. The new production migration and OPS-Web/Bible push are awaiting Jackson's explicit approval. This does not change the recorded Phase 12 activation release.

## Incident and corrected behavior

Authenticated Maverick use-case testing made 40 calls: 29 successes, eight input-validation rejections and three runtime errors. No business change or approval package was created. The unchanged-title preparation probe failed before its no-change guard. These are call counts, not 40 independent scenarios.

- **Grant ordering:** the trusted principal constructor used locale sorting, reversing `ops.catalog.read` and `ops.catalog_costs.read` relative to the stored ASCII catalogue. It now canonicalizes validated ASCII scopes with default string sorting. Exact scope sets, actor/company/client/grant identities, revisions and v14/v9 accepted labels remain mandatory. The regression uses all 21 scopes through the actual principal → actor → service → repository path.
- **Conversation reads:** the provider-source substitution omitted `source_connection_id`, `subject`, `provider_delivery_source_sha256` and `original_content_hash` aliases. The corrective migration restores every required alias for recent turns and cited evidence. Authoritative provider tuples/content, redaction, mailbox/record access and tenant predicates remain intact. Once this error was removed, the live compatibility chain exposed another error: applying manifest-envelope reproof to a raw conversation snapshot. Only conversation wrappers stop that incompatible result transformation. Their input/revision validation and the repository's strict snapshot/authorization validation remain in force. The shared generic proof function is unchanged.
- **All-day task dates:** stored task UTC date parts are inclusive civil date labels, consistent with canonical job-summary scheduling. The detail reader now resolves the company's local start midnight and the exclusive midnight after the final included date. List overlap, overdue, actionable filtering and attention timestamps use the same helper. Each midnight is resolved independently across DST. Timed instants remain unchanged. Paving's stored March 15–16 dates remain untouched and its task-detail end becomes March 17 at 07:00Z.
- **Inputs:** task/site-visit status and section selections and integration selections accept unique values in any order. Read-window timestamps accept UTC seconds with optional 1–3 fractional digits and normalize to milliseconds. Evidence/output timestamp schemas remain strict. Advertised input fields explain UTC, all-day exclusive ends, project-only schedule/readiness, financial components, contact purpose and job kinds. Duplicate/unknown values and substantive authority/conditional restrictions still reject. Immutable catalogue/authorization fingerprints do not change.

## Migration and security boundary

OPS-Web source: `supabase/migrations/20260905184652_agent_maverick_read_repairs.sql`, generated with Supabase CLI 2.116.0. SHA-256 `4c4022d54ba0278ca4d0d33705ce10c358242a00d4dfdb3bbb3a54aace40838d`.

Seven read function definitions change, and `private.agent_task_read_instant(timestamptz,boolean,text,boolean)` is added. The helper has no application-role execute grant. Exact before/after definition hashes reject unexpected source drift and permit replay. Existing function identities, owners, ACLs, security attributes and search paths are preserved. There are no business-row, grant, consent, exposure, table or RLS-policy edits. The original migrations remain immutable. The migration is not yet in the production ledger, so no production archive is claimed.

Company-timezone changes already invalidate the `legacy_operational` revision carried by task proofs, through the existing companies operational-revision trigger. This repair preserves that revision mechanism.

## Verification and live state

- 892 application tests across 78 files pass; full TypeScript checking and focused ESLint pass.
- 60 local PostgreSQL assertions pass: 16 conversation, 41 task and three invariants, plus two reproduced pre-repair errors, safe replay and rejected source drift. Empty/populated conversations, provider-source mismatch, invalid normalization, cited evidence, redaction, tenant/inactive-actor denial, 23/25-hour and multi-day DST dates, discovery/overdue boundaries, current attention, partial dates and timed instants are covered.
- Local SQL readback proves every synthetic business/grant/revision row is unchanged, along with original function identity/owner/ACL/security settings. The runner is `bash tests/sql/agent-maverick-repair-run-runtime.sh` and owns only its disposable Unix-socket database.
- Live readback at 2026-09-05 19:05:14 UTC finds the original seven function hashes, unchanged Paving source dates and updated_at, the active original 21-scope Maverick grant revision, and zero Maverick customer-update proposals. Production still serves OPS-Web `3a89c08ca1f5b827ccac2f6194842e83f8f7abc8` in READY deployment `dpl_CTSMvUZksuStAK6yxFNxp5hWPmco`.

The local fixture uses frozen live definitions/column types and real authorization helpers; unrelated FKs, write-trigger graphs and provider workers are not reproduced. Job-summary agreement uses the established helper/formula, not a full summary-RPC runtime fixture. Original live reports remain preserved under OPS-Web `docs/artifacts/phase12/`; repair proof and the readable SQL delta are under `docs/artifacts/maverick-repair/`.

## Separate timezone platform finding

Production resolves Vancouver midnight on November 2, 2026 as 08:00Z; current local PostgreSQL/Node resolve 07:00Z. B.C. [adopted permanent UTC−7 after March 8, 2026](https://news.gov.bc.ca/releases/2026AG0013-000209). Production's timezone data therefore remains older than the rule used by current application runtimes. This repair follows the existing database civil-date resolver and does not claim to solve that platform mismatch. A production timezone-data refresh and subsequent cross-runtime verification remain unresolved and require operational assessment. DST fall-back fixtures use Los Angeles, where the transition still exists.

## Release gate

Await explicit approval for this exact migration and pushing the verified OPS-Web/Bible commits. Then verify the deployment revision and rerun authenticated Maverick conversation, task/date, input and unchanged-title no-change calls with independent task/proposal readbacks. Creating a real proposal, approving/committing a business change, or sending messages remains outside this repair release. No new service or paid tier is introduced; existing hosting/database usage applies.
