# SPEC — Tier Model v2 (2026-07-14)

**Status:** Approved design (Jackson, 2026-07-14 session). Implementation NOT started.
**Owner:** Jackson Sweet.
**Supersedes:** the tier *semantics* everywhere they appear — 01_BUSINESS_MODEL § 2 pricing table + midpoint definitions, 04_CUSTOMER_UX package copy, 09_TIER_GUIDE_DESIGN outcome space, the `spec_capacity` seed, the `/spec` page, and the `SPEC_TIERS` constants in ops-site + ops-web.
**Leaves intact:** buyer identity + owner-approval-before-Stripe (01 § 1), the contract/legal architecture (01 § 3 — prose requires a rewrite pass, § 9 below), the engagement state machine (03), admin UX structure (05, renamed tiers), the capacity board machinery, Quebec exclusion, regulated-workflow exclusions, the chargeback posture, and the Phase 0 launch rule (conversation-only until final legal prose ships).

Decision provenance: 2026-07-14 brainstorm session with Jackson. Pricing grounded in a sourced market sweep (2025-26 rate cards; all USD unless noted; CAD ≈ 1.36-1.40× USD) — automation-setup packages $1,000-$5,000 USD (named anchor: Goodspeed Studio $5,000 fixed / 4 workflows); data-backbone builds $5,000-$15,000 USD + $500-$2,000/mo retainers; bespoke SMB app builds $60,000-$150,000 USD traditional / $25,000-$60,000 USD AI-assisted; white-label premium 10-25% on base build; hosted-app care plans $199-$599 USD/mo; maintenance rule-of-thumb 15-25% of build cost per year.

---

## 1. The model in one line

Three escalating engagement classes on one page — **wire it → run it → own it** — routed by the tier guide, with the free OPS trial (and the $399 Data Setup add-on) preserved as the honest floor.

Tier 1 deliberately does not require OPS. It is the acquisition wedge: every SPEC-01 engagement is a live demonstration of OPS-grade automation applied to the customer's own inbox and spreadsheets. Tier 2 is where the recurring relationship starts. Tier 3 is the flagship: a standalone product with the customer's name on it if they want it.

## 2. Canonical tier table

Designation lockup: `SPEC-0N · DESCRIPTOR`. Short form `SPEC-01` / `SPEC-02` / `SPEC-03` (board cells, chips, conversation). Stripe display names: `OPS SPEC-01 — WORKFLOWS`, `OPS SPEC-02 — SYSTEMS`, `OPS SPEC-03 — PROPRIETARY`. The SPEC-03 descriptor is a classification stamp, not a noun phrase — deliberate pattern-break at the top of the ladder (Jackson, 2026-07-14).

| | SPEC-01 · WORKFLOWS | SPEC-02 · SYSTEMS | SPEC-03 · PROPRIETARY |
|---|---|---|---|
| One-liner | Your tools, wired together | Your operation's backbone, run for you | A standalone app, built only for you |
| Total (CAD) | **$2,000** fixed | **$7,500** fixed | **from $25,000** — locked at scope sign-off |
| Payments | **50/50** — $1,000 books the slot, $1,000 at delivery walkthrough (net-15 invoice) | **25/25/25/25** — $1,875 per checkpoint | P1 **$6,250** fixed at booking; P2/P3/P4 = (locked total − $6,250) ÷ 3, residual cents on P4 |
| Deliverable | Up to **3 production automations** in the customer's own accounts (inbox→ledger, email→spreadsheet, form→list), documented, plus a training walkthrough | Everything in 01 **+ a structured data backbone** (jobs/clients/money in one system) + dashboards + import/cleanup of existing records + training | A standalone **trade tool** on its own database, designed, built, shipped, and operated by OPS — a Deckset, a bespoke roofing estimator, a plumbing planning tool, a landscaping equivalent. Connects to the customer's OPS account or runs fully independent. **Scope boundary: not an OPS-scale platform** — anything approaching a full operations platform is out of tier, custom-quoted well above the SPEC-03 band |
| Backbone location (02) | — | **Outcome-defined, case-by-case:** in the customer's OPS account when they run OPS; standalone (OPS-operated infra) when they don't | Own database, always |
| OPS requirement | Free OPS account (identity, approvals, notifications). **No subscription required** | Free account; subscription only if the backbone lives in OPS | Free account; no subscription |
| Support window | 30 days | 60 days | 90 days |
| Monthly | **None** | **Care plan $395/mo, required** — monitoring, fixes, and up to **2 change-hours/mo** (overage $200/hr, quoted first); hosting included when the backbone is standalone. Billing starts when the support window ends. Required while OPS operates a standalone backbone; optional after the support window when the backbone lives in the customer's OPS | **Care plan from $750/mo, required while OPS hosts** — infrastructure, updates, support, store compliance, up to **3 change-hours/mo** (overage $200/hr, quoted first). Billing starts when the support window ends |
| Guarantee | 30-day walk-away (all tiers, single invocation, existing exclusions) — mechanics per § 4 | same | same |
| Slot ceiling (seed) | 6 | 3 | 1 |
| Timeline seed (disc/build days) | 2-4 / 3-7 | 5-10 / 15-25 | 10-15 / 30-60 |

