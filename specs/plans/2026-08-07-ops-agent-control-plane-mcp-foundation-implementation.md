# OPS Agent Control Plane and MCP Foundation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use `custom-skills:executing-plans` to implement this plan task-by-task. Use an isolated worktree. Do not apply production migrations, register external OAuth clients, change DNS, push, deploy, or submit a connector without Jackson's explicit authorization.

**Goal:** Build the approved shared OPS agent control plane, replace Phase C whole-history prompting with job-anchored versioned memory, expose the first read-only operational tools through a secure dual-era remote MCP server, and complete the general prepare/confirm/commit foundation for future financial, estimate, catalog, and communication tools.

**Architecture:** One typed `OpsAgentDomainService` receives a server-created `ActorContext` and returns bounded, source-provenanced contracts. Phase C, REST, and MCP are adapters only. Job conversations are independent of provider threads. External access uses OAuth 2.1 protected-resource discovery and exact-audience tokens. All material writes use server-owned change sets, explicit confirmation receipts, expected versions, idempotency, atomic commit, audit, and readback.

**Tech Stack:** Next.js 15 App Router, TypeScript 5.9, Node 22, React 19, Vitest, Playwright, Supabase Postgres, Firebase Admin identity, `jose`, existing OPS `zod@^3.24.0`, isolated MCP-schema alias `zod-v4@npm:zod@4.2.0`, official MCP TypeScript SDK `@modelcontextprotocol/server@2.0.0`, Vercel, public HTTPS Streamable HTTP.

**Design System:** The OAuth consent, connected-app management, and confirmation surfaces use the existing OPS-Web design system at `ops-design-system/project/DESIGN.md`. Use current OPS-Web Tailwind tokens and `lucide-react`; no new visual system, raw values, marketing surface, MCP App widget, or motion language.

**Execution status (2026-08-14):** Tasks 1–13 plus Task 4A are locally committed on `feat/ops-agent-control-plane-takeover-20260807` through `d4118344`. This includes the SDK/schema boundary, actor scope, capability manifest revision `2026-08-14.capability-manifest.v6`, immutable conversation and memory foundations, the transport-neutral `OpsAgentDomainService`, schedule/readiness reads, current-only communication/participant reads, customer-job listing, selected job summaries, bounded history search, and exact correspondence-evidence pages. Exactly nine capabilities are internally available: `get_job_conversation_context`, `list_scheduled_jobs`, `list_job_readiness_issues`, `get_job_communication_context`, `resolve_job_participants`, `list_customer_jobs`, `get_job_summary`, `search_job_history`, and `get_correspondence_evidence`. Every external exposure remains disabled and every unimplemented method remains absent from the facade rather than stubbed. The Task 9, Task 11, Task 12, and Task 13 migrations have not been catalog-compiled, executed, or applied to local, test, preview, or production Supabase. No Phase C consumer, memory worker, REST/MCP handler, OAuth facade, or remote MCP server invokes the facade. The site-visit read services and change-set participants remain unbuilt and dark; the canonical booking RPCs and prompt/calendar workers are separately production-live but are not wired into this control plane. Nothing has been pushed or deployed from this branch; Tasks 14 onward remain incomplete. Checklist boxes below remain acceptance gates rather than deployment evidence.

**Required Skills:** `custom-skills:executing-plans`, `superpowers:using-git-worktrees`, `superpowers:test-driven-development`, `superpowers:systematic-debugging` when a failure appears, `supabase:supabase`, `supabase:supabase-postgres-best-practices`, `openai-docs`, `plugin-dev:mcp-integration`, `ops-design`, `frontend-design:frontend-design`, `custom-skills:interface-design`, `custom-skills:ui-ux-pro-max`, `ops-copywriter:ops-copywriter`, `custom-skills:wizard-audit`, `custom-skills:audit-design-system`, `superpowers:verification-before-completion`, and `superpowers:requesting-code-review`.

---

## Source of truth

Read before implementation:

- `/Users/jacksonsweet/Projects/OPS/ops-software-bible/specs/2026-08-07-ops-agent-control-plane-mcp-foundation.md`
- `/Users/jacksonsweet/Projects/OPS/ops-web-lead-reply-quality/AGENTS.md`
- `/Users/jacksonsweet/Projects/OPS/ops-design-system/project/DESIGN.md` before the UI tasks
- Current official MCP, OpenAI, and Anthropic references linked from the design spec; re-check them at implementation because host requirements can change.

The design spec wins when this plan is terse. If production schema/code differs from this plan, verify the current state, update the design and plan, and do not guess.

## Local implementation checkpoint — 2026-08-10

- Tasks 1-5 are present in the local branch history through `6f9e387f`.
- Task 6 is committed locally as `bfb5099b` (`feat(agent-control-plane): normalize source-provenanced evidence`).
- Task 7 is committed locally as `5f9e4d6a` (`feat(agent-memory): ingest provider-delivered job turns`).
- Exact local proof for the last two tasks is 214/214 evidence tests plus 492/492 staged delivered-turn/provider tests, green TypeScript and formatting, zero ESLint errors, and a clean fresh adversarial review.
- The provider-source migration was verified structurally, not executed against PostgreSQL, because no local Supabase/PostgreSQL runtime was available.
- Nothing in this checkpoint has been pushed, deployed, applied to production, exposed through a public connector, or proven customer-live. Tasks 8 onward remain unimplemented.

---

## Execution gates

### Gate 0 — authorization

This plan is documentation, not authorization to execute. Before Task 1:

- [ ] Jackson explicitly authorizes implementation.
- [ ] Confirm whether production migration/deploy/push authority is included. Treat each as separate if not explicit.
- [ ] Do not infer permission to mutate production from approval of the design.

### Gate 1 — isolated branch

This is a large feature. Create an isolated origin-based worktree using `superpowers:using-git-worktrees`.

Recommended base: exact Phase C commit `cae90581`, because the first internal consumer and replacement target are present there.

```bash
git -C /Users/jacksonsweet/Projects/OPS/ops-web fetch origin
git -C /Users/jacksonsweet/Projects/OPS/ops-web cat-file -e cae90581^{commit}
git -C /Users/jacksonsweet/Projects/OPS/ops-web worktree add \
  /Users/jacksonsweet/Projects/OPS/ops-web-agent-control-plane \
  -b feat/ops-agent-control-plane-20260807 cae90581
```

If that branch already exists, inspect it and coordinate; do not delete/recreate it. If `cae90581` has already landed on `origin/main`, base on current `origin/main` instead and record the exact base commit.

### Gate 2 — current-state proof

- [ ] `git status --short --branch` is clean in the new worktree.
- [ ] Verify no sibling session is editing the planned files.
- [ ] Verify the latest production schema/RLS/policies with Supabase read tools.
- [ ] Verify production migration ledger before choosing timestamps.
- [ ] Verify current official MCP/OpenAI/Anthropic contracts.
- [ ] Record existing Vercel/Supabase/security-provider plans and incremental costs. Escalate any paid tier or vendor purchase to Jackson.
- [ ] Confirm the exact customer-facing resource URL and DNS ownership before implementing discovery metadata. No DNS write yet.

### Gate 3 — verified SDK/Zod dependency boundary

The official stable server package is `@modelcontextprotocol/server@2.0.0`. SDK-bound schemas require Zod 4.2 or newer because that release supplies the `~standard.jsonSchema` contract. OPS-Web must retain its existing `zod@^3.24.0` behavior, so the MCP boundary uses the official migration guide's isolated-alias pattern.

- [ ] Pin `@modelcontextprotocol/server` to `2.0.0` in `package.json` and `package-lock.json`; do not use a floating major.
- [ ] Leave the existing `"zod": "^3.24.0"` dependency unchanged.
- [ ] Add the exact alias `"zod-v4": "npm:zod@4.2.0"`.
- [ ] Import every SDK-bound MCP schema from `zod-v4`, never from `zod` or `zod/v4`.
- [ ] Do not use Zod 3.25's `zod/v4` compatibility subpath: it predates the required `~standard.jsonSchema` support and is not sufficient for SDK v2 registration.
- [ ] Keep Zod 3 and Zod 4 schema objects isolated. Existing OPS schemas remain Zod 3; agent-control-plane schemas exposed to MCP are authored once in `zod-v4`; only parsed plain values cross between them.
- [ ] Verify the installed graph with `npm ls @modelcontextprotocol/server zod zod-v4` and exercise a real MCP `tools/list` call so a quiet schema-conversion failure cannot pass unnoticed.

---

## Target code layout

All new shared business logic lives under:

```text
src/lib/agent-control-plane/
  actor/
  audit/
  changes/
  contracts/
  evidence/
  memory/
  registry/
  services/
  adapters/
  oauth/
  mcp/
```

Transport routes and product UI live in their normal Next.js locations. Existing domain services remain the underlying implementation; the control plane composes/adapts them rather than copying them.

---

## Phase 1 — typed contract and authorization core

### Task 1: Add the official MCP server dependency safely

**Files:**

- Modify: `package.json`
- Modify: `package-lock.json`
- Test: `src/lib/agent-control-plane/__tests__/dependency-boundary.test.ts`

- [ ] **Step 1: Write the dependency-boundary test**

Test that the MCP adapter can import `McpServer`/`createMcpHandler`, while no file outside `src/lib/agent-control-plane/mcp/` and `src/app/mcp/` imports the SDK.

Also enforce that SDK-bound schemas import from `zod-v4`, the repository's existing Zod 3 dependency is unchanged, and no MCP schema imports `zod/v4`.

- [ ] **Step 2: Run it and prove failure**

```bash
npm test -- src/lib/agent-control-plane/__tests__/dependency-boundary.test.ts
```

Expected: fail because the package/adapter does not exist.

- [ ] **Step 3: Install verified dependencies**

Install the exact versions verified in Gate 3 without changing the repository-wide Zod 3 dependency:

```bash
npm install @modelcontextprotocol/server@2.0.0 zod-v4@npm:zod@4.2.0
```

Do not install the deprecated monolithic v1 `@modelcontextprotocol/sdk` package. Do not upgrade or replace the existing `zod@^3.24.0` dependency.

- [ ] **Step 4: Add the smallest import-only adapter shell**

Create `src/lib/agent-control-plane/mcp/sdk.ts` exporting only the approved SDK symbols/types used by OPS. MCP registration schemas import `z` from `zod-v4`; never re-export either Zod instance across the boundary.

- [ ] **Step 5: Verify**

```bash
npm test -- src/lib/agent-control-plane/__tests__/dependency-boundary.test.ts
npm ls @modelcontextprotocol/server zod zod-v4
npm run type-check
```

- [ ] **Step 6: Commit**

```bash
git add package.json package-lock.json src/lib/agent-control-plane
git commit -m "build(agent-control-plane): add MCP v2 server boundary"
```

### Task 2: Define common contracts and schemas

**Files:**

