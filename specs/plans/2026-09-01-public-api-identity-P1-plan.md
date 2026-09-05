# PUBLIC API — P1 Identity Foundation Implementation Plan (2026-09-01)

> **For Claude:** REQUIRED SUB-SKILL: Use `custom-skills:executing-plans` to implement this plan task-by-task. Design authority: `specs/2026-09-01-public-api-customer-identity-design.md` (read it first, in full).

**Goal:** Ship the customer identity foundation: dedicated customer auth project, `private` identity/membership/session tables and RPCs, the OPS authorization broker library, a hosted branded sign-in shell, company public handles, the staff "Portal access" block, and the freeze of the legacy portal share route.

**Architecture:** Supabase Auth (dedicated project) proves identity via email OTP, called server-side only. The broker (ops-web, `src/lib/customer-identity/`) counts OTP attempts, upserts the global identity, mints an opaque hashed first-party session, and resolves company-scoped membership on every request through `*_as_system` RPCs over `private` tables. No customer credential is a JWT on the OPS side; the staff verifier is untouched.

**Tech Stack:** Next.js 15 App Router, `@supabase/supabase-js` admin client pointed at the **customer** project (new env vars), Supabase `private` schema + SECURITY DEFINER RPCs (house pattern from `20260807204914_agent_control_plane_actor_authority.sql` and `20260818155813_mcp_oauth_authorization_server.sql`), Node `crypto` (SHA-256 digests, HMAC key ring pattern from `.worktrees/lead-intake-api/src/lib/external-api/auth/credential-secret.ts`), vitest (`tests/unit`, `tests/integration`), Playwright for the hosted page.

**Design System:** `ops-design-system/project/DESIGN.md`; hosted pages additionally apply `portal_branding` via the existing `generatePortalTheme` in `src/lib/portal/theme.ts`.

**Required Skills:** `custom-skills:executing-plans`, `superpowers:test-driven-development`, `supabase:supabase` (all DB tasks), `ops-design` + `frontend-design:frontend-design` + `custom-skills:interface-design` + `ops-copywriter:ops-copywriter` (Tasks 6, 7), `custom-skills:audit-design-system` (before any UI is called done), `superpowers:verification-before-completion`.

**Worktree rule:** ops-web work happens in a fresh worktree off `origin/main` (never branch-switch the primary checkout; run your own `npm ci`; build with `NODE_OPTIONS=--max-old-space-size=8192`). Branch: `feat/public-api-identity-p1`. Commit atomically, no AI attribution, never push.

---

## Verified starting state (2026-09-01, live)

- Main project `ijeekuhbatykdomumfjx`. `clients.id uuid`, `clients.company_id uuid`, `clients.merged_into_client_id uuid`; unique constraints on `clients`: `clients_pkey(id)`, `clients_bubble_id_key(bubble_id)` — **no** `UNIQUE(id, company_id)` yet. `sub_clients(id, client_id, company_id, name, email, phone_number, deleted_at)` exists.
- Normalizers: `private.agent_normalize_discovery_email(text)`, `private.agent_normalize_discovery_phone(text)`; partial indexes `clients_agent_discovery_exact_email_idx`, `sub_clients_agent_discovery_exact_email_idx`.
- Identity helpers: `private.get_current_user_id()`, `private.get_user_company_id()` resolve `users` by `auth.jwt()->>'sub'` (`auth_id`/`firebase_uid`). Customer tokens never reach them (I9).
- Staff verifier: `src/lib/firebase/admin-verify.ts` — Firebase issuer + audience pinned; cookies read: `ops-auth-token`, `__session`.
- Middleware `src/middleware.ts:32-101`: portal prefixes; `/c/` is not yet public.
- Legacy portal: `src/app/api/portal/share/route.ts` mints tokens (freeze target). `portal_branding` columns: `logo_url, accent_color, template, theme_mode, font_combo, welcome_message, show_*`.
- Notifications RPC: `create_notification_if_new_with_identity(p_user_id uuid, p_company_id uuid, p_type text, p_title text, p_body text, p_persistent boolean, p_action_url text, p_action_label text, p_project_id text, p_deep_link_type text, p_dedupe_key text)`. **Verify the `notifications.type` CHECK enum before choosing a type** (bible: no dedicated lead-lifecycle type; `leads_waiting` was the compatible choice).
- MCP OAuth library to mirror (origin main `b26c2730`): `src/lib/agent-control-plane/mcp/oauth/{tokens.ts,grants.ts,pkce.ts}` — `sha256Hex`, `mintCredential(prefix)`, `secretsEqual`, `callRpc` wrapper with zod row schemas.
- Test company: MAVERICK PROJECTS LTD `ddee107c-33cd-483e-8278-0f8d8a180181` (admin actor `8e811f98-9f2b-4f64-b409-ed56074b7dc8`).
- `companies` has no slug/handle column (`website` only).

