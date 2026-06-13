# SPEC — Tier Guide Design (2026-06-13)

Design spec + implementation plan for a **net-new** feature on the public `/spec`
marketing page: a short questionnaire ("the guide") that gives a prospect a straight
answer about what they actually need — **standard OPS (no paid build), or Setup,
Build, or Enterprise** — with a plain-English reason.

- **Status:** design only. No production code written. No shipped `/spec` file
  touched. This document is the brief a follow-up build chip executes from.
- **Vintage:** designed 2026-06-13, against SPEC Phase 1 as shipped to production
  (behind the `depositsEnabled` kill switch — currently OFF). **Hardened** by an
  8-agent design + conversion review, then **extended to a 4th outcome + 5 questions**
  by a second grounded/adversarial workflow (see § 0).
- **Prototype:** [`specs/2026-06-13-spec-tier-guide-PROTOTYPE.html`](../specs/2026-06-13-spec-tier-guide-PROTOTYPE.html)
  — a throwaway, interactive, token-faithful artifact. Not production; § 7 / § 8 are
  canonical, not the HTML.

Primary sources: [01_BUSINESS_MODEL.md](01_BUSINESS_MODEL.md) (tiers, pricing, §4
upgrade mechanics), [04_CUSTOMER_UX.md](04_CUSTOMER_UX.md) (`/spec` composition,
voice, conversion-tracking), [07_ROLLOUT.md](07_ROLLOUT.md) § 3, plus the standard-OPS
capability research cited in § 2.1 (00_EXECUTIVE_SUMMARY, 01_PRODUCT_REQUIREMENTS,
03_DATA_ARCHITECTURE, 12_SUBSCRIPTION_MANAGEMENT). Live component patterns:
`SpecPageContent.tsx`, `SpecPricing.tsx`, `PackageCard.tsx`, `SpecOpsBoard.tsx`,
`lib/theme.ts`, `lib/marketing-analytics.ts`, `lib/spec/conversion-events.ts`,
`app/api/contact/route.ts`, `components/resources/ContactForm.tsx`.

---

## 0. Review log + conversion verdict (2026-06-13)

**Two review passes, both multi-agent and adversarial.**

**Pass 1 (8 agents — design-compliance, craft, 3 CRO lenses, 2 adversaries):**
hardened the original 3-question / 3-outcome design — result now carries its own
inline action; the Enterprise guard is surfaced; tokens/focus/a11y fixed; entry copy
re-led with payoff. Conversion verdict (still holds): **with `depositsEnabled` OFF
this is an engagement + qualification feature, not a deposit-conversion lever** — it
becomes one once deposits are ON and the § 12.0 dictionary fix lands. Success today =
`completed → inquiry_submitted` ratio, **not** the `tier_guide_completed` vanity
count.

