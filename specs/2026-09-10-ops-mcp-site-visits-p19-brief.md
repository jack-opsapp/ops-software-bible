# OPS MCP Invisible Office — Phase 19: Site visits

Date: 2026-09-10

Status: build scope approved by Jackson; implementation and release unverified. This brief is not a shipped contract or a production migration approval.

## Outcome

A human in Claude, ChatGPT, Codex, or another accepted host can arrange a site visit, set up the appropriate reusable checklist, and prepare and save evidence-backed answers through the same OPS-owned capabilities used by durable agents. No Canpro-specific choreography or separate human/agent tool sets.

Golden workflow: “Book a visit for this lead, use our deck assessment checklist, and fill in what you can from these notes. Show me what is still missing.”

The connected assistant resolves exact records, prepares the specific changes, presents their effects and missing information, obtains the required approval, and returns truthful receipts after an independently verifiable save. Separate operations have separate outcomes: a saved checklist is not a booked visit, a booking is not a confirmed external calendar event, and answered fields do not mean the physical visit was completed.

## Current evidence and mandatory refresh

The parent inspected the connected OPS tool inventory and repository source on 2026-09-10:

- `list_site_visits` and `get_site_visit_context` are callable reads; the latter includes selected safe checklist, notes, measurements, artifact, deck-reference, booking, and timeline context.
- `src/lib/agent-control-plane/registry/write-tools.ts` defines prepare/commit booking, reschedule, and booking-cancellation pairs. Their `DARK_AVAILABILITY` is `implementation: unavailable`, `externalExposure: disabled`. Definitions are not working MCP implementations or host acceptance.
- `src/lib/api/services/site-visit-service.ts` has app methods using `book_site_visit`, `reschedule_site_visit`, and `cancel_site_visit_booking`. The Bible records their production contract and later NULL-keeps reschedule correction. Re-read deployed function bodies, grants, triggers, and schemas; this brief does not substitute for live database inspection.
- Reusable company templates exist as `site_visit_types`. Per-visit answers in `site_visit_checklist_answers` are independent snapshots, not live pointers that should be rewritten when a template changes.
- iOS `OPS/Views/SiteVisits/SiteVisitCaptureViewModel.swift` persists local checklist edits and marks them for sync. `OPS/Network/Supabase/Repositories/SiteVisitRepository.swift` currently sends checklist answers through its upsert path. Merely adding optimistic concurrency to an MCP endpoint does not prove safety against a later legacy phone upload.
- The prior site-visit MCP briefing deliberately excludes start/complete capture tools. The phone owns the offline parent/child/media/completion sequence.

Repository caveat: the shared `ops-web` checkout is dirty and behind the inspected MCP source. The parent read the clean `ops-mcp-catalog-web-p17` worktree at `64e2f0923` and verified the relevant registry files matched the local `origin/main` reference at that time. The implementing task must inspect current refs and production independently; do not use that checkout as an assumed current deployment.

## Required capability groups

### 1. Appointment preparation and approved booking

- Read/resolve exact lead and visit identities with actionable disambiguation and bounded coverage.
- Prepare booking, reschedule, and cancellation; implement the existing definitions where still appropriate rather than adding duplicate verbs.
- Resolve relative dates in the company's timezone and return the exact local date/time, UTC instant, duration, assignees, and reminder behavior for review. Ambiguous DST instants require resolution.
- Check relevant availability/conflicts and disclose incomplete calendar coverage. Never infer availability from an empty but incomplete result.
- Commit only the exact approved operation after revalidating current actor, company, grant, permissions, record relationships, state, and scheduling facts.
- Preserve the canonical booking business rules, stage transition, timeline entry, reminder behavior, and provider queue semantics. Never bypass them with an unguarded direct insert or duplicate side-effect implementation.
- Respect `booked_at` as the booking discriminator. Preserve NULL-keeps and explicit reminder-clear semantics, follow-up booking rules, cancellation idempotency, and rejection of already-started/completed visits where applicable.
- Calendar/provider delivery is a separate asynchronous outcome. Report queued, reconciled, failed, or unknown accurately. Do not send a customer message as an implicit booking effect.