## Architecture decisions settled here

1. Env vars (server-only, never `NEXT_PUBLIC_`): `OPS_CUSTOMER_AUTH_URL`, `OPS_CUSTOMER_AUTH_SECRET_KEY` (service/secret key of the customer project), `OPS_CUSTOMER_IDENTITY_HMAC_KEYS` (key ring, same format as the intake credential ring). Blank in prod until G1 → the broker fails closed with `customer_identity_unavailable`.
2. Session cookie: `ops-customer-session`, httpOnly, Secure, SameSite=Lax, Path=`/` (ruled 2026-09-02: `/c` would never reach `/api/customer/*`; the guardrail test proves no staff route or middleware prefix consults this cookie). Value = opaque 256-bit `ops_cs_` prefixed credential; stored as SHA-256 digest only.
3. Route namespace: hosted pages `/c/[handle]/...`; broker API `/api/customer/...`. Middleware: `/c` and `/api/customer` are public prefixes (no staff cookie), and the staff dashboard never reads `ops-customer-session`.
4. OTP: Supabase issues and checks the code; OPS owns attempt accounting (`private.customer_otp_challenges`) and refuses before proxying when exhausted. Customer project config: OTP expiry 600s, email template carries `{{ .Token }}` (no link), custom SMTP = SendGrid, Data API disabled, signups via OTP only.
5. Membership evidence promotion (I2) is a SQL function `private.customer_membership_evidence(company_id, client_id, normalized_email) → text` returning `on_file_transacted | none`, evaluated inside `resolve_customer_membership_as_system` and by the staff confirm RPC.

## Database migration (Task 2 — Fable writes the SQL directly; contract below is binding)

Ledger name: `<ts>_customer_identity_foundation.sql`, applied via MCP `apply_migration` after local review; mirrored byte-exact into `ops-software-bible/migrations/`.

Objects:
- `ALTER TABLE public.clients ADD CONSTRAINT clients_id_company_id_key UNIQUE (id, company_id);`
- `ALTER TABLE public.companies ADD COLUMN public_handle text;` + backfill (slugified name, `-2`, `-3` … on collision) + `UNIQUE INDEX companies_public_handle_key` + CHECK `^[a-z0-9]+(-[a-z0-9]+)*$` length 3–48.
- Tables in `private` (all privileges revoked from `public, anon, authenticated, service_role`): `customer_identities`, `customer_verified_contacts`, `customer_sessions`, `customer_otp_challenges`, `company_client_memberships`, `customer_integrations`, `customer_pairwise_refs`, `customer_identity_events` (columns per design §4; every table `company_id uuid` where applicable; `created_at/updated_at` triggers).
- Trigger on `public.clients` AFTER UPDATE OF `merged_into_client_id`: re-point live memberships from loser to winner (state `merged` on the old row, new/merged row on the winner, event appended).
- RPCs (`public.*_as_system`, SECURITY DEFINER, `search_path` pinned `'pg_catalog','public','private','pg_temp'`, gate `auth.role() is distinct from 'service_role'` → `42501 access_denied`):
  - `begin_customer_otp_challenge_as_system(p_email_digest text, p_network_fingerprint text) → (challenge_id uuid, allowed boolean, retry_after_seconds int)` — enforces I8 send limits.
  - `record_customer_otp_attempt_as_system(p_challenge_id uuid, p_success boolean) → (attempts int, exhausted boolean)`.
  - `upsert_customer_identity_as_system(p_auth_subject text, p_email text) → (identity_id uuid, created boolean)` — also upserts the verified email contact; conflict on a live contact owned by another identity raises `customer_contact_conflict` (`23505`) — never silently moves a contact.
  - `mint_customer_session_as_system(p_identity_id uuid, p_session_hash text, p_network_fingerprint text) → session_id uuid`.
  - `resolve_customer_session_as_system(p_session_hash text) → (identity_id uuid, session_id uuid, status text)` — slides idle expiry; `status ∈ ok, expired, revoked, unknown`; stamps `customer_identities.last_seen_at`.
  - `revoke_customer_session_as_system(p_session_hash text, p_reason text) → boolean` and `revoke_all_customer_sessions_as_system(p_identity_id uuid, p_reason text) → int`.
  - `resolve_customer_membership_as_system(p_identity_id uuid, p_company_id uuid) → (membership_id uuid, client_id uuid, sub_client_id uuid, state text, outcome text)` — implements design §5.3 with advisory lock; `outcome ∈ existing, matched_forward_only, matched_full, created, created_possible_duplicate`; creates client rows through the same insert shape `create_opportunity_guarded` expects (`company_id`, `name`, `email`, `created_at`); writes possible-duplicate notification.
  - `confirm_customer_membership_as_system(p_membership_id uuid, p_staff_user_id uuid) → text` and `revoke_customer_membership_as_system(p_membership_id uuid, p_staff_user_id uuid, p_reason text) → boolean` — staff actions; both verify the staff user belongs to the membership's company.
  - `list_customer_memberships_for_client_as_system(p_company_id uuid, p_client_id uuid) → setof (membership_id, state, evidence_kind, contact_email_masked, last_seen_at)` — masked email only.
  - `ensure_customer_pairwise_ref_as_system(p_identity_id uuid, p_integration_id uuid) → text`.
  - `read_customer_profile_as_system(p_identity_id uuid, p_company_id uuid) → (display_name text, contact_email_masked text, membership_state text)` (added 2026-09-02 for `GET /api/customer/me`): `display_name` = live membership's `sub_clients.name` if set, else `clients.name`, else NULL with no live membership in that company; `contact_email_masked` = the identity's live verified email masked by the same private function the listing RPC uses; `membership_state` = live state or `'none'`.
  - `append_customer_identity_event_as_system(...)` — single writer for the audit table.