Price rationale: $2,000 sits decisively under the $5,000-USD-class productized automation package while clear of the commodity floor; $7,500 + $395/mo undercuts the backbone market band on entry while carrying higher lifetime value than v1 Build ($7,500 up front + $4,740/yr in care once billing starts, vs $8,500 + an optional retainer most customers would skip); from-$25,000 passes the AI-velocity advantage through against $34k-$82k CAD AI-assisted comps and $82k+ traditional quotes. Clean escalation: totals 3.75× / 3.3×; deposits $1,000 / $1,875 / $6,250.

## 3. White label (SPEC-03 add-on)

**+$4,000 one-time at build, +$200/mo on the care plan.** Customer's name, icon, App Store listing, screenshots, description — end-to-end their brand.

- **Published under OPS's Apple Developer organization account. Turnkey by design** (Jackson, 2026-07-14): the customer sets up nothing, owns no Apple account, renews nothing. OPS is invisibly the operator.
- The App Store **"Seller:" line reads OPS's legal entity** — account-bound, cannot show the customer's name. Everything above the fold is their brand. Disclosed in the tier detail and the white-label rider, never hidden.
- Apple risk posture: guideline 4.2.6 targets commercialized template mills; a bespoke single-client build under the builder's org account is standard agency practice. OPS administering the listing end-to-end is the mitigation.
- **Off-boarding escape hatch:** Apple App Transfer moves the app to the customer's own account (reviews and installs preserved) if they ever want full publisher-of-record ownership. Administered by OPS, quoted as billable hours at the then-current rate. Turnkey today is not lock-in forever — sell it that way.
- Customer warrants brand ownership and grants OPS a publishing license (white-label rider, § 9).
- At ~10-16% of expected SPEC-03 totals, +$4,000 sits inside the market's 10-25% white-label premium band. OPS's own Apple account cost (~$119 CAD/yr across all white-label apps) is absorbed by the care bump.

## 4. Guarantee mechanics per tier

The 30-day walk-away guarantee (single invocation, written notice, no defect proof, no cure period, existing exclusion list) survives unchanged in *policy*. The **refund lever** now varies by where the deliverable lives — v1's single mechanism ("feature-flag the modules off in `spec_module_entitlements`") only works for OPS-hosted work:

| Tier | Deliverable location | Guarantee lever |
|---|---|---|
| SPEC-01 | Customer's own accounts (their Gmail, their sheets, their Zapier/n8n/scripts) | **Money back; automations cannot be disabled.** Max exposure $2,000. Anti-abuse: existing exclusions + single invocation. Accepted cost of the wedge tier |
| SPEC-02 (OPS backbone) | Customer's OPS account | Feature-flag off via `spec_module_entitlements` (existing mechanism) |
| SPEC-02 (standalone backbone) | OPS-operated infra | Access revoked; data export delivered per off-boarding rules |
| SPEC-03 | OPS-hosted app | App disabled + store listing removed; refund per the milestone-state matrix (01 § 3) |