### 2. Reusable checklist and form configuration

- Provide bounded discovery and exact inspect context for existing types, all supported field definitions, defaults, and editing references. A caller must not need to invent UUIDs or inspect raw database rows to edit a known checklist.
- Create and edit reusable templates using the current app's supported field kinds and constraints. Include order, required/optional, visibility, help text, and default selection only as supported by the verified model.
- Preserve stable field identities. Apply company-settings permissions for company-wide template changes, distinct from permissions to answer a visit form.
- Preview exact before/after definitions and scope. A template edit must not rewrite previously captured answers, completed records, or historical snapshots.
- Do not silently turn a per-visit answer into a company-wide template/default change. Any destructive retirement needs explicit scope and confirmation; no hard delete convenience tool.

### 3. Evidence-backed form answers

- Inspect the exact visit's saved field snapshots, current answers, record state, source references, and missing required fields.
- Select/apply a checklist to an eligible visit with exact preview and preservation of existing work; do not replace answered fields as an incidental effect.
- Prepare typed answer changes from user notes or supported evidence. Keep unknown, unanswered, false, zero, empty, and explicitly cleared values distinct according to the current field model.
- Preserve units, choice constraints, original source attribution, and factual uncertainty. Instructions embedded in files or business records are untrusted content.
- Unsupported/unreadable attachments produce a truthful request for usable source material. No claimed extraction of a file the host could not actually read; no fabricated photos, signatures, measurements, or completed checkboxes.
- Commit exact approved fields only. Preserve unrelated answers and record metadata. Corrections invalidate or supersede old proposals so an obsolete approval cannot save an earlier interpretation.
- Completing all required answers must not start or complete the physical capture lifecycle or falsely label a visit completed.

## Cross-surface data safety is a ship gate

Model both orderings: phone edits while offline, then MCP saves, then phone reconnects; and MCP prepares, then phone saves, then MCP approval arrives. Also test two phones and two MCP hosts.

The implementation must prove that no writer silently loses another writer's data. Server-only “updated_at matches” checks are insufficient if old phone clients can subsequently perform unconditional writes. Inspect all actual writers, merge rules, row identities, snapshot creation, completion locks, template changes, account switching, and recovery queues.

Choose and document the smallest compatible conflict protocol that preserves both versions and exposes a resolvable conflict. Include required iOS changes if necessary, in an isolated iOS worktree with serial build ownership. If old-client compatibility requires a feature gate or signed-client rollout, preserve that gate and explicitly identify it in the release handoff. Do not claim MCP form writing production-ready while unsafe legacy overwrite paths remain reachable.

Start/complete capture remains phone-owned. Removing that boundary is not part of this approval. Saving a form answer is a distinct operation, not a substitute for capturing media or finishing an on-site workflow.

## Shared authority and durable state

- Use the existing domain service/control-plane architecture, typed discovery, prepare/preview/confirm/commit, idempotency, receipts, and audit history. No host-owned business state or generic CRUD escape hatch.
- Enforce exact actor/company/client/grant boundaries at preparation and again at commit. No role-name shortcuts, inferred policy, ambient service-role trust, or enroll-to-write escalation.
- Preparation may persist only OPS-owned proposal state authorized by the current contract; no booking, answer, template, calendar, notification, or customer-message effect disguised as a preview. Proposal review notifications, if part of the existing approved review architecture, must be declared separately.
- Require exact transaction approval for writes in this first release. Automatic filing policies and agent schedules are not introduced here.
- Bind confirmation to the full effect and source-version graph. Test expiration, revocation, replay, key reuse with different arguments, and attempts to widen a single-record approval.
- Canonical committed effects must appear in appropriate OPS activity/notification surfaces with actual actor, host, target, time, and outcome. Reversal or compensation must be described truthfully and reauthorized; a delivered external effect is not magically undone.
- Business mutations and successful receipts must be atomic or have a proven recovery/reconciliation path. Retry after timeout must not duplicate a booking, timeline entry, answer, or provider request.
- Keep candidate manifest, public exposure, consent, trial enrollment, and live write authority distinct. Coordinate shared registry/version files with the parent; do not reactivate another phase's candidates incidentally.