- Create: `src/lib/agent-control-plane/contracts/version.ts`
- Create: `src/lib/agent-control-plane/contracts/common.ts`
- Create: `src/lib/agent-control-plane/contracts/errors.ts`
- Create: `src/lib/agent-control-plane/contracts/jobs.ts`
- Create: `src/lib/agent-control-plane/contracts/conversation.ts`
- Create: `src/lib/agent-control-plane/contracts/evidence.ts`
- Create: `src/lib/agent-control-plane/contracts/index.ts`
- Test: `src/lib/agent-control-plane/contracts/__tests__/schemas.test.ts`
- Test fixtures: `src/lib/agent-control-plane/contracts/__fixtures__/v1.ts`

- [ ] **Step 1: Write failing schema/serialization tests**

Cover:

- exact `contract_version`;
- discriminated `JobRef`;
- opaque string IDs;
- RFC 3339 timestamps;
- IANA timezone plus local/UTC schedule representation;
- integer minor-unit money;
- source versions/evidence/trust labels;
- deterministic cursor page;
- warnings and the stable error code union;
- maximum limits and rejected unknown fields on tool input;
- compatible parsing of frozen v1 fixtures.

- [ ] **Step 2: Run tests and prove failure**

```bash
npm test -- src/lib/agent-control-plane/contracts/__tests__/schemas.test.ts
```

- [ ] **Step 3: Implement schemas and inferred types**

Author the new agent-control-plane contracts exposed through MCP once with `zod-v4` and infer their TypeScript types. Existing OPS Zod 3 schemas remain unchanged and exchange only parsed plain values with these contracts. Do not compose Zod 3 and Zod 4 schema objects or hand-maintain duplicate TypeScript interfaces and JSON schemas.

- [ ] **Step 4: Add contract fixture snapshot**

Freeze one complete success result, one cursor page, one evidence result, and one error result. Future additive changes must continue to parse these fixtures.

- [ ] **Step 5: Verify and commit**

```bash
npm test -- src/lib/agent-control-plane/contracts/__tests__/schemas.test.ts
npm run type-check
git add src/lib/agent-control-plane/contracts
git commit -m "feat(agent-control-plane): define stable v1 contracts"
```

### Task 3: Build `ActorContext` and current permission resolution

**Files:**

- Create: `src/lib/agent-control-plane/actor/types.ts`
- Create: `src/lib/agent-control-plane/actor/resolve-actor-context.ts`
- Create: `src/lib/agent-control-plane/actor/authorize-capability.ts`
- Create: `src/lib/agent-control-plane/actor/entity-scope.ts`
- Modify: `src/lib/permissions/resolve.ts` only if a pure shared primitive is missing
- Test: `src/lib/agent-control-plane/actor/__tests__/resolve-actor-context.test.ts`
- Test: `src/lib/agent-control-plane/actor/__tests__/authorize-capability.test.ts`
- Test: `src/lib/agent-control-plane/actor/__tests__/entity-scope.test.ts`

- [ ] **Step 1: Write the authorization matrix first**

Cover internal/Firebase and MCP grant actors; owner/admin bypass; role plus override; revoked/narrowed override; inactive user; wrong company; assigned/all/own; OAuth scope ceiling; entity reassignment after token issue; financial section permission; privacy-safe not-found.

- [ ] **Step 2: Run and prove failure**

```bash
npm test -- src/lib/agent-control-plane/actor
```

- [ ] **Step 3: Implement one server-owned resolver**

Resolve current user/company/role/overrides/assignments from authoritative data for every request. Never accept `company_id`, role, or assignment from a tool payload or bearer-token claim as sufficient authorization.

- [ ] **Step 4: Add service-role query guard**

Every control-plane repository/query receives an authorized context and explicit entity visibility predicate. Make unscoped repository construction impossible by type.

- [ ] **Step 5: Cross-check existing semantics**

Keep behavior aligned with:

- `src/lib/permissions/resolve.ts`
- database `has_permission` / `current_user_scope_for` behavior
- existing project/task/client/calendar permission definitions

- [ ] **Step 6: Verify and commit**

```bash
npm test -- src/lib/agent-control-plane/actor
npm run type-check
git add src/lib/agent-control-plane/actor src/lib/permissions/resolve.ts
git commit -m "feat(agent-control-plane): enforce actor and entity scope"
```

### Task 4: Add capability registry and tool policy

**Files:**

- Create: `src/lib/agent-control-plane/registry/capability-types.ts`
- Create: `src/lib/agent-control-plane/registry/capability-manifest.ts`
- Create: `src/lib/agent-control-plane/registry/read-tools.ts`
- Create: `src/lib/agent-control-plane/registry/write-tools.ts`
- Test: `src/lib/agent-control-plane/registry/__tests__/manifest.test.ts`

- [ ] **Step 1: Write manifest invariant tests**

Every capability must have unique stable name, schema, risk tier, scopes, OPS permission resolver, bounds, evidence policy, audit class, rate bucket, annotations, and confirmation rule. Commit capability cannot exist without prepare sibling. No generic CRUD/raw-data names allowed.

- [ ] **Step 2: Implement the server-owned manifest**

Register the nine initial read tools and four dark write pairs from the foundation design. Keep external exposure flags separate from implementation availability. Task 4A owns the later site-visit delta to eleven reads and seven write pairs.

- [ ] **Step 3: Prove annotations are accurate**

Snapshot `readOnlyHint`, `destructiveHint`, and `openWorldHint`; tests fail if a write is mislabeled read-only.

- [ ] **Step 4: Verify and commit**

```bash
npm test -- src/lib/agent-control-plane/registry
git add src/lib/agent-control-plane/registry
git commit -m "feat(agent-control-plane): add governed capability manifest"
```

### Task 4A: Extend the dark manifest for site-visit booking

**Files:**

- Modify: `src/lib/agent-control-plane/registry/capability-types.ts`
- Modify: `src/lib/agent-control-plane/registry/capability-manifest.ts`
- Modify: `src/lib/agent-control-plane/registry/read-tools.ts`
- Modify: `src/lib/agent-control-plane/registry/write-tools.ts`
- Modify: `src/lib/agent-control-plane/registry/__tests__/manifest.test.ts`
- Create: `src/lib/agent-control-plane/registry/__tests__/site-visit-capabilities.test.ts`
- Modify: `supabase/migrations/20260807223000_agent_correspondence_evidence_read.sql`
- Modify: `src/lib/agent-control-plane/evidence/__tests__/rpc-contract.test.ts`
- Modify: `src/lib/agent-control-plane/evidence/__tests__/bounds.test.ts`

- [x] **Step 1: Freeze the domain boundary**

Use `specs/2026-08-10-site-visit-mcp-capability-briefing.md` and its approved companion design. Add two reads plus three prepare/commit booking families. Explicitly prohibit start/complete and direct row-write tools.

- [x] **Step 2: Write the failing manifest tests**

Cover the `booked_at` appointment discriminator, separate `created_at` history window, linked/unlinked authorization, bounded evidence, company-timezone schedule instants, `pipeline.convert`, exact confirmation, accurate MCP annotations, and dark availability.

- [x] **Step 3: Add manifest revision v2**

Advance the global manifest identity to `2026-08-10.capability-manifest.v2`, propagate it through the evidence-read contract, reuse existing OAuth scopes, and keep every site-visit entry unavailable and externally disabled. The definitions do not implement the read services, change-set participants, booking RPCs, migrations, or calendar workers.

- [x] **Step 4: Verify, independently review, and commit**

```bash
npm test -- src/lib/agent-control-plane/registry src/lib/agent-control-plane/evidence/__tests__/rpc-contract.test.ts src/lib/agent-control-plane/evidence/__tests__/bounds.test.ts
npm run type-check
git diff --check
git add src/lib/agent-control-plane/registry src/lib/agent-control-plane/evidence/__tests__/rpc-contract.test.ts src/lib/agent-control-plane/evidence/__tests__/bounds.test.ts supabase/migrations/20260807223000_agent_correspondence_evidence_read.sql
git commit -m "feat(agent-control-plane): add dark site visit capabilities"
```

Do not flip availability or exposure here. The booking RPC implementation plan must first resolve RPC idempotency, `pipeline.convert`, stale-version comparison, same-company assignee validation, unlinked-read isolation, external calendar reconciliation, and the contradictory reminder-dedupe wording. The only accepted key is `site_visit:<visit_id>:<kind>:<user_id>:<scheduled_at epoch>`.

Implemented locally in `91419970`. The full agent-control-plane source suite passes (22 files, 485 tests), plus TypeScript, focused ESLint, Prettier, diff checks, and independent P0/P1 review. This is manifest/source proof only. Every site-visit entry remains unavailable and externally disabled; no booking RPC, handler, migration, database write, calendar effect, deployment, or customer-live behavior is claimed.

**As-built update (2026-08-14):** The canonical `book_site_visit`, `reschedule_site_visit`, and `cancel_site_visit_booking` RPCs, booking schema, prompt cron, and Google Calendar sync worker were later implemented and are production-live outside this agent-control-plane branch. That does not complete Task 4A's control-plane read services, handlers, change-set participants, receipts, or adapters. Every site-visit manifest entry therefore remains unavailable and externally disabled.

---

## Phase 2 — evidence and job conversation memory

### Task 5: Design and apply the local/test memory schema

**Files:**

- Create: `supabase/migrations/<timestamp>_agent_job_conversation_memory.sql`
- Mirror only after production apply/readback: `ops-software-bible/migrations/<same-file>.sql`
- Modify after implementation: `ops-software-bible/03_DATA_ARCHITECTURE.md`
- Test: `src/lib/agent-control-plane/memory/__tests__/schema-contract.test.ts`

- [x] **Step 1: Re-read production schema and migration ledger**

Verify opportunities/projects/client identifiers, email/activity source IDs, cascade behavior, RLS helpers, and conversion references. Choose a fresh timestamp after the current ledger.

- [x] **Step 2: Write failing repository/schema expectations**

Cover:

- `job_conversations`;
- `job_conversation_anchors` with unique company/type/source identity;
- `job_conversation_turns` with immutable delivered source identity and content hash;
- `job_memory_versions` with per-conversation version uniqueness and predecessor/high-watermark;
- `job_memory_version_evidence`;
- `job_conversation_redaction_events`;
- foreign-key indexes, RLS, CHECK constraints, and no direct client update/delete on immutable turns/versions.

- [x] **Step 3: Write migration with comments and guarded functions**

Use UUID foreign keys where authoritative tables use UUID; do not copy guessed text types. Enforce company consistency. Add append-only triggers/policies. Add a guarded function for atomic turn insert plus conversation/anchor resolution.

- [ ] **Step 4: Apply only to local/test Supabase**

Do not apply production in this task unless Jackson explicitly authorized production migrations. Run schema/RLS/readback tests against the local/test database.

- [x] **Step 5: Commit code migration only**

```bash
git add supabase/migrations/<timestamp>_agent_job_conversation_memory.sql src/lib/agent-control-plane/memory
git commit -m "feat(agent-memory): add immutable job conversation schema"
```

