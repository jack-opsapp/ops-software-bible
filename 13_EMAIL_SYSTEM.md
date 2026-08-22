# 13_EMAIL_SYSTEM.md

**OPS Software Bible — Outbound Email: Transport, Templates, Lifecycle Drip, Campaigns, Killswitches & Deliverability**

**Purpose**: Definitive reference for every outbound email OPS sends — the SendGrid transport, the four sender identities, the gated send chokepoint, the React Email template library, the trial-expiry lifecycle, the campaign engine (dispatcher + worker), the pause killswitch, the suppression list, the deliverability anomaly detector, and the `/admin/email` console. Covers what fires automatically, what an operator schedules manually, and what fires not at all.

**Last Updated**: 2026-05-27
**Source Reference**: `ops-web/src/lib/email/`, `ops-web/src/app/api/cron/email/`, `ops-web/src/app/api/cron/trial-expiry/`, `ops-web/src/app/api/webhooks/sendgrid/`, `ops-web/src/lib/api/services/trial-expiry-service.ts`, `ops-web/src/app/admin/email/`, `ops-web/supabase/migrations/053, 065–066, 079–107`

**Out of scope**: Inbound email (Gmail/M365 OAuth, sync, AI classification, drafts) is documented in `04_API_AND_INTEGRATION.md` §20. Tables `email_connections`, `email_threads`, `email_thread_category_corrections`, `email_filter_presets`, `email_ingest_heartbeat_log` belong to that subsystem.

---

## Table of Contents