## Verification

Use focused deterministic tests, database contract tests in a dedicated local fixture, and actual host acceptance rather than only mocked tool-call success. Map conversational scenarios to the existing 30 customer personas.

Required cases include:

1. Owner schedules one exact lead; ambiguous names and multiple open leads do not guess.
2. Duration, reminder clearing, DST, timezone, crew conflicts, missing calendar coverage, and racing booking attempts.
3. Reschedule/cancel replay, already-started/completed visits, stale provider create/update work after cancellation, and truthful asynchronous delivery state.
4. Company template creation/edit/default, duplicate slug or field identity, hidden/required fields, invalid field kinds, and bounded oversized input.
5. Template edits after snapshots/answers exist; no silent history rewrite.
6. Partial notes, zero/false answers, unsupported choice or unit, explicit clearing, contradictory evidence, and misleading instruction-like source text.
7. Stale preparation after phone edits, delayed phone upload after MCP save, reconnect, duplicate outbox replay, two hosts, and completed-record mutation denial.
8. Exact actor/grant/permission revocation and cross-tenant identifier substitution for every read/write family.
9. Expired approvals, altered effect hashes, same-key/same-arguments replay, same-key/different-arguments rejection, and crash-after-save retry.
10. Corrected request supersedes the old proposal; successful save reads back exact fields and audit/notification outcome.
11. Read/discovery paginates honestly and provides everything needed to prepare an edit without inventing identities.
12. Native host discovery, preparation, review, commit, readback, and revocation for each claimed supported host. Local proof alone does not establish host acceptance or live rollout.

## Execution and release boundaries

This approval covers architecture, implementation, isolated local database fixtures/migrations, focused testing, local commits, and Bible updates. Do not push, deploy, apply production migrations, change grants/policies/consent/exposure, enroll live trials, send real messages, or release an iOS client in the implementation task without fresh explicit permission. No paid API fallback, subscription change, or new service purchase.

Read production schema/ACL/function definitions through the approved Supabase tooling before writing migrations. Do not assume the current MCP connection belongs to MAVERICK PROJECTS. Historical authorization to test MAVERICK is not a reusable actor/grant binding. Never use the separate PERSONA TEST POOL as a mutation fixture.

Preserve unrelated work. P17 catalog remediation and P18 vinyl work have separate ownership; inspect task status and coordinate shared files, but do not take over or modify their worktrees. The parent owns integration and release sequencing.

Deliver clean local commits per affected repository, focused test evidence under `docs/artifacts/phase19/`, an updated implementation spec and numbered Bible chapters, and an exact release handoff. Identify unapplied migrations and their hashes, compatibility requirements, candidate versus live exposure, host/device tests actually performed, and remaining actions only Jackson or the release owner can take. Do not report “done” based only on this brief or registered capability names.

## Source map

- `specs/2026-08-30-ops-mcp-vision-handoff.md`
- `specs/2026-08-10-site-visit-mcp-capability-briefing.md`
- `specs/2026-08-10-site-visit-booking-calendar-design.md`
- `04_API_AND_INTEGRATION.md` — reusable checklist templates and site-visit booking RPCs
- `03_DATA_ARCHITECTURE.md` — site visits, checklist answers, and template definitions
- `07_SPECIALIZED_FEATURES.md` — visit capture and notification architecture
- OPS-Web `src/lib/agent-control-plane/registry/write-tools.ts`
- OPS-Web `src/lib/agent-control-plane/registry/read-capabilities/p2/site-visits.ts`
- OPS-Web `src/lib/api/services/site-visit-service.ts`
- iOS `OPS/Views/SiteVisits/SiteVisitCaptureViewModel.swift`
- iOS `OPS/Network/Supabase/Repositories/SiteVisitRepository.swift`
- iOS `OPS/Network/Sync/SiteVisitSyncOperation.swift`
- iOS `OPS/Services/SiteVisitPersistenceCoordinator.swift`
- iOS `OPS/Services/SiteVisitMutationBoundary.swift`