## 5. Retired from v1

- **Setup / Build / Enterprise** names and semantics ("custom modules on the OPS platform" as the product definition).
- **`subscription_multiplier_estimate`** and the locked-multiplier concept ("your OPS subscription may increase 15-50%") — replaced by flat published care plans. The ongoing-costs section shows fixed numbers only; the OPS subscription is listed separately and only applies when the customer actually runs OPS.
- The 4-milestone structure **for Tier 1 only** (now 50/50). SPEC-02/03 keep 25/25/25/25 rhythm (03 with variable total).
- `spec_module_entitlements` as the *universal* guarantee lever (retained where deliverables are OPS-hosted, § 4).

**Unchanged and explicitly carried:** owner-approval-before-Stripe path A/B, account-required-before-deposit, Quebec exclusion + attestations + webhook defense, regulated-workflow exclusions, net-15 invoicing, non-payment disablement, chargeback evidence chain, referral program hooks, the **$399 Data Setup add-on** (in-app OPS product; the tier guide's rider for simple bring-my-history-across), and the Phase 0 rule: **the relaunched page ships conversation-only; `SPEC_LIVE_DEPOSITS_ENABLED` stays false until the § 9 legal rewrite ships.**

## 6. Schema + seed deltas (implementation contract)

- **Tier slugs:** `spec01` / `spec02` / `spec03` (text, stable even if descriptors evolve; display names live in dictionaries). Replaces `setup` / `build` / `enterprise` in `spec_capacity`, `SPEC_TIERS` constants (ops-site `lib/spec/pricing.ts`, ops-web `lib/spec/constants.ts` — 19 typed files on ops-site follow the compiler), analytics event payloads, and Stripe metadata. Zero live engagements exist (verified 2026-07-14: `spec_projects` = 0 rows), so this is a re-seed, not a migration of customer data.
- **`spec_capacity` re-seed** per § 2 table: price cents 200000 / 750000 / 2500000 (03 = floor), retainer cents NULL / 39500 / 75000, slot ceilings 6 / 3 / 1, support days 30 / 60 / 90, discovery/build day ranges per § 2. `subscription_multiplier_estimate` column retired from all published surfaces (column may remain, unread).
- **SPEC-01 payment shape** (50/50) and **SPEC-03 variable-total** (P1 fixed $6,250; total locked at P2 scope sign-off) need first-class support in the milestone helpers (`computeMilestones` gains per-tier shapes) and the scope-doc flow (locked total written at sign-off).
- **SPEC-01 keeps the scope-lock evidence event even though no payment attaches to it:** the intake responses distill into a short written work order (the versioned scope-doc mechanism, lightweight template), countersigned via the existing `spec_acceptance_events.event_type='scope_signoff'` before build starts. The 50/50 schedule changes when money moves, not the evidence chain — every engagement still carries ToS acceptance → scope sign-off → delivery acceptance.
- **Care plans:** Stripe subscriptions ($395 / $750-base + $200 white-label bump), started when the support window ends; state tracked per engagement. New: white-label flag + care-tier on the engagement row.
- `spec_public_board_snapshot` + its refresh cron re-emit the new slugs; board fallback dictionary entries rewritten.

## 7. Customer journey deltas

- **Intake forms fork by tier.** SPEC-01 asks about their tools and their inbox (what arrives, where it should land); SPEC-02 adds data-shape questions (what records, what mess, what reports); SPEC-03 is a product-vision intake. Same storage + evidence chain.
- **Tier guide (09, v3.1) outcome remap:** `{ops, data_setup rider, spec01, spec02, spec03-conversation}`. The honest-floor rules carry verbatim: ties resolve down, uncertainty routes free, the OPS trial leads every result it can. **SPEC-01 is cold-diagnosable** — its qualifying questions are about the prospect's own inbox and tools, never OPS internals — so the cold path gains its first honestly-diagnosable paid outcome (v1 Build never had this). SPEC-03 always routes to a founder conversation from the guide; the deposit path stays open from the package card.
- **Board copy:** "limited SPEC slots each quarter" survives; per-tier windows re-derived from § 2 seeds.

## 8. /spec page redesign (UI/UX pass contract)

Baseline: fold the never-merged `release/spec-launch-ops-site-20260607` conversion work (sticky deposit bar, full-width packages, analytics instrumentation, accent cleanup) into the rebuild where it serves; its questionnaire logic is superseded by the 09-v3.1 guide remapped per § 7. All tier copy, ES dictionary included, is rewritten for v2 (the branch's ES-i18n follow-up folds in).

1. **Hero** — 3D phone scene slot preserved as-is (a parallel agent is upgrading the phone visual; it drops into the same slot). New headline direction: `WE BUILD THE MACHINE THAT RUNS YOUR BUSINESS.` Founder line rewritten — **"contractor" is banned**; approved: owner-operator / the trades / subtrades. Final copy via ops-copywriter at implementation.
2. **The ladder** — three tiers presented as an escalation (wire it → run it → own it), not three equal cards. Prominence follows the guide's honesty rules, not price.
3. **The guide** — 60-second fit check, § 7 outcomes, result deep-links `?fit=`.
4. **OPS BOARD** — live, three new tier rows.
5. **Tier detail** — per-trade example jobs per tier (release-branch example pattern retained, examples rewritten: 01 = inbox/ledger/spreadsheet wiring; 02 = backbone + dashboards; 03 = Deckset-class apps).
6. **White label strip** — quiet, one confident line + the care-bump number; detail behind the SPEC-03 card.
7. **Ongoing costs** — flat numbers only ($395 / from $750 / +$200 white label; OPS subscription listed separately as its own product).
8. **Standing behind the work** — guarantee columns updated to § 4 mechanics in plain language.
9. **FAQ** — rewritten for v2 (payment shapes, care plans, white label seller-line honesty, App Transfer escape hatch, "do I need OPS?" → no).
10. **Bottom CTA** — rebuilt; **fixes the live `BOTTOMCTA.CTATEXT` bug** (the Phase 0 dict filter strips every key ending `.ctaText`, catching `bottomCta.ctaText`; the rebuilt filter must be deposit-key-scoped, not suffix-global).

Design-system compliance per DESIGN.md; marketing surface keeps the heavier Mohave display register; motion on the single OPS curve with reduced-motion variants (release-branch components already comply). JSON-LD (Service now; Product + Offers when deposits flip), metadata, and sitemap copy updated to v2 language.

## 9. Legal rewrite (gates the deposit flip, not the page relaunch)

Scope for the ToS/rider pass (06A/06B/06C update): per-tier scope-of-services and acceptance definitions; per-tier guarantee levers (§ 4) including the SPEC-01 money-back posture; SPEC-03 variable-total mechanics (deposit against floor, total locked at scope sign-off); care-plan terms (required-while-hosted, billing start, cancellation/off-boarding, reasonable-efforts uptime posture — **no SLA at these price points, stated plainly**); white-label rider (customer brand warranty + publishing license to OPS, OPS publisher-of-record disclosure incl. the seller line, App Transfer off-boarding at billable hours); **SPEC-03 build-exclusivity clause** — the PROPRIETARY name obligates it: OPS will not sell the customer's app to another company (patterns, infrastructure, and non-customer-specific components remain reusable; the app itself is exclusive); IP otherwise unchanged (OPS owns code, customer licensed; brand assets remain the customer's). Quebec exclusion, prohibited workflows, refund matrix skeleton, LIL cap all carry from the fourth pass.

## 10. Implementation phasing (input to the plan doc)

- **P1 — Model:** slugs, seeds, milestone shapes, care-plan plumbing, admin console rename (ops-web `spec-launch-consolidation` worktree is the base), bible doc-pass across 01-07.
- **P2 — Page:** /spec rebuild per § 8 (EN + ES), guide remap, analytics slugs, board copy, live-bug fixes.
- **P3 — Legal + flip readiness:** § 9 prose, Stripe test-mode payment proof for the two new payment shapes, deposit-flip checklist per 07/08.
- Founder media assets + Cal.com scheduling remain carried open items from 07/08; unblocked by nothing in this design.
