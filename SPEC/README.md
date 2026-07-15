# SPEC — Custom Software Build Service

**Status:** Fourth revision pass complete (2026-05-25). Gate-resolution pass complete (2026-05-25). **Tier Model v2 approved 2026-07-14 — see [10_TIER_MODEL_V2.md](10_TIER_MODEL_V2.md); it supersedes the tier table below and every tier semantic in 01/04/05/09 pending the implementation doc-pass.** Phase 0 conversation-only launch approved; automated live SPEC deposits not approved until final customer-facing legal prose ships (v2 legal rewrite scope in 10 § 9).
**Owner:** Jackson Sweet.
**Last updated:** 2026-07-14.

This directory is the authoritative spec for OPS SPEC — the custom-software-build service sold at `/spec` on `opsapp.co`. It captures the full business operating model, data architecture, customer journey, admin operations, contractual terms, and phased rollout plan.

The current revision incorporates a fourth-pass legal/commercial correction after the locked third-pass SPEC. The prior passes inverted the owner-approval-before-Stripe gate, split holds by type, rebuilt the schema against the live identity model, added the dedicated `is_spec_operator()` operator gate, moved the public board to a refreshed snapshot table, and split refund mechanics per milestone. This fourth pass applies the external legal/pro verdict: SPEC is ready for conversation-only Phase 0, but automated live SPEC deposits are blocked until final customer-facing ToS / Privacy / DPA prose exists and the legal fixes in this pass are applied. Counsel review remains recommended risk mitigation, not a hard launch blocker per Jackson's decision. See [CHANGELOG.md](CHANGELOG.md) for the full per-file delta.

## What SPEC is

A productized custom-software-development service for trades businesses. Three deposit tiers — **Tier Model v2 (2026-07-14, [10_TIER_MODEL_V2.md](10_TIER_MODEL_V2.md)):**