Update the bible schema chapter in the same session as a real code implementation. The bible `migrations/` archive is production-applied history, so mirror this SQL there only after the production ledger/readback proves it was applied. Do not claim deployment before that proof.

### Task 6: Implement evidence normalization and prompt-safe output

**Files:**

- Create: `src/lib/agent-control-plane/evidence/types.ts`
- Create: `src/lib/agent-control-plane/evidence/normalize-correspondence.ts`
- Create: `src/lib/agent-control-plane/evidence/source-version.ts`
- Create: `src/lib/agent-control-plane/evidence/prompt-safe.ts`
- Create: `src/lib/agent-control-plane/evidence/repository.ts`
- Test: `src/lib/agent-control-plane/evidence/__tests__/normalize-correspondence.test.ts`
- Test: `src/lib/agent-control-plane/evidence/__tests__/prompt-injection.test.ts`
- Test: `src/lib/agent-control-plane/evidence/__tests__/bounds.test.ts`

- [x] **Step 1: Write adversarial fixtures**

Include hidden HTML, scripts/styles, tracking markup, remote includes, prompt instructions, hostile filenames, oversized bodies, attachment metadata, Unicode controls, contradictory claims, and cross-company evidence IDs.

- [x] **Step 2: Implement normalization**

Return exact persisted normalized plain text plus immutable content hash and trust classification. Preserve source text as data while stripping active/hidden markup. Do not “clean” semantic content into a summary.

- [x] **Step 3: Implement bounded evidence repository**

Require authorized context, maximum 20 evidence IDs, maximum 60,000 total characters, deterministic ordering, and privacy-safe not-found.

- [x] **Step 4: Verify and commit**

```bash
npm test -- src/lib/agent-control-plane/evidence
git add src/lib/agent-control-plane/evidence
git commit -m "feat(agent-control-plane): normalize source-provenanced evidence"
```

### Task 7: Ingest immutable delivered turns

**Files:**

- Create: `src/lib/agent-control-plane/memory/resolve-conversation.ts`
- Create: `src/lib/agent-control-plane/memory/resolve-participant-side.ts`
- Create: `src/lib/agent-control-plane/memory/ingest-delivered-turn.ts`
- Create: `src/lib/agent-control-plane/memory/turn-repository.ts`
- Modify: exact inbound email ingestion seam discovered in current `src/lib/api/services/`
- Modify: exact outbound delivery/reconciliation seam discovered in current `src/lib/api/services/email-send-*.ts`
- Test: `src/lib/agent-control-plane/memory/__tests__/ingest-delivered-turn.test.ts`
- Test: `src/lib/agent-control-plane/memory/__tests__/conversation-anchor.test.ts`

- [x] **Step 1: Write lifecycle tests**

Cover inbound/outbound, replay, unsent draft exclusion, send-intent exclusion, delivery reconciliation, ambiguous participant, provider thread spanning jobs, opportunity conversion, new returning-customer job, and redaction overlay.

- [x] **Step 2: Resolve anchors and roles from evidence**

Use opportunity/project conversion links. Preserve one conversation across conversion. Never anchor to provider thread. Current client/sub-client rows map to memory `user`; a related contact does so only when a concrete authorized relationship record confirms it. OPS actor/Phase C maps to memory `assistant`; conversation-only or otherwise ambiguous identity remains unresolved.

- [x] **Step 3: Insert idempotently at delivery chokepoints**

Do not scatter hooks through draft generation. The inbound delivered-message persist and outbound delivery reconciliation paths are the only initial entry points.

- [x] **Step 4: Verify and commit**

```bash
npm test -- src/lib/agent-control-plane/memory/__tests__/ingest-delivered-turn.test.ts src/lib/agent-control-plane/memory/__tests__/conversation-anchor.test.ts
git add src/lib/agent-control-plane/memory src/lib/api/services
git commit -m "feat(agent-memory): ingest delivered job turns"
```

### Task 8: Generate versioned running memory

**Files:**

- Create: `src/lib/agent-control-plane/memory/memory-schema.ts`
- Create: `src/lib/agent-control-plane/memory/build-memory-version.ts`
- Create: `src/lib/agent-control-plane/memory/memory-repository.ts`
- Create: `src/lib/agent-control-plane/memory/memory-deadline.ts`
- Create: `src/lib/agent-control-plane/memory/catch-up-memory.ts`
- Create: `src/lib/agent-control-plane/memory/cross-job-seed.ts`
- Modify: `src/lib/agent-control-plane/memory/ingest-delivered-turn.ts`
- Modify: `src/lib/agent-control-plane/memory/turn-repository.ts`
- Modify: `src/lib/agent-control-plane/evidence/normalize-correspondence.ts`
- Modify: `src/lib/api/services/provider-delivery-source-service.ts`
- Modify: `src/lib/data/company-data-manifest.ts`
- Modify: `supabase/migrations/20260807220000_agent_job_conversation_memory.sql`
- Modify: `supabase/migrations/20260807224500_agent_provider_delivery_sources.sql`
- Test: `src/lib/agent-control-plane/memory/__tests__/build-memory-version.test.ts`
- Test: `src/lib/agent-control-plane/memory/__tests__/catch-up-memory.test.ts`
- Test: `src/lib/agent-control-plane/memory/__tests__/cross-job-seed.test.ts`
- Test: `src/lib/agent-control-plane/memory/__tests__/memory-repository.test.ts`
- Test: `src/lib/agent-control-plane/memory/__tests__/ingest-delivered-turn.test.ts`
- Test: `src/lib/agent-control-plane/memory/__tests__/persist-captured-provider-delivery-turn.test.ts`
- Test: `src/lib/agent-control-plane/memory/__tests__/schema-contract.test.ts`
- Test: `tests/integration/company-data-manifest.test.ts`
- Test: `tests/unit/email/provider-delivery-source-service.test.ts`
- Test: `tests/unit/supabase/agent-provider-delivery-source-migration.test.ts`

- [x] **Step 1: Freeze the structured memory schema**

Include facts, decisions, commitments, preferences, open questions, contradictions, schedule assertions, financial facts relevant to conversation, excluded assumptions, and evidence IDs. Every claim requires evidence.

- [x] **Step 2: Write failing generation tests**

Cover optimistic version conflict, model failure, missing evidence, contradiction preservation, replay, high-watermark, no raw prior-job copy, and current-through-required-turn behavior.

- [x] **Step 3: Implement deterministic input assembly plus structured model output**

Use bounded previous memory, new exact turns, and exact evidence. Validate model output. A failed/invalid output never advances current memory.

- [x] **Step 4: Implement synchronous catch-up for source-bound drafts**

If `required_through_turn_id` is newer than memory, catch up within a bounded deadline. Otherwise return `STALE_CONTEXT`. Never silently use stale memory.

- [x] **Step 5: Implement minimal cross-job seed**

Return only prior-job boolean/count/latest visible date/status and one safe continuity marker. Deeper data remains behind explicit history search.

- [x] **Step 6: Verify and commit**

```bash
npm test -- src/lib/agent-control-plane/memory tests/unit/email/provider-delivery-source-service.test.ts tests/unit/email/provider-delivery-source-wiring.test.ts tests/unit/supabase/agent-provider-delivery-source-migration.test.ts tests/integration/company-data-manifest.test.ts
npm run type-check
git diff --check
git add src/lib/agent-control-plane/memory src/lib/agent-control-plane/evidence/normalize-correspondence.ts src/lib/api/services/provider-delivery-source-service.ts src/lib/data/company-data-manifest.ts supabase/migrations/20260807220000_agent_job_conversation_memory.sql supabase/migrations/20260807224500_agent_provider_delivery_sources.sql tests/integration/company-data-manifest.test.ts tests/unit/email/provider-delivery-source-service.test.ts tests/unit/supabase/agent-provider-delivery-source-migration.test.ts
git commit -m "feat(agent-memory): add versioned evidence-backed job memory"
```

Implemented locally in `14969c4c`. Focused source tests, TypeScript, lint, and diff checks pass. The SQL remains unapplied, and no runtime consumer, background worker, deployment, or customer-live behavior is claimed.

### Task 9: Build `get_job_conversation_context`

**Files:**

- Create: `src/lib/agent-control-plane/services/get-job-conversation-context.ts`
- Create: `src/lib/agent-control-plane/services/job-conversation-context-authorization.ts`
- Create: `src/lib/agent-control-plane/services/job-conversation-context-repository.ts`
- Create: `supabase/migrations/20260811120000_agent_job_conversation_context_read.sql`
- Modify: `src/lib/agent-control-plane/registry/read-tools.ts`
- Modify: `src/lib/agent-control-plane/registry/capability-manifest.ts`
- Modify: `src/lib/agent-control-plane/evidence/repository.ts`
- Modify: `supabase/migrations/20260807223000_agent_correspondence_evidence_read.sql`
- Test: `src/lib/agent-control-plane/services/__tests__/get-job-conversation-context.test.ts`
- Test: `src/lib/agent-control-plane/services/__tests__/job-conversation-context-rpc.test.ts`
- Test: `src/lib/agent-control-plane/registry/__tests__/conversation-context-capability.test.ts`

- [x] **Step 1: Write contract tests**

Assert ordering: memory, recent exact turns, triggering evidence, participants, freshness/gaps. Default 20 turns, maximum 50, complete result maximum 60,000 characters. Permission checks apply to every source.

- [x] **Step 2: Implement service**

Return memory version/high-watermark and warnings. Evidence excerpts are exact normalized source, not a second model summary.

- [x] **Step 3: Verify and commit**

```bash
node node_modules/vitest/vitest.mjs run src/lib/agent-control-plane
node node_modules/typescript/bin/tsc --noEmit
git diff --check
git commit -m "feat(agent-control-plane): expose job conversation context"
```

Implemented locally in `7472219a`. At the Task 9 checkpoint, the final gate passed 25 agent-control-plane test files / 514 tests, TypeScript, focused lint, formatting, staged diff checks, and three independent P0/P1 reviews. The capability was still dark (`implementation=unavailable`, `externalExposure=disabled`) because no shared facade existed yet. Its SQL remains source-reviewed and structurally tested but has not been executed by PostgreSQL or applied to any Supabase environment. Task 10 below adds the shared facade and advances internal implementation availability only; no Phase C consumer, background worker, OAuth surface, remote MCP transport, push, deployment, or customer-live behavior is claimed.

---

## Phase 3 — shared operational read services

### Task 10: Define the domain service facade

**Files:**

- Create: `src/lib/agent-control-plane/services/domain-service.ts`
- Create: `src/lib/agent-control-plane/services/create-domain-service.ts`
- Create: `src/lib/agent-control-plane/services/repositories.ts`
- Test: `src/lib/agent-control-plane/services/__tests__/domain-service.test.ts`
- Modify: `src/lib/agent-control-plane/registry/read-tools.ts`
- Modify: `src/lib/agent-control-plane/registry/__tests__/conversation-context-capability.test.ts`
- Modify: `src/lib/agent-control-plane/registry/__tests__/manifest.test.ts`