**Pass 2 (research → 2 designs + adversary → synthesis) — this revision:** adds a
**4th outcome, `ops`** ("you don't need a custom build — standard OPS already does
this; start the free trial and set it up yourself"), and expands to **5 questions**.
Rationale for both, per Jackson's direction:

- **The 4th outcome is the ultimate anti-upsell.** A guide that sometimes says "you
  don't need to pay us a cent past your subscription" is the strongest possible proof
  of the trust OPS sells. It routes low-fit prospects to the free self-serve path
  where they belong (happier, stickier, no refund risk) and offers Setup honestly as
  the *done-for-you* alternative rather than forcing it.
- **5 questions, not 3.** A 3-question survey reads as too thin to credibly say
  "here's exactly what you need," and a 4-outcome decision — especially the subtle
  *standard-OPS-vs-Setup* line — genuinely needs more signal. The two new questions
  each earn their place (§ 3.1): **Q3 (DIY vs done-for-you)** is the only thing
  separating the free `ops` verdict from paid Setup; **Q4 (capability gate,
  multi-select)** is the hard backstop that makes "Just OPS" impossible to misroute.
  No personalizer padding — trade/crew-size/urgency were considered and **cut** as
  scored questions.

**The grounding that makes `ops` honest (§ 2.1):** standard OPS is a 30-day free
trial with **no feature paywalls**; the *only* two things a paid Setup unlocks that a
user genuinely cannot self-serve are **renamed/new pipeline stages** (beyond the
fixed eight) and **custom fields** on projects/clients (plus migrating *historical*
data). Everything else Setup does — stage colors, follow-up timing, thresholds,
win-odds, lead sources, tags, roles, catalog, tax, connecting QuickBooks/Sage going
forward — is already free and self-serve. So the `ops` copy must **never** imply you
can self-serve stages or fields; that exact line is the honesty boundary (§ 5.2).

**Adversary-driven guards encoded in the scoring (§ 3.2):** a Build/Enterprise lane
is never demoted to `ops`/Setup by a self-serve-sounding later answer; a true
capability lock forbids `ops` outright; the under-estimator (migrating GC) is still
forced up; the unsure user is sent to the *free* trial, never a $3k engagement.

---

## 1. Problem & intent

A prospect lands on `/spec`, sees three packages, and can't tell which one is theirs
— or whether they even need one. Today the page answers passively. The guide answers
actively: ask the fewest questions that genuinely discriminate, then hand back a
confident, honest answer — up to and including "you don't need to buy anything here."

The user is a trades business owner "drowning in texts, paper, and chaos" — stressed,
unsure. The bar for every decision: does it feel like a lifeline, or a tech-demo
quiz? If it reads as a quiz, it's wrong.

Three non-negotiables:

1. **No upsell-by-default.** The honest answer wins. Enterprise is never recommended
   on ambition alone (§ 3.2 guard, surfaced not hidden).
2. **Sometimes the honest answer is "don't pay us."** If standard OPS covers them,
   the guide says so and points them at the free trial — with Setup offered as the
   *done-for-you* option, never as a thing they must buy. This is outcome `ops`.
3. **Every question earns its place** — a real discriminator or an explicit qualifier.
   No padding. (Five questions, all discriminators; zero personalizer padding.)

---

## 2. What actually distinguishes the outcomes

Four outcomes, lowest commitment first:

| Outcome | Price | What it is |
|---|---|---|
| **OPS** | subscription only ($90–$190/mo, 30-day free trial) | **Nothing to build or pay extra for.** Standard OPS already covers them; they self-serve the config in Settings. |
| **Setup** | $3,000 / $750 deposit | **Done-for-you** configuration + the two things OPS can't self-serve (renamed/new pipeline stages, custom fields). 2 discovery sessions, workflow analysis, staging review, walkthrough, 30-day guarantee. |
| **Build** | $8,500 / $2,125 | **One** custom module — new features/views/logic OPS doesn't have. iOS + web. |
| **Enterprise** | $18,000 / $4,500 | **Multiple** modules + **data migration** off an incumbent + deep integrations + structural complexity (multi-trade/division/subs). |

The highest-signal axis is **how much of what you need already exists in OPS vs. has
to be built — and who does the configuring.** The override axes are **migration**
(Enterprise scope, catches the under-estimator) and **structural complexity**
(Enterprise tell — structural, not headcount).

**Out of scope for the guide: eligibility.** Quebec + excluded regulated workflows
([01_BUSINESS_MODEL.md](01_BUSINESS_MODEL.md) §3) are disqualifiers handled downstream
(Quebec at `/spec/billing-address`; regulated at intake). The `ops` free-trial CTA
routes through the **same** onboarding that screens these — it does **not** create an
unscreened fast-path (§ 5.2). The guide recommends; it does not gate eligibility.

### 2.1 Standard OPS vs. paid Setup — the honest boundary (research-grounded)

Source: standard-OPS capability research (00_EXECUTIVE_SUMMARY L90–138, 223–261;
01_PRODUCT_REQUIREMENTS L1118–1148; 03_DATA_ARCHITECTURE permissions; 12_SUBSCRIPTION_MANAGEMENT
L79–136; SPEC/01_BUSINESS_MODEL §2). This is the first time this line is drawn
publicly — **§ 13.3 flags it for Jackson's positioning sign-off.**

**Free + self-serve in standard OPS (NO Setup needed):** 30-day free trial (10 seats),
self-serve signup; all core features with **no feature paywalls** (scheduling, crew,
the 8-stage pipeline CRM, estimates, invoices, catalog, inventory, notes, calendar,
email import, QuickBooks/Sage OAuth connect); and self-serve configuration of pipeline
stage **colors / stale thresholds / follow-up rules / win-probability**, lead sources,
tags, roles (RBAC), catalog, tax — all set by an Admin/Owner in Settings.

**Setup-only (genuinely NOT self-serve):**
1. **Renaming or adding pipeline stages** beyond the built-in eight (the stage *set*
   is a fixed enum — colors/thresholds are tunable, the stage *names/count* are not).
2. **Custom fields** on projects/clients (standard OPS has no custom-fields feature
   at all — repo-grep-verified).
3. **Migrating historical data** across (connecting QuickBooks/Sage *going forward* is
   free OAuth; bringing *years of history* over is Setup-or-up).

Everything else Setup sells is **done-for-you convenience + expertise** (discovery,
workflow analysis, configured-for-you, staging review, recorded walkthrough, 30-day
money-back, polish hours) — valuable, but not a locked capability.

**The two honest lines (the copy traces to these — § 5.2):**
- *OPS:* "If all you need is OPS shaped the way you already work — your colors, your
  follow-up timing, your thresholds, your lead sources, your team and roles, your
  catalog and tax — you don't pay us a cent past your subscription. Start the free
  trial and set it up yourself in an afternoon. The only things you can't switch on
  yourself are renaming/adding pipeline stages and custom fields on your jobs or
  clients — if you need those, that's Setup."
- *Setup:* "Setup is worth it when you want it configured *for* you, or you need the
  two things standard OPS can't self-serve (new/renamed stages, custom fields), or
  you've got history to migrate. If you don't, skip it."

---

## 3. Question set + scoring

### 3.1 The five questions

Each is phrased in the user's own world, never OPS's taxonomy. Roles: **D** =
discriminator (scored), all five are discriminators; no qualifier/personalizer is
included (trade/crew/urgency were cut — they may ride only on the post-result inquiry
form, § 12.7, physically unable to change the verdict — § 3.2 firewall).

**Q1 — `// WHAT YOU NEED` — "What do you actually need OPS to do for you?"** *(D, primary lane-selector, weight 3)*

| id | label | hint | signal |
|---|---|---|---|
| `already_fits` | Run my jobs — it already does what I need | "Scheduling, crew, the pipeline, estimates, invoices, the catalog. The bones are there. I just need it shaped to how I run." | already-exists lane → **ops or setup** (decided by Q3/Q4). **Never auto-Setup.** |
| `build_one` | Build something it doesn't do yet | "A tool, view, or workflow made for my trade that OPS doesn't have today." | **Build** lane (floor). Cannot be demoted by a later self-serve answer. |
| `rebuild` | Rebuild my whole operation on it | "Several custom pieces — and move me off what I'm running now." | **Enterprise** candidate (needs corroboration or guards to Build). |
| `not_sure` | Honestly, not sure — show me where I land | "I just know what I've got isn't working. Point me the right way." | **Defer** — resolves from Q2/Q4/Q5; falls to `ops` if no paid signal. Uncertainty is never monetized. |

*Earns its place:* the only question mapping onto what each outcome IS; selects the
free/Setup lane vs the paid-build lane. The old `configure` answer is now
`already_fits` and is **never auto-Setup** — Q3 + Q4 decide ops vs Setup, killing the
over-route that a 3-question design couldn't avoid.

**Q2 — `// WHAT YOU RUN ON` — "What are you running your business on today?"** *(D, migration axis)*

| id | label | hint | signal |
|---|---|---|---|
| `manual` | Texts, paper, spreadsheets | "Nothing to move over. Just starting fresh." | ops/setup-lean (nothing to migrate). |
| `one_tool` | One main app, plus the usual mess | "Jobber, Housecall Pro, QuickBooks — but I'm fine starting clean." | ops/setup-eligible. **Connecting QB/Sage forward is FREE OAuth — must not inflate the tier.** |
| `heavy_system` | A heavy platform I need to get off of | "ServiceTitan, Buildertrend, AppFolio — years of data and integrations to bring across." | Enterprise +2 (the under-estimator catcher). |

*Earns its place:* the under-estimator catch. Migrating *historical data* is
Setup-or-up and is captured precisely in Q4 (`migrate_data`); `one_tool` stays
ops-eligible so a QuickBooks user isn't punished for a free connection.

**Q3 — `// WHO SETS IT UP` — "Setting it up to fit you — do it yourself, or have it done for you?"** *(D, the OPS-vs-Setup clincher)*

| id | label | hint | signal |
|---|---|---|---|
| `myself` | I'll do it myself — point me at the settings | "Me or my office admin. An afternoon in there is fine." | **ops** (decisive DIY — self-serve config is free; no reason to pay Setup). |
| `for_me` | Do it for me — around how I actually run | "I'd rather someone who knows OPS map it to my business, done right the first time." | **Setup** (decisive done-for-you — exactly what Setup sells). |
| `show_me` | Show me once, then I've got it | "A walkthrough or a template to start from, then I run with it." | leans **ops** (guided self-start; Setup stays the also-door). |

*Earns its place:* the **only** thing separating the free `ops` verdict from paid
Setup when the need is pure self-serve config. The bulk of Setup's $3k is done-for-you
convenience, not locked capability — so the honest fork is *who does it.* Phrased
without shame in either direction. **Only changes the result inside the already-exists
/ no-lock lane.**

**Q4 — `// WHAT IT HAS TO DO` — "To make OPS fit, does any of this have to be true? (Check all that apply.)"** *(D, the capability gate — MULTI-SELECT)*

| id | label | hint | signal |
|---|---|---|---|
| `rename_stages` | My sales stages have different names than the built-in ones | "OPS ships New Lead → Qualifying → Quoting → Quoted → Follow-up → Negotiation → Won/Lost. I need stages it doesn't have — Permit, Rough-In, Final Inspection — added or renamed, not just recolored." | **capability lock → Setup floor.** (Colors/thresholds ARE self-serve; the stage *names* are the boundary.) |
| `custom_fields` | I need to track info OPS has no box for | "Permit #, lot size, HOA, warranty expiry — details on every job or client that aren't standard." | **capability lock → Setup floor.** (Custom fields exist nowhere in standard OPS.) |
| `migrate_data` | My existing data has to come across — not just connect going forward | "Years of jobs, clients, or QuickBooks history I can't lose. Bring it over, not just link from here on." | **capability lock → Setup floor** + structural signal for the Enterprise guard. (Distinct from the free OAuth connect.) |
| `new_module` | A whole feature it doesn't have | "A tool, view, or automation for my trade OPS just doesn't do today." | **Build +3** (catches a custom-module need under-described in Q1). |
| `none` | None of these — just my colors, timing, lists, the usual | "Recolor the pipeline, set my follow-up timing and thresholds, my lead sources, tags, roles, catalog, tax. Nothing exotic." | ops +2, **mutually exclusive** (clears the others). Clears the gate → Q3 decides. |

*Earns its place:* the hard no-misroute backstop. It isolates the **three Setup-only
unlocks** from the free self-serve set, and catches a Build need Q1 under-described.
**Multi-select** because a user can need a custom field AND a renamed stage; a radio
would let the first ops-eligible tap under-route them. `none` is mutually exclusive.
**Interaction exception (§ 5.1, § 11):** Q4 is a checkbox group with an explicit
`CONTINUE` button — exempt from auto-advance; the build chip must not "consistency-fix"
it back to a radio.

**Q5 — `// HOW YOU'RE BUILT` — "How's your operation built?"** *(D, structural corroborator)*

| id | label | hint | signal |
|---|---|---|---|
| `solo` | One trade, one crew | "Just me, or a single tight crew." | ops/setup-lean. |
| `multi_crew` | One trade, a few crews | "Growing, but still one line of work." | neutral (growth alone never inflates the tier). |
| `multi_division` | Multiple trades, divisions, subs, or locations | "Different divisions, subs to manage, or more than one location." | Enterprise +2 (structural corroborator). |

*Earns its place:* second Enterprise corroborator (the guard) and the under-estimator
override. **Critical guard:** `multi_division` does **not** by itself pull a user out
of the free `ops` floor — a multi-division shop that picks `already_fits` + `myself` +
`none` is still standard-OPS self-serve. Structure only escalates *within* the
build/enterprise lane or corroborates Enterprise.

### 3.2 Scoring (deterministic, lane-gated, client-side)

Pure `recommendTier(answers)` → `{ winner, others[], runnerUp, closeCall, guarded,
capabilityGate, diyClincher, structuralSignal, headsUp, driver, scores }`. **Not
pure-additive** — a free outcome can't be expressed as "more points"; it's a **lane
gate** (Q1/Q4) then additive corroboration. Ladder, lowest first: **`ops` < `setup` <
`build` < `enterprise`**; **all tie-breaks resolve to the lower index.** Extends the
Pass-1 logic; keeps every prior guard verbatim.

**Step 0 — signal detection.**
- `capabilityLock` = Q4 contains any of `{rename_stages, custom_fields, migrate_data}`
  (the only things standard OPS can't self-serve). **Master anti-misroute switch: if
  true, `ops` is impossible.**
- `buildSignal` = Q1 = `build_one` **or** Q4 has `new_module`.
- `structuralSignal` = Q2 = `heavy_system` **or** Q5 = `multi_division` **or** Q4 has
  `migrate_data`.
- `diyClincher` = Q3 = `myself`. `capabilityGate` = `capabilityLock`.
- Q4 multi-select: `none` is mutually exclusive (clears others); across checked items,
  **max-commitment wins** (any lock beats any ops-eligible item).

**Step 1 — lane from Q1 (weight-3).** `build_one` → BUILD lane; `rebuild` →
ENTERPRISE-candidate; `already_fits` → ALREADY-EXISTS lane (Step 2); `not_sure` →
defer: `structuralSignal` → ENTERPRISE-candidate, elif `buildSignal` → BUILD, else →
ALREADY-EXISTS. **Hard precedence:** a BUILD/ENTERPRISE lane is **never** demoted to
`ops`/Setup by a self-serve-sounding Q3/Q4. `ops` is reachable **only** from the
already-exists lane.

**Step 2 — already-exists lane → `{ops, setup}`.**
- (a) `capabilityLock` → **SETUP**, `driver` = the lock (custom_fields / custom_stages
  / data_migration). **`ops` forbidden and NOT offered as an also-row** (would promise
  a capability OPS lacks).
- (b) no lock (Q4 = `none`): Q3 = `myself` → **OPS**; `show_me` → **OPS** with
  `closeCall` vs Setup; `for_me` → **SETUP** (a done-for-you *preference*, not a need).
- **Structure does not escalate this lane** — only the Step-4 override does.

**Step 3 — build/enterprise lane → `{build, enterprise}`** (Enterprise-corroboration
guard, verbatim from Pass 1). Start BUILD floor. Promote ENTERPRISE iff Q1 = `rebuild`
**and** `structuralSignal`. Else BUILD, with `guarded = true` when Q1 = `rebuild`
(never sell $18k on ambition alone; the guard is **surfaced**, § 5.2).

**Step 4 — under-estimator override (honest upward).**
- (a) Q2 = `heavy_system` **and** Q5 = `multi_division` → force **ENTERPRISE** (even
  from `already_fits`/`build_one`), `driver` = `migration`.
- (b) **Safety valve:** exactly *one* structural hint (heavy_system OR multi_division
  alone, Q4 = none) in a Step-2 `ops` case → **keep OPS, `headsUp = true`**, attach an
  honest note (§ 5.2) — neither lie nor auto-charge; discovery decides. (`migrate_data`
  already sets `capabilityLock` → handled in Step 2a.)

**Step 5 — point vectors `[ops,setup,build,enterprise]`** (corroboration / tie-break /
runner-up ordering only; the lane gate is authoritative for the winner). Q1:
`already_fits[2,1,0,0]` `build_one[0,0,3,0]` `rebuild[0,0,0,3]` `not_sure[1,0,0,0]`.
Q2: `manual[1,0,0,0]` `one_tool[1,0,0,0]` `heavy_system[0,0,0,2]`. Q3: `myself[3,0,0,0]`
`show_me[1,1,0,0]` `for_me[0,3,0,0]`. Q4 (sum checked): `rename_stages[0,3,0,0]`
`custom_fields[0,3,0,0]` `migrate_data[0,1,0,2]` `new_module[0,0,3,0]` `none[2,0,0,0]`.
Q5: `solo[1,0,0,0]` `multi_crew[0,0,1,0]` `multi_division[0,0,0,2]`.

**Step 6 — suppressions / also-consider.**
- **`ops` win:** suppress build + enterprise; only **Setup** as the quiet "want it done
  for you?" door.
- **Setup win:** `others = [ops, build]`, and surfacing the **free** `ops` option
  **above** the paid one is **mandatory** — UNLESS Setup was forced by `capabilityLock`,
  in which case **do not offer `ops`** (it would promise something OPS can't self-serve).
  Drop `enterprise` on a Setup win with no `structuralSignal`.
- **Build win:** `others = [setup, enterprise]`. **Enterprise win:** `others = [build]`;
  suppress ops/setup.

**Step 7 — close-call** (extended to the `ops`<`setup` seam). `closeCall` = runner-up
within 1pt, not `guarded`, not `capabilityGate`-forced. The ops-vs-setup close call
**always resolves to `ops`** (lower commitment) and nudges **down**: "You can do this
yourself, free — start the trial. Rather we set it up for you? Setup's right here."

**Step 8 — driver (winner-consistent).** `guarded`→`guarded`; elif Setup-by-lock →
`custom_fields` | `custom_stages` | `data_migration`; elif `enterprise` → `migration`
(heavy_system/migrate_data) | `structure` (multi_division) | `multi_modules`; elif
`build` → `new_module` (Q4) | `build_one`; elif Setup (no lock) → `done_for_you`; elif
`ops` → `fits_oob` (already_fits + none + myself) | `guided_self` (show_me) |
`self_serve`.

**Primary-action divergence (§ 5.2):** `ops` → **`START FREE — 30 DAYS`** linking the
existing self-serve onboarding (config-driven URL — **never hardcode `app.opsapp.co`**,
§ 13.1); routes through the same Quebec/regulated screening as normal signup. Paid
outcomes → the inline inquiry form (§ 12.7). The `ops` result presents Setup as a
legitimate, valuable choice — **never a thing to avoid.**

**Personalizer firewall.** `recommendTier()` accepts ONLY the five scored
discriminators. Trade/crew-size/urgency, if ever added, are a separate payload
enriching the lead + copy and are **physically incapable** of changing the winner
(unit test: vary any non-scored field across all values, holding the five fixed →
winner/driver never change).

### 3.3 Worked cases (the honesty test — all four outcomes)

| # | Q1 / Q2 / Q3 / Q4 / Q5 | Result | Driver | Why it's right |
|---|---|---|---|---|
| A | already_fits / manual / myself / [none] / solo | **OPS** | `fits_oob` | Pure free floor. Build/Ent suppressed; only Setup as the quiet also-door. Primary = START FREE, **not** a lead form. The verdict a 3-outcome guide could never produce. |
| B | already_fits / one_tool / myself / [none] / multi_crew | **OPS** | `self_serve` | QuickBooks `one_tool` does **not** inflate the tier (free OAuth). Setup = honest lower-commitment also-door. |
| C | already_fits / manual / myself / [custom_fields] / solo | **SETUP** | `custom_fields` | Capability lock overrides DIY. `ops` forbidden + not offered. Names the reason: custom fields exist nowhere in standard OPS. |
| D | already_fits / one_tool / for_me / [none] / multi_crew | **SETUP** | `done_for_you` | `others[]` **leads with OPS** — "you could do all this yourself for free; Setup is the done-for-you version." Mandatory free-disclosure. |
| E | already_fits / manual / show_me / [none] / solo | **OPS** (closeCall) | `guided_self` | Close-call nudges **down** to the free start, not up to paid. |
| F | build_one / manual / myself / [new_module] / multi_crew | **BUILD** | `new_module` | Hard precedence blocks demotion despite Q3 = myself. Refuses to misroute DOWN. |
| G | already_fits / heavy_system / myself / [none] / multi_division | **ENTERPRISE** | `migration` | Step 4a forces it. Migration overrides DIY exactly as a lock does — refuses to under-sell the lowballing migrating GC. |
| H | already_fits / heavy_system / myself / [none] / solo | **OPS** (`headsUp`) | `fits_oob` | One structural hint only (migrate_data unchecked) → safety valve keeps OPS but surfaces the honest note. Hardest middle case — no lie, no auto-charge. |
| I | rebuild / manual / for_me / [none] / solo | **BUILD** (`guarded`) | `guarded` | Guard fails → Build + surfaced refusal note. $18k guard preserved. |
| J | not_sure / manual / myself / [none] / solo | **OPS** | `fits_oob` | Unsure owner → **free trial**, never a $3k engagement. Uncertainty never monetized. |
| K | rebuild / heavy_system / for_me / [migrate_data] / multi_division | **ENTERPRISE** | `migration` | Ambition + migration + structure all agree. The one place $18k is honest. |
| L | already_fits / one_tool / myself / [migrate_data] / solo | **SETUP** | `data_migration` | Connecting QB forward is free; migrating 3 years of history is Setup-or-up. Not forced to Enterprise (solo, single tool). |

Cases A, H, J prove the guide will send people to the *free* product. C and L prove it
won't wrongly tell a lock-needer "just use OPS." F and G prove it won't misroute down.

---

## 4. Placement

The guide's job is to help a person choose what they need *among the options on this
page*. It belongs welded to the cards, in the same scan moment — not a separate
section, modal, or route.

| # | Variant | Verdict |
|---|---|---|
| 1 | **Entry at the top of `#packages`, expands inline above the cards** | **Recommended.** |
| 2 | Takeover — guide replaces the cards | Rejected: hides the cards from the user who knows; big layout shift. |
| 3 | Dedicated full-width section before Pricing | Rejected: competes with the OPS BOARD; divorces the guide from the cards. |
| 4 | Sticky right-rail helper | Rejected: the right 55% of the desktop viewport is the fixed phone scene. |

A slim tactical entry bar is the first thing inside `#packages`, above the cards.
SSR'd + collapsed (indexable, zero layout shift). `START` expands the guide inline;
the cards stay below. On a paid result, the guide carries its own action **and** the
matching card scrolls into view + takes the highlight. On an `ops` result, the primary
action is the free-trial CTA (no card to highlight; Setup is the quiet also-door).

**Reconcile with the page's hardcoded BUILD defaults.** `SpecPageContent.tsx`
hardcodes `recommended: tier === 'build'` and the board defaults to BUILD. Once the
guide runs, **its result owns "recommended" for the session**: when the winner ≠
`build`, suppress the generic pill and render "YOUR MATCH" on the guided card (§ 12.3).
On an `ops` win, suppress the BUILD pill entirely (no paid tier is "recommended").

**Real desktop layout (corrected).** `#packages` is `lg:w-[55%]` with the phone scene
`fixed right-0 w-[55%]` — ~10% overlap at the right edge. Keep the guide's interactive
content in the left ~720px safe area; the scroll-to-card handoff must clear the phone
(§ 5.3).

---

## 5. Interaction & flow

### 5.1 States

```
[entry bar] → Q1 → Q2 → Q3 → Q4(multi) → Q5 → [result]
     ▲         │    │    │       │        │       │
     └─ START OVER ─┴────┴───────┴────────┘       └─ ‹ BACK (to Q5, answers kept)
                ◄ BACK (Q2–Q5)
```

- **One question at a time, five steps.** Enough to credibly determine the answer
  without becoming a form. Each step: one prompt + its options.
- **Auto-advance on the four single-select questions (Q1, Q2, Q3, Q5)** — hardened for
  the field: ~360–420ms commit hold; suppress commit during a scroll/`touchmove`
  gesture; `‹ BACK` is ≥44px, enabled from Q2, focus to the prior answer; the result
  carries a quiet `‹ BACK` to Q5.
- **Q4 (capability) is the exception — checkbox multi-select with an explicit
  `CONTINUE` button. No auto-advance.** `None of these` is mutually exclusive (checking
  it clears the locks; checking a lock clears `none`). The build chip must not convert
  Q4 to a radio (silent under-route of a lock-needer — § 11).
- **Progress `01 / 05` in mono** — current number `--text`, rest `--text-mute` (a
  contrast step, never accent). No bar, no percent.
- **Back / restart.** `‹ BACK` restores the prior answer; `START OVER` clears all.

### 5.2 The result — a place to ACT (four outcomes)

The result is peak intent. It states the answer plainly (headline + one-sentence
reason + bracketed "because you said X"), then lets the user act *there*.

**Paid outcomes (Setup / Build / Enterprise):** primary action is the inline
pre-contextualized **inquiry form** (`START YOUR {tier}`, § 12.7) — editable context
summary, name/phone/email, a "what do you need?" textarea pre-filled from their
answers, submitting the lead + the full guide payload to `/api/contact` (extended).
Secondary `see the {tier} package ›` scrolls to + highlights the card (§ 5.3). When
`depositsEnabled` flips ON, the primary slot becomes `PAY {tier} DEPOSIT`.

**Setup specifics:** when Setup was **not** forced by a capability lock, the
also-consider **leads with the free `ops` door** (mandatory — "you could do all this
yourself, free; Setup is the done-for-you version"). When Setup **was** forced by a
lock (custom fields / new stages / migration), `ops` is **not** offered, and the
driver names the exact lock. The guard note still renders for a guarded Build.

**`ops` outcome — the free answer.** Headline `OPS`; reason traceable to the § 2.1
*honest_ops_line*, scoped to **exactly** the free self-serve surface — it must **never**
use the unqualified words "stages" or "fields" as things you self-serve:

```
// YOUR MOVE
OPS
▔▔▔
Standard OPS already covers you. Start the 30-day free trial — you (or your office
admin) set your pipeline colors, follow-up timing, stale-deal thresholds, win-odds,
lead sources, tags, team and roles, catalog and tax, yourself, in an afternoon. You
don't pay us a cent past your subscription.
[ everything you need is already in OPS — you just make it yours ]

The only things you can't switch on yourself are renaming or adding pipeline stages
beyond the built-in eight, and custom fields on your jobs or clients — if you ever
need those, that's Setup.            ← mandatory honest carve-out

[ START FREE — 30 DAYS ]             ← PRIMARY (config-driven onboarding URL)
rather we set it up for you? → Setup ← quiet secondary (opens the Setup inquiry form)

‹ BACK        START OVER
```

- The carve-out is **mandatory** — it's the one place "stages"/"fields" appear, stating
  honestly that they're *not* self-serve. Removing it would let the reason over-promise.
- The Setup secondary is offered as legitimate and valuable (traceable to *honest_setup_line*):
  "Two discovery sessions, we map OPS to how your jobs run, deploy to staging for you to
  check, then a recorded walkthrough. $3,000, four milestones, 30-day money-back. The
  done-for-you version of what you'd otherwise do free." It opens the **inquiry form
  pre-set to Setup** — not a separate page.
- `headsUp` note (Step 4b) appends only when the safety valve fired: "One heads-up — if
  it turns out you've got history to move over, that's where Setup earns its keep.
  Start free; we're here if you hit that."
- The free-trial CTA routes through the **same** onboarding that screens Quebec +
  regulated workflows — no eligibility bypass. Fires `tier_guide_trial_started`.

### 5.3 Connection to the cards (paid outcomes only)

Secondary `see the {tier} package ›` and "also consider" rows call `gotoCard(tier)`:
smooth-scroll the card (`block:'start'`+offset on desktop to clear the phone,
`'center'` on mobile), expand it (`expandedTier`), apply the held accent rail + swap
"RECOMMENDED" → "YOUR MATCH" (§ 12.3). The `ops` result has no card handoff (its action
is the free trial). The guide never auto-triggers payment; deposits-ON pre-select is
§ 13.2.

---

## 6. Copy

All strings via `ops-copywriter` (Anti-Pitch — the reader is skeptical every quiz
upsells; the trust hooks are *"we don't default to the expensive one"* and now *"you
might not need to pay us at all"*). Terse, sentence case content / UPPERCASE authority,
`//` and `[bracket]` prefixes, no emoji, no exclamation, numbers in mono.

The result composes from enumerated dictionary strings only (no free-text
interpolation): per-outcome reason, driver clause, guard note / heads-up note, the
`ops` carve-out + Setup-alt, and also-consider lines. The only interpolated tokens are
outcome **names**. **Honesty rule (load-bearing):** the `ops` reason must never imply
self-serve "stages"/"fields"; those words appear only in the carve-out stating they
require Setup (§ 2.1, § 5.2).

---

## 7. Animation choreography

Routed through `animation-studio:animation-architect` → `web-animations`. The guide
**adopts the `SpecOpsBoard.tsx` selection + reduced-motion vocabulary and adds two
guide-specific beats on the same easing curve and durations.** Single easing
`cubic-bezier(0.22,1,0.36,1)` (`theme.animation.easing`), no spring/bounce, durations
from `theme.animation.durations`, Framer Motion (`framer-motion`), `will-change` only
on the actively-animating element.

| Moment | Beat | Motion | Duration |
|---|---|---|---|
| Expand the guide | Entry | Body height `0→auto` + opacity, crisp ease-out. Mirrors `PackageCard` expand. | 350ms |
| Question → question | Transition | Fade + 8px y-slide out/in (`AnimatePresence mode="wait"`). Camera-move, not a cut. Optional direction-aware variant § 13.10. | 200–240ms |
| Option select (Q1/Q2/Q3/Q5) | Discovery+Commitment | Chosen row: 2px **accent** rail + `bg-ops-accent/[0.04]` tint (200ms); siblings dim to 0.4; auto-advance after ~390ms hold. | 200ms + ~390ms |
| Q4 checkbox toggle | Discovery | Box check + row tint on; **no auto-advance** (explicit `CONTINUE`). | 150ms |
| Result reveal | **Achievement (restraint)** | Fade + slide in; the headline's 1px **neutral hairline** (`white/0.12`, not accent) draws L→R. A stamp, not a parade. | 300ms + 500ms |
| Scroll-to-card (paid) | Transition | Smooth-scroll + card expand + held rail. | 350ms |

**Token fidelity (accent = CTA-fill + focus-ring ONLY — DESIGN.md §3):** accent CTAs
are `bg-ops-accent text-white rounded-[3px]` (matching `PackageCard`); the open
container uses `--line` (active cue `white/0.15`, never accent); the progress number is
a contrast step; the underline is a neutral hairline. **No ambient motion** (the board's
LIVE pulse is the page's only ambient motion). **Reduced motion** → instant final state,
opacity-only ≤200ms, underline at full width, `behavior:'auto'` scroll.

---

## 8. Wireframes

### 8.1 Desktop (real `lg:w-[55%]` column, fixed phone overlapping ~10% right)

**Option-row anatomy (canonical two-line stack — block label over block hint, never
inline):** label `--text` 15px; hint `--text-3` 13px, `mt-1`, line-height 1.4; 2px
accent rail + tint when selected, siblings dim 0.4.

**Entry collapsed (SSR):**
```
// PACKAGES
┌──────────────────────────────────────────────────────────────┐
│ // NOT SURE WHICH ONE                                         │
│ We'll tell you which one's yours — or if you even need us. [ START ] │
│ [ five questions · no upsell · no signup ]                   │
└──────────────────────────────────────────────────────────────┘
[ SETUP $750 ] [ BUILD ·RECOMMENDED· $2,125 ] [ ENTERPRISE $4,500 ]   (pill yields to YOUR MATCH / suppressed on OPS)
```

**Single-select question (Q1/Q2/Q3/Q5):**
```
┌──────────────────────────────────────────────────────────────┐
│ // WHAT YOU NEED                                    01 / 05   │
│ What do you actually need OPS to do for you?                 │
│ │▍ Run my jobs — it already does what I need                 │
│ │  Scheduling, crew, the pipeline, estimates… the bones are  │
│ │  there. I just need it shaped to how I run.                │
│ ├─ Build something it doesn't do yet                         │
│ ├─ Rebuild my whole operation on it                          │
│ ├─ Honestly, not sure — show me where I land                 │
│ ‹ BACK                                                       │
└──────────────────────────────────────────────────────────────┘
```

**Q4 — capability gate (MULTI-SELECT + CONTINUE; no auto-advance):**
```
┌──────────────────────────────────────────────────────────────┐
│ // WHAT IT HAS TO DO                                04 / 05   │
│ To make OPS fit, does any of this have to be true?           │
│ [✓] My sales stages have different names than the built-in   │
│ [ ] I need to track info OPS has no box for                  │
│ [ ] My existing data has to come across — not just connect   │
│ [ ] A whole feature it doesn't have                          │
│ [ ] None of these — just my colors, timing, lists, the usual │   (mutually exclusive)
│ ‹ BACK                                          [ CONTINUE ]  │
└──────────────────────────────────────────────────────────────┘
```

**Result — `ops` (the free answer):**
```
┌──────────────────────────────────────────────────────────────┐
│ // YOUR MOVE                                                 │
│ OPS   ▔▔▔                                                     │
│ Standard OPS already covers you. Start the 30-day free trial │
│ — set your colors, follow-up timing, thresholds, lead        │
│ sources, roles, catalog and tax yourself, in an afternoon.   │
│ You don't pay us a cent past your subscription.              │
│ [ everything you need is already in OPS — you just make it yours ] │
│ The only things you can't switch on yourself are new/renamed │
│ pipeline stages and custom fields — if you need those, Setup.│
│ [ START FREE — 30 DAYS ]                                     │
│ rather we set it up for you? → Setup                         │
│ ‹ BACK        START OVER                                     │
└──────────────────────────────────────────────────────────────┘
```

**Result — paid (Setup/Build/Enterprise):** as Pass 1 — headline + reason + driver,
`[ START YOUR {tier} ]` primary (inline inquiry form), `see the {tier} package ›`
secondary, also-consider (Setup win leads with the free OPS door unless lock-forced),
`‹ BACK` / `START OVER`.

### 8.2 Mobile (<768px)

Full-bleed single column; entry CTA full-width; two-line option rows ≥44px; progress
top-right. Q4 is a stacked checkbox list with a full-width `CONTINUE`. *Sequential vs.
single-combined-screen is an open A/B (§ 13.9) — but with five questions the combined
screen is a taller panel; sequential is the safer default.*

---

## 9. SEO / SSR posture

Below the fold, text-only, no images/fonts → no LCP impact. The entry bar + a static
"how to choose" summary (now four outcomes: *"Most people just need OPS itself — start
free. Setup configures it for you; Build adds one custom module; Enterprise rebuilds +
migrates."*) are **SSR'd** in the collapsed container (indexable, JS-off fallback),
mirroring the FAQ `<details>` pattern. The questionnaire hydrates as progressive
enhancement. Keywords earned: "do I need [setup/custom software]," the four outcomes,
and the named incumbents in Q2/Q4. No new JSON-LD required.

---

## 10. i18n — the full key set

New namespace `guide.*` in **both** `en/spec.json` and `es/spec.json`, flat dot-keys,
option arrays of `{id,label,hint}` (ids shared across locales — the scoring keys on
them). Added in the same commit as the § 12.0 fix, behind the `t()` raw-key CI canary.
**The 4th outcome + 5 questions expand the key set below — every key in both locales.**

### 10.1 English (`en/spec.json`)

| Key | Value |
|---|---|
| `guide.entry.label` | `// NOT SURE WHICH ONE` |
| `guide.entry.headline` | `We'll tell you which one's yours — or if you even need us.` |
| `guide.entry.subnote` | `[ five questions · no upsell · no signup ]` |
| `guide.entry.cta` | `START` |
| `guide.q1.kicker` | `// WHAT YOU NEED` |
| `guide.q1.prompt` | `What do you actually need OPS to do for you?` |
| `guide.q1.options` | `[ {id:"already_fits", label:"Run my jobs — it already does what I need", hint:"Scheduling, crew, the pipeline, estimates, invoices, the catalog. The bones are there. I just need it shaped to how I run."}, {id:"build_one", label:"Build something it doesn't do yet", hint:"A tool, view, or workflow made for my trade that OPS doesn't have today."}, {id:"rebuild", label:"Rebuild my whole operation on it", hint:"Several custom pieces — and move me off what I'm running now."}, {id:"not_sure", label:"Honestly, not sure — show me where I land", hint:"I just know what I've got isn't working. Point me the right way."} ]` |
| `guide.q2.kicker` | `// WHAT YOU RUN ON` |
| `guide.q2.prompt` | `What are you running your business on today?` |
| `guide.q2.options` | `[ {id:"manual", label:"Texts, paper, spreadsheets", hint:"Nothing to move over. Just starting fresh."}, {id:"one_tool", label:"One main app, plus the usual mess", hint:"Jobber, Housecall Pro, QuickBooks — but I'm fine starting clean."}, {id:"heavy_system", label:"A heavy platform I need to get off of", hint:"ServiceTitan, Buildertrend, AppFolio — years of data and integrations to bring across."} ]` |
| `guide.q3.kicker` | `// WHO SETS IT UP` |
| `guide.q3.prompt` | `Setting it up to fit you — do it yourself, or have it done for you?` |
| `guide.q3.options` | `[ {id:"myself", label:"I'll do it myself — point me at the settings", hint:"Me or my office admin. An afternoon in there is fine."}, {id:"for_me", label:"Do it for me — around how I actually run", hint:"I'd rather someone who knows OPS map it to my business, done right the first time."}, {id:"show_me", label:"Show me once, then I've got it", hint:"A walkthrough or a template to start from, then I run with it."} ]` |
| `guide.q4.kicker` | `// WHAT IT HAS TO DO` |
| `guide.q4.prompt` | `To make OPS fit, does any of this have to be true?` |
| `guide.q4.subprompt` | `[ check all that apply ]` |
| `guide.q4.continue` | `CONTINUE` |
| `guide.q4.options` | `[ {id:"rename_stages", label:"My sales stages have different names than the built-in ones", hint:"OPS ships New Lead → Qualifying → Quoting → Quoted → Follow-up → Negotiation → Won/Lost. I need stages it doesn't have — Permit, Rough-In, Final Inspection — added or renamed, not just recolored."}, {id:"custom_fields", label:"I need to track info OPS has no box for", hint:"Permit #, lot size, HOA, warranty expiry — details on every job or client that aren't standard."}, {id:"migrate_data", label:"My existing data has to come across — not just connect going forward", hint:"Years of jobs, clients, or QuickBooks history I can't lose. Bring it over, not just link from here on."}, {id:"new_module", label:"A whole feature it doesn't have", hint:"A tool, view, or automation for my trade OPS just doesn't do today."}, {id:"none", label:"None of these — just my colors, timing, lists, the usual", hint:"Recolor the pipeline, set my follow-up timing and thresholds, my lead sources, tags, roles, catalog, tax. Nothing exotic."} ]` |
| `guide.q5.kicker` | `// HOW YOU'RE BUILT` |
| `guide.q5.prompt` | `How's your operation built?` |
| `guide.q5.options` | `[ {id:"solo", label:"One trade, one crew", hint:"Just me, or a single tight crew."}, {id:"multi_crew", label:"One trade, a few crews", hint:"Growing, but still one line of work."}, {id:"multi_division", label:"Multiple trades, divisions, subs, or locations", hint:"Different divisions, subs to manage, or more than one location."} ]` |
| `guide.result.label` | `// YOUR MOVE` |
| `guide.result.ops.reason` | `Standard OPS already covers you. Start the 30-day free trial — you (or your office admin) set your pipeline colors, follow-up timing, stale-deal thresholds, win-odds, lead sources, tags, team and roles, catalog and tax, yourself, in an afternoon. You don't pay us a cent past your subscription.` |
| `guide.result.ops.carveout` | `The only things you can't switch on yourself are renaming or adding pipeline stages beyond the built-in eight, and custom fields on your jobs or clients — if you ever need those, that's Setup.` |
| `guide.result.ops.setupAlt` | `Rather we set it up around your workflow for you? That's Setup — two discovery sessions, we map OPS to how your jobs run, deploy it to staging for you to check, then a recorded walkthrough. $3,000, four milestones, 30-day money-back. The done-for-you version of what you'd otherwise do free.` |
| `guide.result.ops.headsUp` | `One heads-up — if it turns out you've got history to move over, that's where Setup earns its keep. Start free; we're here if you hit that.` |
| `guide.result.setup.reason` | `We shape OPS around the way you already work — your pipeline, your stages, your fields, dialed to your business. Nothing for you to learn. Just OPS, built to fit.` |
| `guide.result.build.reason` | `We build the one thing you're missing — a custom module for your trade, on iOS and web, wired straight into your live OPS.` |
| `guide.result.enterprise.reason` | `Multiple custom modules, your data moved off the old system, your tools integrated. Your whole operation, rebuilt on OPS.` |
| `guide.driver.fits_oob` | `[ everything you need is already in OPS — you just make it yours ]` |
| `guide.driver.guided_self` | `[ a quick walkthrough and you're running — nothing to build or buy ]` |
| `guide.driver.self_serve` | `[ you'd rather set it up yourself — and it's all free to do ]` |
| `guide.driver.done_for_you` | `[ you'd rather we set it up for you — that's exactly what Setup is ]` |
| `guide.driver.custom_fields` | `[ you need to track details OPS has no box for — that's Setup ]` |
| `guide.driver.custom_stages` | `[ you need pipeline stages OPS doesn't ship — that's Setup ]` |
| `guide.driver.data_migration` | `[ you've got history to bring across — that's Setup, not a free connect ]` |
| `guide.driver.build_one` | `[ you need one specific thing built — not the whole operation ]` |
| `guide.driver.new_module` | `[ a whole feature OPS doesn't have — that's a custom build ]` |
| `guide.driver.migration` | `[ you're moving off a system that has to come with you ]` |
| `guide.driver.structure` | `[ you're running more than one trade, division, or location ]` |
| `guide.driver.multi_modules` | `[ several custom pieces — that's the full rebuild ]` |
| `guide.driver.guarded` | `[ you want the whole thing rebuilt — we start with one module and prove it ]` |
| `guide.result.guardNote` | `You said rebuild — but with nothing to migrate and a lean crew, Enterprise would be overkill. We start with Build and prove it. If discovery shows it's bigger, we move up.` |
| `guide.result.ctaTrial` | `START FREE — 30 DAYS` |
| `guide.result.ctaPrimary` | `START YOUR {tier}` *(opens the inline inquiry form, § 12.7)* |
| `guide.result.ctaPrimaryDeposit` | `PAY {tier} DEPOSIT` *(only when depositsEnabled is ON)* |
| `guide.result.ctaSecondary` | `See the {tier} package ›` |
| `guide.result.opsSetupLink` | `rather we set it up for you? → Setup` |
| `guide.inquiry.heading` | `// START YOUR {tier}` |
| `guide.inquiry.summary.setup` | `Setting OPS up around how you already work, done for you.` |
| `guide.inquiry.summary.build` | `A custom module for your trade, built on OPS.` |
| `guide.inquiry.summary.enterprise` | `Your operation rebuilt on OPS — modules, migration, integrations.` |
| `guide.inquiry.name` | `Name` |
| `guide.inquiry.phone` | `Phone` |
| `guide.inquiry.email` | `Email` |
| `guide.inquiry.message` | `What do you need?` |
| `guide.inquiry.prefill.setup` | `I want OPS set up around my workflow. Here's how my jobs run:` |
| `guide.inquiry.prefill.build` | `I need a custom module for my trade. Here's what it has to do:` |
| `guide.inquiry.prefill.enterprise` | `I want to move my operation onto OPS. Here's what I'm running and what I need:` |
| `guide.inquiry.submit` | `SEND IT` |
| `guide.inquiry.sending` | `SENDING…` |
| `guide.inquiry.success` | `Got it. Jackson will reach out about your {tier}.` |
| `guide.inquiry.error` | `// SEND FAILED — try again, or email hello@opsapp.co` |
| `guide.result.alsoLabel` | `ALSO CONSIDER` |
| `guide.also.ops` | `you can set all this up yourself, free — start the trial.` |
| `guide.also.setup` | `if you'd rather we configure it around your workflow for you.` |
| `guide.also.build` | `if one custom module would close most of the gap.` |
| `guide.also.enterprise` | `if discovery shows you need more than one module, or a migration.` |
| `guide.result.closeCall` | `You can do this yourself, free — start the trial. Rather we set it up for you? Setup's right here.` |
| `guide.back` | `‹ BACK` |
| `guide.restart` | `START OVER` |
| `guide.a11y.progress` | `Question {n} of {total}` |
| `guide.a11y.recommended` | `Your match: {outcome}` |

### 10.2 Spanish (`es/spec.json`) — faithful mirror

Same `id`s, `//` and `[ ]` preserved, tactical register. Native-voice polish welcome;
keys + meaning locked.

| Key | Value |
|---|---|
| `guide.entry.label` | `// ¿CUÁL ES LA TUYA?` |
| `guide.entry.headline` | `Te decimos cuál es la tuya — o si siquiera nos necesitas.` |
| `guide.entry.subnote` | `[ cinco preguntas · sin upsell · sin registro ]` |
| `guide.entry.cta` | `EMPEZAR` |
| `guide.q1.kicker` | `// QUÉ NECESITAS` |
| `guide.q1.prompt` | `¿Qué necesitas de verdad que haga OPS por ti?` |
| `guide.q1.options` | `[ {id:"already_fits", label:"Correr mis trabajos — ya hace lo que necesito", hint:"Agenda, cuadrilla, el pipeline, estimados, facturas, el catálogo. La base está. Solo necesito ajustarlo a cómo trabajo."}, {id:"build_one", label:"Construir algo que todavía no hace", hint:"Una herramienta o flujo para mi oficio que OPS no tiene hoy."}, {id:"rebuild", label:"Reconstruir toda mi operación en él", hint:"Varias piezas a medida — y migrarme de lo que uso ahora."}, {id:"not_sure", label:"La verdad, no sé — muéstrame dónde caigo", hint:"Solo sé que lo que tengo no funciona. Oriéntame."} ]` |
| `guide.q2.kicker` | `// CON QUÉ TRABAJAS` |
| `guide.q2.prompt` | `¿Con qué trabajas hoy?` |
| `guide.q2.options` | `[ {id:"manual", label:"Mensajes, papel, hojas de cálculo", hint:"Nada que migrar. Empezando de cero."}, {id:"one_tool", label:"Una app principal, más el desorden", hint:"Jobber, Housecall Pro, QuickBooks — pero puedo empezar limpio."}, {id:"heavy_system", label:"Una plataforma pesada de la que necesito salir", hint:"ServiceTitan, Buildertrend, AppFolio — años de datos e integraciones que migrar."} ]` |
| `guide.q3.kicker` | `// QUIÉN LO CONFIGURA` |
| `guide.q3.prompt` | `Configurarlo a tu medida — ¿lo haces tú, o te lo hacemos?` |
| `guide.q3.options` | `[ {id:"myself", label:"Lo hago yo — muéstrame los ajustes", hint:"Yo o mi administrador. Una tarde ahí me alcanza."}, {id:"for_me", label:"Háganmelo — según cómo trabajo de verdad", hint:"Prefiero que alguien que conoce OPS lo ajuste a mi negocio, bien a la primera."}, {id:"show_me", label:"Muéstrenme una vez y sigo solo", hint:"Un recorrido o una plantilla para arrancar, y yo sigo."} ]` |
| `guide.q4.kicker` | `// QUÉ TIENE QUE HACER` |
| `guide.q4.prompt` | `Para que OPS encaje, ¿algo de esto tiene que ser cierto?` |
| `guide.q4.subprompt` | `[ marca todo lo que aplique ]` |
| `guide.q4.continue` | `CONTINUAR` |
| `guide.q4.options` | `[ {id:"rename_stages", label:"Mis etapas de venta tienen otros nombres que las de fábrica", hint:"OPS trae Nuevo → Calificando → Cotizando → Cotizado → Seguimiento → Negociación → Ganado/Perdido. Necesito etapas que no tiene — Permiso, Obra Gris, Inspección Final — agregadas o renombradas, no solo recoloreadas."}, {id:"custom_fields", label:"Necesito registrar datos para los que OPS no tiene casilla", hint:"# de permiso, tamaño de lote, HOA, vencimiento de garantía — datos de cada trabajo o cliente que no son estándar."}, {id:"migrate_data", label:"Mis datos actuales tienen que venir — no solo conectar de aquí en adelante", hint:"Años de trabajos, clientes o historial de QuickBooks que no puedo perder. Traerlo, no solo enlazarlo."}, {id:"new_module", label:"Una función entera que no tiene", hint:"Una herramienta o automatización para mi oficio que OPS no hace hoy."}, {id:"none", label:"Nada de esto — solo mis colores, tiempos, listas, lo normal", hint:"Recolorear el pipeline, mis tiempos de seguimiento y umbrales, fuentes de leads, etiquetas, roles, catálogo, impuestos. Nada exótico."} ]` |
| `guide.q5.kicker` | `// CÓMO ESTÁS ARMADO` |
| `guide.q5.prompt` | `¿Cómo está armada tu operación?` |
| `guide.q5.options` | `[ {id:"solo", label:"Un oficio, una cuadrilla", hint:"Solo yo, o una cuadrilla."}, {id:"multi_crew", label:"Un oficio, varias cuadrillas", hint:"Creciendo, pero todavía una línea de trabajo."}, {id:"multi_division", label:"Varios oficios, divisiones, subs o ubicaciones", hint:"Distintas divisiones, subcontratistas, o más de una ubicación."} ]` |
| `guide.result.label` | `// TU MOVIDA` |
| `guide.result.ops.reason` | `OPS estándar ya te cubre. Empieza la prueba gratis de 30 días — tú (o tu administrador) configuras los colores de tu pipeline, tiempos de seguimiento, umbrales, probabilidad de cierre, fuentes de leads, etiquetas, equipo y roles, catálogo e impuestos, tú mismo, en una tarde. No nos pagas ni un peso más allá de tu suscripción.` |
| `guide.result.ops.carveout` | `Lo único que no puedes activar tú son renombrar o agregar etapas de pipeline más allá de las ocho de fábrica, y campos personalizados en tus trabajos o clientes — si algún día los necesitas, eso es Setup.` |
| `guide.result.ops.setupAlt` | `¿Prefieres que te lo configuremos según tu flujo? Eso es Setup — dos sesiones de descubrimiento, mapeamos OPS a cómo corren tus trabajos, lo dejamos en staging para que lo revises, y un recorrido grabado. $3,000, cuatro pagos, garantía de 30 días. La versión hecha-para-ti de lo que harías gratis.` |
| `guide.result.ops.headsUp` | `Un aviso — si resulta que tienes historial que mover, ahí es donde Setup vale la pena. Empieza gratis; estamos aquí si llegas a eso.` |
| `guide.result.setup.reason` | `Ajustamos OPS a tu forma de trabajar — tu pipeline, tus etapas, tus campos, a la medida de tu negocio. Nada que aprender. Solo OPS, hecho a tu medida.` |
| `guide.result.build.reason` | `Construimos lo único que te falta — un módulo a medida para tu oficio, en iOS y web, conectado directo a tu OPS.` |
| `guide.result.enterprise.reason` | `Varios módulos a medida, tus datos migrados del sistema viejo, tus herramientas integradas. Toda tu operación, reconstruida en OPS.` |
| `guide.driver.fits_oob` | `[ todo lo que necesitas ya está en OPS — solo lo haces tuyo ]` |
| `guide.driver.guided_self` | `[ un recorrido rápido y estás corriendo — nada que construir ni comprar ]` |
| `guide.driver.self_serve` | `[ prefieres configurarlo tú — y todo es gratis de hacer ]` |
| `guide.driver.done_for_you` | `[ prefieres que te lo configuremos — eso es exactamente Setup ]` |
| `guide.driver.custom_fields` | `[ necesitas registrar datos para los que OPS no tiene casilla — eso es Setup ]` |
| `guide.driver.custom_stages` | `[ necesitas etapas de pipeline que OPS no trae — eso es Setup ]` |
| `guide.driver.data_migration` | `[ tienes historial que traer — eso es Setup, no una conexión gratis ]` |
| `guide.driver.build_one` | `[ necesitas una cosa específica construida — no toda la operación ]` |
| `guide.driver.new_module` | `[ una función entera que OPS no tiene — eso es un build a medida ]` |
| `guide.driver.migration` | `[ estás saliendo de un sistema que tiene que venir contigo ]` |
| `guide.driver.structure` | `[ manejas más de un oficio, división o ubicación ]` |
| `guide.driver.multi_modules` | `[ varias piezas a medida — esa es la reconstrucción completa ]` |
| `guide.driver.guarded` | `[ quieres reconstruirlo todo — empezamos con un módulo y lo probamos ]` |
| `guide.result.guardNote` | `Dijiste reconstruir — pero sin nada que migrar y con una cuadrilla, Enterprise sería demasiado. Empezamos con Build y lo probamos. Si discovery muestra que es más grande, subimos.` |
| `guide.result.ctaTrial` | `EMPIEZA GRATIS — 30 DÍAS` |
| `guide.result.ctaPrimary` | `EMPIEZA TU {tier}` |
| `guide.result.ctaPrimaryDeposit` | `PAGAR DEPÓSITO {tier}` |
| `guide.result.ctaSecondary` | `Ver el paquete {tier} ›` |
| `guide.result.opsSetupLink` | `¿prefieres que te lo configuremos? → Setup` |
| `guide.inquiry.heading` | `// EMPIEZA TU {tier}` |
| `guide.inquiry.summary.setup` | `Configurar OPS según cómo ya trabajas, hecho para ti.` |
| `guide.inquiry.summary.build` | `Un módulo a medida para tu oficio, sobre OPS.` |
| `guide.inquiry.summary.enterprise` | `Tu operación reconstruida en OPS — módulos, migración, integraciones.` |
| `guide.inquiry.name` | `Nombre` |
| `guide.inquiry.phone` | `Teléfono` |
| `guide.inquiry.email` | `Correo` |
| `guide.inquiry.message` | `¿Qué necesitas?` |
| `guide.inquiry.prefill.setup` | `Quiero OPS configurado según mi flujo. Así corren mis trabajos:` |
| `guide.inquiry.prefill.build` | `Necesito un módulo a medida para mi oficio. Esto es lo que tiene que hacer:` |
| `guide.inquiry.prefill.enterprise` | `Quiero mover mi operación a OPS. Esto es lo que uso y lo que necesito:` |
| `guide.inquiry.submit` | `ENVIAR` |
| `guide.inquiry.sending` | `ENVIANDO…` |
| `guide.inquiry.success` | `Listo. Jackson te contactará sobre tu {tier}.` |
| `guide.inquiry.error` | `// FALLÓ EL ENVÍO — intenta de nuevo, o escribe a hello@opsapp.co` |
| `guide.result.alsoLabel` | `TAMBIÉN CONSIDERA` |
| `guide.also.ops` | `puedes configurar todo esto tú mismo, gratis — empieza la prueba.` |
| `guide.also.setup` | `si prefieres que lo configuremos según tu flujo por ti.` |
| `guide.also.build` | `si un módulo a medida cubriría casi todo.` |
| `guide.also.enterprise` | `si discovery muestra que necesitas más de un módulo, o una migración.` |
| `guide.result.closeCall` | `Puedes hacer esto tú mismo, gratis — empieza la prueba. ¿Prefieres que te lo configuremos? Setup está aquí mismo.` |
| `guide.back` | `‹ ATRÁS` |
| `guide.restart` | `EMPEZAR DE NUEVO` |
| `guide.a11y.progress` | `Pregunta {n} de {total}` |
| `guide.a11y.recommended` | `Tu opción: {outcome}` |

---

## 11. Accessibility

- **Semantics.** Single-select questions (Q1/Q2/Q3/Q5) are `radiogroup`s
  (`aria-label` = prompt), options `role="radio"` + `aria-checked`, arrow-key nav,
  Space/Enter selects (and auto-advances). **Q4 is a `group` of native checkboxes**
  with an explicit `CONTINUE` button — Tab/Space per box, no auto-advance; `none`
  toggles clear the lock boxes and vice-versa, announced via `aria-live`. The entry
  bar is a `button` with `aria-expanded`/`aria-controls`.
- **Focus ring (mandatory accent — DESIGN.md §9/§15):** `:focus-visible` →
  `outline:1.5px solid var(--ops-accent); outline-offset:2px` on every interactive
  element (entry, options, checkboxes, `CONTINUE`, result CTAs, also-rows, `BACK`,
  `START OVER`, the OPS free-trial CTA + Setup link).
- **Focus management.** Expand → first option of Q1. Advance → first option/checkbox of
  the next question. `‹ BACK` → prior answer. Result → result heading (`tabindex=-1`);
  result `‹ BACK` → Q5.
- **Announce.** Progress via `guide.a11y.progress`; the outcome via `aria-live="polite"`
  using `guide.a11y.recommended` ("Your match: OPS").
- **Never color-alone** (rail + `aria-checked` + dim). **Contrast** via the `theme`
  ladder. **Field-mis-tap hardening** per § 5.1. **Reduced motion** per § 7. **≥44px**
  targets. **Keyboard-only** completes the flow including the Q4 checkbox group →
  `CONTINUE`.

---

## 12. Implementation plan

### 12.0 Hard precondition — base-dictionary reconciliation (BLOCKER)

Before any `guide.*` keys land, fix the Phase-1 `spec.json` drift: the committed
`en/spec.json` is missing `startFrom`, `headlineSub`, `milestoneAmount`,
`packages.milestones.*` (the keys `SpecPageContent.tsx`/`PackageCard.tsx` read) while
still carrying stale `packages.<tier>.price`/`.deposit` + "50%" copy — so the cards the
guide points at render raw keys in prod today. Restore the missing keys + strip the
stale ones in **both** locales, verified by a `t()` raw-key CI canary. Separate
base-page hygiene; coordinate with sibling WIP, don't stomp parallel edits.

### 12.1 Pure logic module — `src/lib/spec/tier-guide.ts` (new)

```ts
export type Outcome = 'ops' | 'setup' | 'build' | 'enterprise';
export type Q1 = 'already_fits' | 'build_one' | 'rebuild' | 'not_sure';
export type Q2 = 'manual' | 'one_tool' | 'heavy_system';
export type Q3 = 'myself' | 'for_me' | 'show_me';
export type Q4 = 'rename_stages' | 'custom_fields' | 'migrate_data' | 'new_module' | 'none';
export type Q5 = 'solo' | 'multi_crew' | 'multi_division';
export interface GuideAnswers { need: Q1; stack: Q2; hands: Q3; caps: Q4[]; shape: Q5 }
export interface GuideResult {
  winner: Outcome;
  others: Outcome[];           // §3.2.6 suppression rules
  runnerUp: Outcome | null;
  closeCall: boolean;
  guarded: boolean;            // Enterprise→Build guard
  capabilityGate: boolean;     // Setup forced by a lock (→ no ops also-row)
  diyClincher: boolean;        // Q3 = myself
  structuralSignal: boolean;
  headsUp: boolean;            // Step 4b safety valve
  driver: 'fits_oob'|'guided_self'|'self_serve'|'done_for_you'|'custom_fields'|'custom_stages'|'data_migration'|'build_one'|'new_module'|'migration'|'structure'|'multi_modules'|'guarded';
  scores: Record<Outcome, number>;
}
export function recommendTier(a: GuideAnswers): GuideResult;  // §3.2 Steps 0–8
```

Ship `__tests__/tier-guide.test.ts` covering all §3.3 cases A–L **plus**: every
capability-lock forbids `ops`; `one_tool` never inflates the tier; the lane
hard-precedence (no demotion to ops/setup from a self-serve Q3/Q4); the Step-4a force
and Step-4b safety valve; the close-call resolves to `ops`; and the **personalizer
firewall** (any non-scored field, varied, never changes the winner).

### 12.2 Components — `src/components/spec/tier-guide/` (new)

`SpecTierGuide.tsx` (state + flow), `GuideQuestion.tsx` (single-select, auto-advance),
`GuideCapabilityQuestion.tsx` (**Q4 checkbox group + CONTINUE, mutually-exclusive
`none`**), `GuideResult.tsx` (four-outcome result — `ops` branch renders the free-trial
CTA + carve-out + Setup link; paid branch renders the inquiry form + card-scroll),
`GuideInquiry.tsx` (§ 12.7), `tier-guide-copy.ts` (the `t(dict,…)` assembly). Small,
bounded, presentational children; state only in the container.

### 12.3 Wiring into the page

Render `<SpecTierGuide>` at the top of `SpecPricing`. On a **paid** `onRecommend`:
`setExpandedTier` + `highlightTier` + scroll (desktop `block:'start'`+offset) and apply
the pill override (`PackageCard` gets `highlighted?` + `matchLabel?`; suppress the
hardcoded BUILD `recommended` pill when `guidedTier !== 'build'`; **suppress entirely on
an `ops` win** — no paid tier is "recommended"). On an **`ops`** result there is no card
handoff. Screenshot-verify the desktop scroll clears the fixed phone.

### 12.4 i18n

Add the full § 10 key set (four outcomes, five questions) to `en` + `es` in one commit,
after § 12.0, behind the raw-key canary.

### 12.5 Analytics

Client-side `trackMarketingEvent` (gtag + Vercel), no PII. The inquiry submit is the
one server touch (§ 12.7).

| Event | When | Properties |
|---|---|---|
| `tier_guide_viewed` | entry bar in viewport (once) | `{ locale }` — START denominator |
| `tier_guide_started` | `START` clicked | `{ locale }` |
| `tier_guide_answered` | each select (Q4 fires on `CONTINUE` with the array) | `{ step, question_id, option_id(s) }` |
| `tier_guide_completed` | result shown | `{ recommended_outcome ∈ {ops,setup,build,enterprise}, capability_gate, diy_clincher, heads_up, guarded, close_call, driver }` |
| `tier_guide_trial_started` | `ops` free-trial CTA clicked | `{ driver, heads_up }` |
| `tier_guide_inquiry_opened` / `_submitted` | paid primary CTA / form submit | `{ recommended_tier, driver, … , source:'tier_guide' }` |
| `tier_guide_card_opened` | secondary card-scroll / also-row | `{ from_tier, to_tier }` |

**Success metric:** the split funnel — `ops` completions → `tier_guide_trial_started`
(free-signup intent), paid completions → `tier_guide_inquiry_submitted` (later
→ `stripe_checkout_completed`). `tier_guide_completed` count alone is **vanity**. The
`recommended_outcome` distribution is itself a signal: a healthy honest guide sends a
real share to `ops`.

### 12.6 Build-complexity estimate

**Moderate, one focused session for the guide** + the separate § 12.0 dictionary fix +
the § 12.7 `/api/contact` extension (small). The 4-outcome lane-gated scorer is ~120
lines of pure TS + a thorough test suite (the routing guards are the risk surface — test
them hard). Q4's multi-select component is the one genuinely new UI pattern; everything
else reuses existing selection/card/motion patterns.

### 12.7 Inquiry submission — the one server touch (reuses existing backend)

Paid results submit the inline inquiry via the existing `POST /api/contact` →
`contact_messages` (+ newsletter upsert). **Extend, don't rebuild:** accept optional
`{ phone, company?, tier, guide:{need,stack,hands,caps,shape,driver}, source:'tier_guide' }`;
store the context in a new `metadata jsonb` column (schema change → mirror migration to
`migrations/`, update `03_DATA_ARCHITECTURE.md`, verify the live table via Supabase MCP
first); notify Jackson via the existing `notifications.ts`/email-outbox path tagged
`source:tier_guide`; `GuideInquiry.tsx` mirrors `ContactForm.tsx` styling + states,
pre-fills from `guide.inquiry.prefill.<tier>`, confirms inline. The `ops` outcome does
**not** hit this route — it links the free self-serve onboarding.

---

## 13. Open questions for Jackson

The capability research surfaced things only Jackson can ratify — the first four are
**new and gating for the `ops` copy:**

1. **Self-serve signup URL is unconfirmed.** The bible documents the onboarding flow +
   internal routes but no canonical public signup URL (`app.opsapp.co` is **not** in the
   bible). The `ops` free-trial CTA must read the URL from config — **what is the real
   production signup URL?** (The build must not hardcode it.)
2. **Sign off the public OPS-vs-Setup boundary (§ 2.1).** This is the *first time* OPS
   draws the "free self-serve (colors/timing/thresholds/win-odds/lead sources/tags/
   roles/catalog/tax) vs. Setup-only (new/renamed stages, custom fields, data migration)"
   line publicly. The guide encodes it in Q4 + the `ops` carve-out. **Is this how you
   want it positioned?** (It will divert some Setup sales into the free trial — by
   design.)
3. **Custom fields = Setup-only — confirm nothing in-flight changes that.** Repo-grep
   confirms standard OPS has no custom-fields feature today; the honest line is "only via
   Setup." Confirm no self-serve custom-fields feature is about to ship.
4. **"Up to 3 custom configurations" — firm or approximate?** §2 of the canonical SPEC
   model says "custom pipeline stages + custom fields" without a number; the tier-guide
   summary said "up to 3." Confirm the published number.
5. **When deposits flip ON, pre-select the tier into Stripe?** *Rec:* yes — the guide
   already knows it; never auto-charge.
6. **Soft regulated-workflow nudge on a Build/Enterprise result whose described module
   sounds regulated?** *Rec:* keep eligibility downstream; the free-trial path already
   routes through the same screening.
7. **Entry-bar prominence + a skip affordance** (slim payoff-led bar vs. louder; a
   "skip — show the packages" link). *Rec:* slim bar + skip link.
8. **Verify Q5 is load-bearing** before build: generate the full Q1×Q2×Q3×Q4×Q5 truth
   table; confirm Q5 (structure) flips the result on a non-trivial count of paths not
   already covered by Q2/Q4. *Rec:* run it; keep Q5 if it earns it, else fold into Q2.
9. **Mobile: sequential (rec) vs. single combined screen** — A/B; with five questions a
   combined screen is a tall panel, so sequential is the safer default.
10. **Answer-derived noun in the result + direction-aware transitions** — both i18n-safe
    craft upgrades; optional for v1.

**Considered and rejected:** gating the build behind deposits ON (ship now as
qualification + the now-instant free-trial path, gated only on § 12.0); stripping the
progress counter / underline as "quiz tells" (on-brand restraint — the real issue was
accent *hue*, recolored); adding a trade/crew/urgency *scored* question (cut — it would
be padding and risks misrouting; rides only on the inquiry form, firewalled from the
score).

---

## 14. Confirmation of scope

- No production code written; no shipped `/spec` component, route, dictionary, or `lib`
  file modified. Only this design doc + the non-production prototype under `specs/`.
- No flags flipped, nothing deployed, no `git push`.
- Reuses the existing `/spec` composition, interaction/motion/token/i18n patterns, and
  the existing `/api/contact` backend (extended).
- The honest framing it must ship under: a **qualification + honest-routing** feature —
  it sends genuinely-fit prospects to paid SPEC *and* genuinely-unfit ones to the free
  trial. Real conversion proof arrives once deposits are ON and § 12.0 lands; the `ops`
  free-trial path is the one honestly-instant outcome today.
