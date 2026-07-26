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
- The browser immediately renders an optimistic operator message.
- While a turn is running, the control is inert and the activity state is
  announced accessibly.
- A failed request retains the pending answer. Retry resubmits the same
  structured answer at the same expected version without duplicating the
  visible message.
- A successful server response replaces optimistic state with the stored
  transcript.
- Refreshing or returning to setup resumes the stored transcript.
- The transcript is presentation and audit state. It is not added to the model
  prompt; confirmed facts remain the canonical interview memory and avoid added
  token cost.
- Review and commit remain separate. Conversation persistence cannot mutate the
  live catalog.

## Implementation references

- `ops-web/src/lib/catalog-setup/phase-c/conversation-history.ts`
- `ops-web/src/lib/catalog-setup/phase-c/session-service.ts`
- `ops-web/src/lib/catalog-setup/phase-c/turn-service.ts`
- `ops-web/src/components/catalog/setup/guided-catalog-setup.tsx`