- [x] **Step 1: Write adapter-independence test**

The same actor/input must yield the same parsed result through internal, REST, and MCP adapter stubs. No transport type may appear in a domain service signature.

- [x] **Step 2: Implement the typed facade**

Wire `getJobConversationContext`; keep unimplemented methods explicit and unavailable in the capability manifest until their tests pass. Do not add placeholder success values.

- [x] **Step 3: Verify and commit**

```bash
npm test -- src/lib/agent-control-plane/services/__tests__/domain-service.test.ts
git add src/lib/agent-control-plane/services
git commit -m "feat(agent-control-plane): add shared domain service facade"
```

Implemented locally in `73712b4f`. The runtime interface exposes only `getJobConversationContext`; internal, OPS API, and fully scoped MCP actor contexts produce the same parsed result through test-only forwarders, while strict injected authority/tenant/token fields, missing MCP scopes, cloned actors, and structural repositories fail before a read. Factory dependencies are captured once before validation and never reread from caller-owned getters. Only `get_job_conversation_context` is `implementation=available`; all external exposure remains disabled. The final gate passed 26 agent-control-plane test files / 521 tests, TypeScript, focused ESLint, Prettier, staged and working diff checks, and three independent P0/P1 reviews. No Phase C/REST/MCP adapter, route, OAuth surface, remote server, migration application, push, deployment, or customer-live behavior is claimed.

### Task 11: Implement schedule and readiness reads

**Files:**

- Create: `src/lib/agent-control-plane/contracts/schedule.ts`
- Create: `src/lib/agent-control-plane/services/list-scheduled-jobs.ts`
- Create: `src/lib/agent-control-plane/services/list-job-readiness-issues.ts`
- Create: `src/lib/agent-control-plane/services/readiness-rules.ts`
- Create: `src/lib/agent-control-plane/services/scheduled-jobs-authorization.ts`
- Create: `src/lib/agent-control-plane/services/job-readiness-authorization.ts`
- Create: `src/lib/agent-control-plane/services/scheduled-jobs-repository.ts`
- Create: `src/lib/agent-control-plane/services/job-readiness-repository.ts`
- Create: `src/lib/agent-control-plane/services/operational-read-cursor.ts`
- Create: `src/lib/agent-control-plane/services/operational-read-projection.ts`
- Create: `supabase/migrations/20260812120000_agent_operational_schedule_readiness.sql`
- Modify: shared domain-service facade/repository bundle and capability manifest
- Modify: guarded schedule-confirmation writers and generated database types
- Test: schedule/readiness contracts, rules, authorization, repositories, reducers, facade parity, cursors, projection hashes, SQL/RPC structure, and confirmation writer contracts

- [x] **Step 1: Write adversarial schedule tests**

Include DST boundaries, company timezone, multiple task occurrences, stale/versioned schedules, locked/unconfirmed tasks, assignments, reschedule during pagination, and assigned-scope filtering.

- [x] **Step 2: Write readiness tests**

Cover missing/non-missing photos, deleted photos, site-visit photos, legacy fallback, unresolved customer, incomplete address, crew missing, unconfirmed schedule, and rule revision evidence.

- [x] **Step 3: Implement fixed source reads, keyset pagination, and hard bounds**

Do not adapt the browser project/team/photo services: their caller-supplied tenant IDs, multi-query snapshots, offset pagination, and broad employee/photo payloads cannot satisfy the agent-control-plane authority boundary. Use nominal service-owned authorization proofs and repository brands over two fixed service-role-only RPCs. Each RPC must re-resolve the complete actor permission registry, entity access, scopes, tenant, permission revision, and source fence inside the same SQL statement.

Schedule v1 is project-task-only, with maximum 90-day windows, default 25/maximum 50 rows, exact company-local time conversion, orthogonal lifecycle/timing/confirmation state, current-version confirmation proof, safe bounded crew display, and signed source-stable keyset pagination. Site visits remain dark and excluded.

Readiness SQL returns bounded safe raw facts, never rule decisions. `readiness-rules.ts` alone derives the five versioned rules. Conditional manifest variants add photos/customer scopes only when their rule is requested. One read may scan at most five 50-project source pages under one fence, while returned claims/proofs remain under the 60,000-character and 100-evidence limits.

The operational source revision advances for every table that can change selection, ordering, schedule display, assignments, customer resolution, or photo readiness. Cursors bind that revision and all authority/query/schema/rule inputs. Any relevant mutation returns `STALE_CONTEXT`; it never silently duplicates or omits rows.

The manifest advances once to `2026-08-12.capability-manifest.v4`. Existing conversation/evidence reads receive compatibility wrappers so the revision bump does not break the already-available internal conversation capability. Only `get_job_conversation_context`, `list_scheduled_jobs`, and `list_job_readiness_issues` may be internally available after the complete gate; all external exposure remains disabled.

- [x] **Step 4: Verify and commit**

```bash
npm test -- --run src/lib/agent-control-plane
npm run type-check
git diff --check
git add <Task 11 paths only>
git commit -m "feat(agent-control-plane): add schedule and readiness reads"
```

Implemented locally in OPS Web commit `5bba3c5e` on 2026-08-13. The final Task 11 matrix passed 47 files / 784 tests; the company-data manifest passed 71/71; exact TypeScript, Prettier, and diff checks passed. An independent final review of the frozen SQL and TypeScript boundaries found no P0/P1 issue. The full repository run passed 11,495 tests and retained 82 pre-existing email/provider fixture failures that reproduce unchanged on baseline `73712b4f`; Task 11 adds no deterministic full-suite failure.

Both migrations remain unapplied. No Supabase branch, local/test/preview/production migration apply, push, deployment, MCP/REST adapter, external advertisement, or customer-live behavior is claimed. Production PostgreSQL tzdata must be updated to the current BC permanent-UTC-7 rules and pass the migration's database/runtime conformance vectors before release; platform update cost and downtime remain unknown.

### Task 12: Implement communication and participant reads

**Files:**

- Create: `src/lib/agent-control-plane/contracts/communication.ts`
- Create: `src/lib/agent-control-plane/services/communication-participant-snapshot.ts`
- Create: `src/lib/agent-control-plane/services/get-job-communication-context.ts`
- Create: `src/lib/agent-control-plane/services/resolve-job-participants.ts`
- Create: `src/lib/agent-control-plane/services/job-communication-authorization.ts`
- Create: `src/lib/agent-control-plane/services/job-participants-authorization.ts`
- Create: `src/lib/agent-control-plane/services/job-communication-context-repository.ts`
- Create: `src/lib/agent-control-plane/services/job-participants-repository.ts`
- Create: `supabase/migrations/20260813120000_agent_job_communication_participants.sql`
- Modify: shared readiness photo derivation, domain facade/repository bundle, capability manifest, and compatibility RPCs
- Test: communication contracts; pure derivation/services; authorization; repositories; SQL/RPC structure; manifest/facade parity; proof, freshness, bounds, abort, and privacy invariants

- [x] **Step 1: Write participant/privacy tests**

Cover current primary client and sub-client rows, conversation ambiguity/unresolved/redaction, the deliberate absence of confirmed conversation-only related contacts, OPS delivery actors, Phase C, purpose-bound task assignments, global email suppression, duplicate email ownership, missing/invalid/unavailable contactability, private employee contact/role exclusion, wrong-company identity collisions, malicious source strings, projection tampering, source freshness, abort forwarding, and bounded reduction.

- [x] **Step 2: Implement current-only, purpose-specific context**

Do not adapt the browser contact resolver, party classifier, or broad contactability services: their multi-query/browser trust boundaries cannot prove one current actor-authorized snapshot. Use two nominal service-owned authorization/repository paths over one private strict snapshot schema and two fixed service-role-only RPCs. The private SQL implementation re-resolves the actor, company, permission snapshot, job/customer/project/mailbox visibility, and purpose-dependent task/photo access inside the same statement.

Inputs are current-only: neither capability accepts `as_of`. `get_job_communication_context` supports `general`, `schedule_notice`, and `photo_request`; the latter two add only their bounded schedule/photo facts. Photo readiness reuses the Task 11 TypeScript-owned `SITE_PHOTOS_MISSING` rule. `resolve_job_participants` defaults to `general`; only `schedule` and `assignment` may add active same-company assignment users after task/project authorization.

V1 contactability is email-only. Only one confirmed, normalized, unsuppressed address is returned. Suppression, duplicate ownership, absence, ambiguity, unavailable/query-bound/invalid sources, unresolved identity, and redaction withhold the address and produce a matching fixed non-recipient state. Primary client is the only default-eligible recipient; a contactable sub-client requires explicit selection. Preferred channel is always null; phone/SMS consent, preference, and opt-out claims are unavailable. OPS and Phase C stay assistant-side and expose no private contact or employee-role fields.

Concrete IDs require a current confirmed record. Ambiguous/unresolved identities receive `unknown:sha256:<digest>`; redacted identities receive `redacted:sha256:<digest>`. Conversation evidence alone never confirms a related contact. Each participant carries one authoritative projection evidence atom; collection/context proofs bind the actor, tenant, job, purpose, permission/manifest/source/contactability revisions, lower-bound truth, fixed gaps, and ordered claim proofs. The service retains complete claims with evidence/proofs under 60,000 characters, prioritizing schedule occurrences before participant claims for communication context.

Manifest revision `2026-08-13.capability-manifest.v5` makes both capabilities internally available and keeps external exposure disabled. V5 compatibility wrappers accept only the exact v5 revision and privately supply the frozen v4 literal to the earlier conversation, evidence, schedule, and readiness implementations; callers cannot select a legacy revision.

- [x] **Step 3: Verify and commit**

```bash
/Users/jacksonsweet/.nvm/versions/node/v22.22.3/bin/node node_modules/vitest/vitest.mjs run \
  --maxWorkers=4 --minWorkers=1 --testTimeout=60000 \
  src/lib/agent-control-plane/contracts/__tests__/communication.test.ts \
  src/lib/agent-control-plane/registry/__tests__/manifest.test.ts \
  src/lib/agent-control-plane/services/__tests__/communication-participant-authorization.test.ts \
  src/lib/agent-control-plane/services/__tests__/communication-participant-domain-service.test.ts \
  src/lib/agent-control-plane/services/__tests__/get-job-communication-context.test.ts \
  src/lib/agent-control-plane/services/__tests__/job-communication-context-repository.test.ts \
  src/lib/agent-control-plane/services/__tests__/job-communication-rpc-contract.test.ts \
  src/lib/agent-control-plane/services/__tests__/job-participants-repository.test.ts \
  src/lib/agent-control-plane/services/__tests__/job-participants-rpc-contract.test.ts \
  src/lib/agent-control-plane/services/__tests__/readiness-rules.test.ts \
  src/lib/agent-control-plane/services/__tests__/resolve-job-participants.test.ts \
  src/lib/agent-control-plane/services/__tests__/task12-manifest-v5-rpc-compatibility.test.ts
/Users/jacksonsweet/.nvm/versions/node/v22.22.3/bin/node node_modules/typescript/bin/tsc --noEmit --pretty false
git diff --check
git commit -m "feat(agent-control-plane): add communication and participant reads"
```

