# OPS MCP Promise Recovery — Phase 4 Vertical

**Status:** Local release candidate; read-only and dormant

**Golden task:** “Did I ever get back to [customer] about [thing]?”

**Definition revision:** `promise-recovery:2026-08-31.v1`

## Product promise

`check_customer_reply` resolves one exact OPS customer and one bounded topic, then answers only what the authoritative delivered-correspondence record proves. It returns exact chronology and stable OPS evidence references. It never drafts, sends, schedules, updates, or treats thread metadata as proof of a reply.

The four possible answer states are:

- `replied`: a readable, topic-matching outbound delivery attributable to the current authenticated operator follows the latest qualifying request or promise;
- `outstanding`: complete readable retained evidence contains a request or promise but no later qualifying reply;
- `not_found`: complete readable retained evidence contains no qualifying request, promise, or reply; this does not claim the event never occurred outside OPS history; and
- `insufficient_evidence`: customer ambiguity, unreadable or unattributed sources, incomplete attachment enumeration, or a source/payload bound could change the answer.

No confident negative may be returned from incomplete evidence.

## Caller contract

The caller may provide only:

```json
{
  "customer_query": "Exact customer name",
  "topic": "the quote",
  "as_of": "optional RFC 3339 UTC timestamp"
}
```

Tenant, actor, grant, client, permissions, policy, source population, chronology rules, classification markers, and evidence budgets are server-owned. The customer query must resolve to one active, unmerged customer in the authenticated company. More than 12 significant topic terms rejects rather than truncates.

## OPS-owned definitions

- **Topic match:** every significant normalized topic term appears as a whole token in normalized safe body text. Subject, snippet, summary, routing state, attachment presence, and provider metadata cannot establish the match.
- **Customer request:** an inbound, exactly customer-attributed topic match containing a question or a defined request marker.
- **Promise:** a topic-matching outbound delivery attributable to the current operator containing a first-person future commitment and a defined follow-up verb.
- **Reply:** the first later readable, exactly customer-attributed and current-operator-attributed topic-matching outbound delivery after the latest request or promise.
- **Resolution:** a qualifying reply also containing a positive completion/delivery marker. A nearby negation blocks the marker.
- **Unanswered commitment:** an explicit promise with no later qualifying reply as of the cutoff.

The tool may say `replied` without claiming resolution. It may claim resolution only from a positive resolution marker in the qualifying body.

## Correspondence-readability gate

The authoritative body source is `private.agent_provider_delivery_sources`, not the copied body on `private.agent_job_conversation_turns`. A conversation turn is a stable evidence link only when company, provider source ID, and captured source hash agree.

The candidate migration repairs two active-v2 Foundation Zero read-wrapper defects without widening their signatures:

1. conversation-context manifest reproof accepts only a complete known predecessor lineage, re-mints the nested proof, and rejects an incomplete or substituted source chain; and
2. correspondence evidence overlays body, subject, source hash, and attachment references from the exact provider source. When a stable attachment reference exists but optional verified metadata does not, the wrapper returns that reference with `metadata_state: incomplete` instead of hiding an otherwise readable body.

Both repairs are guarded against production function-definition drift. Empty normalized bodies remain invalid. Rejected normalization stays rejected; the repair does not weaken the HTML safety transform.

## Chronology and bounds

Customer identities come from active client/sub-client email identities in the actor's company. A provider thread linked to the customer but missing exact participants is retained as an attribution gap and forces `insufficient_evidence`; it is never classified as a reply.

Rows are ordered by `(delivered_at, provider_delivery_source_id)`. The read is bounded to:

- 500 source rows;
- 100,000 safe characters per body;
- 2,000,000 safe body characters across the snapshot;
- 20 returned chronology items; and
- 100 stable attachment references across the snapshot.

Aggregate budgets retain the newest complete evidence first. An exhausted body or attachment envelope marks older evidence incomplete and forces `insufficient_evidence` instead of silently producing a partial answer.

“Did I” means the current authenticated operator. Company-mailbox direction alone is not authorship. Outbound evidence qualifies only through that operator's individual mailbox or an exact hash-bound activity created by that operator.

## Evidence contract

Each chronology item can carry:

- `provider_delivery_source:<uuid>`;
- a hash-bound `job_conversation_turn:<uuid>` and stable `ops://evidence/...` locator;
- delivery timestamp and direction;
- classified role;
- bounded safe excerpt marked `untrusted_business_data`;
- normalization revision and source SHA-256;
- exact participant attribution state; and
- stable `email_attachment:<uuid>` references plus enumeration completeness.

Raw HTML, raw provider payloads, customer email addresses, and transport secrets never cross the repository boundary.

## Authority and dormant exposure

The tool requires `ops.correspondence.read`, `ops.customer_contacts.read`, and `ops.customers.read`, plus current `clients.view` and `email.view` permissions. The application authorizes the original actor, re-resolves current grant/permission authority, and the fixed service-role RPC independently verifies the actor, company, OAuth client/grant, exact grant revision and scope ceiling, permission snapshot, capability/manifest revision, and dormant exposure revision.

Immutable exposure `2026-09-01.mcp-exposure.v6` is additive to Phase 3. It contains exactly:

1. `analyze_hiring_break_even`
2. `check_customer_reply`

Its scope ceiling is the complete v5 hiring ceiling plus the three promise-recovery reads. Capability manifest `2026-09-01.capability-manifest.v12` re-mints v11 and adds only `check_customer_reply`. Production `ACTIVE_MCP_EXPOSURE_REVISION` remains v2. Dormant v3, v4, and v5 definitions remain preserved.

## Read-only and release boundary

OPS-Web local commit `cf858e0d2d65e9642be8a9aa7b791246b78af8fb` contains the Phase 4 implementation on top of authoritative Phase 3 commit `cd72a74f5ff26d0ff85ffad3778a8851aecc5ea1`. The vertical stores no result and contains no action, approval, routine, notification, model/provider call, DML, draft, or send path. The SQL file is a local candidate only. It has not been applied. No DCR client, consent grant, deployment, exposure activation, or production mutation exists for v6.

There is no new paid service. If released later, the work uses the existing OPS-Web and Supabase paths; ordinary database compute/storage remains governed by the existing plans.

## Live evidence snapshot

Read-only production discovery on 2026-09-01 found 309 provider-delivery sources: 238 readable projections and 71 rejected projections. The readable bodies total 675,955 characters; the largest is 39,000 characters. Twenty-one readable sources originated as real HTML, and six retain stable attachment evidence references. Sixteen hash-bound conversation turns still carry an older placeholder even though their authoritative provider projection is readable, confirming that the source ledger—not the copied turn body—must be authoritative.

The live sample proved a real normalized HTML body, exact provider-source/hash-bound-turn chronology, and stable attachment reference. Its attachment row lacks optional verified size/content-hash metadata, reproducing the active evidence-wrapper defect that the candidate repair addresses.

Production currently has 90 outbound provider sources, but none meet the stricter current-operator attribution rule. Therefore a production run today must report `insufficient_evidence` rather than claim the current operator personally replied. The existing active wrappers also still fail on the two defects above until a separately approved migration and application release occur.

## Verification contract

Release-candidate proof must include strict schema/definition tests, repository binding and malformed-row tests, service chronology/classification and no-mutation tests, immutable manifest/exposure/runtime tests, SQL no-DML and tenant/actor/source-ledger contract tests, PostgreSQL runtime proof, full MCP regression tests, typechecking, linting, and a production build. Final live readback must prove v2 remains active, v3-v6 remain ungranted/inactive, and the candidate migration is absent.
