# MCP Mount — Claude First, P1 Implementation Plan (2026-08-18)

> **For Claude:** REQUIRED SUB-SKILL: Use `custom-skills:executing-plans` to implement this plan task-by-task.

**Execution status (2026-08-20): COMPLETE AND PRODUCTION-LIVE.** The implementation is merged to ops-web `main`, deployed at `https://app.opsapp.co/api/mcp`, configured with the server-only cursor key, and connected to Claude through an active OPS OAuth grant. Production audit records prove successful calls across the read surface. The “starting state” and task instructions below are retained as implementation provenance, not current rollout status.

**Goal:** Mount the OPS agent control plane as a remote MCP server that Jackson can add to claude.ai as a custom connector — streamable HTTP at `/api/mcp`, OAuth 2.1 binding each connection to one OPS user, the nine v6 reads only, read-only, dark to unauthenticated traffic.

**Architecture:** A new OAuth 2.1 authorization-server facade (DB-backed, opaque hashed tokens, Firebase as the human identity step) mints grants bound to one OPS user + company. The existing `/api/mcp` route wraps `createMcpHandler` from `@modelcontextprotocol/server@2.0.0` (stateless, both protocol eras); every request resolves the bearer token to a grant, mints a `ValidatedMcpPrincipal` through the existing branded boundary, re-resolves actor authority via `resolve_agent_actor_authority_as_system`, and dispatches to the already-shipped `OpsAgentDomainService`. The MCP layer never invents authority; company scope derives from the grant, never tool arguments.

**Tech Stack:** Next.js 15 App Router route handlers, `@modelcontextprotocol/server@2.0.0` (already a dependency), `zod-v4` alias (already installed), Supabase private-schema tables + `*_as_system` SECURITY DEFINER RPCs (shipped wave house pattern), Node `crypto` for token entropy/hashing (no new key material beyond the already-specified cursor key).

**Design System:** Consent + settings surfaces only — `ops-design-system/project/DESIGN.md` tokens; `.pmf-scope`-style divergence forbidden.

**Required Skills:** `custom-skills:executing-plans`, `superpowers:test-driven-development`, `ops-design` + `frontend-design:frontend-design` + `ops-copywriter:ops-copywriter` (Task 5 and Task 7 UI only), `custom-skills:audit-design-system` (before UI done), `superpowers:verification-before-completion`.

---

## Verified starting state (read directly from origin/main `780cbd4f`, 2026-08-18)

