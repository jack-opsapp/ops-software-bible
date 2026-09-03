# OPS Public API — Customer Identity & Client Membership (Program Brief + Design)

**Date:** 2026-09-01
**Status:** Approved direction (independent review 2026-09-01: APPROVE WITH CHANGES, changes folded in below). Jackson assigned PM ownership 2026-09-01. Product decisions in §2 are the PM's recommendations and stand unless Jackson overrides.
**Program tag for spawned work:** `PUBLIC API - P<phase>-<n>`
**Owner:** PM session (Fable principal). Executors: Opus sessions per task card.

---

## 1. Outcome

An OPS customer (a trades business) connects its website to OPS so that the business's own customers (homeowners, property managers) can:

1. submit an attributed lead with typed custom fields;
2. sign in as an OPS customer, or proceed as a verified guest;
3. see safe, OPS-controlled availability;
4. book, reschedule and cancel a site visit;
5. book a job directly only when there is explicit accepted-order evidence.

The same customer identity powers the OPS client portal. One global identity maps to many isolated company-client memberships. Public APIs are guarded business intents, never CRUD.

## 2. Locked decisions

| # | Decision | Rationale (evidence) |
|---|----------|----------------------|
| D1 | **Dedicated Supabase Auth project for customers.** Never the main project. | Supabase Auth keys an account on email per project. Main `auth.users` already holds 4 legacy rows whose email matches an active staff user (live query 2026-09-01), and 4 staff emails are also client emails. A customer OTP-ing into a shared project would sign into the legacy staff auth row; `users.auth_id` is the token `sub`, so RLS helpers would resolve them **as the employee**. One project cannot hold two accounts on one email. Separate project = separate namespace + separate signing key; the main verifier rejects customer tokens structurally. Cost: $10/mo (Supabase cost API, org `zfkuhfgkgfmaqakokedt`). |
| D2 | **OPS-owned authorization broker; Supabase Auth only proves identity.** | Supabase OAuth server is public beta, scopes limited to `openid email profile phone`, no pairwise subjects, claims stale until refresh. OPS already runs a production OAuth 2.1 AS for MCP (`private.mcp_oauth_*`, PKCE S256, 600s opaque tokens, rotating refresh with family reuse revocation). Same primitives, **separate tables** — employee/agent and customer principals never share storage. |
| D3 | **Customer-facing surfaces are OPS-hosted** (branded with `portal_branding`), the business's website links or embeds them. | No third-party origin ever holds a customer token in V1. Removes the "public browser client" token class, the redirect-URI attack surface, and the contradiction with the locked intake design ("no browser-safe write token; first consumer is a site with a server component"). Third-party OAuth clients on their own origin = Phase 6, when a real integrator needs it. |
| D4 | **Email OTP only at launch.** Phone captured, stored, never verified or matched in V1. | Six-digit code, not a link: Supabase's own troubleshooting doc confirms link prefetchers consume magic links. SMS adds Twilio setup, per-message cost, toll-fraud surface; deferred to a later phase. |
| D5 | **Every verified contact at an organization client sees that organization's full history once confirmed.** | Property-manager staff are the customer. Membership carries the contact (`sub_client_id`) for attribution. |
| D6 | **Unified matching rule: lead always gets a client; access is what waits.** | Intake spec creates a fresh client flagged possible-duplicate on conflict; review proposal held resolution with no client. Merged: the record is never orphaned (fresh client on conflict, staff merge later via `execute_client_merge_guarded`), and the identity's membership to that fresh client is forward-only until confirmed. Memberships follow client merges. |
| D7 | **Legacy portal auth is retired, not migrated.** | Production: 4 `portal_tokens`, all `is_preview=true` with the all-zeros client id, 0 live sessions. No customer has ever used it. Defects (multi-use 7-day link, sessions non-revocable, raw tokens, TEXT ids without FKs, verify route returns raw ids) are retired with it. Share route frozen in P1, tables dropped in P3. |
| D8 | **All new tables live in `private`, reachable only through `*_as_system` SECURITY DEFINER RPCs gated on service role.** | The app runs as `anon`; policies target `public`. Audit 2026-09-01: 495 policies, 86 target the `authenticated` role, 2 trust login alone (`onboarding_analytics` read-all, `promo_codes`), 18 use deprecated `auth.role()`. Nothing customer-related may be reachable via PostgREST. |

## 3. Non-negotiable invariants (from the review; P0/P1)

