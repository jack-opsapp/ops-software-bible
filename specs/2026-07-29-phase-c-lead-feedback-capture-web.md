# Phase C Lead Feedback — Deployed Contract + Web Discard Capture

**Date:** 2026-07-29 · **Status:** Live contract documented from prod; web capture shipped on `ops-web` branch `feat/lead-discard-feedback` (bug `ad2b6850-7536-4deb-8847-94000fd5c169`)
**Supersedes:** nothing — first bible coverage of `lead_disposition_feedback` (the 2026-07-27 deploy merged the learning side without bible updates).
**Related:** `ops-web/docs/plans/2026-07-29-lead-discard-feedback-capture.md` (implementation plan), feat-branch design doc `docs/superpowers/specs/2026-07-27-phase-c-lead-feedback-design.md`.

## 1. What this system is

When an operator discards (or archives) a lead that OPS should never have created, the correction is captured as a structured, company-scoped learning signal and applied as an atomic lifecycle action. The Phase C classifier consumes that evidence to score future inbound email (bounded priors — see §4). Free-text notes are audit-only; classifier code never reads them.

## 2. Data (deployed on prod `ijeekuhbatykdomumfjx`)

### `lead_disposition_feedback` — append-only correction history
Key columns: `company_id`, `opportunity_id`, `actor_user_id`; `reason_code`, `canonical_outcome`, `learning_polarity` (`negative|positive|neutral`), `learning_state` (`active|retracted`), `resolution_status` (`applied|review_required|undone`), `optional_note` (≤500, audit-only), `phase_c_enabled` (stamped at write); prior-state snapshot (`prior_stage`, `prior_stage_entered_at`, `prior_stage_manually_set`, `prior_lost_*`, `prior_actual_close_date`, `prior_archived_at`) and applied-state snapshot (`applied_stage`, `applied_archived_at`, `applied_opportunity_updated_at` — the undo conflict guard); disposition links (`prior_disposition_id`, `disposition_id` → `opportunity_dispositions`); server-derived email evidence (`source_thread_id/-connection_id/-provider_thread_id/-message_id/-thread_key`, `sender_email`, `sender_domain`, `participants_hash`); `model_context`/`policy_context` jsonb; idempotency (`apply_idempotency_key` unique per `(company, actor)`, `undo_idempotency_key`), retraction (`retracted_at/by`).

RLS/grants: `anon`+`authenticated` = **SELECT only** (gated by `private.current_user_can_view_opportunity`); all writes are owned by the SECURITY DEFINER RPCs below. `service_role` reads for the classifier loader.

Reason vocabulary (CHECK): Phase C disposition set `spam, job_applicant, vendor_sales, internal, platform_notification, test_traffic, duplicate, not_a_fit, other, legacy_unspecified` + archive set `not_now, seasonal, waiting_on_client, archive_unspecified`. Canonical outcomes: `discarded, lost, duplicate_review, review_deferred, archived`.

### `lead_classification_reviews` — service-only review queue
Durable hold for future messages a feedback prior moves into the uncertainty band. Identifiers + numeric evidence only; unique `(company_id, connection_id, provider_message_id)`; written by the sync path (`persistDeferredLeadClassification`), never by clients.

## 3. RPCs (SECURITY DEFINER, EXECUTE granted to `anon, authenticated`)

| Function | Purpose |
|---|---|
| `apply_lead_disposition_feedback(p_opportunity_id, p_reason_code, p_optional_note, p_idempotency_key)` | THE discard/correction action. Resolves actor from JWT, checks edit permission, `FOR UPDATE` lock, idempotent replay per `(company, actor, key)`; validates reason against the company's Phase C state (`admin_feature_overrides.feature_key='phase_c'`); refuses terminal/merged leads (`opportunity_terminal_or_merged`). Applies the mapped lifecycle + `stage_transitions` audit + `opportunity_dispositions` supersession + feedback row in ONE transaction. Server derives all email evidence; the client cannot submit company, actor, sender, lifecycle target, or polarity. |
| `undo_lead_disposition_feedback(p_feedback_id, p_idempotency_key)` | Guarded undo: retracts the learning row (`learning_state='retracted'`, `resolution_status='undone'`), restores prior stage/lost fields/dispositions, writes the reverse stage transition. Raises `feedback_undo_conflict` if the opportunity changed after the apply — undo never overwrites a later human decision. Retracted rows replay idempotently. |
| `apply_lead_archive_feedback` / `undo_lead_archive_feedback` | Archive siblings (outcome `archived`, polarity always `neutral`, reason optional → `archive_unspecified`). Same locking/idempotency/undo-guard pattern; archive writes `archived_at`, not `stage`. |
| `get_lead_disposition_context(p_opportunity_id)` | Returns `{phase_c_enabled, policy_version}` for the caller's company (edit-gated). The web UI does NOT use it — the feature-flags store already carries the synthetic `phase_c` slug. |