- `src/lib/agent-control-plane/mcp/sdk.ts` re-exports `McpServer`, `createMcpHandler`, `InMemoryTransport`, `mcpZod` (zod-v4). Nothing imports it from `src/app/` — `/api/mcp` 404s today.
- `@modelcontextprotocol/server@2.0.0` installed. Verified from the installed d.mts: `createMcpHandler(factory, opts) → { fetch(request, {authInfo}) }` — web-standard, stateless, serves modern `2026-07-28` + legacy 2025-era (`2024-10-07`…`2025-11-25`) from one factory; performs **no** token verification (authInfo is pass-through); origin/host validation is explicitly the mounter's job; `registerTool(name, {inputSchema, description, annotations}, handler)` accepts zod-v4 schemas directly.
- Actor layer (all shipped, live): `createMcpPrincipalFromValidatedGrant` (branded, WeakSet-gated — `src/lib/agent-control-plane/actor/principal-boundary.ts:191`), `resolveActorContext` with `MCP_PRINCIPAL_KEYS` already defined (`actor/resolve-actor-context.ts:347`), authority re-resolution per call via `resolve_agent_actor_authority_as_system(uuid,uuid,text[])` (`actor/authority-repository.ts:402`), `authorizeCapability` enforcing the OAuth scope ceiling with `insufficient_scope` + `WWW-Authenticate` (`actor/authorize-capability.ts:77-92`).
- Domain service: `createOpsAgentDomainService({repositories})` (`services/create-domain-service.ts:318`) — frozen, trusted, all nine reads; checks `implementation === "available"` but **not** `externalExposure` — external exposure gating is deliberately the transport's job.
- Composition pattern to mirror: `createInternalPhaseCAdapterRuntime` (`adapters/internal-runtime.ts:45`) — `rpcClient` + `cursorCodec` → nine repositories → domain service.
- Manifest `2026-08-14.capability-manifest.v6` (`registry/capability-manifest.ts:18`): nine reads `INTERNAL_ONLY_AVAILABILITY` (`implementation: "available"`, `externalExposure: "disabled"` — `registry/read-tools.ts:46`), each with `requiredOAuthScopes`, permission requirement groups, `riskTier`, `annotations`, `rateLimitBucket` (`lightweight_read` default; `evidence_search` on `search_job_history`, `get_correspondence_evidence`, `get_job_conversation_context`), and a declarative `rolloutFlag` (grep-verified: zero consumers — no flag layer exists to honor; the manifest constant IS the rollout control).
- Cursor codec: `createOperationalReadCursorCodec({key: 32B, keyId, version})` (`services/operational-read-cursor.ts:263`); production instantiation pattern at `src/lib/api/services/phase-c-reply-context-shadow.ts:110-120` — env `OPS_AGENT_OPERATIONAL_READ_CURSOR_KEY`, `/^[0-9a-f]{64}$/`, **blank in prod today** (Jackson-gated provision).
- Error surface: `ActorAccessError` with `code ∈ {INSUFFICIENT_SCOPE, FORBIDDEN, NOT_FOUND, INVALID_ARGUMENT, TEMPORARILY_UNAVAILABLE, INTERNAL}`, `retryable`, `wwwAuthenticate`, `toAgentError()` envelope (`actor/errors.ts`).
- Prompt-safety serializer: `serializeUntrustedPromptData(value)` (`src/lib/prompt-safety/untrusted-json.ts:29`).
- Rate limiter: `src/lib/utils/ratelimit.ts` — sliding window, Vercel KV when provisioned, per-instance in-memory fallback otherwise (KV is NOT provisioned; documented degradation, acceptable at current scale).
- Middleware (`src/middleware.ts`): prefix-based protection; `/.well-known/*` and `/api/*` pass through untouched.
- Firebase human auth: `verifyAdminAuth(request)` (`src/lib/firebase/admin-verify.ts`) + `findUserByAuth` — the pattern in `src/app/api/agent/_lib/auth.ts:20`.
- House SQL pattern (from shipped `20260807204914_agent_control_plane_actor_authority.sql`): tables + implementation fns in `private`, `public.*_as_system` wrappers gated `auth.role() is distinct from 'service_role'` → `42501 access_denied`, `security definer`, pinned `search_path to 'pg_catalog', 'public', 'private', 'pg_temp'`.
- Existing DB has **no** MCP OAuth tables (grep of all 401 migrations: only `20260713204000_one_time_email_oauth_state.sql`, a different domain).
- Test company: MAVERICK PROJECTS LTD `ddee107c-33cd-483e-8278-0f8d8a180181`, admin actor `8e811f98-9f2b-4f64-b409-ed56074b7dc8` (Firebase sub `pnLo4LsWtvMi7oxDrRIcLASCash2`).

## Claude-side requirements (live research, 2026-08-18 — details + sources in §Research appendix)