Implemented locally in OPS Web commit `dc91a349` on 2026-08-14. The exact focused Task 12 matrix passed 12 files / 169 tests; Node 22 TypeScript `--noEmit` and `git diff --check` passed; an independent frozen cross-boundary review found no P0/P1 issue. This is local source/test evidence, not database-runtime or deployment proof.

Migration `20260813120000_agent_job_communication_participants.sql` remains unapplied and has not been database-compiled or executed. It requires the Task 9 and Task 11 tables/functions plus both Task 11 migrations in order. Any schedule-bearing Task 12 purpose also invokes the Task 11 timezone conformance gate, so production PostgreSQL tzdata and the pinned Node runtime must first agree with the current BC permanent-UTC-7 rules. After those prerequisites, apply and rollback must be exercised on an isolated Supabase branch, then the fixed RPCs must receive runtime same-statement authority, wrong-company, suppression-change, source-change, bound, proof, and privilege tests before any adapter or rollout flag can be enabled. No migration copy belongs in the Bible archive until it is actually applied.

No Supabase branch, local/test/preview/production migration apply, Phase C/REST/MCP adapter, push, deployment, external advertisement, or customer-live behavior is claimed.

### Task 13: Implement customer jobs, job summary, history search, and evidence lookup

**Files:**

- Create: `src/lib/agent-control-plane/contracts/job-catalog.ts`
- Create: `src/lib/agent-control-plane/services/list-customer-jobs.ts`
- Create: `src/lib/agent-control-plane/services/get-job-summary.ts`
- Create: `src/lib/agent-control-plane/services/search-job-history.ts`
- Create: `src/lib/agent-control-plane/services/get-correspondence-evidence.ts`
- Create: four capability-specific nominal authorization modules and four fixed repository modules
- Create: `supabase/migrations/20260814120000_agent_job_catalog_reads.sql`
- Modify: shared domain-service facade/repository bundle, operational cursor, capability manifest, Task 12 manifest compatibility, and legacy correspondence-evidence compatibility wrapper
- Test: contracts, authorization, repositories, services/reducers, facade parity, manifest compatibility, cursor/proof tampering, SQL/RPC structure, bounds, abort, privacy, and earlier-read regressions

- [x] **Step 1: Write permission/section tests**

Financial summary requires the exact existing financial permission. Correspondence/history require their scopes. An unauthorized section cannot leak through evidence or warning text.

- [x] **Step 2: Write search/pagination tests**

Maximum one-year window, query length 500, result maximum 20, deterministic keyset cursor, exact versus summary match labeling, contradiction preservation, and cross-job relevance.

- [x] **Step 3: Implement one authorized snapshot per read**

Do not sequentially compose Task 9, Task 11, and Task 12 repositories: independently timed snapshots can disagree across sections and cannot prove one authorization/source fence. Each Task 13 capability owns one nominal authorization array and one fixed service-role-only RPC. The RPC re-resolves the complete actor, company, permission registry, entity/customer/mailbox/section authority, canonical input, source/history fences, and every retained source row inside one statement. TypeScript revalidates exact projection hashes, ordered claim/proof/evidence coupling, cursor identity, source completeness, and the public 60,000-character boundary.

- [x] **Step 4: Verify all read services**

```bash
/Users/jacksonsweet/.nvm/versions/node/v22.22.3/bin/node node_modules/vitest/vitest.mjs run \
  src/lib/agent-control-plane \
  tests/unit/supabase/agent-control-plane-actor-authority-migration.test.ts \
  tests/unit/supabase/agent-job-catalog-reads-migration.test.ts \
  tests/unit/supabase/agent-memory-schema-reconciliation-migration.test.ts \
  tests/unit/supabase/agent-provider-delivery-source-migration.test.ts
/Users/jacksonsweet/.nvm/versions/node/v22.22.3/bin/node --max-old-space-size=8192 \
  node_modules/typescript/bin/tsc --noEmit --pretty false
git diff --check
```

- [x] **Step 5: Commit**

```bash
git commit -m "feat(agent-control-plane): add job catalog reads"
```

Implemented locally in OPS Web commit `d4118344` on 2026-08-14. The final source gate passed 57 files / 1,141 tests, Node 22 TypeScript `--noEmit`, Prettier, and staged/working diff checks. Independent cross-boundary review found no remaining P0/P1 issue. A PostgreSQL 18 ECPG grammar audit parsed all 132 statements in the frozen 7,281-line migration, matched the four RPC arities, and found no generated-schema-column or custom-function-arity conflict. This is structural source evidence, not catalog-bound database-runtime proof.

The four reads use signed source-stable cursors or exact bounded inputs, atomic child and collection/section proofs, explicit source gaps, and one-MiB private wire fences before the public 60,000-character reducers. `list_customer_jobs` filters opportunity/project sources before reciprocal same-client collapse. `get_job_summary` reuses Task 11 schedule/readiness semantics and Task 12 safe participant identity rules. `search_job_history` preserves immutable correspondence selectors and explicit source-bound/data-invalid gaps. `get_correspondence_evidence` is exact-job-bound; full-text mode is all-or-error and returns a fixed non-retryable invalid-argument result when the selected evidence exceeds the public budget.

Migration `20260814120000_agent_job_catalog_reads.sql` remains unapplied and has not been catalog-compiled or executed. It depends on the Task 9, Task 11, and Task 12 migrations and inherits the Task 11 database/runtime timezone-conformance gate for schedule-bearing summaries. After those prerequisites, an isolated Supabase branch must prove ordered apply/rollback, function compilation, grants, RLS/authority behavior, source/history revisions, FTS/index behavior, wrong-company isolation, proof/cursor tampering, source bounds, error mapping, and v6 compatibility wrappers before any adapter or rollout flag is enabled. The platform update and branch costs are not established. No migration copy belongs in the Bible archive until an authorized apply occurs.

No Supabase branch, local/test/preview/production migration apply, Phase C/REST/MCP adapter, push, deployment, external advertisement, or customer-live behavior is claimed.

---

## Phase 4 — Phase C adoption and reply-quality replacement

### Task 14: Add the internal adapter

**Files:**

- Create: `src/lib/agent-control-plane/adapters/internal.ts`
- Test: `src/lib/agent-control-plane/adapters/__tests__/internal.test.ts`

- [ ] **Step 1: Write context-construction tests**

Internal Phase C calls still require an explicit actor/company context derived from the routed job/mailbox. They do not receive blanket service authority.

- [ ] **Step 2: Implement adapter**

Translate internal Phase C request metadata only. Parse the result through the same contracts used by MCP.

- [ ] **Step 3: Verify and commit**

```bash
npm test -- src/lib/agent-control-plane/adapters/__tests__/internal.test.ts
git add src/lib/agent-control-plane/adapters
git commit -m "feat(agent-control-plane): add internal Phase C adapter"
```

### Task 15: Shadow the new memory context against whole-history prompting

**Files:**

- Modify: `src/lib/api/services/ai-draft-service.ts`
- Create: `src/lib/agent-control-plane/memory/reply-context-shadow.ts`
- Create: `src/lib/agent-control-plane/memory/__tests__/reply-context-shadow.test.ts`
- Create: `src/lib/agent-control-plane/evals/lead-reply-quality.ts`
- Add fixtures under: `src/lib/agent-control-plane/evals/fixtures/`

- [ ] **Step 1: Preserve the current path as control**

Do not remove `MAX_SOURCE_BOUND_CONVERSATION_MESSAGES=200` or the 120,000-character path yet. Behind a company flag, assemble both contexts; only the current path supplies the customer-facing draft.

- [ ] **Step 2: Build representative eval fixtures**

Include long histories, contradictions, reschedules, exact attachments, prior job contamination, participant ambiguity, delivery retries, and malicious instructions in correspondence.

- [ ] **Step 3: Compare outcomes**

Score factual correctness, recipient identity, schedule accuracy, commitment continuity, source citation, style, hallucination, context tokens, latency, and safety. Do not score token savings as success if reply quality drops.

- [ ] **Step 4: Verify shadow emits no second draft/send**

Shadow generation must not persist a user-visible draft, create a provider draft, mutate mailbox state, or enter memory.

- [ ] **Step 5: Commit**

```bash
npm test -- src/lib/agent-control-plane/memory src/lib/agent-control-plane/evals
git add src/lib/agent-control-plane src/lib/api/services/ai-draft-service.ts
git commit -m "test(agent-memory): shadow bounded context against full history"
```

### Task 16: Gate and switch Phase C to the shared context

**Files:**

- Modify: `src/lib/api/services/ai-draft-service.ts`
- Modify: exact Phase C feature/config service
- Test: existing AI draft/conversation-state suites
- Add: `src/lib/agent-control-plane/evals/README.md`

- [ ] **Step 1: Define release thresholds before switch**

Required: no regression on factual/recipient/schedule safety; no autonomous draft when memory is stale; evidence coverage for every carried fact; bounded tokens materially below whole history; production shadow sample reviewed.

- [ ] **Step 2: Add per-company rollback flag**

The new path can return to control instantly without schema rollback. Do not delete the old path in the same release.

- [ ] **Step 3: Switch only after measured gate passes**

Record evidence. If not passed, keep shadow mode and fix the shared service; do not widen prompt bounds as the default answer.

- [ ] **Step 4: Verify and commit**

```bash
npm test -- src/lib/api/services src/lib/agent-control-plane
npm run type-check
git add src/lib/api/services src/lib/agent-control-plane
git commit -m "feat(phase-c): use evidence-backed job memory context"
```

---

## Phase 5 — general change-set and confirmation foundation

### Task 17: Add change-set/confirmation persistence locally

**Files:**

- Create: `supabase/migrations/<timestamp>_agent_change_set_confirmation.sql`
- Create: `src/lib/agent-control-plane/changes/types.ts`
- Create: `src/lib/agent-control-plane/changes/repository.ts`
- Test: `src/lib/agent-control-plane/changes/__tests__/schema-contract.test.ts`
- Bible mirror/chapter update after code implementation

- [ ] **Step 1: Verify reusable existing tables/functions**

Inspect `agent_actions`, `audit_log`, guided catalog sessions, approval queue, and guarded RPC patterns. Reuse shared audit/action records where semantics match; do not overload them if required immutable hashes/targets/receipts cannot be represented safely.

- [ ] **Step 2: Write schema expectations**

Expected concepts:

- immutable `agent_change_sets`;
- itemized `agent_change_set_targets` with expected versions;
- `agent_confirmation_requests`;
- hashed, single-use `agent_confirmation_receipts`;
- `agent_commit_receipts`/readback;
- unique actor/idempotency/tool/arguments-hash replay protection;
- company FKs, indexes, RLS, expiry, revocation, append-only controls.

- [ ] **Step 3: Write/apply migration to local/test only**