Reason → outcome map (server-owned): `spam / job_applicant / vendor_sales / internal / platform_notification / test_traffic` → `discarded` (negative); `not_a_fit` → `lost` + disposition `disqualified` (positive — protects future genuine inquiries); `duplicate` → `duplicate_review` (neutral, **no lifecycle change**); `other` → `review_deferred` (neutral, **no lifecycle change**); `legacy_unspecified` → `discarded` (neutral, accepted only while Phase C is disabled for the company).

### Undo defect — found 2026-07-30, fix authored, NOT yet applied

`undo_lead_disposition_feedback` raised `feedback_undo_conflict` (errcode 40001) on **every** call, making Undo unusable on both the discard and archive paths.

Cause: the apply RPCs write `opportunities.updated_at = v_now` (`clock_timestamp()`) and record that same value into `applied_opportunity_updated_at` as the optimistic-concurrency snapshot. `opportunities` carries a BEFORE UPDATE trigger, `trg_opp_timestamp` → `public.update_timestamp()`, whose body is `NEW.updated_at = now()` — the **transaction** timestamp. The trigger overwrites the RPC's value, landing the row ~3ms behind the recorded snapshot, so undo's guard `v_opportunity.updated_at is distinct from v_feedback.applied_opportunity_updated_at` is always true. Measured on prod: recorded `16:29:23.822686+00` vs stored `16:29:23.819340+00` (−3.346ms); second row −3.502ms.

Fix: `ops-web/supabase/migrations/20260730000000_fix_lead_feedback_undo_conflict.sql` replaces both apply RPCs so they read the stored `updated_at` (and `archived_at`) back with `RETURNING` instead of predicting it. Undo's guard is deliberately unchanged. No backfill needed — the table held only verification rows when the defect was found, so no customer row carries a stale snapshot. **Status: authored and committed on `feat/lead-discard-feedback`, awaiting operator approval to apply to prod.** Until applied, web Undo surfaces the guard honestly as "Undo blocked — this lead changed after the discard".

### Migration drift (flagged)
Both defining migrations exist on prod but NOT in `ops-web` `main`'s `supabase/migrations/`: `20260727193418_phase_c_lead_disposition_feedback.sql` lives only on branch `feat/phase-c-lead-feedback`; `20260728120000_lead_archive_feedback.sql` only on branch `fix/lead-archive-feedback-migration`. Landing those files on `main` is an open housekeeping item — match by NAME against the prod ledger when reconciling.

## 4. Learning loop (shipped 2026-07-27, `ops-web` main)

`src/lib/api/services/lead-feedback-prior-service.ts` loads active, `phase_c_enabled=true` evidence per company and applies bounded adjustments to the model's lead probability inside `sync-engine` / `ai-sync-reviewer`: exact provider message (−0.42) > exact thread (−0.32) > repeated independent sender (−0.16/−0.24) > mature domain (−0.12; requires ≥3 independent threads + ≥2 senders; `platform_notification` never counts domain-wide; public/protected domains excluded). Positive `not_a_fit` evidence (+0.12/+0.25). Total clamped to [−0.45, +0.3]. Uncertain outcomes defer to `lead_classification_reviews` + `email_threads.routing='require_human_review'`. One correction can send a borderline message to review but can never auto-suppress on its own.

## 5. Web capture UX (this ship — pipeline discard)

Single choke point: `requestStageChange` in `src/app/(dashboard)/pipeline/_components/use-stage-transition.ts` (board + table + detail panel + focused drag-to-discard all funnel through it).

- **Phase C ON** (company flag via feature-flags store, `initialized && canAccessFeature("phase_c")`): discard flips the card optimistically and defers the write. ONE toast (`discard-feedback-toast.tsx`, glass-dense, olive rail, 10s) carries UNDO + a nine-chip one-tap reason rack (`// REASON — TRAINS THE FILTER`). Chip tap → `apply_lead_disposition_feedback` performs the whole action atomically; toast updates in place (olive reason tag, `REASON LOGGED`, outcome line — `duplicate`/`other` explicitly say "stays on board" because the server made no lifecycle change); UNDO and the global undo stack route through `undo_lead_disposition_feedback`. Ignoring/dismissing the toast commits today's plain stage move — **skipping costs nothing and writes no learning row** ("a reason is a bonus, never a toll").
- **Phase C OFF:** identical UX to the pre-feature discard (same toast copy), but the write routes through the RPC with `legacy_unspecified` so actor, audit, disposition, and idempotency stay atomic; falls back to the legacy `moveStage` on unexpected RPC errors so discard can never break.
- **Won/Lost sources:** plain legacy stage move (the contract excludes terminal leads).
- All commit/undo flows use `mutateAsync` + explicit cache invalidation (survive unmount); idempotency keys are `crypto.randomUUID()`; double-undo (toast + Cmd+Z) is safe because the undo RPC replays idempotently.

**iOS status:** the approved one-tap reason sheet (flow-focused list) is specced in the feat-branch design doc but not yet shipped; iOS discard still writes no feedback. **Archive capture** (web + iOS) is a separate open item on the archive RPC pair.