1. **Transport:** Streamable HTTP only (legacy HTTP+SSE deprecated; no SSE fallback needed). Single endpoint; POST is the only method that must work; 405 on GET/DELETE is compliant. Stateless is explicitly fine (`sessionIdGenerator: undefined` is Anthropic's own sample). CORS is not involved — claude.ai calls server-to-server from `160.79.104.0/21`; Origin validation must not be strict (documented cause of initialize timeouts).
2. **Protocol era:** Claude clients today speak the **2025-era handshake protocols** (2025-03-26 / 2025-06-18 / 2025-11-25) — they still send `initialize`. The 2026-07-28 revision is announced but **not confirmed live in any Claude surface**. `@modelcontextprotocol/server@2.0.0`'s default `legacy: 'stateless'` serves exactly these eras plus 2026-07-28 from one factory — the legacy leg is the hot path for now.
3. **OAuth:** Authorization-code + **PKCE S256 on every request**. Claude supports DCR (RFC 7591 — its default for custom connectors), CIMD (only if the AS advertises `client_id_metadata_document_supported: true`), and manual client-ID entry. Claude sends **RFC 8707 `resource`** on authorize and token requests, canonicalized (lowercase scheme/host, no trailing slash/fragment/default port). Audience checks must compare canonically, not byte-for-byte against what the user typed.
4. **Callback allowlist (exact):** `https://claude.ai/api/mcp/auth_callback` (covers web, Desktop, mobile, Cowork). A `https://claude.com/api/mcp/auth_callback` twin is claimed by third parties only — unverified on Anthropic pages; allowlisted as free insurance, still exact-match.
5. **Discovery:** RFC 9728 PRM — Claude honors the `WWW-Authenticate: Bearer resource_metadata="…"` pointer on the 401, then probes `/.well-known/oauth-protected-resource/<mcp-path>` before the root form. RFC 8414 AS metadata at `/.well-known/oauth-authorization-server` (openid-configuration fallback; one 200 suffices). PRM `resource` must match the URL exactly as typed into Claude. Discovery responses are cached globally ~5 minutes.
6. **The auth-trigger trap:** a `200` carrying `isError: true` never triggers OAuth — only a **transport-level 401** does, and a 403 re-triggers auth only with `error="insufficient_scope"`. The bearer gate must therefore sit **in front of the MCP SDK**, never inside a tool handler.
7. **Budgets:** OAuth discovery/register/token 10s, refresh 30s; tool calls 300s; claude.ai tool-result cap ≈150,000 chars (our contract's 60,000-char ceiling is comfortably inside). Vercel body cap 4.5 MB.
8. **Plan gating:** custom connectors exist on Free (1 max), Pro, Max, Team, Enterprise — on Team/Enterprise only an **Owner** can add them. There is no staging surface; testing happens against production claude.ai.

---

## Architecture decisions (settled here, senior-owned)

**D1 — Resource identity: `https://app.opsapp.co/api/mcp`; issuer `https://app.opsapp.co`.** The P1 scope doc consistently names `/api/mcp` on the existing deployment and reserves no DNS work; the foundation spec's `mcp.opsapp.co` hostname is a later move (new audience ⇒ re-consent — free while exactly one connection exists). No DNS or Vercel domain change in P1.

**D2 — Opaque tokens, hashed at rest; no signing keys.** Access and refresh tokens are 256-bit random values, stored as SHA-256 digests, all claims (issuer, audience, scopes, expiry, grant, actor, company) resolved from the DB row on every call. AS and RS are the same deployment sharing one DB, so a signature adds key management without adding security; the foundation spec's own rule that "the access token does not contain a trusted permission snapshot; current OPS authorization is reloaded on every call" (§12.3) is exactly what DB resolution delivers, and §12.3's "contain/**resolve**" phrasing permits it. Access token lifetime 600s; refresh tokens rotated on every use, reuse-detected (family revocation), hashed at rest. No second Jackson-gated env provision.

**D3 — OAuth persistence in `private` schema behind `public.*_as_system` RPCs** — the shipped wave pattern exactly (service-role-only EXECUTE, definer, pinned search_path). PostgREST never sees the tables.

**D4 — Client registration: DCR (RFC 7591) only, with the redirect-URI allowlist pinned to `https://claude.ai/api/mcp/auth_callback` (+ the unverified `claude.com` twin as exact-match insurance).** CIMD is deliberately NOT advertised in P1 — accepting CIMD means fetching remote client metadata (an SSRF surface the foundation spec §12.6 requires hardening for) to serve exactly one connection; Claude's documented fallback when CIMD is unadvertised is DCR, which it "supports out of the box." DCR's known cost (a fresh client row per connection) is noise at one connection. Public clients only (`token_endpoint_auth_method: "none"`); PKCE S256 mandatory, `plain` rejected; RFC 8707 `resource` validated canonically on authorize AND token requests (Claude always sends it), bound into the code and the token rows.

**D5 — Consent rides the existing Firebase session.** `GET /oauth/authorize` renders a focused consent page (no dashboard chrome); unauthenticated → existing `/login?returnTo=` flow. Approval POSTs to a Firebase-token-authenticated decision endpoint that validates every OAuth parameter server-side, mints the single-use code (10-minute expiry, PKCE-bound, redirect-bound, resource-bound), and returns the redirect. The grant binds exactly `(user, company, client)` — company is the user's OPS company row, never a request parameter.

**D6 — Tool surface = manifest filter.** The per-request `McpServerFactory` registers exactly the capabilities with `implementation === "available" && externalExposure === "enabled"`, using the manifest's own zod-v4 `inputSchema`, `description`, and MCP annotations. Flipping a capability is a one-line manifest change (`INTERNAL_ONLY_AVAILABILITY` → `EXTERNAL_READ_AVAILABILITY`), each flip carrying its own transport-level test. Ship state for P1: all nine flipped, each individually verified.

**D7 — Safety rails.** Per-grant sliding-window rate limits keyed by manifest bucket (`lightweight_read`: 120/min/grant + 600/min/company; `evidence_search`: 30/min/grant + 120/min/company — foundation §13.3 ceilings) via the existing ratelimit util (KV-degradation caveat documented). Every tool call — including denials — appends an audit row (`private.mcp_request_audit`) with actor/company/grant/client/tool/era/outcome/latency/result-size and a SHA-256 input digest; never raw input, never tokens, never message bodies. Tool results serialize through `serializeUntrustedPromptData`.

**D8 — Unauthenticated posture.** The bearer gate sits in the route handler **before** `handler.fetch` (research trap: only a transport-level 401 triggers Claude's OAuth; a 200 with `isError` never does). Missing bearer → `401` + `WWW-Authenticate: Bearer resource_metadata="https://app.opsapp.co/.well-known/oauth-protected-resource/api/mcp", scope="<the eight read scopes>"`; presented-but-invalid bearer → same with `error="invalid_token"` prepended (Anthropic's documented challenge shape). Body names nothing — no tool list, no capability names, no schema, no OPS vocabulary. Discovery documents describe OAuth endpoints and scope strings only (RFC-required), never capabilities. `GET`/`DELETE` `/api/mcp` → same 401 gate; authenticated GET/DELETE fall through to the SDK's compliant 405.

**D9 — Error mapping.** Transport/auth failures (no token, bad token, audience mismatch, revoked) → HTTP 401/403 as D8. Rate limit exceeded pre-dispatch → HTTP 429 + `Retry-After`. Domain `ActorAccessError` → in-band MCP tool error: `isError: true`, content = `serializeUntrustedPromptData(error.toAgentError())` — the structured envelope the contract already defines (`INSUFFICIENT_SCOPE`, `FORBIDDEN`, privacy-safe `NOT_FOUND`, …). Unexpected exceptions → generic `INTERNAL` envelope with `request_id`; no stack traces, no internals.

**D10 — No auto-send interaction.** Nothing in this build reads or writes `INBOX_AUTO_SEND_ENABLED`, email intents, or any outbound surface. Read-only manifest entries only; `WRITE_CAPABILITY_DEFINITIONS` untouched.

---

## Database migration (Task 2 — Fable writes this SQL directly)

One file: `supabase/migrations/<ts>_mcp_oauth_authorization_server.sql`. All tables `private.`, all RPCs `public.*_as_system` service-role-gated definer functions, house style throughout.

**Tables** (all with `created_at timestamptz not null default now()`):

- `private.mcp_oauth_clients` — `client_id uuid PK default gen_random_uuid()`, `client_name text not null`, `redirect_uris text[] not null check (cardinality > 0)`, `token_endpoint_auth_method text not null check (= 'none')`, `grant_types text[] not null`, `response_types text[] not null`, `scope text not null`, `registration_source text not null check (in ('dynamic','manual'))`, `software_id text`, `software_version text`, `disabled_at timestamptz`.
- `private.mcp_oauth_authorization_codes` — `code_hash text PK` (sha256 hex), `client_id uuid not null FK`, `user_id uuid not null`, `company_id uuid not null`, `scopes text[] not null`, `redirect_uri text not null`, `code_challenge text not null`, `code_challenge_method text not null check (= 'S256')`, `resource text not null`, `expires_at timestamptz not null`, `consumed_at timestamptz`.
- `private.mcp_oauth_grants` — `id uuid PK`, `user_id uuid not null`, `company_id uuid not null`, `client_id uuid not null FK`, `scopes text[] not null`, `revision text not null`, `created_at`, `last_used_at timestamptz`, `revoked_at timestamptz`, unique partial index `(user_id, company_id, client_id) where revoked_at is null` (re-consent revokes + recreates → rotation).
- `private.mcp_oauth_tokens` — `token_hash text PK`, `kind text check (in ('access','refresh'))`, `grant_id uuid not null FK`, `family_id uuid not null` (refresh reuse detection), `issuer text not null`, `audience text not null`, `expires_at timestamptz not null`, `rotated_to_hash text`, `used_at timestamptz`, `revoked_at timestamptz`; index `(grant_id, kind)`, index `(family_id)`.
- `private.mcp_request_audit` — `id bigint generated always as identity PK`, `request_id text not null`, `occurred_at timestamptz not null default now()`, `grant_id uuid`, `client_id uuid`, `actor_user_id uuid`, `company_id uuid`, `tool text`, `protocol_era text`, `outcome text not null` (`ok | domain_error | unauthenticated | forbidden | rate_limited | internal`), `error_code text`, `input_sha256 text`, `result_bytes integer`, `latency_ms integer`. Append-only: `revoke all` mutations; only the append RPC writes.

**RPCs** (each: service-role gate `auth.role() is distinct from 'service_role'` → `42501`; single statement where possible; fixed errcodes):

1. `public.register_mcp_oauth_client_as_system(p_client_name text, p_redirect_uris text[], p_scope text, p_software_id text, p_software_version text) returns table(client_id uuid, …)` — inserts a dynamic registration. Redirect-URI allowlist enforcement lives in TypeScript (it is policy, not storage); the RPC re-asserts non-empty https URIs.
2. `public.get_mcp_oauth_client_as_system(p_client_id uuid) returns table(…)` — active client row or empty.
3. `public.create_mcp_oauth_authorization_code_as_system(p_code_hash text, p_client_id uuid, p_user_id uuid, p_company_id uuid, p_scopes text[], p_redirect_uri text, p_code_challenge text, p_resource text, p_expires_at timestamptz)` — asserts client active, user active + company member (reuses `private.user_is_active_company_member`).
4. `public.consume_mcp_oauth_authorization_code_as_system(p_code_hash text, p_client_id uuid, p_redirect_uri text) returns table(user_id, company_id, scopes, code_challenge, resource, …)` — single-statement `update … set consumed_at = now() where code_hash = … and client_id = … and redirect_uri = … and consumed_at is null and expires_at > now() returning …`; empty result = invalid_grant. A consumed-code replay additionally revokes any grant already minted from that code (RFC 6749 §4.1.2 replay defense) — second statement in the same function, keyed by a `minted_grant_id` column stamped at exchange.
5. `public.mint_mcp_oauth_grant_as_system(p_code_hash text, p_client_id uuid, p_user_id uuid, p_company_id uuid, p_scopes text[], p_access_hash text, p_refresh_hash text, p_issuer text, p_audience text, p_access_expires_at timestamptz, p_refresh_expires_at timestamptz) returns table(grant_id uuid, revision text)` — revokes any prior live grant for `(user, company, client)`, inserts grant + both tokens + stamps `minted_grant_id` on the code row, one transaction.
6. `public.rotate_mcp_oauth_refresh_token_as_system(p_presented_hash text, p_new_access_hash text, p_new_refresh_hash text, p_access_expires_at timestamptz, p_refresh_expires_at timestamptz) returns table(grant_id, user_id, company_id, scopes, revision, issuer, audience, reuse_detected boolean)` — if the presented refresh row is already `used_at is not null` → **reuse**: revoke the whole family + grant, return `reuse_detected = true`; else mark used, insert successors in the same family, touch `grants.last_used_at`.
7. `public.resolve_mcp_oauth_access_token_as_system(p_token_hash text) returns table(grant_id, client_id, user_id, company_id, scopes, revision, issuer, audience, expires_at, grant_revoked boolean, client_disabled boolean)` — one join; the TypeScript layer rejects on any of expired/revoked/disabled. Touches `last_used_at` (update-returning).
8. `public.revoke_mcp_oauth_grant_as_system(p_grant_id uuid, p_user_id uuid) returns boolean` — revokes grant + all its tokens; `p_user_id` must match the grant row (operator self-service path).
9. `public.revoke_mcp_oauth_token_as_system(p_token_hash text) returns boolean` — RFC 7009: revokes the token's grant + family regardless of kind; unknown token → `true` (7009 requires 200).
10. `public.list_mcp_oauth_grants_for_user_as_system(p_user_id uuid, p_company_id uuid) returns table(grant_id, client_name, scopes, created_at, last_used_at)` — live grants only, for the settings surface.
11. `public.append_mcp_request_audit_as_system(p_request_id text, …) returns void` — the only writer to the audit table.

**Verification without a local PG runtime:** full-file parse sweep with local PostgreSQL 17 (`begin;`/`commit;` stripped so each statement validates independently; zero-column stub tables for composite DECLAREs — the proven 2026-08-17 technique). Apply to prod happens in the ship sequence, not during the build.

---

## Tasks

Execution model: subagent-driven in this session. **Fable (main loop) writes:** the migration SQL (Task 2), the token/PKCE security core (Task 3 core), the bearer→actor wiring inside `/api/mcp` (Task 6 core), and reviews every other diff. **Opus subagents execute:** route boilerplate, the consent/settings UI from spec, and test suites from enumerated cases. TDD per task: write the failing test, watch it fail, implement, watch it pass, commit (`feat(mcp): …` / `test(mcp): …` conventional style, atomic).

### Task 1 — Plan committed (this document)
Commit to bible: `docs(specs): P1 implementation plan for the Claude-first MCP mount`.

### Task 2 — Migration `<ts>_mcp_oauth_authorization_server.sql` (Fable)
Files: `supabase/migrations/…` (ops-web), mirrored to bible `migrations/` in Task 10.
Steps: write SQL per spec above → PG17 parse sweep green → commit `feat(mcp): OAuth authorization-server schema + system RPCs`.

### Task 3 — OAuth core library (Fable core, Opus tests)
Files: `src/lib/agent-control-plane/mcp/oauth/tokens.ts` (entropy, sha256 hex hashing, constant-shape lookups), `pkce.ts` (S256 verify via `crypto`), `clients.ts` (DCR metadata validation + claude.ai redirect allowlist from research appendix), `grants.ts` (lifecycle over the RPCs), `config.ts` (issuer/resource/base-URL resolution — `NEXT_PUBLIC_APP_URL` in prod, request origin in dev), `scopes.ts` (the supported read scopes + human-readable consent strings — **correction during build:** the true union of `requiredOAuthScopes` across the nine reads is SEVEN scopes, adding `ops.customer_contacts.read`; an early single-line grep missed multi-line arrays and the manifest-consistency test caught it), `index.ts`.
Tests: `src/lib/agent-control-plane/mcp/oauth/__tests__/` — token entropy/hash determinism; PKCE S256 vectors (RFC 7636 appendix B) + rejection of `plain`/absent; client validation (allowlist, https-only, exact-match redirect); grant flows against a mocked rpcClient (mint, rotate, reuse→family revocation, revoke).
Commit: `feat(mcp): OAuth core — opaque tokens, PKCE S256, client policy, grant lifecycle`.

### Task 4 — Discovery + DCR + token + revoke routes (Opus from this spec, Fable review)
Files:
- `src/app/.well-known/oauth-protected-resource/api/mcp/route.ts` and `…/oauth-protected-resource/route.ts` (RFC 9728: `resource`, `authorization_servers`, `scopes_supported`, `bearer_methods_supported: ["header"]`)
- `src/app/.well-known/oauth-authorization-server/route.ts` (RFC 8414: endpoints, `code_challenge_methods_supported: ["S256"]`, `grant_types_supported: ["authorization_code","refresh_token"]`, `token_endpoint_auth_methods_supported: ["none"]`, `scopes_supported`, registration endpoint)
- `src/app/api/mcp/oauth/register/route.ts` (POST, RFC 7591 — rate-limited 10/hour/IP, allowlist-validated, 201 with client_id, no secret)
- `src/app/api/mcp/oauth/token/route.ts` (POST form-encoded; `authorization_code` + `refresh_token` grants; PKCE verified server-side; `resource` validated; RFC 6749 error bodies; `Cache-Control: no-store`)
- `src/app/api/mcp/oauth/revoke/route.ts` (POST, RFC 7009, always 200)
Tests: `tests/unit/mcp/oauth-routes.test.ts` — metadata shapes byte-stable; DCR happy/reject paths; token endpoint: wrong client, wrong redirect, bad verifier, expired/replayed code (replay revokes minted grant), refresh rotation, reuse detection, revoked grant; revoke idempotency; every error is RFC-shaped with no OPS vocabulary.
Commit: `feat(mcp): OAuth discovery, registration, token, and revocation endpoints`.

### Task 5 — Consent page + decision endpoint (Opus UI from spec; skills: ops-design, frontend-design, ops-copywriter; audit-design-system before done)
Files: `src/app/oauth/authorize/page.tsx` + `_components/consent-panel.tsx` (client), `src/app/api/mcp/oauth/authorize/decision/route.ts` (POST, Firebase-token-authenticated via `verifyAdminAuth` + `findUserByAuth`; validates client/redirect/scope/PKCE/resource server-side; mints code via RPC; returns `{redirect_to}`).
Design: focused single panel, no dashboard chrome; OPS mark; `// CONNECT :: <client_name>`; company line; scope list as human capability lines (from `scopes.ts`); APPROVE (primary) / DENY. Tokens only — zero hardcoded values. Deny → `error=access_denied` redirect.
Tests: decision endpoint unit tests (auth required, param tampering, scope escalation attempt → clamped/rejected, open-redirect attempts rejected by exact-match).
Commit: `feat(mcp): OAuth consent surface and decision endpoint`.

### Task 6 — `/api/mcp` transport route (Fable wiring, Opus tests)
Files: `src/app/api/mcp/route.ts`, `src/lib/agent-control-plane/mcp/runtime.ts` (mirror of `internal-runtime.ts`: service-role rpcClient + prod cursor codec (`keyId "mcp-operational-read"`, version 1) → repositories → domain service, module-scope singleton), `src/lib/agent-control-plane/mcp/bearer.ts` (header parse → hash → `resolve_mcp_oauth_access_token_as_system` → expiry/revocation/audience/issuer checks → `createMcpPrincipalFromValidatedGrant` → `resolveActorContext`), `src/lib/agent-control-plane/mcp/server-factory.ts` (per-request `McpServerFactory`: manifest filter per D6, `registerTool` per capability with zod-v4 inputSchema + annotations; handler = rate-limit check → domain call with 25s AbortSignal → `serializeUntrustedPromptData` result → audit append; ActorAccessError → D9 envelope), `src/lib/agent-control-plane/mcp/audit.ts`, `src/lib/agent-control-plane/mcp/rate-limit.ts` (D7 buckets).
Route: POST → permissive origin policy (absent Origin = allow, server-to-server; present-and-foreign → 403 — Anthropic warns strict Origin validation breaks initialize) → bearer (absent/invalid → D8 401, BEFORE the SDK sees any JSON-RPC) → rate-limit gate → `handler.fetch(request, {authInfo})` with `authInfo = {token, clientId, scopes, expiresAt, resource, extra: {grantId, actorUserId, companyId, revision, era}}`. GET/DELETE → the same 401 gate, then SDK 405. `export const maxDuration = 60` (tool budget 300s upstream; domain signal 25s). Raw `@modelcontextprotocol/server` (already shipped as the `mcp/sdk.ts` boundary), NOT `mcp-handler` — the auth gate needs to own the request before any SDK wrapper, `handler.fetch` is already web-standard, and adding a second wrapper with its own auth opinions buys nothing.
Tests: `tests/unit/mcp/transport.test.ts` + `src/lib/agent-control-plane/mcp/__tests__/` — unauthenticated non-disclosure (assert response bytes contain no capability name, no tool vocabulary); expired/revoked/reuse-revoked tokens; audience mismatch; tools/list returns exactly the enabled set (starts at zero → empty); tools/call on a disabled capability → method-not-found-shaped error with no existence hint; happy dispatch with mocked domain service asserting the minted principal's user/company come from the grant; rate-limit 429; audit rows on every outcome; both protocol eras (modern envelope + legacy initialize).
Commit: `feat(mcp): mount streamable-HTTP MCP transport with actor-authority bearer boundary`.

### Task 7 — Exposure flips + settings revoke surface
7a (Fable, one commit per flip batch): `EXTERNAL_READ_AVAILABILITY = { implementation: "available", externalExposure: "enabled" }` in `read-tools.ts`; flip `list_scheduled_jobs` first → transport test proves listing + dispatch + scope denial → flip remaining eight, each with a listing/dispatch test.
7b (Opus, skills as Task 5): `src/app/(dashboard)/settings/integrations/` — "CONNECTED AGENTS" section: live grants (client name, scopes as capability lines, created/last-used) + REVOKE (calls a new `src/app/api/mcp/oauth/grants/` GET/DELETE pair, Firebase-authenticated, self-service only). Empty state `—`. Design-system audit.
Commits: `feat(mcp): expose the nine v6 reads externally`, `feat(mcp): connected-agents grant management in settings`.

### Task 8 — Full gate
`npx tsc --noEmit` clean; `npx vitest run` on all new suites + `src/lib/agent-control-plane` suite green; `npx eslint` on touched files zero errors. Known caveat: full-suite cross-file pollution — isolate any failing file against origin/main before calling regression. Build check `NODE_OPTIONS=--max-old-space-size=8192 npm run build` (heap gotcha).

### Task 9 — Live E2E vs Maverick (local dev server, prod Supabase)
Local `.env.local` copy (never edit the symlink) + a dev cursor key (any 64-hex; prod key is Jackson's). Scripted probes (scratchpad, then deleted; evidence to `docs/artifacts/` if kept):
1. DCR register → authorize as Maverick admin (Firebase session) → consent APPROVE → code → token exchange → refresh rotate → reuse-replay proves family revocation.
2. MCP initialize/discover both eras; tools/list = exactly nine; every read called with real Maverick data; paging on `list_scheduled_jobs` proves the cursor codec against the dev key.
3. Tenant-isolation probes: other-company opportunity/project/customer UUIDs in every ID position → sentinel `NOT_FOUND`/`FORBIDDEN` envelopes, zero data.
4. Unauthenticated `/api/mcp` (POST tools/list, GET, garbage bearer) → D8, response bytes free of capability vocabulary.
5. Revoke in settings → next MCP call 401.
6. Cleanup: delete test grants/clients/codes/tokens/audit rows; verify zero residue.

### Task 10 — Bible (same session)
`04_API_AND_INTEGRATION.md`: new section "OPS Remote MCP Server (P1, 2026-08-18)" — routes, OAuth contract, token model (D2 rationale), rate limits, audit, non-disclosure posture, cursor-key operational note. `03_DATA_ARCHITECTURE.md`: the five tables + eleven RPCs. `migrations/` mirror (byte-exact). Status updates: foundation spec §status + mount scope doc (built/awaiting gates). Commits per bible convention.

### Task 11 — Jackson gates (flag, never route around)
1. **Cursor key**: provision `OPS_AGENT_OPERATIONAL_READ_CURSOR_KEY` in Vercel prod (64 lowercase hex, `openssl rand -hex 32`); prove readback without exposure (probe endpoint? No — verify via a paged read once live).
2. **Apply migration + push main** — one GO: migration to prod (additive, dark until code lands), then push auto-deploys to customers.
3. **Connector**: Jackson adds `https://app.opsapp.co/api/mcp` in claude.ai (typed exactly — the PRM `resource` must match as-typed; if his workspace is Team/Enterprise, adding custom connectors requires the Owner role) → OAuth consent in his browser → live handshake, tool listing visible in Claude UI → Maverick reads from the Claude UI → tenant probes from Claude. Note: discovery responses cache ~5 minutes globally — metadata iterations propagate lazily.

**Cost note:** no new paid services. Vercel function invocations at one-connection scale ≈ noise; KV is NOT provisioned so rate limiting degrades per-instance (documented; attach KV later if abuse appears — that would be a new ~$1-10/mo line Jackson approves).

---

## Verification bar (from the scope doc — P1 is done when)
- Live connector handshake from Jackson's claude.ai account; tool listing visible.
- Scoped reads exercised against Maverick through the connector.
- Tenant-isolation probes return sentinel errors, not data.
- Unauthenticated `/api/mcp` rejects without capability disclosure.
- Auto-send posture untouched.

## Research appendix (live-verified 2026-08-18, all claims from pages fetched today)

**Transport + protocol.** Claude supports Streamable HTTP; legacy HTTP+SSE is deprecated (claude.com/docs/connectors/building/index). Claude's auth-spec support lists 2025-03-26 / 2025-06-18 / 2025-11-25 only; clients still send `initialize` (building/testing), which 2026-07-28 removed — so Claude is pre-2026-era today; Anthropic's 2026-07-28 rollout is announced "soon" with no surface confirmed (claude.com/blog/bringing-mcp-2026-07-28-to-claude). Stateless is explicitly acceptable — sessions are optional under 2025-11-25 (modelcontextprotocol.io/specification/2025-11-25/basic/transports) and Anthropic's own sample uses `sessionIdGenerator: undefined` (building/lazy-authentication). 405 on GET is compliant for servers without a server-initiated stream. Origin validation must not be strict — a documented initialize-timeout cause (building/testing). Connectors run server-side from Anthropic infra (building/troubleshooting), egress `160.79.104.0/21` (platform.claude.com/docs/en/api/ip-addresses), IPv4-only (A record required), public reachability screened before any request is sent.

**OAuth.** Authorization-code + PKCE S256 always; AS must advertise `code_challenge_methods_supported: ["S256"]` (building/authentication). Registration: DCR out of the box (default), CIMD only when the AS advertises `client_id_metadata_document_supported: true` AND `none` in `token_endpoint_auth_methods_supported`, manual client-ID entry via Advanced settings (secret optional). Callback URL for claude.ai web/Desktop/mobile/Cowork: `https://claude.ai/api/mcp/auth_callback` (building/authentication § Callback URLs); the `claude.com` twin is third-party-claimed only, unverified. Claude Code uses its own CIMD client with loopback redirects (port ignored) — out of P1 scope since CIMD is unadvertised. RFC 8707 `resource` is sent on authorize and token requests in canonical form; audience checks should compare canonically (building/troubleshooting). Discovery: PRM via the 401 `resource_metadata` pointer, probe order path-inserted-then-root; AS metadata at `/.well-known/oauth-authorization-server` with openid-configuration fallback; `authorization_servers` first entry only. 401 challenge shape verbatim: `WWW-Authenticate: Bearer error="invalid_token", resource_metadata="…", scope="…"` (building/lazy-authentication). Token endpoint must accept form-encoded; `/register` JSON (415 on mismatch). Dead refresh tokens must return `invalid_grant`. Budgets: 10s discovery/register/token, 30s refresh.

**Auth-trigger behavior.** Only a transport-level 401 triggers the OAuth flow; a 200 with `isError: true` is passed to the model with no auth prompt; `WWW-Authenticate` on a 200 is ignored; 403 re-triggers auth only with `error="insufficient_scope"` (building/troubleshooting). ⇒ the bearer gate lives in the route, in front of the SDK.

**SDK.** `@modelcontextprotocol/server@2.0.0` (published 2026-07-27) is the stable v2 line; the v1 monolith `@modelcontextprotocol/sdk` is maintenance-only with a ~Jan-2027 sunset. v2 serves 2026-07-28 natively plus legacy `2024-10-07…2025-11-25` from one stateless factory ("One factory, one endpoint, both eras" — ts.sdk.modelcontextprotocol.io/v2/migration/support-2026-07-28); verified in the installed package (`SUPPORTED_PROTOCOL_VERSIONS` + modern-era constants). `registerTool` takes full zod-v4 schemas (`zod@^4.2` is a hard dep — satisfied by the shipped `zod-v4` alias). Vercel's `mcp-handler@2.1.1` exists as a Next.js convenience wrapper; not used per D6/D9 rationale. Vercel's prose MCP docs (last updated 2026-03-19) show the removed 1.x API — ignore them; the template repo `vercel-labs/mcp-for-next.js` reflects the current stack.

**Limits + gating.** claude.ai/Desktop tool-result cap ≈150,000 chars; tool timeout 300s; Vercel 4.5 MB body cap. Custom connectors on Free (1 max)/Pro/Max/Team/Enterprise; Team/Enterprise add = Owner-only; no staging surface (support.claude.com article 11175166). Supported primitives: tools, prompts, resources (no subscriptions/sampling). Directory review (only if ever listed publicly): tool names ≤64 chars, `title` + accurate `readOnlyHint`/`destructiveHint` required.

**Unverified/flagged.** No documented per-server tool-count limit; HTTPS-for-MCP-endpoint never stated verbatim (treated as required); `claude.com` callback twin unverified; 2026-07-28 client-side rollout status unknown.