Use short transactions, deterministic lock order, FK indexes, server-side CHECKs, and no client authority to mint receipts.

- [ ] **Step 4: Verify and commit**

```bash
npm test -- src/lib/agent-control-plane/changes/__tests__/schema-contract.test.ts
git add supabase/migrations/<timestamp>_agent_change_set_confirmation.sql src/lib/agent-control-plane/changes
git commit -m "feat(agent-control-plane): add guarded change-set persistence"
```

### Task 18: Implement prepare, confirmation, commit, and readback engine

**Files:**

- Create: `src/lib/agent-control-plane/changes/normalize-change-set.ts`
- Create: `src/lib/agent-control-plane/changes/prepare.ts`
- Create: `src/lib/agent-control-plane/changes/request-confirmation.ts`
- Create: `src/lib/agent-control-plane/changes/issue-confirmation-receipt.ts`
- Create: `src/lib/agent-control-plane/changes/commit.ts`
- Create: `src/lib/agent-control-plane/changes/readback.ts`
- Create: `src/lib/agent-control-plane/changes/domain-participant.ts`
- Create: `supabase/migrations/<timestamp>_agent_change_set_commit_coordinator.sql`
- Test: `src/lib/agent-control-plane/changes/__tests__/prepare.test.ts`
- Test: `src/lib/agent-control-plane/changes/__tests__/confirmation.test.ts`
- Test: `src/lib/agent-control-plane/changes/__tests__/commit.test.ts`
- Test: `tests/unit/supabase/agent-change-set-commit-coordinator-migration.test.ts`

- [ ] **Step 1: Write attack/concurrency tests first**

Cover fake `confirmed`, wrong actor/company/client/grant, changed normalized args, expired/replayed receipt, stale targets, revoked permission/grant, idempotent retry, conflicting idempotency key, lock ordering, mid-commit failure, batch atomicity, and readback mismatch.

- [ ] **Step 2: Implement canonical hashing**

Normalize exact arguments deterministically and hash capability revision, actor/company/client/grant, targets/versions, evidence, and proposed effects.

- [ ] **Step 3: Implement receipt issuance**

Only the Firebase-authenticated OPS approval action for the exact preview can mint it. MCP `input_required` may present that action's secure OPS URL and poll its status, but host/model continuation text or an unverified host approval assertion cannot mint a receipt. Store only a hash; return an opaque single-use secret to the approved flow.

- [ ] **Step 4: Implement atomic commit harness**

Create a service-role-only generic commit coordinator RPC and private static domain dispatcher. The wrapper accepts only change-set ID, opaque receipt secret, and idempotency key; it reloads actor/company/client/grant from locked immutable rows. Use an explicit fixed `search_path` and security mode, revoke execution from `PUBLIC`, `anon`, and `authenticated`, and grant only `service_role`. The private dispatcher uses a static capability-to-participant mapping—never a caller-supplied function name or dynamic SQL—and fails closed when no participant is registered.

Reauthorize, lock deterministic targets, verify all versions, dispatch the registered private domain transaction participant, consume the receipt, write the sole generic audit/readback record, and return the receipt in that one database transaction. A participant owns only domain validation/effects/readback and cannot consume a receipt or write a parallel generic commit record. Use a documented durable saga only for external effects that cannot share the database transaction.

- [ ] **Step 5: Verify and commit**

```bash
npm test -- src/lib/agent-control-plane/changes tests/unit/supabase/agent-change-set-commit-coordinator-migration.test.ts
git add src/lib/agent-control-plane/changes supabase/migrations/<timestamp>_agent_change_set_commit_coordinator.sql tests/unit/supabase/agent-change-set-commit-coordinator-migration.test.ts
git commit -m "feat(agent-control-plane): enforce confirmed atomic mutations"
```

---

## Phase 6 — first domain write adapters, dark by default

### Task 19: Adapt guided catalog setup

> **Refined task:** Execute this task through `specs/plans/2026-08-07-phase-c-catalog-authoring-control-plane-integration-implementation.md`. That plan preserves this control-plane boundary while expanding the catalog operation from import-only cards to a complete, service-scoped graph. Do not retain or recreate the former import-specific service pair as a parallel path.

**Files:**

- Create: `src/lib/agent-control-plane/services/prepare-catalog-service-change.ts`
- Create: `src/lib/agent-control-plane/services/commit-catalog-service-change.ts`
- Modify only as needed: `src/lib/catalog-setup/phase-c/commit-service.ts`
- Modify only as needed: `src/lib/catalog-setup/phase-c/supabase-commit-adapter.ts`
- Test: `src/lib/agent-control-plane/services/__tests__/catalog-service-change.test.ts`
- Run existing: `src/lib/catalog-setup/phase-c/__tests__/`

- [ ] **Step 1: Prove adapter parity**

The control-plane proposal must reuse the guided session's source facts, capability revision, live snapshot hash, transport-neutral catalog proposal hash, validation, commit operation, journal, and readback. Migrate the old Guided Catalog approval hash into the generic change-set/confirmation receipt; do not retain it as a second authorization system.

- [ ] **Step 2: Support both provenance modes**

OPS file source, structured imports, and model-transcribed structured source feed the same prepared service change. Lower assurance is visible in preview. Unsupported/ambiguous capabilities block commit.

- [ ] **Step 3: Keep external exposure disabled**

Manifest availability may be internal/dark; no public commit tool until OAuth/confirmation/host evals pass.

- [ ] **Step 4: Verify and commit**

```bash
npm test -- src/lib/agent-control-plane/services/__tests__/catalog-service-change.test.ts src/lib/catalog-setup/phase-c
git add src/lib/agent-control-plane/services src/lib/catalog-setup/phase-c
git commit -m "feat(agent-control-plane): adapt guarded catalog service changes"
```

### Task 20: Add estimate import and project cost allocation

**Files:**

- Create: `src/lib/agent-control-plane/services/prepare-estimate-import.ts`
- Create: `src/lib/agent-control-plane/services/commit-estimate-import.ts`
- Create: `src/lib/agent-control-plane/services/prepare-project-cost-allocation.ts`
- Create: `src/lib/agent-control-plane/services/commit-project-cost-allocation.ts`
- Reuse/adapt: `src/lib/api/services/estimate-service.ts`
- Reuse/adapt: `src/lib/api/services/invoice-service.ts`
- Test: corresponding service tests

- [ ] **Step 1: Write financial invariants**

Totals, line-item sums, tax, currency, duplicate source/hash, project/customer resolution, permission, source provenance, and exact version checks. Allocations must sum exactly and cannot partially apply.

- [ ] **Step 2: Prepare itemized previews**

Every created/changed estimate, shared line item, source document, project allocation, and total appears. Ambiguity blocks commit.

- [ ] **Step 3: Commit through existing domain invariants**

Do not insert estimate/invoice/line-item rows directly from the adapter. Add guarded service/RPC primitives if the existing service cannot provide atomic versioned commit.

- [ ] **Step 4: Verify and commit**

```bash
npm test -- src/lib/agent-control-plane/services/__tests__/estimate-import.test.ts src/lib/agent-control-plane/services/__tests__/project-cost-allocation.test.ts
git add src/lib/agent-control-plane/services src/lib/api/services
git commit -m "feat(agent-control-plane): add guarded financial import proposals"
```

### Task 21: Add client communication batch preparation/commit

**Files:**

- Create: `src/lib/agent-control-plane/services/prepare-client-message-batch.ts`
- Create: `src/lib/agent-control-plane/services/commit-client-message-batch.ts`
- Reuse/adapt: current email send intent/delivery/reconciliation services
- Test: `src/lib/agent-control-plane/services/__tests__/client-message-batch.test.ts`

- [ ] **Step 1: Test audience and delivery safety**

Bound 25 recipients; exact job/contact/schedule facts; opt-outs; duplicate recipients; changed schedule/contactability after prepare; idempotent intent; provider ambiguity; partial provider outcome; reconciliation; delivered-turn memory.

- [ ] **Step 2: Separate draft and send effects**

Host-only text generation does not touch OPS. OPS provider draft creation and send are explicit different effects. Both require preview/confirmation when OPS writes the mailbox; sends use durable intents/reconciliation.

- [ ] **Step 3: Verify and commit**

```bash
npm test -- src/lib/agent-control-plane/services/__tests__/client-message-batch.test.ts src/lib/api/services/email-send-intent-service.ts
git add src/lib/agent-control-plane/services src/lib/api/services
git commit -m "feat(agent-control-plane): add confirmed communication batches"
```

All four write families remain unadvertised externally until the staged rollout gates enable them.

---

## Phase 7 — OAuth 2.1 authorization facade

### Task 22: Add OAuth/grant/audit persistence locally

**Files:**

- Create: `supabase/migrations/<timestamp>_mcp_oauth_and_tool_audit.sql`
- Create: `src/lib/agent-control-plane/oauth/types.ts`
- Create: `src/lib/agent-control-plane/oauth/repository.ts`
- Create: `src/lib/agent-control-plane/audit/repository.ts`
- Test: OAuth/audit schema tests
- Bible mirror/chapter update after implementation

- [ ] **Step 1: Verify established OAuth library/provider choice and cost**

Do not implement protocol state until the proven OAuth component is selected and current compatibility/cost is documented. Firebase remains the human identity step.

- [ ] **Step 2: Model required records**

Expected concepts:

- registered clients and issuer binding;
- short-lived hashed authorization codes with PKCE/resource/redirect/scopes;
- single-company grants;
- rotated hashed refresh-token families and reuse detection;
- revocations;
- optional access-token JTI denylist for emergency revocation;
- immutable tool audit metadata.

- [ ] **Step 3: Add RLS and server-only mutation boundaries**

Operators may list/revoke only their/company-authorized grants. Browsers cannot issue codes/tokens/receipts directly. Service role does not bypass application actor checks.

- [ ] **Step 4: Apply local/test, verify, commit**

```bash
npm test -- src/lib/agent-control-plane/oauth src/lib/agent-control-plane/audit
git add supabase/migrations/<timestamp>_mcp_oauth_and_tool_audit.sql src/lib/agent-control-plane/oauth src/lib/agent-control-plane/audit
git commit -m "feat(mcp-auth): add tenant-bound OAuth grant persistence"
```

### Task 23: Implement discovery, client metadata, and OAuth endpoints

**Files:**

- Create: `src/app/.well-known/oauth-protected-resource/route.ts`
- Create: `src/app/.well-known/oauth-protected-resource/mcp/route.ts`
- Create: `src/app/.well-known/oauth-authorization-server/route.ts`
- Create: `src/app/api/oauth/token/route.ts`
- Create: `src/app/api/oauth/revoke/route.ts`
- Create: `src/app/api/oauth/register/route.ts` only for backward-compatible DCR
- Create: `src/lib/agent-control-plane/oauth/discovery.ts`
- Create: `src/lib/agent-control-plane/oauth/client-registration.ts`
- Create: `src/lib/agent-control-plane/oauth/token-service.ts`
- Test: `src/lib/agent-control-plane/oauth/__tests__/discovery.test.ts`
- Test: `src/lib/agent-control-plane/oauth/__tests__/token-service.test.ts`