| Tier | Total | Description |
|---|---|---|
| SPEC-01 · WORKFLOWS | $2,000 CAD | The customer's existing tools wired together (inbox→ledger, email→spreadsheet); up to 3 production automations. Does not require OPS. Paid 50/50 |
| SPEC-02 · SYSTEMS | $7,500 CAD + $395/mo care | Workflows plus a structured, maintained data backbone (in the customer's OPS or standalone) + dashboards + import/cleanup. Paid 25/25/25/25 |
| SPEC-03 · PROPRIETARY | from $25,000 CAD + from $750/mo care | A standalone trade tool built only for the customer (a Deckset, a bespoke roofing estimator) on its own database, operated by OPS; connects to their OPS or runs independent. Not OPS-scale platform builds (out of tier). White label +$4,000 / +$200/mo. Deposit $6,250; total locked at scope sign-off |

*(v1 Setup $3,000 / Build $8,500 / Enterprise $18,000 with universal 25/25/25/25 is superseded; the docs below retain v1 language pending the implementation doc-pass.)*

SPEC-02/03 use the **25 / 25 / 25 / 25** four-milestone payment structure (deposit / scope sign-off / midpoint demo / delivery); SPEC-01 is 50/50 (deposit / delivery). Net-15 invoicing and a **30-day post-walkthrough Guarantee Refund** with explicit exclusions and anti-abuse rules apply to every tier (per-tier refund levers in 10 § 4).

Canada-only at launch (Quebec excluded by billing address, head office, operating address, establishment, and material SPEC use). Multi-engagement supported per company.

## Navigation

Read in order for a complete understanding. Each document is self-contained but cross-links to siblings.

| File | Purpose |
|---|---|
| [01_BUSINESS_MODEL.md](01_BUSINESS_MODEL.md) | Every locked policy decision — buyer identity, owner-approval-before-Stripe gate, payment terms, refund matrix, 12-month-fees LIL cap, scope, acceptance, SLA, hold-type semantics, subscription entitlements, retainer, off-boarding, referrals, edge cases |
| [02_DATA_MODEL.md](02_DATA_MODEL.md) | Full Supabase schema — 17 new tables (16 SPEC engagement tables + 1 public board snapshot table), dedicated `is_spec_operator()` SECURITY DEFINER function, every admin RLS policy routed through it, full per-table CONCRETE RLS (no placeholders), Storage bucket policy for intake uploads, OPS Operations internal company, `is_test` column on every engagement table |
| [03_WORKFLOW.md](03_WORKFLOW.md) | State machine — Path A (buyer = owner) vs Path B (owner-approval-before-Stripe), `hold_type` semantics, walkthrough_completed_at as canonical anchor |
| [04_CUSTOMER_UX.md](04_CUSTOMER_UX.md) | `/spec` marketing page, intake form, confirmation, owner-approval, awaiting-approval, post-approval checkout, conversion tracking |
| [05_ADMIN_UX.md](05_ADMIN_UX.md) | `/admin/spec` in OPS-Web — TODAY command queue, Kanban, project detail (incl. Entitlements tab), capacity config, refund queue with eligibility chips |
| [06_CONTRACT_AND_EMAILS.md](06_CONTRACT_AND_EMAILS.md) | SPEC Terms drafting requirements plus required final-prose clauses (Quebec exclusion, regulated-workflow prohibitions, revised LIL, IP/license, guarantee, subprocessors, DPA reference, order-of-precedence) + email/event triggers |
| [07_ROLLOUT.md](07_ROLLOUT.md) | Phase 0 (immediate safety mitigation), Phase 1 (ads-launch-ready), Phase 2 (volume polish), Phase 3 (scale), verification scenarios, critical files, open items |
| [10_TIER_MODEL_V2.md](10_TIER_MODEL_V2.md) | **Tier Model v2 (2026-07-14, current)** — SPEC-01/02/03 definitions, pricing + payment shapes, care plans, white-label add-on, per-tier guarantee levers, schema/seed deltas, /spec redesign contract, legal-rewrite scope |
| [CHANGELOG.md](CHANGELOG.md) | What changed in the May 2026 revision pass |

## Why this exists

The `/spec` route ships today as scaffolded marketing copy + a 50% Stripe handoff with no business model behind it — unsafe for paid ads. Before any campaign can run, every eventuality of a real customer engagement needed an explicit policy answer: identity, payment, contract, scope, acceptance, SLA, off-boarding, refund eligibility, and the legal evidence chain. This spec captures those answers and maps them onto the schema + UX + plumbing.

## Cross-references

- Marketing page: `ops-site/src/app/spec/` (rewrite per [04_CUSTOMER_UX.md](04_CUSTOMER_UX.md))
- Legal pages: `ops-site/src/app/legal/` with `spec-terms` tab added to existing `terms / privacy / eula / dpa` set
- Admin surface: `ops-web/src/app/admin/spec/` (NEW per [05_ADMIN_UX.md](05_ADMIN_UX.md))
- Stripe webhook: existing consolidated `/api/shop/webhook` in OPS-Web, dispatched on `metadata.type === 'spec_deposit'` and `charge.dispute.created`
- Email infrastructure: existing SendGrid + `email_template_versions` / `email_campaigns` system in OPS-Web
- Supabase project: `ops-app` (`ijeekuhbatykdomumfjx`), shared with all OPS surfaces
- Identity model (verified live 2026-05-25):
  - `public.users.id` uuid; `public.companies.account_holder_id` text storing `users.id::text`
  - `public.get_user_id()` returns text
  - `public.has_permission(p_user_id uuid, p_permission text, p_required_scope text default 'all')` is the canonical permission check for general use — but it short-circuits through `is_company_admin` / `account_holder_id` / `admin_ids` before consulting `role_permissions`, which makes it unsafe as a SPEC operator gate
  - **SPEC admin gate: `public.is_spec_operator()`** — a dedicated SECURITY DEFINER function that consults `role_permissions(permission='spec.admin', scope='all')` and `user_permission_overrides(permission='spec.admin', granted=true)` only, never customer-company admin status

## Launch gates and open items

See the bottom of [07_ROLLOUT.md](07_ROLLOUT.md) — items deferred from the brainstorm or surfaced by review that need follow-up before or during implementation. The current launch rule is:

- **Approved now:** Phase 0 conversation-only launch with no automated live SPEC deposits.
- **Required before automated live deposits:** final customer-facing ToS / Privacy / DPA prose, the fourth-pass legal fixes, payment-flow proof in Stripe test mode, and the Phase 1 implementation gates.
- **Recommended but not required before deposits:** outside counsel review. Jackson can launch after final legal prose and owner self-review, but counsel review remains the recommended risk mitigation before volume scaling or first dispute.

The six fourth-pass implementation bug_reports were resolved in the gate-resolution pass on 2026-05-25 — see [07_ROLLOUT.md](07_ROLLOUT.md) § Gate resolutions for the locked answers (Stripe Checkout posture + webhook Quebec defense; live-schema verification + `SPEC Operator` role seed; SECURITY DEFINER functions in `private` schema; company-required-before-deposit lock; notification rail confirmed active; complete Phase 1 server-route enumeration). Remaining open items are operational and asset-dependent only: founder media assets, Calendly choice, billing-engine wiring, Meta CAPI / Google Enhanced credentials, and Stripe Connect Express setup (Phase 2 referrals).