- Dormancy job (I7): `private.customer_identity_dormancy_sweep()` scheduled daily via `pg_cron`, demotes `active_full` → `active_forward_only` for identities with `last_seen_at < now() - interval '180 days'`, re-runs evidence promotion, appends events.

Acceptance for Task 2: advisors clean; zero table grants to any role on the new tables (query `information_schema.role_table_grants`); the non-service gate live-fired (`select public.resolve_customer_session_as_system('x')` as anon → `42501`).

## Tasks

### Task 1 — Plan committed (this document). Done in the PM session.

### Task 2 — Migration (Fable). Files: `ops-web/supabase/migrations/<ts>_customer_identity_foundation.sql`, mirror in `ops-software-bible/migrations/`. Apply to prod only after Task 3's contract tests are written against the SQL locally; record ledger + verification in bible `03_DATA_ARCHITECTURE.md` (new section "Customer identity & memberships").

### Task 3 — Broker library (Opus; TDD)
**Files:** create `src/lib/customer-identity/{config.ts, credentials.ts, otp.ts, session.ts, membership.ts, rpc.ts, errors.ts, index.ts}`; tests `tests/unit/customer-identity/*.test.ts`.
- `credentials.ts`: `mintSessionCredential()` → `ops_cs_` + 43-char base64url; `sessionDigest(value)` SHA-256 hex; `emailDigest(email, keyRing)` HMAC with key id; `normalizeEmail` (lower, trim, NFKC).
- `otp.ts`: `startOtp(email, ctx)` → begin challenge RPC → if allowed call customer-project admin client `auth.signInWithOtp({ email, options: { shouldCreateUser: true } })` → always return `{ challengeId, retryAfterSeconds }` (identical shape either way, I5). `verifyOtp(challengeId, email, code)` → refuse when exhausted → `auth.verifyOtp({ email, token: code, type: 'email' })` → on failure record attempt → on success `upsert_customer_identity_as_system(user.id, email)`, set `app_metadata.principal='customer'` via `auth.admin.updateUserById` when `created`, **never persist or return the Supabase session**, mint broker session, append events.
- `session.ts`: `readSession(request)` → cookie → digest → `resolve_customer_session_as_system` → typed `CustomerSession | null`; `setSessionCookie(response, credential)`; `signOut(request)`; `signOutEverywhere(identityId)`.
- `membership.ts`: `resolveMembership(identityId, companyId)` → RPC → typed result; `requireMembership(session, companyId, { needFullHistory })` → throws `CustomerAccessError` with privacy-safe codes `NOT_FOUND | FORWARD_ONLY | REVOKED`.
- `rpc.ts`: `callRpc` wrapper with zod row schemas (mirror `mcp/oauth/grants.ts:102-150`); service-role client from `getServiceRoleClient`.
- Tests: unit for credentials/normalization (property: digest stable across case/whitespace), otp state machine with mocked admin client + mocked RPC (exhaustion refuses before proxy; unknown email returns same shape; success never returns Supabase tokens), session (expired/revoked → null, cookie attributes exact), membership (all five outcomes mapped, forward-only gate).
- Commit per module.