- [ ] **Step 1: Write standards/security tests**

Protected-resource metadata; AS metadata; resource echo; exact audience; PKCE S256; issuer; redirect equality; CIMD preference; DCR compatibility; client/issuer binding; `none`/`private_key_jwt`; code one-time use; refresh rotation/reuse; scope step-up; revoked/inactive grants.

- [ ] **Step 2: Implement discovery and registration with SSRF controls**

Metadata/CIMD fetches need HTTPS, allow/deny IP ranges, DNS re-resolution protection, redirect cap, response-size/time cap, content-type/schema validation, and no credential forwarding.

- [ ] **Step 3: Implement access tokens**

10-minute signed tokens with exact `aud=https://mcp.opsapp.co/mcp`, issuer, subject, client, grant, scopes, time claims, and JTI. Signing keys use managed secrets/key rotation; never source control.

- [ ] **Step 4: Implement revocation**

Revoke grant/token family, invalidate authorization cache, block pending commits at reauthorization, and write audit.

- [ ] **Step 5: Verify and commit**

```bash
npm test -- src/lib/agent-control-plane/oauth
npm run type-check
git add src/app/.well-known src/app/api/oauth src/lib/agent-control-plane/oauth
git commit -m "feat(mcp-auth): implement OAuth discovery and tokens"
```

### Task 24: Build authorize, consent, connected-app, and confirmation surfaces

**Required before coding:** Load the UI/copy/wizard/design-system skills listed at the top. State the implementation intent and token mapping. Run `custom-skills:audit-design-system` before completion.

**Files:**

- Create: `src/app/oauth/authorize/page.tsx`
- Create: `src/app/oauth/authorize/actions.ts`
- Create: `src/components/ops/agent-access-consent.tsx`
- Create: `src/components/ops/agent-change-confirmation.tsx`
- Create or extend: connected-app settings surface discovered in current OPS-Web
- Create: `src/app/api/agent-control-plane/change-sets/[changeSetId]/approve/route.ts`
- Test: component/unit tests
- Test: `e2e/mcp-oauth-consent.spec.ts`
- Test: `e2e/agent-change-confirmation.spec.ts`

- [ ] **Step 1: Define the human task**

An owner/operator needs to know which application, which OPS company, which data categories, and which actions are being granted—then connect, cancel, review, revoke, or confirm without understanding OAuth/MCP vocabulary.

- [ ] **Step 2: War-game the flow**

Cover multiple companies, inactive user, expired request, changed scopes, malicious client name/logo/URL, back/cancel, duplicate submit, CSRF, open redirect, revoked client, mobile viewport, keyboard, screen reader, and permission loss mid-flow.

- [ ] **Step 3: Write UI tests first**

The consent page shows one requesting app, one selected company, grouped data/action capabilities, and one primary connect action. Technical scopes are progressively disclosed. No preselected scope expansion. Confirmation shows the exact immutable change-set preview and changed/stale state.

- [ ] **Step 4: Implement from existing OPS tokens/components**

Use pure-black canvas, glass/hairline surfaces, Cake/JetBrains/Mohave roles, standard 36px form controls, steel-blue only for the primary action/focus, rose only for destructive revoke, current `lucide-react`, visible focus, semantic HTML, reduced motion, and no raw values.

- [ ] **Step 5: Implement secure actions**

Firebase-authenticated session, CSRF/state validation, exact request/redirect binding, active membership, current permission, receipt issuance, and single-use submission. UI cannot mint authority from client-provided fields.

- [ ] **Step 6: Verify design/accessibility/e2e and commit**

```bash
npm test -- src/components/ops src/app/oauth
npm run test:e2e -- e2e/mcp-oauth-consent.spec.ts e2e/agent-change-confirmation.spec.ts
npm run type-check
git add src/app/oauth src/app/api/agent-control-plane src/components/ops e2e
git commit -m "feat(mcp-auth): add explicit consent and confirmation surfaces"
```

---

## Phase 8 — remote MCP transport

### Task 25: Implement token validation and resource auth middleware

**Files:**

- Create: `src/lib/agent-control-plane/mcp/authenticate-mcp-request.ts`
- Create: `src/lib/agent-control-plane/mcp/www-authenticate.ts`
- Test: `src/lib/agent-control-plane/mcp/__tests__/authenticate-mcp-request.test.ts`

- [ ] **Step 1: Write rejection matrix**

Missing/malformed token, wrong signature, issuer, audience/resource, expiry/nbf, revoked grant, inactive actor/company, insufficient scope, token passthrough, company field injection, and privacy-safe errors.

- [ ] **Step 2: Implement exact validation**

Validate token first, then resolve current actor context. Emit compliant `WWW-Authenticate` for initial auth and insufficient-scope step-up. Never pass the bearer token downstream.

- [ ] **Step 3: Verify and commit**

```bash
npm test -- src/lib/agent-control-plane/mcp/__tests__/authenticate-mcp-request.test.ts
git add src/lib/agent-control-plane/mcp
git commit -m "feat(mcp): validate exact-audience OPS grants"
```

### Task 26: Register the read-only MCP catalogue

**Files:**

- Create: `src/lib/agent-control-plane/mcp/create-server.ts`
- Create: `src/lib/agent-control-plane/mcp/register-tools.ts`
- Create: `src/lib/agent-control-plane/mcp/tool-adapter.ts`
- Create: `src/lib/agent-control-plane/mcp/errors.ts`
- Test: `src/lib/agent-control-plane/mcp/__tests__/tool-catalogue.test.ts`
- Test: `src/lib/agent-control-plane/mcp/__tests__/tool-parity.test.ts`

- [ ] **Step 1: Snapshot tool schemas/descriptions/annotations**

Register exactly the nine initial launch reads. Do not advertise the two dark site-visit reads until their repositories/handlers and booking-layer gates pass. No resources, prompts, or write tools are advertised. Descriptions are concise, goal-shaped, data-sensitive, and explicit that source content is untrusted data.

- [ ] **Step 2: Implement adapter-only calls**

Validate input, invoke `OpsAgentDomainService`, validate output, map domain errors, add request IDs/audit. No direct business queries in tool handlers.

- [ ] **Step 3: Prove internal/MCP parity**

Same fixture actor/input produces semantically identical contract result.

- [ ] **Step 4: Verify and commit**

```bash
npm test -- src/lib/agent-control-plane/mcp
git add src/lib/agent-control-plane/mcp
git commit -m "feat(mcp): expose governed OPS read tools"
```

### Task 27: Serve dual protocol eras at `/mcp`

**Files:**

- Create: `src/app/mcp/route.ts`
- Test: `src/app/mcp/__tests__/route.test.ts`
- Test: `src/lib/agent-control-plane/mcp/__tests__/protocol-eras.test.ts`

- [ ] **Step 1: Write 2025/2026 protocol tests**

Modern `server/discover`/per-request metadata and legacy initialize/stateless calls must reach the same tool catalogue/service. No sticky session/state dependency. Unsupported transport/methods fail correctly.

- [ ] **Step 2: Implement official v2 `createMcpHandler`**

Serve modern and default stateless legacy eras. Enforce HTTPS/proxy trust, body/time limits, origin/host checks, auth, rate limits, cancellation, and audit. Do not add legacy HTTP+SSE as a new path.

- [ ] **Step 3: Verify with SDK clients and Inspector locally**

```bash
npm test -- src/app/mcp src/lib/agent-control-plane/mcp
npx @modelcontextprotocol/inspector --help
```

Use the Inspector against local `/mcp`; store screenshots/logs only under `docs/artifacts/` and remove one-off artifacts after proof.

- [ ] **Step 4: Commit**

```bash
git add src/app/mcp src/lib/agent-control-plane/mcp
git commit -m "feat(mcp): serve stateless modern and legacy clients"
```

### Task 28: Add optional modern confirmation response support

**Files:**

- Create: `src/lib/agent-control-plane/mcp/input-required.ts`
- Test: `src/lib/agent-control-plane/mcp/__tests__/input-required.test.ts`

- [ ] **Step 1: Test both eras**

Modern clients may receive `input_required`; legacy clients receive the OPS approval URL/status contract. Both point to the same Firebase-authenticated OPS confirmation action and later observe the same server-issued receipt/status. Neither host response can mint the receipt.

- [ ] **Step 2: Implement without exposing write tools**

This is foundational/dark until a write capability is enabled. Never fall back to trusting `confirmed=true`, continuation text, or a host approval assertion. `input_required` is presentation/status only unless a separately approved cryptographic human-attestation profile is implemented.

- [ ] **Step 3: Verify and commit**

```bash
npm test -- src/lib/agent-control-plane/mcp/__tests__/input-required.test.ts
git add src/lib/agent-control-plane/mcp
git commit -m "feat(mcp): support secure confirmation across protocol eras"
```

---

## Phase 9 — REST parity, audit, rate limits, and operations

### Task 29: Add REST adapter routes only for current OPS consumers

**Files:**

- Create: `src/lib/agent-control-plane/adapters/rest.ts`
- Add narrowly required routes under: `src/app/api/agent-control-plane/`
- Test: route and parity tests

- [ ] **Step 1: Inventory actual OPS API consumers**

Do not expose every domain method merely because it exists. Add routes required by Phase C/web/iOS integration, with the same contracts and Firebase actor context.

- [ ] **Step 2: Implement adapter**

No REST-specific business logic. Parse the exact same agent-control-plane `zod-v4` schemas, domain errors, evidence, and freshness; existing OPS Zod 3 schemas meet this boundary only as parsed plain values.

- [ ] **Step 3: Verify and commit**

```bash
npm test -- src/lib/agent-control-plane/adapters src/app/api/agent-control-plane
git add src/lib/agent-control-plane/adapters src/app/api/agent-control-plane
git commit -m "feat(agent-control-plane): expose shared REST adapter"
```

### Task 30: Implement immutable audit and redaction

**Files:**

- Create: `src/lib/agent-control-plane/audit/audit-event.ts`
- Create: `src/lib/agent-control-plane/audit/write-audit.ts`
- Create: `src/lib/agent-control-plane/audit/redaction.ts`
- Test: `src/lib/agent-control-plane/audit/__tests__/audit.test.ts`

- [ ] **Step 1: Test every outcome**

Success, denial, not-found, scope step-up, validation, rate limit, internal error, prepare, confirmation, commit, reconciliation. Raw tokens/codes/bodies/documents must never appear.

- [ ] **Step 2: Make audit failure fail closed for writes**

A write cannot commit without its durable audit/receipt. Read-call audit may use a reliable buffered path only if dropped-event alerts and request tracing remain intact.

- [ ] **Step 3: Verify and commit**

```bash
npm test -- src/lib/agent-control-plane/audit
git add src/lib/agent-control-plane/audit
git commit -m "feat(agent-control-plane): add immutable privacy-safe audit"
```

