# Phase C Durable Catalog Conversation (2026-07-25)

## Scope

OPS-Web guided catalog setup presents the Phase C interview as a durable
operator conversation. The behavior is general to every catalog domain; Canpro
vinyl is an acceptance case, not a prescribed setup path.

## Data contract

Migration `migrations/20260726015328_add_guided_setup_conversation.sql` adds
`catalog_guided_setup_sessions.conversation`:

- `jsonb not null default '[]'`;
- array-shaped and capped at 200 entries;
- updated in the same version-guarded write as facts, unresolved questions,
  sources, contradictions, and the proposed plan.

Each message records a stable ID, `assistant` or `operator` role, `text` or
`source_document` kind, display content, session version, and an optional source
filename. Spreadsheet rows remain in the existing source evidence record and
are not copied into the transcript.

New sessions seed the first assistant question. Legacy active sessions without a
transcript expose their current unresolved question as the starting message and
persist the normalized conversation on their next successful turn.

Migration
`ops-web/supabase/migrations/20260727210000_phase_c_input_revision_fence.sql`
adds a durable `input_ledger`, monotonic `input_revision` /
`processed_input_revision` counters, and a pinned
`capability_manifest_revision`. Operator messages are stored before generation;
the generated turn may commit only when both the session version and input
revision still match.

## Runtime contract

- The interview is adaptive and supplier-neutral. Production code contains no
  company- or supplier-specific setup blueprint.
- A supplier name is a confirmed session fact, not permission to infer that
  supplier's catalog. Missing products, SKUs, prices, dimensions, coverage, and
  compatibility are asked for or extracted from operator-provided evidence.
- Supplier-shaped acceptance scenarios may exist as test fixtures, but cannot
  be imported by the production turn service.
- Future external supplier research must be on-demand, source-attributed,
  session-scoped, and reviewed before it can become a catalog fact.
- Each turn retrieves only active, catalog-relevant `agent_memories` under the
  route-resolved company ID. It does not read writing profiles, commitments,
  client behavior, or the company knowledge graph.
- Deterministic lexical ranking uses the current question, answer, and confirmed
  facts. At most 12 bounded entries reach the model; there is no added embedding
  or research model call.
- Company knowledge is untrusted background evidence. A fact derived from it
  remains unresolved with `source.kind=company_knowledge` until the operator
  confirms it, and unresolved company knowledge blocks review.
- Retrieval failures do not block the interview. Successful turns store only a
  query hash, selected memory IDs, categories, and version as provenance; raw
  memory content is not copied into the guided session.
- Phase C may ask about or propose only behavior marked `available` in the
  server-owned capability manifest. The released manifest supports core catalog
  products and static product-material quantity rules. Deck geometry,
  layout-derived waste, roll/sheet inventory, dynamic purchasing, and
  Deck Designer automation are unavailable and cannot be implied.
- Review readiness is server-owned. Phase C never asks the operator whether the
  setup is ready: it returns a review blueprint when all required confirmed
  facts exist, otherwise it asks one concrete question backed by an available
  capability.
- Question templates and the model policy are generated from the same manifest.
  Semantic validation rejects unsupported capabilities before review, and
  commit revalidates the pinned manifest revision before any live catalog write.
- The browser persists and renders each operator message immediately, then
  starts generation from that exact input revision.
- An assistant question is logically identified by question ID plus prompt, not
  by the session version embedded in its durable message ID. Version changes
  cannot insert a second copy after the operator's answer; legacy synthetic
  duplicates are removed while the original question and answer order remain.
- While Phase C is working, the compact composer stays available for a quick
  follow-up or correction. The newest queued text message can be edited or
  removed.
- If a newer input arrives during generation, the stale response cannot commit
  or publish. The client automatically runs the latest queued revision.
- A failed generation retains the persisted queued answer. Retry processes that
  same revision without duplicating the visible message.
- Refreshing or returning to setup resumes the stored transcript.
- An active interview stranded on the former review-readiness prompt after an
  unsupported roll/sheet-inventory answer is repaired on resume. The repair
  preserves the operator message and valid confirmed catalog facts, removes
  only unsupported derived inventory/purchasing facts and the invalid prompt,
  records a `system_repair` source, then asks whether handling stays
  staff-managed or uses released fixed material quantities. It never mutates
  the live catalog.
- The transcript is presentation and audit state. It is not added to the model
  prompt; confirmed facts remain the canonical interview memory and avoid added
  token cost.
- Review and commit remain separate. Conversation persistence cannot mutate the
  live catalog.

## Presentation contract

- The transcript is full-bleed vertically and is the only conversation scroll
  owner. Auto-scroll targets that element directly and never repositions a page
  or ancestor container.
- The compact composer floats over the transcript. A measured bottom spacer
  keeps the newest exchange clear of the composer at the fully scrolled
  position.
- Short conversations remain stationary. Long conversations keep the newest
  exchange fully visible.
- Upload remains a quiet action inside the composer. Send uses a 16px
  paper-airplane icon with the terse `SEND` label in the 32px compact control
  tier.
- Start over, alternate method, and back controls are reachable chips outside
  the composer surface.
- Phase C activity uses an accessible five-bar ripple. Only a newly returned
  assistant message receives the typewriter reveal; restored history renders
  immediately. Both effects resolve immediately under reduced motion.

## Implementation references

- `ops-web/src/lib/catalog-setup/phase-c/conversation-history.ts`
- `ops-web/src/lib/catalog-setup/phase-c/catalog-knowledge-context.ts`
- `ops-web/src/lib/catalog-setup/phase-c/session-service.ts`
- `ops-web/src/lib/catalog-setup/phase-c/turn-service.ts`
- `ops-web/src/components/catalog/setup/guided-catalog-setup.tsx`