1. [Source of Truth](#source-of-truth)
2. [Transport — SendGrid](#transport--sendgrid)
3. [Sender Identities](#sender-identities)
4. [Email Kinds Catalog](#email-kinds-catalog)
5. [Data Model](#data-model)
6. [The Send Chokepoint — `gatedSend`](#the-send-chokepoint--gatedsend)
7. [Suppression List](#suppression-list)
8. [Pause Killswitches](#pause-killswitches)
9. [RFC 8058 Unsubscribe Tokens](#rfc-8058-unsubscribe-tokens)
10. [Template Registry & Versioning](#template-registry--versioning)
11. [Campaign Engine — Dispatcher + Worker](#campaign-engine--dispatcher--worker)
12. [Registered Campaigns](#registered-campaigns)
13. [Audience Filter Grammar](#audience-filter-grammar)
14. [Trial-Expiry Lifecycle](#trial-expiry-lifecycle)
15. [Deliverability Anomaly Detector](#deliverability-anomaly-detector)
16. [SendGrid Event Webhook](#sendgrid-event-webhook)
17. [Cron Schedule](#cron-schedule)
18. [Admin Console — `/admin/email`](#admin-console--adminemail)
19. [Environment Variables](#environment-variables)
20. [What Fires on a New Signup](#what-fires-on-a-new-signup)
21. [Operational Runbook](#operational-runbook)
22. [Known Gaps (as of 2026-05-27)](#known-gaps-as-of-2026-05-27)

---

## Source of Truth

**SendGrid is canonical** for every outbound message OPS sends. There is no fallback transport and no second provider. Every send routes through `gatedSend` in `ops-web/src/lib/email/sendgrid.tsx`. Every send writes a row to `email_log`. SendGrid posts engagement events back via webhook (`/api/webhooks/sendgrid`) and they land in `email_events`, which a Postgres trigger fans into `email_suppressions`.

There are three layers above the transport:

1. **Transactional sends** — fire directly from app code (auth, billing, portal, ops alerts). One typed `sendXxx()` per kind, all routed through `gatedSend`.
2. **Lifecycle sends** — fire from a dedicated cron (`/api/cron/trial-expiry`). Schedule is calendar-driven, deduped via `trial_expiry_notifications`. Not modelled as campaigns.
3. **Campaign sends** — operator-scheduled in the `/admin/email` console. Dispatcher cron enqueues `email_jobs`; worker cron drains them. Audience resolved at dispatch time.

Manual operator overrides ("send this thing right now") run via `/api/admin/email/trigger` → Supabase Edge Function. Those edge functions live outside this repo and are not catalogued here.

---

## Transport — SendGrid

**Library**: `@sendgrid/mail` (`ops-web/src/lib/email/sendgrid.tsx:23`).

**Initialization**: Lazy on first call (`ensureInitialized()`, line 67). Requires `SENDGRID_API_KEY`. Throws if unset.

**Rendering**: Every template is a React Email component rendered to HTML at send time via `@react-email/render` (`render(<Component />)`). No pre-rendered templates, no SendGrid Dynamic Templates — full control lives in this repo.

**Compliance**: Every send carries the SMTP headers required by RFC 2369 + RFC 8058:

```
List-Unsubscribe: <https://app.opsapp.co/api/email/unsubscribe?t=…>, <mailto:support@opsapp.co?subject=unsubscribe>
List-Unsubscribe-Post: List-Unsubscribe=One-Click
```

Headers are auto-built by `buildComplianceHeaders()` (`sendgrid.tsx:85`) when the caller omits them, so a typed `sendXxx()` function cannot ship without compliance. The per-recipient unsubscribe URL is a signed HMAC token (see [§9](#rfc-8058-unsubscribe-tokens)).

**Attribution**: When a send belongs to a campaign, `customArgs.campaign_id` is attached to the SendGrid envelope (`sendgrid.tsx:198`) so the inbound webhook can attribute opens/clicks/bounces back to the originating campaign via `email_jobs.sg_message_id`.

---

## Sender Identities

Defined in `ops-web/src/lib/email/senders.ts`. Four buckets, each with a distinct job. DNS (SPF / DKIM / DMARC) must be aligned on `opsapp.co` before flipping any caller to a new bucket.

| Constant | Address | Display Name | Use |
|---|---|---|---|
| `DISPATCH` | `dispatch@opsapp.co` | OPS Dispatch | Product updates, team invites, beta access, trial expiry, ads briefing, role-needed, inbox-connection-down |
| `GATE` | `gate@opsapp.co` | OPS Gate | Password reset, email verification, email-change confirmation — every auth/security flow |
| `FIELD_NOTES` | `field@opsapp.co` | OPS Field Notes | Blog newsletter, Field Notes digest |
| `portalSender(companyName)` | env `SENDGRID_FROM_EMAIL` (fallback `noreply@opsapp.co`) | The contractor's company name | Whitelabel client-portal emails (magic link, estimate ready, invoice ready, questions reminder) — recipient sees the contractor's brand, not OPS |

Bucket assignment per email kind is encoded in `resolveEmailBucket()` (`ops-web/src/lib/email/pause.ts:42`). Default is `dispatch` so any unmapped kind still gets bucket-level pause coverage.

---

## Email Kinds Catalog

Every typed `sendXxx()` call passes an `emailType` string into `gatedSend`. The kind drives:

- Which sender bucket carries the message (`resolveEmailBucket`, `pause.ts:42`)
- Which suppression list the recipient must NOT be on (`KIND_TO_LIST`, `ops-web/src/lib/email/constants.ts:35`)
- The bucket-level pause that can stop it
- The compliance footer's "you're receiving this because…" sentence (`LIST_DISPLAY_NAMES`, `constants.ts:19`)

| Email Kind | Bucket | Suppression List | Template |
|---|---|---|---|
| `password_reset` | gate | global | `PasswordReset.tsx` |
| `email_verification` | gate | global | `EmailVerification.tsx` |
| `email_change_confirmation` | gate | global | `EmailChangeConfirmation.tsx` |
| `team_invite` | dispatch | global | `TeamInvite.tsx` |
| `role_needed` | dispatch | global | `RoleNeeded.tsx` |
| `trial_expiry_warning` | dispatch | global | `TrialExpiryWarning.tsx` |
| `trial_expiry_discount` | dispatch | global | `TrialExpiryDiscount.tsx` |
| `trial_expiry_reengagement` | dispatch | global | `TrialExpiryReengagement.tsx` |
| `beta_access_request` | dispatch | global | `BetaAccessRequest.tsx` |
| `beta_access_decision` | dispatch | global | `BetaAccessDecision.tsx` |
| `ads_briefing` | dispatch | global | `AdsBriefing.tsx` |
| `inbox_connection_down` | dispatch | global | `InboxConnectionDown.tsx` |
| `portal_magic_link` | portal | global | `PortalMagicLink.tsx` |
| `portal_estimate_ready` | portal | global | `PortalEstimateReady.tsx` |
| `portal_invoice_ready` | portal | global | `PortalInvoiceReady.tsx` |
| `portal_questions_reminder` | portal | global | `PortalQuestionsReminder.tsx` |
| `blog_newsletter` | field_notes | blog | `BlogNewsletter.tsx` |
| `field_notes_newsletter` | field_notes | field_notes | `FieldNotesNewsletter.tsx` |
| `product_update` | dispatch | product_updates | `ProductUpdate.tsx` |
| `feature_announcement` | dispatch | product_updates | `FeatureAnnouncement.tsx` |
| `reengagement` | dispatch | reengagement | `Reengagement.tsx` |
| `pmf_threshold_alert` | dispatch | global | (PMF — see `ops-web/CLAUDE.md`) |
| `pmf_daily_digest` | dispatch | global | (PMF) |
| `pmf_weekly_digest` | dispatch | global | (PMF) |
| `transactional_generic` / `generic` | dispatch | global | Back-compat shims (`sendgrid.tsx:1351, 1371`) |

**List semantics**: Auth, billing, portal, and PMF kinds use the **global** list — unsubscribing from one suppresses all email from OPS (the user is asking us to leave them alone). Marketing kinds use a per-channel list so unsubscribing from one channel doesn't kill transactional. Global suppressions always block regardless of the kind's nominal list.

**Two add-on senders** (`sendDataSetupRequest`, `sendPrioritySupportActivated`, `sendgrid.tsx:667, 707`) currently bypass `gatedSend` and call `sgMail.send()` directly. They are internal-ops / customer-confirmation messages tied to Stripe checkout. *Flagged in [Known Gaps](#known-gaps-as-of-2026-05-27).*

---

## Data Model

Fifteen `public.email_*` tables exist in prod. Five belong to the inbound subsystem and are documented in `04_API_AND_INTEGRATION.md` §20. The eleven outbound-relevant tables — ten `email_*` tables plus the related `trial_expiry_notifications` dedup table — are:

### `email_log` *(created via Supabase dashboard pre-migration-system; documented in 083, 088, 094, 098)*

One row per attempted send through `gatedSend`. Schema verified against prod `2026-05-27`:

| Column | Type | Null | Default | Purpose |
|---|---|---|---|---|
| `id` | uuid | NO | `gen_random_uuid()` | PK |
| `user_id` | uuid | yes | — | OPS user who triggered the send. NULL for system-initiated (auth, portal magic link, anonymous newsletter). Nullable since migration 083. |
| `email_type` | text | NO | — | The kind string passed to `gatedSend` (see [§4](#email-kinds-catalog)) |
| `recipient_email` | text | NO | — | Lowercased before insert |
| `subject` | text | yes | — | As sent |
| `sent_at` | timestamptz | yes | `now()` | Send attempt time |
| `status` | text | yes | `'sent'` | One of: `sent`, `failed`, `suppression_skipped`, `paused_skipped` (per migrations 083, 094) |
| `error_message` | text | yes | — | Transport error when status='failed' |
| `metadata` | jsonb | yes | `'{}'` | Per-send context. Always includes `list`. May include `sg_message_id`, `pause_scope`, `pause_reason`, template-specific fields. |
| `campaign_id` | uuid | yes | — | FK → `email_campaigns(id)` ON DELETE SET NULL. NULL for transactional. Added migration 088. |
| `template_version` | text | yes | — | Semver of the rendered template at send time. Added migration 098. |

### `email_events` *(migration 079)*

Persistence for SendGrid Event Webhook. Idempotent on `(sg_message_id, event, timestamp)` partial unique index. Canonical event values: `delivered`, `open`, `click`, `bounce`, `dropped`, `deferred`, `spamreport`, `unsubscribe`, `processed`, `group_unsubscribe`, `group_resubscribe`.

Trigger `trg_email_events_auto_suppress` (migration 081) fans `bounce` (hard only, when `raw.type IN ('bounce','blocked')`), `spamreport`, `unsubscribe`, and `group_unsubscribe` into `email_suppressions`. Severity ordering on conflict: `spam_report > hard_bounce > unsubscribe`.

### `email_suppressions` *(migration 080)*

The do-not-send list. `gatedSend` queries this on every call.

| Column | Type | Notes |
|---|---|---|
| `email` | text | Stored lowercase (caller normalises) |
| `list` | text | `global` blocks all email; per-channel values (`field_notes`, `product_updates`, `reengagement`, `blog`, `beta`) block only that channel |
| `reason` | text CHECK | `hard_bounce` / `soft_bounce` / `spam_report` / `unsubscribe` / `group_unsubscribe` / `manual` / `invalid_address` |
| `source` | text CHECK | `webhook` / `manual` / `backfill` / `import` |
| `source_event_id` | uuid | FK → `email_events(id)` when source=webhook |
| `metadata` | jsonb | sg_message_id + event context |
| `expires_at` | timestamptz | NULL = permanent. Used for soft bounces / operator cooling-off |

Unique on `(lower(email), list)`. Re-suppressing updates the row; earliest `created_at` preserved.

Backfill in migration 082; status documentation in 083; sweep indexes in 097.

### `email_pause_state` *(migration 092)*

Live per-scope pause flags. One row per scope. Read by `getActivePauseScope()` on every send.

```
scope text PK  -- 'global' | 'bucket:dispatch|gate|field_notes|portal' | 'campaign:<uuid>'
is_paused bool
pause_reason text
paused_until timestamptz  -- NULL = indefinite; populated by /api/cron/email/auto-resume
paused_at, paused_by uuid (→ auth.users)
resumed_at, resumed_by uuid
```

CHECK constraint enforces scope shape. Seeded with `global=false` so the chokepoint always has a row to read.

### `email_pause_audit_log` *(migration 093, extended 104)*

Append-only audit log. UPDATE/DELETE revoked from anon/authenticated. Every `pause` / `resume` / `auto_resume` writes a row. Migration 104 added `severity` (`warn` | `critical`, NULL for manual) and `anomaly_log_id` (FK → `email_anomaly_log`) for auto-pauses triggered by [§15](#deliverability-anomaly-detector).

### `email_campaigns` *(migration 086)*

One row per scheduled / dispatched campaign. Status enum `email_campaign_status`: `draft`, `scheduled`, `in_flight`, `completed`, `failed`, `cancelled`, `paused`.

Counters (`sent_count`, `delivered_count`, `bounced_count`, `opened_count`, `clicked_count`, `suppressed_skipped_count`, `failed_count`) are updated atomically via `increment_campaign_counter()` RPC (migration 089, allowlist-validated to prevent SQL injection).

`audience_filter jsonb` holds inline filters; `audience_template_id` (FK added migration 095) references a reusable saved filter. Dispatcher uses the template's filter when set and bumps `last_used_count`.

### `email_jobs` *(migration 087)*

One row per `(campaign, recipient)`. Status enum `email_job_status`: `pending`, `dispatching`, `sent`, `bounced`, `failed`, `cancelled`, `skipped_suppressed`. Worker claims `pending` rows via `claim_email_jobs()` RPC.

Unique constraint `(campaign_id, recipient_email)` — caller lowercases first (migration 091). `template_payload jsonb` holds per-recipient variables resolved by dispatcher. `template_version` added migration 099.

### `email_audience_templates` *(migration 095)*

Saved audience filters. Built in the audience-builder tab, reused across campaigns. Filter grammar documented in [§13](#audience-filter-grammar). `increment_audience_template_usage()` RPC bumps `last_used_count` on each resolve.

### `email_template_versions` *(migration 102)*

Append-only history. UPDATE/DELETE revoked. Build-time script syncs from the `@template-version` comment header in each template TSX file plus a sha256 of the source. Hash collision within an existing version fails the build. Powers the admin Versions timeline and the version-compare analytics.

### `email_anomaly_log` *(migration 105)*

Tamper-evident log of deliverability anomalies detected by `/api/cron/email/anomaly-check`. Kinds: `bounce_spike`, `spam_spike`, `delivery_drop`, `volume_drop`. Severity: `warn`, `critical`. For criticals that triggered an auto-pause, `pause_audit_id` links back to `email_pause_audit_log`. See [§15](#deliverability-anomaly-detector).

Notification projection is event-scoped, not presentation-state-scoped. `public.create_email_anomaly_notification_if_new(...)` derives `dedupe_key = email-anomaly:<anomaly UUID>` and returns `{notification_id, created}`; the partial unique index on `(type, dedupe_key)` prevents a second rail entry after read, resolution, retry, or operator rotation. `public.reconcile_email_pause_notification_fanout(...)` performs the corresponding durable fanout for an active automatic pause. Both RPCs are `SECURITY DEFINER`, service-role-only contracts.

### `trial_expiry_notifications` *(migration 053)*

Dedup table for the trial-expiry cron. Unique on `(company_id, notification_type)` where notification_type ∈ {`warning_7d`, `warning_5d`, `discount_3d`, `warning_1d`, `reengagement_7d`, `reengagement_30d`}. Each row records the promo codes attached to the send (`promo_code_50`, `promo_code_30`). See [§14](#trial-expiry-lifecycle).

### `companies` — `initialize_company_trial` trigger *(migrations 065, 066)*

Not an email table, but the trigger that makes trial-expiry email possible. Fires `BEFORE INSERT ON companies`. If `trial_end_date IS NULL`, stamps:

- `subscription_status := COALESCE(NEW.subscription_status, 'trial')`
- `subscription_plan := COALESCE(NEW.subscription_plan, 'trial')`
- `trial_start_date := COALESCE(NEW.trial_start_date, NOW())`
- `trial_end_date := NOW() + INTERVAL '30 days'`

Migration 066 widened from "both NULL" to "trial_end_date NULL" so a partial insert that sets only `subscription_status='trial'` still gets an expiry — without it, `lib/subscription.ts` treated undefined `daysRemaining` as an unlimited trial. Cross-ref `12_SUBSCRIPTION_MANAGEMENT.md` § Lifecycle.

---

## The Send Chokepoint — `gatedSend`

`ops-web/src/lib/email/sendgrid.tsx:122` — every send funnels through this function. Order of operations:

1. **Ensure SendGrid initialized** (lazy, once per process).
2. **Lowercase recipient**; reject empty.
3. **Resolve list** from `KIND_TO_LIST[emailType]`, defaulting to `global`.
4. **Pause check** (`getActivePauseScope`, [§8](#pause-killswitches)) — resolution order `global → bucket → campaign`. If matched: write `email_log` with `status='paused_skipped'`, return `{status:'paused_skipped', scope}`. Never throws — pause read failures fail-open per design tradeoff (`pause.ts:128`).
5. **Suppression check** (`isSuppressed`, [§7](#suppression-list)) — checks `global` + the resolved list. If matched: write `email_log` with `status='suppression_skipped'`, return `{status:'suppression_skipped'}`. Read failures fail-closed.
6. **Build compliance headers** (`buildComplianceHeaders`) when caller omits them — RFC 2369 + 8058.
7. **Build `customArgs`** — `campaign_id` (if any), `user_id` (if any), `email_type` — for webhook attribution.
8. **Call `sgMail.send()`** — throws on transport error, propagates to caller.
9. **Extract `x-message-id`** response header for `email_jobs.sg_message_id` linkage.
10. **Write `email_log`** with `status='sent'`, `sg_message_id` in metadata.

Pause takes precedence over suppression because pauses are reversible and we want them to short-circuit any further state mutation. Suppressions are permanent, so we want the log row to record the suppression anyway.

`gatedSend` **never throws on suppression or pause** (silent skip); it **does throw on transport error** so callers can retry or surface to the user.

---

## Suppression List

API surface: `ops-web/src/lib/email/suppressions.ts`.

| Function | Purpose |
|---|---|
| `isSuppressed(email, list?)` | Single-recipient check. Fails closed on DB error — if we can't verify, do not send. |
| `filterSuppressed(emails[], list?)` | Bulk variant for campaign dispatch. Returns `Set<string>` of suppressed addresses. Fails closed (returns all as suppressed). |
| `addSuppression({...})` | Manual suppression. Idempotent via `(lower(email), list)` unique. |
| `removeSuppression(email, list)` | Hard delete. |
| `listSuppressions({...})` | Admin pagination. |

**Auto-suppress chain**: SendGrid webhook → `email_events` insert → `trg_email_events_auto_suppress` trigger (migration 081) → `email_suppressions` upsert. Only terminal events suppress: hard bounce (`raw.type IN ('bounce','blocked')` only — soft bounces do NOT auto-suppress), spam report, unsubscribe, group_unsubscribe. Group unsubscribes capture `raw.asm_group_id` as the list slug.

Auto-suppress reasons map: `bounce` → `hard_bounce`, `spamreport` → `spam_report`, `unsubscribe` → `unsubscribe`, `group_unsubscribe` → `group_unsubscribe`. The trigger's `ON CONFLICT` clause preserves the most severe reason (`spam_report > hard_bounce > unsubscribe`).

---

## Pause Killswitches

API surface: `ops-web/src/lib/email/pause.ts`.

**Three scope shapes**, resolved in order:

| Scope | Example | Effect |
|---|---|---|
| `global` | `global` | Hard stop. Every send paused. |
| `bucket:<name>` | `bucket:dispatch` | All sends through one sender bucket paused (`dispatch`, `gate`, `field_notes`, `portal`) |
| `campaign:<uuid>` | `campaign:7f2d…` | One campaign paused. Worker re-pends matching jobs each tick. |

**Pause** (`pause({scope, reason, pausedUntil?, actorUserId, actorEmail, severity?, anomalyLogId?})`):

1. Require `reason.length >= 3`.
2. Upsert `email_pause_state` row.
3. Insert `email_pause_audit_log` row (severity + anomaly_log_id for auto-pauses).
4. **Fan out persistent rail notifications** to every admin via `notifications` table (type=`email_pause`, action_url=`/admin/email?tab=killswitches`).
5. Return `{state, pauseAuditId}` so callers (anomaly cron) can write the audit id back onto `email_anomaly_log.pause_audit_id`.

Audit insert failures do NOT roll back the pause — the killswitch must activate even if the legal record fails.

**Resume** (`resume({scope, reason?, actorUserId, actorEmail})`):

1. Set `is_paused=false`, stamp `resumed_at/by`.
2. Insert `audit_log` row with `action='resume'`.
3. Mark all persistent pause notifications for the scope `is_read=true`.

**Auto-resume** (`autoResume(scope)`): Called by `/api/cron/email/auto-resume` every 5 min for any pause row where `paused_until < now()`. Writes `action='auto_resume'` audit row, reason=`'paused_until elapsed'`, no actor.

**Fail-open reads, fail-closed writes**: `getActivePauseScope` swallows DB errors and returns null (no pause), because blocking every send during a Supabase outage is worse than briefly missing a pause. Writes throw so the admin route surfaces the failure.

---

## RFC 8058 Unsubscribe Tokens

Implementation: `ops-web/src/lib/email/unsubscribe-token.ts`.

**Format**: `base64url(email|list|expiresAt).base64url(HMAC-SHA256(email|list|expiresAt))`.

**Secret**: `EMAIL_UNSUBSCRIBE_SECRET` (must be ≥32 chars; generate via `openssl rand -hex 32`). Rotating the secret instantly invalidates every outstanding token.

**TTL**: 365 days default.

**Verification**: `verifyUnsubscribeToken(token)` returns `{ok:true, email, list, expiresAt}` or `{ok:false, reason: 'malformed'|'bad_signature'|'expired'}`. Uses `timingSafeEqual` to prevent timing attacks.

**URL**: `${NEXT_PUBLIC_APP_URL}/api/email/unsubscribe?t=<token>` (built by `buildUnsubscribeUrl`).

Per-recipient token is embedded in both the `List-Unsubscribe` SMTP header AND the in-body footer link rendered by `ComplianceFooter` in every template.

---

## Template Registry & Versioning

Two registries serve different consumers:

### `template-registry.ts` — admin preview

Static array of 17 entries used by the `/admin/email/templates/[templateId]` preview pages. Each entry exposes:

- `templateId` — slug
- `displayName` — UI label
- `defaultSubject` — fallback when caller omits subject
- `Component` — the React Email TSX
- `previewProps` — sample data for the preview
- `sourcePath` — relative file path for "view source"

`renderTemplate(templateId, props)` renders to `{html, text}` via `@react-email/render` (text via `{plainText: true}`).

### `campaign-templates.ts` — runtime dispatch

In-memory `Record<templateId, CampaignTemplateMeta>`. Bootstrap is idempotent (`bootstrapCampaignTemplates()` in `campaign-templates-bootstrap.ts`) and is called from every worker tick because cron processes start cold.

Each entry has `{id, label, description, sender}` where `sender(ctx)` is an async function the worker calls with `{recipientEmail, recipientUserId, payload, campaignId}` and which returns the underlying `gatedSend` result.

### Templates on disk

Twenty-five React Email TSX files in `ops-web/src/lib/email/react/templates/`:

| File | Bucket / kind | Used by |
|---|---|---|
| `PasswordReset.tsx` | gate / `password_reset` | `sendPasswordReset` |
| `EmailVerification.tsx` | gate / `email_verification` | `sendEmailVerification` |
| `EmailChangeConfirmation.tsx` | gate / `email_change_confirmation` | `sendEmailChangeConfirmation` |
| `TeamInvite.tsx` | dispatch / `team_invite` | `sendTeamInvite` |
| `RoleNeeded.tsx` | dispatch / `role_needed` | `sendRoleNeeded` |
| `BetaAccessRequest.tsx` | dispatch / `beta_access_request` | `sendBetaAccessRequest` |
| `BetaAccessDecision.tsx` | dispatch / `beta_access_decision` | `sendBetaAccessDecision` |
| `TrialExpiryWarning.tsx` | dispatch / `trial_expiry_warning` | `sendTrialExpiryWarning`, campaign `trial_expiry_campaign` |
| `TrialExpiryDiscount.tsx` | dispatch / `trial_expiry_discount` | `sendTrialExpiryDiscount` |
| `TrialExpiryReengagement.tsx` | dispatch / `trial_expiry_reengagement` | `sendTrialExpiryReengagement` |
| `ProductUpdate.tsx` | dispatch / `product_update` | campaign `product_update` |
| `FeatureAnnouncement.tsx` | dispatch / `feature_announcement` | campaign `feature_announcement` |
| `Reengagement.tsx` | dispatch / `reengagement` | campaign `reengagement` |
| `InboxConnectionDown.tsx` | dispatch / `inbox_connection_down` | `sendInboxConnectionDown` |
| `AdsBriefing.tsx` | dispatch / `ads_briefing` | `sendAdsBriefing` |
| `DataSetupRequest.tsx` | dispatch / direct send | `sendDataSetupRequest` (bypasses `gatedSend`) |
| `PrioritySupportActivated.tsx` | dispatch / direct send | `sendPrioritySupportActivated` (bypasses `gatedSend`) |
| `BlogNewsletter.tsx` | field_notes / `blog_newsletter` | `sendBlogNewsletter` |
| `FieldNotesNewsletter.tsx` | field_notes / `field_notes_newsletter` | `sendFieldNotesNewsletter` |
| `PortalMagicLink.tsx` | portal / `portal_magic_link` | `sendMagicLink` |
| `PortalEstimateReady.tsx` | portal / `portal_estimate_ready` | `sendEstimateReady` |
| `PortalInvoiceReady.tsx` | portal / `portal_invoice_ready` | `sendInvoiceReady` |
| `PortalQuestionsReminder.tsx` | portal / `portal_questions_reminder` | `sendQuestionsReminder` |
| `PmfThresholdAlert.tsx` | dispatch / `pmf_threshold_alert` | PMF — see `ops-web/CLAUDE.md` § PMF |
| `PmfDailyDigest.tsx` | dispatch / `pmf_daily_digest` | PMF |
| `PmfWeeklyDigest.tsx` | dispatch / `pmf_weekly_digest` | PMF |

Note: `template-registry.ts` lists 17 entries (omits the PMF templates, the two direct-send Stripe confirmations, the trial-expiry warning is listed once even though it's used by both a typed sender and a campaign). The admin preview is therefore a strict subset of the actual template surface.

### Versioning (PR 6+)

Every template TSX file carries a `@template-version` semver comment header. A build-time script computes `sha256(source)` and upserts into `email_template_versions`. Hash mismatch for an existing version fails the build, so old versions cannot be silently mutated. `email_log.template_version` and `email_jobs.template_version` are stamped at send time (migrations 098, 099) so version-compare analytics can attribute open / click rate deltas to template changes.

---

## Campaign Engine — Dispatcher + Worker

Two crons, ten minutes apart each, working off Postgres tables. No queue service — Postgres + `FOR UPDATE SKIP LOCKED` is the queue.

### Dispatcher — `/api/cron/email/dispatcher` *(every 10 min during business hours)*

`ops-web/src/app/api/cron/email/dispatcher/route.ts`. Schedule: `*/10 13-23,0-4 * * *` UTC (= business hours + evening PT).

Auth: `Bearer ${CRON_SECRET}`. Service-role DB.

1. Read up to **5 campaigns** (`READY_BATCH`) where `send_status='scheduled'` AND `scheduled_for <= now()`, oldest first.
2. For each: resolve the filter (template if `audience_template_id` set, else inline `audience_filter`). Bump `increment_audience_template_usage` if a template was used.
3. Call `resolveAudience(filter, db)` ([§13](#audience-filter-grammar)) to get `[{email, userId}]`.
4. Call `enqueueCampaignJobs({campaignId, recipients})`:
   - `filterSuppressed(emails, 'global')` — global-only at enqueue; per-list checks happen at send time.
   - Upsert `email_jobs` rows with `status='pending'`. `onConflict: 'campaign_id,recipient_email', ignoreDuplicates: true` makes retries idempotent.
   - Transition `email_campaigns.send_status` to `in_flight` (jobs enqueued) or `completed` (zero recipients after suppression).
5. Failure → set campaign to `send_status='failed'` so it stops being retried. No notification on dispatcher failure — *flagged in [Known Gaps](#known-gaps-as-of-2026-05-27).*

### Worker — `/api/cron/email/worker` *(every 10 min during business hours)*

`ops-web/src/app/api/cron/email/worker/route.ts`. Schedule: `*/10 13-23,0-4 * * *` UTC.

1. `bootstrapCampaignTemplates()` — register the 4 campaign templates (idempotent).
2. Call **`claim_email_jobs(p_limit:=200)`** RPC (`migration 090`). Atomic `FOR UPDATE SKIP LOCKED` claim that transitions `pending → dispatching`, restricted to campaigns currently in `in_flight`. Parallel workers cannot double-dispatch.
3. Look up campaign metadata once per batch (template_id, send_status, name, created_by_user_id).
4. **Resolve campaign-scope killswitch** once per campaign in the batch (`getPauseState('campaign:<uuid>')`).
5. For each claimed job:
   - If campaign missing / cancelled / paused (status or killswitch): re-pend or finalise as cancelled. Killswitch-paused jobs **stay pending**; pauses are reversible.
   - If template unknown: mark `failed`, increment `failed_count`.
   - Otherwise: call `tpl.sender(ctx)` (which calls `gatedSend` internally).
     - `suppression_skipped` → `email_jobs.status='skipped_suppressed'`, increment `suppressed_skipped_count`.
     - `paused_skipped` (e.g. global flipped on between batches) → re-pend, no counter change.
     - `sent` → `status='sent'`, stamp `sent_at`, `sg_message_id`, increment `sent_count`.
   - Throw → increment `retry_count`; if `>= MAX_RETRIES=3`, status='failed', increment `failed_count`; else re-pend.
6. `INTER_SEND_DELAY_MS=10` between sends (paces a 200-job batch).
7. After processing, call `completeCampaignIfDone(cid)` per touched campaign — if no jobs remain `pending`/`dispatching`, set `send_status='completed'` and insert a `campaign_done` notification for `created_by_user_id`.

**Counter invariant**: bounce/open/click counts are NOT updated by the worker — they come from the SendGrid webhook ([§16](#sendgrid-event-webhook)). Worker only writes `sent_count`, `suppressed_skipped_count`, `failed_count`.

### Campaign service — `ops-web/src/lib/email/campaigns.ts`

| Function | Purpose |
|---|---|
| `createCampaign({...})` | Draft. Status = `draft`. |
| `scheduleCampaign(id, when)` | Sets `scheduled_for`, transitions to `scheduled`. |
| `cancelCampaign(id)` | Sets `cancelled`. Cascades to pending jobs. |
| `pauseCampaign(id, reason)` | Sets `paused`. Worker stops dispatching. |
| `resumeCampaign(id)` | Reverts `paused → in_flight`. |
| `enqueueCampaignJobs({...})` | Used by dispatcher. Upserts `email_jobs`. |
| `completeCampaignIfDone(id)` | Used by worker. Transitions to `completed` when no pending/dispatching jobs remain. |
| `getCampaignStats(id)` | Hydrates a row. |
| `listCampaigns({status?, limit?, offset?, includeVersions?})` | Admin list. Optionally returns distinct `template_version` values per campaign. |

---

## Registered Campaigns

Bootstrapped at every worker tick (`campaign-templates-bootstrap.ts`). All four use sender `DISPATCH` and target `firstName`-personalised content with a `ctaUrl`. None are auto-triggered — an operator creates a row in `email_campaigns` via `/admin/email` and sets `scheduled_for`.

| Template id | Label | Default audience pattern | Sender function |
|---|---|---|---|
| `product_update` | Product update | Active + trial users | `sendProductUpdate` — `intro`, `items[{title,body}]`, `closing`, `ctaUrl` |
| `trial_expiry_campaign` | Trial expiry warning | Trial users only | `sendTrialExpiryWarning` — `companyName`, `daysRemaining`, `trialEndDisplay`, `subscribeUrl` |
| `feature_announcement` | Feature announcement | Active + trial users | `sendFeatureAnnouncement` — `featureName`, `headline`, `whatItDoes`, `whyItMatters`, `howToFindIt?`, `ctaUrl` |
| `reengagement` | Reengagement | All active users | `sendReengagement` — `headline`, `opener`, `body`, `closing`, `daysSinceActive?`, `ctaUrl` |

The `trial_expiry_campaign` registry entry is **not** what fires the automatic trial countdown — that's the trial-expiry cron ([§14](#trial-expiry-lifecycle)) calling `sendTrialExpiryWarning` directly. The campaign-engine entry exists so an operator can blast a trial-urgency message to an arbitrary trial cohort outside the calendar schedule.

---

## Audience Filter Grammar

Two resolution paths:

### Starter segments

`{segment: 'all_users' | 'trial_users' | 'active_subscribers'}`

Hard-coded resolvers in `ops-web/src/lib/email/audiences.ts`:

- `all_users`: `users` where `is_active=true` AND `removed_from_email_list IS NULL OR false` AND `email IS NOT NULL`.
- `trial_users`: above + INNER JOIN `companies` where `subscription_status='trial'`.
- `active_subscribers`: above + JOIN `companies` where `subscription_status IN ('active','grace')`.

### Full predicate

Anything else falls to `email_audience_filter()` RPC (migration 096). JSONB tree:

```
{ and: [<node>...] }
{ or:  [<node>...] }
{ group: <node> }
{ field: text, op: text, value: any }   -- leaf
```

**Allowlisted fields** (SECURITY DEFINER + field allowlist prevents SQL injection):

`email`, `role`, `user_type`, `is_company_admin`, `is_active`, `removed_from_email_list`, `company_id`, `created_at`, `plan` (=`companies.subscription_plan`), `subscription_status` (=`companies.subscription_status`), `trial_end_date` (=`companies.trial_end_date`).

**Allowlisted ops**: `eq`, `neq`, `in`, `not_in`, `lt`, `gt`, `lte`, `gte`, `gte_days` (relative to `now()`), `lte_days`, `is_null`, `is_not_null`, `like` (ILIKE).

Both paths always exclude inactive users, unsubscribed users, and rows with NULL email. The RPC also has a parallel `email_audience_count(p_filter)` so the admin UI can show an audience size estimate without fetching rows.

Saved filters live in `email_audience_templates` ([§5](#data-model)).

---

## Trial-Expiry Lifecycle

**Cron**: `/api/cron/trial-expiry` (`ops-web/src/app/api/cron/trial-expiry/route.ts`). Schedule: `0 14 * * *` UTC (7am PT). Auth: `Bearer ${CRON_SECRET}`. `maxDuration = 300s`.

Calls `TrialExpiryService.processAll(supabase)` (`ops-web/src/lib/api/services/trial-expiry-service.ts`).

### Schedule

| Day offset | Notification type | Email | Push | In-app |
|---|---|---|---|---|
| trial − 7d | `warning_7d` | ✅ | — | — |
| trial − 5d | `warning_5d` | ✅ | — | — |
| trial − 3d | `discount_3d` | ✅ (`TrialExpiryDiscount`) | ✅ OneSignal | ✅ persistent rail |
| trial − 1d | `warning_1d` | ✅ | — | — |
| trial + 7d | `reengagement_7d` | ✅ (`TrialExpiryReengagement`) | — | ✅ rail |
| trial + 30d | `reengagement_30d` | ✅ (`TrialExpiryReengagement`) | — | ✅ rail |

Day math: `daysRemaining = Math.ceil((trialEnd - now) / day)` (rounds up so "2 days left" still means user has today + tomorrow). `daysSince = Math.floor((now - trialEnd) / day)`.

### Per-company flow

1. Query `companies WHERE subscription_status='trial' AND trial_end_date IS NOT NULL AND deleted_at IS NULL`.
2. Compute `determineNotificationType(trialEnd, now)` — returns one of the 6 types or `null`.
3. **Dedup** via `trial_expiry_notifications` SELECT — already sent → skip silently.
4. Fetch `admin_ids` → resolve to `users` rows → keep those with non-null email and `deleted_at IS NULL`.
5. Resolve company timezone from `(latitude, longitude)` and format `trialEndDisplay`.
6. Look up promo codes for the type:
   - `discount_3d`: `STRIPE_PROMO_PREEXPIRY_50`, `STRIPE_PROMO_PREEXPIRY_30`
   - `reengagement_7d`: `STRIPE_PROMO_POSTEXPIRY_7D_50`, `STRIPE_PROMO_POSTEXPIRY_7D_30`
   - `reengagement_30d`: `STRIPE_PROMO_POSTEXPIRY_30D_50`, `STRIPE_PROMO_POSTEXPIRY_30D_30`
7. **Send email per admin** via the appropriate typed sender (`sendTrialExpiryWarning` / `Discount` / `Reengagement`). One bad admin doesn't block the rest.
8. **Send push** only for `discount_3d` (post-expiry users are assumed disengaged or uninstalled). OneSignal payload includes `promo_code` so the iOS deep link can pre-apply it.
9. **Insert in-app notifications** for discount types (`discount_3d`, `reengagement_7d`, `reengagement_30d`) with `type='trial_expiry'`, `batch_id=promoCode50`, `action_url=/settings?tab=subscription`.
10. **INSERT into `trial_expiry_notifications`** to dedup future runs. Unique-violation (23505) is silently absorbed.

Promo URL: `${NEXT_PUBLIC_APP_URL}/settings?tab=subscription` (via `getAppUrl()`).

### Idempotency

The unique `(company_id, notification_type)` constraint on `trial_expiry_notifications` is the deduplication source of truth. Rerunning the cron the same day is safe.

---

## Deliverability Anomaly Detector

**Cron**: `/api/cron/email/anomaly-check` (`ops-web/src/app/api/cron/email/anomaly-check/route.ts`). Schedule: `3-59/5 13-23,0-4 * * *` UTC.

Pure threshold evaluator in `ops-web/src/lib/email/anomaly-thresholds.ts`:

| Kind | Warn | Critical | Min sends |
|---|---|---|---|
| `bounce_spike` | bounce% ≥ 5 | ≥ 10 | 5 |
| `spam_spike` | spam% ≥ 0.1 | ≥ 0.5 | 5 delivered |
| `delivery_drop` | delivered/sent < 80% | < 60% | 5 sent |
| `volume_drop` | sent/baseline < 10% | < 1% | uses baseline |

Snapshot inputs from `email_event_metrics(p_minutes_back)` RPC (migration 106):

- Live: 15-min window.
- Baseline: 60-min window for volume_drop ratio.

### Flow

1. Fetch both windows.
2. `evaluateThresholds(snapshot)` returns the full breach list.
3. **Dedup** against `email_anomaly_log` rows within the last 60 minutes — skip if same kind at equal-or-higher severity was already logged.
4. Insert `email_anomaly_log` row for each breach.
5. **Auto-pause** ONLY for `critical` + `kind ∈ {bounce_spike, spam_spike}` — calls `pause({scope:'global', severity:'critical', anomalyLogId, ...})`. Requires `PMF_OPERATOR_USER_ID` and `PMF_NOTIFICATION_EMAIL` env vars (actor of record). If unset, pause is skipped and `action_taken` records why.
6. Call service-only `create_email_anomaly_notification_if_new` for the operator rail notification (`type=email_anomaly`). It is persistent for critical breaches, dismissible for warnings, routes to `/admin/email?tab=event-monitor`, and is idempotent by immutable anomaly identity.
7. Reconcile any automatic-pause notification fanout, then update the anomaly row with `action_taken`, `notification_id`, and `pause_audit_id`.

`delivery_drop` and `volume_drop` are alert-only — they don't auto-pause. Operator decides.

**Production contract repair (2026-08-22 UTC).** Production had advanced past historical migration `20260813172000_email_anomaly_notification_identity.sql`, so PostgREST returned `PGRST202` for the missing notification RPC. Ledger `20260822041423_email_anomaly_notification_identity_forward_repair_20260813172000` replayed both RPCs, both exact uniqueness contracts, service-only ACLs, postflight catalog validation, and a schema-cache reload. The next scheduled run returned HTTP 200 at `04:18:25Z`; the durable workload row completed at `04:18:42.952369Z`, released its lease, reset consecutive failures to zero, and left the circuit closed. OPS-Web commit `4770573e18c237bd7e69145d59a1c8cc3991e7b7` records the repair and is live in READY deployment `dpl_8niQ5dLMgRSjNHcdYgwSCrWwXcHb` at `app.opsapp.co` with no alias error. The byte-exact forward migration is archived in `migrations/`.

---

## SendGrid Event Webhook

**Endpoint**: `POST /api/webhooks/sendgrid?secret=<SENDGRID_WEBHOOK_SECRET>` (`ops-web/src/app/api/webhooks/sendgrid/route.ts`).

**Defense in depth**:

- Rate limit: 600 req/min/IP via Vercel KV (`rateLimit` in `ops-web/src/lib/utils/ratelimit.ts`).
- Shared secret query param — leaked credential alone cannot DoS.
- Batch size cap: 1000 events/request (matches SendGrid default).

**Flow**:

1. Validate IP rate, secret, JSON body shape, event count.
2. Filter to `VALID_EVENTS` allowlist.
3. Upsert into `email_events` on the partial unique index `(sg_message_id, event, timestamp) WHERE sg_message_id IS NOT NULL`. Replays absorbed.
4. `trg_email_events_auto_suppress` trigger (migration 081) fans terminal events into `email_suppressions` automatically.
5. Engagement counters on `email_campaigns` (`delivered_count`, `bounced_count`, `opened_count`, `clicked_count`) are updated by the webhook handler from the joined `email_jobs.sg_message_id`.

Aggregate engagement queries are served by `campaign_engagement_stats(uuid)` and `campaign_funnel_stages(uuid)` RPCs (migration 100) and `email_event_metrics(p_minutes_back, p_bucket?)` + `email_top_bounce_domains(p_minutes_back, p_limit)` (migration 106). All service-role only.

---

## Cron Schedule

Email-related entries from `ops-web/vercel.json`. All UTC. Auth: `Bearer ${CRON_SECRET}`. The `13-23,0-4` time window = business hours + evening PT — most marketing/lifecycle crons are gated to it so we never ship at 3am.

| Path | Schedule | Purpose |
|---|---|---|
| `/api/cron/email/dispatcher` | `*/10 13-23,0-4 * * *` | Pulls scheduled campaigns, enqueues `email_jobs` |
| `/api/cron/email/worker` | `*/10 13-23,0-4 * * *` | Claims `pending` jobs, calls `gatedSend`, updates counters |
| `/api/cron/email/auto-resume` | `*/5 13-23,0-4 * * *` | Resumes pause rows where `paused_until < now()` |
| `/api/cron/email/anomaly-check` | `3-59/5 13-23,0-4 * * *` | Bounce/spam/delivery/volume thresholds, auto-pause on critical |
| `/api/cron/trial-expiry` | `0 14 * * *` | Daily 7am PT trial countdown (7/5/3/1 pre, 7/30 post) |
| `/api/cron/payment-reminders` | `0 10 * * *` | (See `09_FINANCIAL_SYSTEM.md`) |
| `/api/cron/financial-digest` | `0 7 * * 1` | Weekly Monday financial summary |
| `/api/cron/appointment-reminders` | `0 * * * *` | Hourly schedule reminders |
| `/api/cron/project-status-updates` | `0 9 * * 1` | Weekly Monday project status digest |
| `/api/cron/ads-briefing` | `0 12 * * 1` | Weekly Monday Google Ads briefing (`sendAdsBriefing`) |

Inbound-email crons (`/api/cron/email-sync`, `/api/cron/email-ingest-heartbeat`, `/api/cron/auto-send`, `/api/cron/webhook-renewal`) belong to `04_API_AND_INTEGRATION.md` §20.

PMF crons (`/api/cron/pmf/*`) are documented in `ops-web/CLAUDE.md` § PMF Dashboard and consume `sendTransactionalEmail`.

---

## Admin Console — `/admin/email`

Page: `ops-web/src/app/admin/email/page.tsx`. Components in `ops-web/src/app/admin/email/_components/`. Admin-gated via `verifyAdminAuth` + `isAdminEmail`.

### Tabs (component → purpose)

| Tab | Component(s) | Purpose |
|---|---|---|
| Overview | `overview-tab.tsx`, `active-pause-banner.tsx` | At-a-glance: live pause banner, recent campaigns, queue depth |
| Schedule | `schedule-tab.tsx`, `scheduled-sends-tab.tsx`, `campaign-create-modal.tsx`, `campaign-detail-modal.tsx`, `campaign-progress-bar.tsx`, `campaign-status-pill.tsx` | Create & schedule campaigns, view in-flight progress |
| Audience builder | `audience-builder-tab.tsx`, `audience-filter-row.tsx`, `audience-save-template-modal.tsx`, `audience-filter-config.ts` | Build JSONB filter trees, save as template |
| Triggers | `triggers-tab.tsx`, `trigger-sheet.tsx` | One-off invocations of Supabase Edge Functions (`lifecycle-emails`, `bubble-reauth-emails`, `unverified-emails`, `newsletter-emails`, `verify-email-domains`) via `/api/admin/email/trigger` |
| Killswitches | `killswitches-tab.tsx`, `pause-confirmation-modal.tsx` | Global / per-bucket / per-campaign pause + resume |
| Suppressions | `suppressions-tab.tsx`, `suppression-detail-drawer.tsx`, `suppression-bulk-add-modal.tsx`, `suppression-import-modal.tsx` | Browse, add (manual / bulk / CSV), remove |
| Event monitor | `event-monitor-tab.tsx`, `event-stream.tsx`, `monitor-metric-bar.tsx`, `monitor-filters.tsx`, `bounce-gauge.tsx`, `top-bounce-domains.tsx`, `anomaly-history.tsx` | Live deliverability dashboard backed by `email_event_metrics` |
| Funnels | `funnels-tab.tsx` | Sankey per-campaign via `campaign_funnel_stages` |
| Email log | `email-log-tab.tsx` | Per-send audit trail (paginated `email_log`) |
| Templates | `templates-tab.tsx`, sub-route `/admin/email/templates/[templateId]/page.tsx` | Preview every template with `previewProps`, see versions |
| Newsletter | `newsletter-tab.tsx` | Blog / Field Notes one-off composer |
| Lifecycle config | `lifecycle-config-panel.tsx` | Operator-tunable lifecycle parameters |

### API routes

`ops-web/src/app/api/admin/email/`:

- `campaigns/` — list, create, detail, cancel
- `campaigns/audience-estimate` — POST a filter, get count via `email_audience_count`
- `audience/` — audience template CRUD
- `pause`, `resume`, `pauses/` — killswitch control + listing
- `suppressions/` — list, add, remove, bulk
- `templates/[templateId]/`, `templates/[templateId]/send-test`, `templates/[templateId]/versions/compare` — preview, test send, version diff
- `monitor/` — event-metrics aggregate
- `cron/` — admin-triggered cron runs (for testing)
- `lifecycle-config/` — operator-tunable parameters
- `schedule/`, `newsletter/`, `last-email/` — composer + recent send introspection
- `trigger/` — invokes Supabase Edge Functions (`ALLOWED_SLUGS`: `lifecycle-emails`, `bubble-reauth-emails`, `unverified-emails`, `newsletter-emails`, `verify-email-domains`)

---

## Environment Variables

| Name | Required | Purpose |
|---|---|---|
| `SENDGRID_API_KEY` | yes | Transport. Initialised lazily; absence throws on first send. |
| `SENDGRID_FROM_EMAIL` | recommended | Fallback for `portalSender` and back-compat shims. Defaults to `noreply@opsapp.co`. |
| `SENDGRID_WEBHOOK_SECRET` | yes | Validates `?secret=` on POSTs to `/api/webhooks/sendgrid` |
| `EMAIL_UNSUBSCRIBE_SECRET` | yes | HMAC-SHA256 key for List-Unsubscribe tokens. ≥32 chars hex. Rotating invalidates every outstanding token. |
| `CRON_SECRET` | yes | `Bearer` auth on every cron route |
| `NEXT_PUBLIC_APP_URL` | yes | Builds unsubscribe URLs + portal URLs + subscription deep links |
| `STRIPE_PROMO_PREEXPIRY_50` / `_30` | yes (trial-expiry) | Stripe promo code IDs for `discount_3d` |
| `STRIPE_PROMO_POSTEXPIRY_7D_50` / `_30` | yes (trial-expiry) | Stripe codes for `reengagement_7d` |
| `STRIPE_PROMO_POSTEXPIRY_30D_50` / `_30` | yes (trial-expiry) | Stripe codes for `reengagement_30d` |
| `PMF_OPERATOR_USER_ID` | yes (anomaly auto-pause) | Actor of record on auto-pauses + recipient of anomaly rail notification |
| `PMF_OPERATOR_COMPANY_ID` | yes (anomaly auto-pause) | `notifications.company_id` NOT NULL satisfies |
| `PMF_NOTIFICATION_EMAIL` | yes (anomaly auto-pause) | Actor email recorded on `email_pause_audit_log` |

PMF telemetry vars (`TWILIO_*`) belong to the PMF subsystem; see `ops-web/CLAUDE.md` § PMF.

---

## What Fires on a New Signup

A new trades business signs up at `/register`. Firebase Auth creates the credential (`signUpWithEmail` in `ops-web/src/lib/firebase/auth.ts:185` — three lines, no backend call). Frontend syncs the user + company rows into Supabase. The `initialize_company_trial` trigger ([§5](#data-model)) stamps `subscription_status='trial'`, `trial_end_date=now()+30d`.

**Day 0 — zero OPS-sent emails.** No welcome, no verification (no `sendEmailVerification()` call exists in code; Firebase Console may send one if configured, but that's invisible to this codebase). No internal alert to the operator. No CRM activity downstream.

**Day 0 through trial − 8 — zero scheduled emails** unless an operator manually scheduled a `product_update`, `feature_announcement`, or `reengagement` campaign whose audience filter happens to match.

**Trial − 7d** — `warning_7d` email via `/api/cron/trial-expiry` (7am PT). Email only.

**Trial − 5d** — `warning_5d`. Email only.

**Trial − 3d** — `discount_3d`. **Email + OneSignal push + persistent in-app rail.** Two promo codes (`STRIPE_PROMO_PREEXPIRY_50`, `STRIPE_PROMO_PREEXPIRY_30`) attached.

**Trial − 1d** — `warning_1d`. Email only.

**Trial + 7d** — `reengagement_7d`. Email + in-app. New promo codes (`STRIPE_PROMO_POSTEXPIRY_7D_*`).

**Trial + 30d** — `reengagement_30d`. Email + in-app. Final promo codes (`STRIPE_PROMO_POSTEXPIRY_30D_*`).

**Throughout the trial**: nothing else is automatic. There is no onboarding drip, no "first project created" email, no "first invoice sent" email, no inactivity nudge before the 7-day expiry mark.

Adjacent flows that do fire:

- **Existing admin invites a teammate** → `sendTeamInvite` via `/api/auth/send-invite` (immediate).
- **New teammate joins** → in-app `role_needed` notification to admins (no email send; the `sendRoleNeeded` function exists but is not currently wired to the join path).
- **CRM client added** → silent. No email to the client, no notification to the team.

---

## Operational Runbook

### Pause all email immediately

POST `/api/admin/email/pause` with `{scope: 'global', reason, pausedUntil?}` — or click Pause in `/admin/email?tab=killswitches`. The chokepoint stops sending within one DB read (≤ few seconds). Persistent rail notification fans to every admin. `paused_until` triggers auto-resume.

### Pause one sender bucket

`{scope: 'bucket:dispatch' | 'bucket:gate' | 'bucket:field_notes' | 'bucket:portal', reason}`. Use when one address is being throttled or its DNS broke — keeps the other three flowing.

### Pause one campaign

`{scope: 'campaign:<uuid>', reason}`. Worker re-pends matching jobs each tick; resume → drain continues.

### Manually suppress an address

POST `/api/admin/email/suppressions` with `{email, list?, reason: 'manual'}`. Default list is `global` (full opt-out). Per-list values let an operator block a marketing channel without killing transactional. Idempotent.

### Remove a suppression (operator override)

DELETE the row, OR call `removeSuppression(email, list)` via the admin UI. Use sparingly — if SendGrid auto-suppressed an address it's because that mailbox bounced or marked us as spam; resurrecting it risks deliverability reputation.

### Replay a SendGrid webhook batch

SendGrid retries on `5xx`. Idempotency is enforced by the `(sg_message_id, event, timestamp)` unique index — safe to replay manually if the prod handler was down. Pre-index duplicates (historical) were cleaned in migration 079.

### Investigate a missed send

1. `SELECT * FROM email_log WHERE recipient_email=$1 ORDER BY sent_at DESC` — was it attempted? Status?
2. `paused_skipped` → check `email_pause_state` for the relevant scope.
3. `suppression_skipped` → check `email_suppressions` for `(lower(email), list)`. Look at `reason` and `source_event_id`.
4. `failed` → check `email_log.error_message`.
5. No row at all → either the typed sender wasn't called, or `gatedSend` was bypassed (currently only `sendDataSetupRequest` and `sendPrioritySupportActivated`).

### Schedule a marketing blast

`/admin/email?tab=schedule` → create campaign → pick template (`product_update`, `feature_announcement`, `reengagement`, or `trial_expiry_campaign`) → build audience (starter segment or full predicate) → `Estimate audience` to preview count → schedule. Dispatcher picks it up within 10 min of `scheduled_for`. Worker drains within 10 min after enqueue.

### Trigger trial-expiry manually

Cron is idempotent and dedup-guarded. Call `/api/cron/trial-expiry` with `Authorization: Bearer ${CRON_SECRET}` to force a same-day run. Existing `trial_expiry_notifications` rows prevent double-sends.

### Roll back a template change

`email_template_versions` is append-only; every published version has a sha256-hashed source snapshot. Reverting the TSX in source control + republishing creates a new version (same id, incremented semver). Old `email_log` / `email_jobs` rows retain the version they were sent with.

---

## Known Gaps (as of 2026-05-27)

1. **No welcome email on signup.** `signUpWithEmail` creates a Firebase user and returns; no backend hook fires a welcome, no `sendEmailVerification` is called. New trial users land in onboarding with zero inbox confirmation.
2. **No internal "new signup" alert.** Operator finds out about new signups by checking PMF or the database; no email or notification fires when a `companies` row is inserted.
3. **No client-add email.** Adding a CRM contact is silent; the contact is never told they've been added.
4. **`sendRoleNeeded` exists but is not wired** to the join-company path — admins get an in-app notification only.
5. **Two senders bypass `gatedSend`.** `sendDataSetupRequest` (`sendgrid.tsx:667`) and `sendPrioritySupportActivated` (`sendgrid.tsx:707`) call `sgMail.send` directly. They skip the pause/suppression check and do not write to `email_log`. Both are tied to Stripe checkout and were intentionally kept on direct send during cutover; the migration to `gatedSend` is still outstanding.
6. **Dispatcher failures are silent.** When a campaign fails during audience resolution or job enqueue, status is set to `failed` but no notification fires. Operator must spot it in the Schedule tab.
7. **The `lifecycle-emails` trigger calls Supabase Edge Functions** that live outside this repo. Their behaviour is not documented here. List of slugs: `lifecycle-emails`, `bubble-reauth-emails`, `unverified-emails`, `newsletter-emails`, `verify-email-domains` (per `/api/admin/email/trigger` `ALLOWED_SLUGS`).
8. **No automatic mid-trial engagement drip.** The trial-expiry cron only fires at the 6 calendar marks above. There is no "you haven't created a project yet" nudge, no "you've created your first invoice" celebration, no "you're 14 days in" recap.
9. **Soft bounce window is undocumented**. The schema (`email_suppressions.expires_at`) supports soft-bounce expiry, but no cron currently writes soft-bounce rows — the auto-suppress trigger explicitly ignores soft bounces and lets SendGrid handle retry.
10. **Template registry has 17 entries; on-disk template count is 25 (or 22 ex-PMF).** The admin preview is therefore a strict subset. Adding a new template requires touching both `template-registry.ts` (for preview) and (if it's a campaign target) `campaign-templates-bootstrap.ts`.

---