### Task 4 — Broker routes (Opus)
**Files:** `src/app/api/customer/auth/start/route.ts` (POST `{handle, email}`), `.../auth/verify/route.ts` (POST `{handle, challengeId, code, email}` → sets cookie, returns `{ ok: true, next: "/c/<handle>/home" }` — **no ids**; ruled 2026-09-02: Supabase `verifyOtp` needs the email and the challenge row holds only its HMAC digest, so the route recomputes the digest of the normalized supplied email and requires equality with the challenge before proxying — on mismatch it records an attempt, skips Supabase, and returns the same generic invalid-code response as a wrong code (I5); a missing email is the only `400 invalid_request`), `.../auth/signout/route.ts`, `.../me/route.ts` (GET → `{ displayName, maskedEmail, membership: { state } }` for the handle's company only). Resolve `handle → company_id` server-side via `companies.public_handle`; unknown handle → same 404 body as inactive integration. Rate limit per IP with the shared limiter in `src/lib/utils/ratelimit.ts` in addition to I8. Tests in `tests/api/customer-auth-*.test.ts` (route handlers invoked directly with `NextRequest`).

### Task 5 — Middleware + freeze (Opus)
- `src/middleware.ts`: add `/c` and `/api/customer` to public prefixes; assert staff-protected prefixes never consult `ops-customer-session`. Test: `tests/unit/middleware-customer-prefixes.test.ts`.
- Freeze `src/app/api/portal/share/route.ts`: return `410 { error: "portal_link_sharing_retired" }`; delete the SendGrid magic-link call site if now unused (`src/lib/email/sendgrid.tsx` `sendMagicLink`); hide the "Share portal" affordance behind the same response (find call sites with `grep -rn "api/portal/share" src`). Test asserts 410 for an admin request.
- Guardrail test `tests/integration/customer-token-rejected-by-staff-routes.test.ts`: a minted `ops_cs_` credential presented as `Authorization: Bearer`, `ops-auth-token`, and `__session` to five representative staff routes yields 401 each time, and `verifyAuthToken` throws.

### Task 6 — Hosted sign-in shell (Opus; skills: ops-design, frontend-design, interface-design, ops-copywriter; audit-design-system before done)
**Files:** `src/app/c/[handle]/layout.tsx` (loads `portal_branding` + company name server-side, applies `generatePortalTheme` CSS vars, "powered by OPS" footer), `src/app/c/[handle]/signin/page.tsx` (email step → code step, 6 single-digit inputs, resend with countdown from `retryAfterSeconds`, error states that never reveal existence), `src/app/c/[handle]/home/page.tsx` (placeholder that reads `/api/customer/me` and renders the membership state copy: full / forward-only / none — P3 replaces it). Tokens only; motion = the single house easing; `prefers-reduced-motion` honored. Copy register: product, terse. Playwright smoke in `tests/e2e/customer-signin.spec.ts` with the admin client stubbed.

### Task 7 — Staff "Portal access" block (Opus; skills as Task 6)
**Files:** `src/components/clients/portal-access-block.tsx` mounted in the client detail page (locate via `grep -rn "ClientDetail" src/app/(dashboard)`), fed by `GET /api/clients/[id]/portal-access` (lists memberships via `list_customer_memberships_for_client_as_system`, staff auth via `verifyAdminAuth` + `findUserByAuth` + company match) with actions `POST .../confirm`, `POST .../revoke`. Row per membership: masked email, state tag (design-system status tags), last seen (JetBrains Mono), actions behind the row. Empty state `—`. Tests for the three routes.

### Task 8 — Full gate (Opus)
`npx vitest run` on the touched files individually (full-suite cross-file pollution is a known liar), `npx tsc --noEmit`, eslint, Playwright smoke. Fix, never skip.

### Task 9 — Live E2E vs Maverick (Fable or Opus with Fable review)
Local dev server bound to prod Supabase + the customer project (after G1): sign-in creates identity; resolution matrix (0 / 1 / many / sub-client match / forward-only → confirm → full); revoke session → next request 401; sign-out-everywhere; customer credential rejected by staff routes; two Maverick clients sharing an email → possible-duplicate path + rail notification; tenant probe with another company's handle → sentinel. Delete all test identities/sessions afterward (zero residue). Evidence to `docs/artifacts/`.

### Task 10 — Bible (same session as Task 9)
`03_DATA_ARCHITECTURE.md` new section; `04_API_AND_INTEGRATION.md` broker routes; `11_CLIENT_PORTAL.md` header note "legacy magic-link auth frozen 2026-09; replacement: specs/2026-09-01-public-api-customer-identity-design.md".

### Task 11 — Jackson gates (flag, never route around)
G1 create the customer auth project ($10/mo) and provide its URL + secret key to Vercel env (Jackson or PM with his GO). G4 push/deploy.

## Verification bar — P1 is done when
- Every invariant I1–I9 in the design has at least one automated test, and I10 is enforced by the absence of any public path calling `book_site_visit`.
- Zero table grants on the new `private` tables; advisors clean; non-service gate live-fired.
- Task 9 matrix passes with screenshots/logs in `docs/artifacts/`.
- Bible updated; branch ready for Jackson's push GO.