### Task 31: Implement multi-dimensional rate limits and bounds

**Files:**

- Create: `src/lib/agent-control-plane/mcp/rate-limit.ts`
- Create: `src/lib/agent-control-plane/mcp/request-limits.ts`
- Test: `src/lib/agent-control-plane/mcp/__tests__/rate-limit.test.ts`
- Modify Vercel/WAF config only after approval if required

- [ ] **Step 1: Test actor/client/company/tool/IP buckets**

Include concurrent calls, batch size, evidence/search weight, retry time, distributed runtime behavior, and one tenant not starving another.

- [ ] **Step 2: Implement shared-store limits**

Do not use per-instance memory for production enforcement. If a paid external rate-limit store/tier is required, price and obtain approval before purchase.

- [ ] **Step 3: Verify and commit**

```bash
npm test -- src/lib/agent-control-plane/mcp/__tests__/rate-limit.test.ts
git add src/lib/agent-control-plane/mcp
git commit -m "feat(mcp): enforce tenant-aware request limits"
```

### Task 32: Add metrics, alerts, kill switches, and runbooks

**Files:**

- Create: `src/lib/agent-control-plane/observability/metrics.ts`
- Create: `src/lib/agent-control-plane/observability/tracing.ts`
- Create: `docs/runbooks/ops-agent-control-plane.md`
- Create: `docs/evals/ops-agent-control-plane-matrix.md`
- Modify: existing feature/capability configuration
- Test: observability/kill-switch tests

- [ ] **Step 1: Implement per-company/client/tool/capability kills**

Disabling a write does not remove read-only service. Revocation and confirmation remain fail-closed.

- [ ] **Step 2: Emit metrics from common dispatcher**

Calls, latency, output size, denials, stale/ambiguous context, memory lag, confirmation, idempotency, reconciliation, protocol/client, prompt safety. No raw content.

- [ ] **Step 3: Write incident procedures**

Cross-tenant suspicion, signing-key compromise, refresh reuse, duplicate send, financial partial attempt, stale schedule, audit loss, runaway client, provider outage, and global/client/tool kill.

- [ ] **Step 4: Verify and commit**

```bash
npm test -- src/lib/agent-control-plane/observability src/lib/agent-control-plane/registry
git add src/lib/agent-control-plane/observability docs feature-config-path
git commit -m "feat(agent-control-plane): add operational controls and runbooks"
```

---

## Phase 10 — adversarial verification and staged release

### Task 33: Run full automated contract/security/eval suite

- [ ] **Focused tests**

```bash
npm test -- src/lib/agent-control-plane
```

- [ ] **Existing affected suites**

```bash
npm test -- src/lib/api/services/conversation-state src/lib/catalog-setup/phase-c src/lib/api/services
```

- [ ] **Static/build checks**

```bash
npm run type-check
npm run format:check
npm run build
```

- [ ] **E2E**

```bash
npm run test:e2e -- e2e/mcp-oauth-consent.spec.ts e2e/agent-change-confirmation.spec.ts
```

- [ ] **Baseline comparison**

If broad existing suites fail, run the same exact command on the exact base commit/worktree before attributing failures to this feature. Serially rerun noisy tests.

- [ ] **Security matrix**

Execute every case in design §16, including cross-tenant IDs, assignment change, prompt injection, token audience/issuer, DCR/CIMD SSRF, confirmation replay, stale versions, DST, deleted photos, financial exactness, catalog capability drift, and duplicate delivery.

### Task 34: Verify live-compatible hosts in a non-production environment

- [ ] Expose a temporary secure HTTPS staging URL; never point developer testing at production customer data.
- [ ] Verify MCP Inspector.
- [ ] Verify Claude custom connector and Claude API `mcp-client-2025-11-20`.
- [ ] Verify ChatGPT developer mode/plugin and OpenAI Responses API remote MCP.
- [ ] Verify modern `2026-07-28` SDK client and legacy `2025-11-25` client.
- [ ] Verify auth discovery, consent, revocation, scope step-up, tool caching/deferred loading, bounds, and sanitized output.
- [ ] Run direct, indirect, follow-up, unsupported, malicious-document, and write-attempt evals.
- [ ] Record host plan/feature caveats: OPS guarantees MCP compatibility, not the continued availability or write capability of another host's Gmail/Drive connector.

Do not register a public production connector or submit for directory review in this task.

### Task 35: Production migration gate

Only if Jackson explicitly authorizes production migrations:

- [ ] Re-fetch production schema and migration ledger immediately before apply.
- [ ] Confirm migration files exactly match reviewed commits.
- [ ] Build an expected-mutation manifest from the exact SQL and fresh production preflight before any write. Include the temporary `ai_auto_send`/mailbox-setting changes and every migration-time DML predicate: legacy pending-send cancellation in `20260807213219`, approved-action retry-cap normalization/eligible terminalization plus alert-outbox writes in `20260809180033`, and missing tenant-root inserts for existing source fences in `20260809183000`. Capture exact qualifying keys, per-predicate counts, and the before values required for readback; abort if the qualifying set changes before apply.
- [ ] Apply one migration at a time through Supabase tooling.
- [ ] Read back tables, columns, constraints, indexes, RLS, grants, functions, and migration ledger after each apply.
- [ ] Reconcile every changed row to the expected-mutation manifest with exact changed keys and before/after counts and values. Verify no unlisted customer row was inserted, updated, or deleted.
- [ ] Mirror each applied migration into the bible and update numbered chapters in the same session.
- [ ] If any readback differs, stop; do not continue the sequence.

#### Mandatory Phase 2 email migration/deploy cutover

Migration `20260809183000_phase_c_auto_send_generation_reservations.sql` deliberately drops the already-shipped 28-argument `schedule_phase_c_auto_send_fenced` overload. The replacement takes a generation token and arguments hash, for 30 arguments total. This is a forward-only safety boundary: never leave the legacy overload installed as a compatibility bridge and never restore it during rollback.

Production execution requires separate migration and deployment authorization plus this exact order:

- [ ] Snapshot the exact pre-cutover values, then disable new Phase C email generation: set and read back the company `ai_auto_send` override as false for every company and `auto_send_settings.enabled` as false for every email connection. Do not rely on the general `phase_c` flag alone. Pause `/api/cron/email-sync`, `/api/cron/stale-leads`, `/api/cron/auto-send`, `/api/cron/auto-execute-actions`, and `/api/cron/email-send-reconciliation`; block provider-webhook and user/manual dispatch to `/api/integrations/email/manual-sync`; then wait for in-flight classification/router requests and mailbox/reconciliation leases to drain.
- [ ] Capture the cutover's expected-mutation manifest and exact qualifying row keys/counts from the now-quiescent database. It must cover cancellation of legacy pending sends, approved-action retry normalization and capped-row terminalization with alert-outbox writes, missing tenant-root backfill, and the temporary settings already changed above. Stop if pre-apply readback no longer matches the captured set.
- [ ] Apply every reviewed migration in ledger order through `20260809183000`; do not apply the final migration alone.
- [ ] Reconcile exact changed keys, before/after counts, and relevant values against the manifest; fail closed on any unlisted customer-data change.
- [ ] Read back the ledger and `pg_proc`/ACL state. Assert the legacy 28-argument scheduling overload is absent; the reservation, resolution, and 30-argument scheduling functions exist; only `service_role` can execute the public system RPCs; and public/anonymous/authenticated execution remains revoked.
- [ ] Verify reconciliation intent tables grant `service_role` read access only, with mutation available solely through the reviewed security-definer RPCs.
- [ ] Deploy the compatible application commit while all workers remain paused. Verify exact commit ancestry and customer alias before any runtime invocation.
- [ ] Run a non-sending internal-company canary: reserve generation from exact delivered source evidence, read back reservation identity/lease/audit fields, and resolve it to `failed` with reason `cutover_canary`. Do not generate text, create a pending send, or contact an email provider.
- [ ] Restore the snapshotted `ai_auto_send` plus connection settings for one internal/test-company path, restore its sync dispatch, and prove the new reservation and reconciliation runtime records. Then restore only the remaining pre-cutover values and deliberately resume the remaining ingress paths and schedulers.
- [ ] On any failure, keep workers paused and use a reviewed forward application/database repair. Do not recreate or grant the 28-argument overload.

### Task 36: Staged production rollout

Each stage requires explicit deployment/push authorization and evidence:

1. Internal domain service/shadow only.
2. Phase C memory for an internal/test company.
3. Phase C measured company cohort with rollback flag.
4. Private read-only external MCP for trusted test tenants.
5. Cross-connector draft workflows.
6. Prepare-only write tools.
7. One confirmed commit domain at a time, catalog first.
8. Broad connector availability/submission.

For each stage:

- [ ] exact deployed commit and customer alias verified;
- [ ] runtime call proof, not just route/READY;
- [ ] actor/company/permission audit readback;
- [ ] output evidence/freshness proof;
- [ ] revocation and kill-switch proof;
- [ ] no write tool advertised before its stage;
- [ ] cost/latency/error metrics reviewed;
- [ ] rollback exercised.

### Task 37: Canonical bible update

After code and any migrations are real:

**Files:**

- Modify: `ops-software-bible/03_DATA_ARCHITECTURE.md`
- Modify: `ops-software-bible/04_API_AND_INTEGRATION.md`
- Modify: `ops-software-bible/07_SPECIALIZED_FEATURES.md` if the control plane becomes a top-level system
- Modify: `ops-software-bible/10_JOB_LIFECYCLE_AND_DATA_RELATIONSHIPS.md`
- Mirror: applied migrations
- Retain/update: the approved design spec with actual commit/deployment status

- [ ] Document exact tables, RLS, routes, tool contracts, OAuth issuer/resource, Phase C memory behavior, change-set confirmation, limits, flags, rollout stage, and what remains disabled.
- [ ] Cite exact migrations/routes/code commits.
- [ ] Never mark the remote MCP or write tools live based only on merged code.
- [ ] Commit bible docs after the code commit, referencing it.

---

## Final completion proof

The initiative is complete only when the approved rollout scope is implemented and every required distinction is reported accurately:

- source/design proof;
- local test/build proof;
- migration ledger/schema/RLS proof when applied;
- deployed commit/alias proof when deployed;
- runtime Claude/ChatGPT/internal proof;
- customer/company permission and audit proof;
- confirmed write/readback proof for any enabled write domain;
- cost and operating-state proof.

“The route responds,” “Vercel says READY,” “tests pass,” or “a model selected the tool” is not sufficient alone.

---

## Explicit non-goals during implementation

Do not add:

- raw SQL/table/CRUD tools;
- arbitrary URL fetching or file access;
- provider-token passthrough;
- payment/refund/banking/payroll tools;
- company deletion, production operations, or permission-administration tools;
- prompts/resources as dependencies for core behavior;
- MCP App UI before a proven need;
- automatic public writes before confirmation/eval rollout;
- broad exports or unrelated private employee/customer data;
- duplicate catalog, schedule, financial, contactability, or email business rules inside the MCP adapter.