- **I1 — Verified-channel-only matching.** Only identifiers verified within the current intent, or already verified on this identity, may match a client. An unverified phone typed by a guest is stored as evidence and never used as a match key.
- **I2 — History waits for company evidence.** A membership created by matching an existing client starts `active_forward_only`. It becomes `active_full` only when (a) the client's on-file email equals the verified email **and** the company has an estimate or invoice for that client in a sent/approved/paid state, or (b) staff confirm in-app. Forward-only means: the customer sees only leads, bookings and documents created through this identity.
- **I3 — Sign-in proves identity, not authority.** Effective authority per request = integration grant ∧ (customer membership ∨ guest intent) ∧ current membership state ∧ endpoint domain rules. Reloaded every request; nothing trusted from a stale token.
- **I4 — No raw identifiers cross the boundary.** Pairwise customer refs per integration, opaque booking refs, opaque signed slot descriptors, company addressed by `public_handle`, crew never named, assignment server-side.
- **I5 — Enumeration-safe.** Browser-facing responses never reveal whether an account, client or booking exists for someone else. OTP start returns the same shape for known and unknown emails.
- **I6 — Broker session is a first-class credential.** Opaque, hashed at rest, 30-day absolute / 7-day idle, revocable per session and everywhere, every issue/revoke in the identity event log.
- **I7 — Dormant and recycled identities re-gate.** Identity inactive > 180 days → every `active_full` membership drops to `active_forward_only` until I2 evidence is re-evaluated. Companies can revoke a membership.
- **I8 — Holds and codes are abuse-bounded.** Slot holds ≤ 5 min, ≤ 3 concurrent unverified holds per network fingerprint and ≤ 10 per company; staff bookings override holds. OTP: 10-minute expiry, 5 attempts per challenge then invalidated, 1 send per identifier per 60s, 5 sends per identifier per hour (broker-enforced; Supabase's limit is per-IP only).
- **I9 — Customer tokens are never JWTs on the OPS side.** Broker credentials are opaque with a distinct prefix; the staff verifier (`src/lib/firebase/admin-verify.ts`) is Firebase-issuer-pinned and stays untouched. The customer project's publishable key is never shipped to any browser; the broker calls the customer project server-side only.
- **I17 — No public read path may create or mutate tenant data.** (Added 2026-09-03 after the P1 live E2E found a write-on-read.) Resolution has two distinct operations and they must not share an RPC: *reporting* a membership (read-only; used by `/api/customer/me`, every hosted page render, and any future read) and *establishing* one (may write; permitted only at a genuine business intent). A signed-in customer requesting any company's handle must never cause a row to appear in that company's data.
- **I18 — A client record is born of intent, not of sign-in.** (Supersedes the zero-match branch of §5.3 for the sign-in path.) Signing in proves identity only (I3). If the verified contact matches an existing client in that company, a membership is established under the I2 evidence rules. If it matches nothing, **no client and no membership are created** — the membership resolves to `none` and the hosted home says so honestly. Client creation belongs to the moments that carry real intent: confirming a booking (P2 `confirm_guest_booking_as_system`), submitting a lead (P4 intake), or claiming a guest booking. Those paths already create through `create_opportunity_guarded` and the guest-intent confirm, and are unaffected.
- **I10 — Public booking never selects crew.** System variants of the booking RPCs take an availability-policy-derived assignee; the live `book_site_visit` (staff-actor, caller-chosen assignees, one-open-booking-per-lead) is not called from public paths.

## 4. Identity model (main OPS database, schema `private`)

| Table | Purpose | Key constraints |
|-------|---------|-----------------|
| `customer_identities` | One row per global customer. `auth_subject` = dedicated-project `auth.users.id`. | `UNIQUE(auth_subject)`. Contains **no** company data. `status ∈ active, suspended, erased`. `last_seen_at` drives I7. |
| `customer_verified_contacts` | Verified channels for an identity. | `UNIQUE(channel, normalized_value) WHERE revoked_at IS NULL` (a live verified email belongs to one identity). `channel ∈ email, phone`. `verified_at`, `revoked_at`, `verification_source ∈ otp, guest_claim, staff_attestation`. |
| `company_client_memberships` | Identity ↔ exact company-owned client (+ optional contact). | `UNIQUE(identity_id, company_id, client_id) WHERE revoked_at IS NULL`; composite FK `(company_id, client_id) → clients(company_id, id)` (P1 adds `UNIQUE(id, company_id)` to `clients`); `sub_client_id` nullable FK; `state ∈ active_forward_only, active_full, revoked, merged`; `evidence_kind ∈ created_by_identity, on_file_transacted, staff_confirmed, guest_claim`; `merged_into_membership_id`. |
| `customer_sessions` | Broker sessions (I6). | `session_hash` SHA-256 digest only; `absolute_expires_at`, `idle_expires_at`, `revoked_at`, `revoked_reason`, `network_fingerprint`. |
| `customer_otp_challenges` | Broker-side OTP attempt accounting (I8). | `email_digest` (HMAC, keyed), `attempts`, `max_attempts=5`, `expires_at`, `consumed_at`, `identity_id` nullable until success. Supabase issues/checks the code; OPS counts attempts and refuses before proxying when exhausted. |
| `customer_integrations` | One row per company-website connection (formerly "site grant"). | `company_id`, `public_handle` (opaque), `kind ∈ hosted_pages, server_credential, oauth_client(P6)`, `allowed_origins` (embed/CORS policy only, never authority), `status`. Server credentials reuse the intake design's principal/credential tables when P4 lands; P1 ships `hosted_pages` only. |
| `customer_pairwise_refs` | Pairwise public ref per (identity, integration). | `UNIQUE(identity_id, integration_id)`, `UNIQUE(public_ref)`. |
| `customer_identity_events` | Append-only audit. | Single writer RPC; no UPDATE/DELETE grant to any role. Never stores codes, tokens or session values. |
| `guest_booking_intents` (P2) | Slot hold + contact proof + immutable booking evidence. | `state ∈ held, verified, confirmed, expired, cancelled`; `hold_expires_at`; `verified_channel`; `resolved_client_id`; `resolved_opportunity_id`; `resolved_site_visit_id`. |
| `customer_booking_claims` (P2) | Exactly-once claim of a guest booking by an identity. | `UNIQUE(intent_id)`; claim requires the intent's verified channel to be verified on the claiming identity. Claiming never creates a client. |

`companies.public_handle` (P1): `text UNIQUE`, URL-safe, backfilled from name with numeric disambiguation, editable later in settings. Never the UUID.

Identifier normalization reuses the live discovery functions so lookups are index-backed: `private.agent_normalize_discovery_email(email)` (indexes `clients_agent_discovery_exact_email_idx`, `sub_clients_agent_discovery_exact_email_idx`).

## 5. Flows

### 5.1 Sign-in (hosted, `/c/<public_handle>/signin`)
1. Customer enters email. Broker: rate-check (I8) → create `customer_otp_challenges` row → call dedicated project `auth.signInWithOtp({ email, shouldCreateUser: true })` server-side. Response identical for known/unknown email (I5).
2. Customer enters code. Broker: load challenge, refuse if consumed/expired/attempts ≥ 5 → `verifyOtp` server-side → on failure increment attempts → on success upsert `customer_identities` by `auth_subject`, set `app_metadata.principal='customer'` on first creation, upsert verified contact, **discard the Supabase session** (never persisted, never returned), mint broker session (I6), append events.
3. Membership resolution for this company (§5.3). Redirect into the hosted surface.

### 5.2 Guest booking (P2)
choose slot → enter contact → hold (I8) → verify email by code (same challenge machinery, no identity created) → intent `verified` → confirm: under the opportunity/company lock re-check availability, resolve client (§5.3 with guest rules), create lead via `create_opportunity_guarded` with `source='website'` and integration provenance, create site visit via system booking RPC, intent `confirmed` → confirmation email with a **re-verify-to-manage** link (code on use; never a long-lived capability). Account creation optional; later sign-in with the same verified email claims the booking (`customer_booking_claims`) and inherits its membership.

### 5.3 Company-scoped client resolution
Inputs: verified identifiers only (I1). Within `company_id`, across live `clients` and `sub_clients` (excluding soft-deleted and `merged_into_client_id IS NOT NULL`):
- exactly one client (directly or via one sub-client's parent) → reuse; membership `active_forward_only` with `evidence_kind=on_file_transacted` promotion check (I2) run immediately;
- zero → **depends on the caller (I18, corrected 2026-09-03).** At a genuine intent (booking confirm, lead submission, claim): create the client (person as client; organization name → client + sub-client per intake rule) and a membership `active_full` with `evidence_kind=created_by_identity` — it is their own new record. At sign-in or any read: **create nothing**; resolve to `none`. The live E2E on 2026-09-03 proved the un-split RPC minted a client and a full-access membership in a live company merely because a signed-in customer's browser asked about that company's handle;
- more than one distinct parent client → create a fresh client flagged possible-duplicate (D6), membership `active_full` on the fresh client only, staff notification via `create_notification_if_new_with_identity` (persistent, dedupe key `customer_identity:possible_duplicate:<client_id>`).
Concurrency: `pg_advisory_xact_lock` on `hashtext(company_id || ':' || normalized_email)` before the final lookup, mirroring the intake design.

### 5.4 Staff surfaces (P1 minimal, P3 full)
- Client detail: "Portal access" block listing memberships with state; actions **Confirm access** (→ `active_full`, `staff_confirmed`), **Revoke**. Copy via `ops-copywriter`.
- Possible-duplicate prompt lands in the notification rail; resolution uses the existing client merge, whose completion re-points memberships (trigger in P1 migration).

## 6. Phases

| Phase | Scope | Exit proof |
|-------|-------|-----------|
| **P1 — Identity foundation** | Dedicated auth project; `private` tables + RPCs; broker library (OTP proxy, sessions, resolution); hosted sign-in shell; `companies.public_handle`; legacy share route frozen; staff "Portal access" block. | E2E against prod DB with Maverick test company: sign-in creates identity, membership resolution matrix (0/1/many, forward-only vs full), session revoke takes effect next request, customer token rejected by every staff route, tenant-isolation probes return sentinels. Suite green, tsc clean. |
| **P2 — Availability + guest booking** | Company booking policy; availability RPC (site visits + holds); hosted booking pages; guest intents, holds, claims; system booking RPCs; confirmation email. | Guest books, reschedules, cancels; later sign-in claims booking; hold abuse caps verified; staff calendar shows the visit. |
| **P3 — Portal on new identity + retirement** | Rebuild `/portal` on broker sessions; erasure/tombstones; drop `portal_tokens`/`portal_sessions`; bible chapter 11 rewritten. | Legacy tables gone; portal E2E on the new session. |
| **P4 — Lead submission with typed custom fields** | Merge with the lead-intake worktree design; typed field schema per form; server credential class from intake principals. **Requires Jackson's approval of the custom-fields section before start.** | Intake E2E; fields preserved on ledger; analytics feed unchanged. |
| **P5 — Direct job booking** | Accepted-order evidence model; guarded conversion. | Job created only with evidence; audit trail. |
| **P6 — Third-party OAuth clients** | Authorization-code + PKCE for external origins; 10-min access tokens; rotating refresh; pairwise refs. Only when an integrator needs it. | — |

## 7. Jackson-only gates
- **G1** ~~GO to create the dedicated Supabase project ($10/month).~~ **DONE 2026-09-01 23:21 UTC (Jackson GO):** project `ops-customer-auth`, ref `icjklxkgajefqqbqhqyx`, region `us-west-1`, org `zfkuhfgkgfmaqakokedt`, status ACTIVE_HEALTHY at creation. Remaining configuration (dashboard/Management API, before Task 9): disable Data API exposure (no schemas exposed), Email OTP expiry 600s, email template body carries `{{ .Token }}` with no confirmation link, custom SMTP = SendGrid sender already used by ops-web, disable anonymous sign-ins and all OAuth providers, keep email signups enabled (OTP creates the account), set Site URL to `https://app.opsapp.co`. Secret key goes to Vercel env `OPS_CUSTOMER_AUTH_SECRET_KEY` (server-only) alongside `OPS_CUSTOMER_AUTH_URL=https://icjklxkgajefqqbqhqyx.supabase.co`. Its publishable key is never shipped to a browser.
- **G2** DNS for a dedicated customer host (recommended later, P3: e.g. `book.opsapp.co`); P1/P2 run path-based on `app.opsapp.co` under `/c/`.
- **G3** Approval of the custom-fields section before P4.
- **G4** Pushes/deploys to `main`, as always.

## 8. Contradictions resolved against live state
- `opportunities.client_id` (uuid, nullable) and `client_ref` (FK) both exist; new code writes both, FKs point at `client_ref`.
- `site_visits.client_id`/`project_id`/`company_id` are TEXT; join through `private.try_parse_uuid` / `agent_uuid_from_legacy_text` as the MCP repair did.
- `book_site_visit` family requires a staff actor (I10) → system variants in P2.
- Bible chapter 11 describes the retired magic-link portal; rewritten in P3.
- **CORRECTION 2026-09-02:** the external intake/analytics API **is** production-live — routes `/v1/intake/*` and `/v1/analytics/*` on `origin/main` since a0d18e12 (2026-07-26), docs at `/developers/api` (HTTP 200), 46 `private.external_api_*` / `external_intake_*` / `external_lead_*` / `lead_intake_*` tables present (the 2026-09-01 check queried `public` only). The credential screen exists: Settings → Comms → Website (`WebsiteIntegrationTab`, permission `settings.integrations`, **feature flag `external_api`**). Zero credentials, principals or sources exist in prod as of 2026-09-02, and the docs page never says where a credential is issued. P4 = typed custom fields on top of the live API, not a first landing.

## 9. Verified evidence log (2026-09-01)
Live SQL against `ijeekuhbatykdomumfjx`: portal tables/rows/RLS/grants; `auth.users` 5 rows, 0 active 90d, providers email+google, 4 email-collide with staff; clients dup-email groups 5; opportunities without client 15; RLS audit counts above; `book_site_visit`/`reschedule_site_visit`/`cancel_site_visit_booking` bodies; MCP OAuth tables in `private`; no proposed identity tables exist. Code: `ops-web` portal auth service, helpers, verify/share/validate routes, middleware; MCP OAuth library on origin main `b26c2730`; intake worktree spec + `external-api` tree. Docs: Supabase pricing/compute/rate-limits/OAuth-server/OTP troubleshooting pages fetched today.
