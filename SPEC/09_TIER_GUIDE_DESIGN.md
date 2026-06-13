# SPEC — Tier Guide Design (2026-06-13)

Design spec + implementation plan for a **net-new** feature on the public `/spec`
marketing page: a short questionnaire ("the guide") that recommends Setup, Build,
or Enterprise to a prospect who does not know which tier they need, with a
plain-English reason.

- **Status:** design only. No production code written. No shipped `/spec` file
  touched. This document is the brief a follow-up build chip executes from.
- **Vintage:** designed 2026-06-13, against SPEC Phase 1 as shipped to production
  (behind the `depositsEnabled` kill switch — currently OFF). **Hardened 2026-06-13**
  by an 8-agent multi-lens design + conversion review (see § 0).
- **Not in the original Phase 1 plan.** This is an additive enhancement to the
  live page. The passive handling it replaces: the FAQ entry "What if I am not
  sure which package I need?" → "Start with Setup; discovery will tell you," plus
  the OPS BOARD defaulting to BUILD.
- **Prototype:** [`specs/2026-06-13-spec-tier-guide-PROTOTYPE.html`](../specs/2026-06-13-spec-tier-guide-PROTOTYPE.html)
  — a throwaway, interactive, token-faithful artifact. It implements the real
  scoring logic and the full flow. Not production; a reference for the build chip
  and a thing for Jackson to click. (Patched 2026-06-13 for the § 0 token/structure
  fixes; some prototype shortcuts remain — § 7 / § 8 are canonical, not the HTML.)

Primary sources this design is derived from:
[01_BUSINESS_MODEL.md](01_BUSINESS_MODEL.md) (tier definitions, pricing, §4 upgrade
mechanics), [04_CUSTOMER_UX.md](04_CUSTOMER_UX.md) (`/spec` composition, voice,
numbers rules, conversion-tracking contract), [07_ROLLOUT.md](07_ROLLOUT.md) § 3
(page-revision history). Component patterns read from the live `ops-site` tree:
`SpecPageContent.tsx`, `SpecPricing.tsx`, `PackageCard.tsx`, `SpecOpsBoard.tsx`,
`SpecFAQ.tsx`, `lib/theme.ts`, `lib/marketing-analytics.ts`,
`lib/spec/conversion-events.ts`.

---

## 0. Conversion verdict + review log (2026-06-13)

This design was reviewed by 8 parallel agents — design-system compliance, craft /
distinctiveness, three CRO lenses (motivation-friction, trust-handoff, mobile-alt),
and two adversarial skeptics — then synthesized. The honest output:

**Will it convert highly? No — and that's the wrong bar today.** With
`depositsEnabled` OFF, every path dead-ends at the same "Talk to the founder"
contact link, so there is no high-intent purchase to convert. Read correctly, this
is a **net-positive engagement + qualification feature** that becomes a real
conversion lever once two preconditions are met (deposits ON + the dictionary fix
in § 12.0). Ship it scoped as exactly that — not sold internally as a deposit-
conversion lift.

**Realistic funnel vs. the passive-FAQ baseline (deposits OFF):**

- **START** ~8–18% of packages-section viewers as originally specced (the entry bar
  was low-salience, cost-led, and sat under a hardcoded "BUILD RECOMMENDED" pill).
  The § 0 fixes (payoff-led entry copy, reconciling the BUILD-default pill) plausibly
  lift this to ~18–28%. *This is the first and biggest funnel question — a
  recommender nobody starts is worth what the FAQ it replaced was worth.*
- **COMPLETE** ~70–85% of starters — genuinely strong (3 taps, auto-advance, near-
  zero load). Only real leak: accidental field mis-taps with a too-quiet BACK.
- **ACT** (completer → contact-CTA click) — *was* the biggest bleed and was
  uninstrumented. Fixed below: the result now carries its own tier-named action and
  fires its own event.

**The crown jewel survives the swap test cold:** the anti-upsell scoring (the
Enterprise-corroboration guard + tie-break toward the lower commitment) is the one
thing a generic quiz would never do — a generic quiz upsells to $18k; this one
visibly refuses to. Logic kept verbatim. **Do not let anyone declare success off
`tier_guide_completed`** — that's a vanity count. Success today is the
completed → contact-click ratio; success later is completed → `stripe_checkout_completed`.

**Changes applied from the review (APPLY_NOW items, woven into the sections below):**

1. Result gets its own first-class action (`TALK TO THE FOUNDER ABOUT {tier}`),
   card-scroll demoted to secondary (§ 5.2, § 5.3, § 8.1). *5 of 7 lenses converged
   here — highest-confidence finding.*
2. The base-dictionary reconciliation is now a **hard precondition** (§ 12.0), not a
   footnote — the cards the guide scrolls to are rendering raw keys in prod today.
3. Action-stage instrumentation added: `tier_guide_viewed` (START denominator) +
   `tier_guide_to_contact` + a `from=guide` marker (§ 12.5).
4. The Enterprise guard is **surfaced**, not silent: a guard-specific result line +
   driver clause; the § 3.2 driver-priority bug (a Setup/Build winner showing a
   migration/structure reason) is fixed.
5. Option-row two-line anatomy made canonical (§ 8.1, § 12.2) — the prototype's
   inline label+hint collision looked like a render bug on first contact.
6. Leading tier word dropped from each result reason (the 40px headline already says
   it; § 10).
7. Guide result overrides the page's hardcoded "BUILD RECOMMENDED" pill → "YOUR
   MATCH" on the guided card (§ 4, § 12.3).
8. Token fidelity: accent CTAs are white-on-accent + `rounded-[3px]` (not black-on-
   accent + 10px); accent removed from the open-container border, progress number,
   and result underline — accent is CTA-fill + focus-ring only (§ 7, § 8).
9. Focus-ring spec added (§ 11) — the one place accent is mandatory, previously
   undefined.
10. Auto-advance hardened against field mis-taps without losing the 3-tap speed
    (§ 5.1, § 11).
11. Entry copy re-led with payoff + trust hook, not cost (§ 8.1, § 10).
12. Entry subnote promise tightened so the funnel can keep it (§ 10).
13. Also-consider rows promoted to a genuine second door + Enterprise row suppressed
    on a Setup win with no structural signal (§ 5.2).
14. § 8.1 desktop layout corrected to the real `lg:w-[55%]` + fixed-phone overlap
    (§ 4, § 8.1).
15. § 7 "adopts the board vocabulary exactly" reworded (it adds two guide-specific
    beats).

**Considered and rejected:** (a) gating the whole build behind deposits ON —
rejected; ship now scoped as qualification, gated only on the dictionary fix; the
deposits-OFF reality is the *reason* the result needs a tier-named contact action,
not a reason to ship nothing. (b) stripping the `01 / 03` counter and the underline
"as quiz tells" — rejected; tactical progress + a restrained reveal are exactly the
brand's confident restraint (the legitimate sub-issue was accent *hue*, fixed by
recoloring, not deletion).

**Deferred to Jackson (new open questions in § 13):** Q2's under-weighting of
QuickBooks-integration intent; proving Q3 is load-bearing vs. folding to two
questions; the mobile single-screen vs. sequential flow fork; an answer-derived noun
in the result; a skip affordance.

---

## 1. Problem & intent

A prospect lands on `/spec`, sees three packages, and can't tell which one is
theirs. Today the page answers that passively. The guide answers it actively:
ask the fewest questions that genuinely discriminate the tiers, then hand back a
confident, honest recommendation.

The user's state is the whole design constraint. They are a trades business owner
"drowning in texts, paper, and chaos." They are not a power user comparing feature
matrices — they are stressed and unsure, and the reason this feature exists is to
replace "three cards and a shrug" with a straight answer from someone who knows.
The bar for every decision below: does it feel like a lifeline, or like a
tech-demo quiz? If it reads as a quiz, it is wrong.

Two non-negotiables fall out of that:

1. **No upsell-by-default.** A solo operator who just wants to get organized must
   be told **Setup**, not nudged to Build. A guide that always says "Build" is
   worthless and actively damages the trust OPS sells. The scoring is built so the
   honest answer wins, and Enterprise specifically cannot be recommended on
   ambition alone (§3, the corroboration guard). When the guard fires, it is shown,
   not hidden (§ 5.2) — the refusal to upsell is the single most trust-building
   moment in the flow.
2. **Genuinely discriminating questions only.** Every question must change the
   recommendation for some real user. If it can't, it's cut. Three questions that
   nail the call beat a ten-question form that feels like work.

---

## 2. What actually distinguishes the tiers

Read from [01_BUSINESS_MODEL.md](01_BUSINESS_MODEL.md) §1, §2, §4, §5, §7. The
tiers are not "small / medium / large." They are three different *kinds of work*:

| Tier | Price (total / P1 deposit) | The work | Midpoint definition (§2) |
|---|---|---|---|
| **Setup** | $3,000 / $750 | **Configure** existing OPS around the customer's workflow. Custom pipeline stages, custom fields on projects/clients, up to 3 custom configurations. **No new code.** | "Custom pipeline stages + custom fields deployed to staging." |
| **Build** | $8,500 / $2,125 | **Build one** custom module — "new features, new views, new logic" OPS doesn't have yet. iOS + web. AI features. Feature-flagged per company. | "Working prototype of the custom module, ~50% of the feature list." |
| **Enterprise** | $18,000 / $4,500 | **Multiple** custom modules + deep integrations (QuickBooks, AppFolio) + **data migration** off an incumbent system + structural platform changes. Multi-trade / multi-division / sub management. | "First of multiple custom modules; the rest stay in build at P3." |

The single highest-signal axis is therefore: **how much of what you need already
exists in OPS vs. has to be built?**

- Nothing to build, just configure → **Setup**
- One new capability → **Build**
- Several new capabilities + migration/integration + structural complexity →
  **Enterprise**

Two secondary axes confirm or override the self-report:

- **Migration / incumbent system.** Data migration and deep integrations are
  *explicitly* Enterprise scope. Someone moving off Buildertrend with years of
  data and a QuickBooks integration is Enterprise regardless of how they describe
  their goal. This axis catches the under-estimator.
- **Structural complexity.** Multi-trade / multi-division / subs / multi-location
  is an Enterprise tell. Crucially this is *structural*, not headcount — a 40-person
  single-trade shop can be a Setup; a solo operator can need a Build module.
  Crew-size-as-tier is a trap and is deliberately avoided.

**Out of scope for the guide: eligibility.** Quebec exclusion and the excluded
regulated workflows (PHI/PHIPA, PCI raw card, regulated credit, surveillance,
CASL — [01_BUSINESS_MODEL.md](01_BUSINESS_MODEL.md) §3) are *disqualifiers*, not
tiers. They are already screened downstream — Quebec at `/spec/billing-address`
(pre-Stripe), regulated workflows in the intake attestation
([04_CUSTOMER_UX.md](04_CUSTOMER_UX.md) §intake step 9). Surfacing "we won't build
HIPAA workflows" on a marketing quiz is off-tone and rare. The guide recommends a
tier; it does not gate eligibility. (Listed as an open question in §13 in case
Jackson wants a soft regulated-workflow nudge.)

---

## 3. Question set + scoring

### 3.1 The three questions

Each question maps to one of the three axes in §2. Each is phrased in the user's
situation, never in OPS's product taxonomy (the user does **not** know what
"configure vs. custom module" means — that's why they're here).

**Q1 — "What do you need OPS to do?"** *(primary axis: configure vs. build, weight 3)*

| id | Option label | Hint | Signal |
|---|---|---|---|
| `configure` | Set it up around how I work | "My job already fits OPS. I need it shaped to my pipeline, my stages, my terms." | Setup +3 |
| `build_one` | Build something it doesn't do yet | "A tool or workflow made for my trade — something OPS doesn't have." | Build +3 |
| `rebuild` | Rebuild my whole operation on it | "Several custom pieces — and move me off what I'm running now." | Enterprise +3 |

*Why it discriminates:* this is the definitional axis of the tiers (§2). It alone
gets ~70% of recommendations right. It is heaviest-weighted because it is the one
question that maps directly onto what each tier *is*. It is framed as an outcome
("set it up" / "build something" / "rebuild") so the user can answer it about
*their* situation without knowing OPS's internals.

**Q2 — "What are you running on today?"** *(migration axis)*

| id | Option label | Hint | Signal |
|---|---|---|---|
| `manual` | Texts, paper, spreadsheets | "Nothing to move over. Just what's in my head and my phone." | Setup +1 |
| `one_tool` | One main app, plus the mess | "Something like Jobber, Housecall Pro, or QuickBooks." | Build +1 |
| `heavy_system` | A heavy system I need off of | "ServiceTitan, Buildertrend, AppFolio — with data and integrations to bring across." | Enterprise +2 |

*Why it discriminates:* data migration + deep integrations are Enterprise-only
work. `heavy_system` is a strong, genuine Enterprise tell and is weighted +2 so it
can pull an under-estimating self-report (someone who picked `configure` in Q1 but
is actually migrating off Buildertrend) toward the truth. `manual` is the lightest
engagement (nothing to bring across → lean Setup). `one_tool` is a simple switch,
maybe a QuickBooks hook → mild Build lean. This question is what makes the guide
*honest in both directions* — it can both raise and confirm a tier.

> **Known edge (open question § 13.7):** a solo operator who needs their existing
> **QuickBooks data integrated** but picks `one_tool` only nets Build +1, so
> `configure + one_tool + multi_crew` ties to Setup — even though QB integration is
> §2 Enterprise scope. Today the human discovery gate corrects this; whether the
> recommender itself should catch it (by splitting `one_tool` on "do you need that
> data/integration brought across?") is deferred to Jackson.

**Q3 — "How's your operation built?"** *(structural complexity axis)*

| id | Option label | Hint | Signal |
|---|---|---|---|
| `solo` | One trade, one crew | "Just me, or a single tight crew." | Setup +1 |
| `multi_crew` | One trade, a few crews | "Growing, but still one line of work." | Build +1 |
| `multi_division` | Multiple trades or divisions | "Different divisions, subs to manage, or more than one location." | Enterprise +2 |

*Why it discriminates:* multi-trade / multi-division / subs is an explicit
Enterprise characteristic (§2). It is a question the user can answer *confidently
about themselves* (people know their own structure), unlike "how custom is your
build" which they cannot self-assess. It is deliberately *not* a headcount
question — option `multi_crew` explicitly says multiple crews is still fine for
Build, so growth alone never inflates the tier.

**Why three (with a caveat).** Q1 covers the definitional axis; Q2 and Q3 are the
two override axes that catch self-misjudgment in the only direction that matters
(under-estimating real complexity). A fourth question would be padding: regulated
workflows are an eligibility disqualifier (handled downstream), budget is not a
discriminator (the deposit is the friendly entry number, not a filter), and
timeline is the OPS BOARD's job. **Caveat (open question § 13.8):** the review
flagged that Q3's structural signal partly overlaps Q2's migration signal (either
alone satisfies the Enterprise guard, and a +1 rarely overturns a weight-3 Q1
lead). Before build, generate the full 27-path truth table and either (a) confirm
the count of paths where Q3 *alone* flips the result — proving it load-bearing — or
(b) fold structure into Q2 and ship two questions. Jackson decides; the build chip
must not.

### 3.2 Scoring algorithm (deterministic, explainable, client-side)

Pure function, no server, no DB. Each answer contributes a point vector
`[setup, build, enterprise]`:

```
configure     [3,0,0]      manual        [1,0,0]      solo            [1,0,0]
build_one     [0,3,0]      one_tool      [0,1,0]      multi_crew      [0,1,0]
rebuild       [0,0,3]      heavy_system  [0,0,2]      multi_division  [0,0,2]
```

Max points: Setup 5, Build 5, Enterprise 7. Q1 dominates by design; Q2/Q3
corroborate or override.

**Steps:**

1. Sum the three vectors → `{setup, build, enterprise}`.
2. Rank tiers by score, descending. **Tie-break toward the lower commitment**
   (`setup` < `build` < `enterprise`). The honest default when scores tie is the
   smaller engagement — this is the existing FAQ ethos ("start with Setup") encoded.
3. **Enterprise-corroboration guard.** If the raw winner is `enterprise` but
   **no structural Enterprise signal is present** (neither `heavy_system` nor
   `multi_division` was chosen), drop the recommendation to **Build** and set
   `guarded = true`. Enterprise ($18k) is never recommended on a Q1 self-report
   alone — it requires a real migration or a real multi-division structure. This is
   the anti-upsell rule made mechanical.
4. Winner = top of the (possibly guarded) ranking. The other two tiers become
   "also consider," ordered by score — **with one suppression:** if the winner is
   `setup` and **no structural signal** was given (no `heavy_system`, no
   `multi_division`), drop `enterprise` from "also consider" entirely. Surfacing the
   $18k tier next to a Setup result reads to a skeptic as "see, they *do* push me
   up" and quietly re-opens the upsell the guard just closed. Show Enterprise as an
   alternate only when at least one structural signal exists — matching the guard's
   own corroboration discipline.
5. **Close-call flag.** If the runner-up is within 1 point of the winner **and**
   the winner wasn't produced by the guard, set `closeCall = true` → the result adds
   a one-line "both fit, start lower" nudge (§10 copy). When `guarded`, the guard
   note (§ 5.2) replaces the close-call line.
6. **Driver clause (corrected priority — winner-consistent).** Pick the single
   bracketed "because you said X" reason, so it can never name a signal that points
   at a *non-winning* tier:
   - if `guarded` → `guarded`
   - else if winner is `enterprise`: `heavy_system` → `migration`; else
     `multi_division` → `structure`; else `structure`
   - else if winner is `build` → `build_one`
   - else (winner is `setup`) → `configure` if Q1 = `configure`, else `simple`

   *(The original spec's "`heavy_system` → migration regardless of winner" was a
   defect: it could print "you're moving off a system" under a Setup result. Fixed.)*

### 3.3 Worked cases (the design's honesty test)

| Scenario | Q1 / Q2 / Q3 | Scores S/B/E | Result | Driver shown | Why it's right |
|---|---|---|---|---|---|
| Solo operator who wants to get organized | configure / manual / solo | 5 / 0 / 0 | **Setup** | `configure` | Canonical no-upsell case. Enterprise also-row **suppressed** (no structural signal). |
| Deck builder needs a measurement tool | build_one / manual / multi_crew | 1 / 4 / 0 | **Build** | `build_one` | One custom module, simple structure → Build. |
| GC off Buildertrend, multi-trade, QB integration | rebuild / heavy_system / multi_division | 0 / 0 / 7 | **Enterprise** | `migration` | Migration + multi-division + rebuild all agree. |
| **Under-estimator** | configure / heavy_system / multi_division | 3 / 0 / 4 | **Enterprise** | `migration` | Said "just set me up," but migrating off a heavy system and running multiple divisions. The override axes catch it; the driver explains it. |
| **Over-estimator** (ambitious solo) | rebuild / manual / solo | 1 / 0 / 3 | **Build** (`guarded`) | `guarded` + guard note | Raw winner Enterprise, no structural signal → guard drops to Build and **says so** (§ 5.2 guard note), instead of contradicting the user with a "you only need one thing" line. We do not sell $18k to a solo paper operator on a feeling. |
| Torn between Setup and Build | configure / one_tool / multi_crew | 4 / 2 / 0 | **Setup** + close-call note | `configure` | Setup wins; Build within range → "both fit, start with Setup." |

The under-estimator and over-estimator rows are the two cases that prove the guide
is honest rather than decorative. A naive "highest Q1 answer wins" model fails both.

---

## 4. Placement

The guide's job is to help a person choose *among the three cards*. It therefore
belongs welded to those cards, in the same scan moment — not in a separate section,
a modal, or a route.

Four variants were explored (full wireframes in §8):

| # | Variant | Verdict |
|---|---|---|
| 1 | **Entry point at the top of `#packages`, expands inline above the cards** | **Recommended.** |
| 2 | Takeover — guide replaces the cards while active | Rejected: hides the cards from the user who *does* know, and creates a large layout shift. |
| 3 | Dedicated full-width section between HowItWorks and Pricing | Rejected: competes with the OPS BOARD (already a heavy full-width section there) and divorces the guide from the cards it's about. |
| 4 | Persistent sticky right-rail helper | Rejected by layout reality: the right 55% of the desktop `/spec` viewport is the fixed phone scene (`SpecPageContent.tsx`). No room. |

**Recommendation — Variant 1.** A slim tactical entry bar is the first thing
inside the `#packages` section, above the three `PackageCard`s. Collapsed by
default and server-rendered (indexable, zero layout shift). Clicking `START`
expands the guide inline *in place*; the three cards stay exactly where they are
below it. On result, the guide carries its own action **and** the matching card
below scrolls into view, expands, and takes the accent rail.

**Reconcile with the page's hardcoded BUILD defaults.** `SpecPageContent.tsx`
hardcodes `recommended: tier === 'build'` (a permanent "BUILD RECOMMENDED" pill) and
the OPS BOARD defaults its selection to BUILD. You cannot run an honest no-upsell
recommender *underneath* a permanent "BUILD RECOMMENDED" pill — a solo correctly
guided to Setup would scroll to a card stack still wearing "BUILD RECOMMENDED," a
quiet contradiction that erodes the straight-answer trust the guide just earned.
**Rule: once the guide has run, its per-user result owns "recommended" for that
session.** When the guide's winner ≠ `build`, suppress the generic pill and render a
"YOUR MATCH" treatment on the guided card instead (reusing the § 12.3 highlight
rail). Implementation in § 12.3.

Rationale:

- **In the scan path, not buried.** The unsure user meets the guide at the exact
  moment of indecision; a route or modal would hide it and break SEO continuity.
- **Inline, not modal.** A modal fights the page and reads as an interruption —
  wrong for the "lifeline" tone. Inline keeps the user in the flow.
- **Respects the user who already knows.** The cards are never hidden or blocked.
  Someone who knows their tier ignores the bar and reads the cards. The guide is an
  offer, not a gate.
- **Reuses the page's own interaction grammar.** The guided card's highlight is the
  same accent-rail vocabulary as the OPS BOARD row selection and the same card-expand
  the cards already do.

**Real desktop layout (corrected).** The `#packages` block is **not** a clean 720px
column with breathing room — `SpecPageContent.tsx` wraps Packages in `lg:w-[55%]`
while the phone scene is `fixed right-0 w-[55%]`, so the content column and the phone
overlap by ~10% at the right edge. The guide must be designed against that real
constraint: keep the guide's interactive content within the left ~720px safe area,
and the scroll-to-card handoff must clear the phone's visual mass (§ 5.3).

---

## 5. Interaction & flow

### 5.1 States

```
[collapsed entry bar]  →  Q1  →  Q2  →  Q3  →  [result]
        ▲                 │     │     │       │   │
        └──────── START OVER ───┴─────┴───────┘   └─ ‹ BACK (to Q3, answers kept)
                       ◄ BACK (Q2, Q3)
```

- **One question at a time.** Three steps, not a wall of form fields. This suits
  the "someone who knows is asking you three things" framing and keeps cognitive
  load near zero for a stressed user. Each step is one prompt + three option rows.
- **Auto-advance on select — hardened for the field.** Choosing an option commits
  it (selection feedback, §7) and advances. Keep the 3-tap speed, but defend the
  exact user OPS designs for (gloves, sunlight, scrolling thumb):
  - Commit hold is **~360–420ms** (not 260ms) so the selected state is legible
    before the slide.
  - **Suppress commit while a scroll/touch gesture is in flight** (`touchmove` /
    `pointercancel` guard) so a scroll-tap never silently commits the wrong answer —
    critical because a wrong Q1 tap corrupts the weight-3 answer driving ~70% of the
    result.
  - `‹ BACK` is a real **≥44px** target (not a 6px ghost), enabled from Q2, focus
    landing on the previously-chosen option.
  - The **result** also carries a quiet `‹ BACK` (returns to Q3, answers intact)
    next to `START OVER`, so a wrong last tap doesn't force a full reset.
  - No per-step "Next" button — the one-at-a-time auto-advance is the deliberate
    speed call. (Two restructures that trade speed for control — a single combined
    screen, and a select-then-NEXT button — are live A/B candidates, § 13.9.)
- **Progress is tactical, not playful.** `01 / 03` in mono. The current number is a
  **contrast step** — `--text` for the live number, `--text-mute` for the rest — **not
  an accent hue** (accent is CTA/focus only, § 7). No progress bar, no percent, no
  "you're almost there!" The number *is* the progress.
- **Back / restart.** `‹ BACK` returns to the prior question with the prior answer
  pre-selected. `‹ START OVER` clears all answers and returns to Q1.

### 5.2 The result — a place to ACT, not a signpost

The result is the moment of peak intent. It must let the user *act* there, not just
point at a place where they could act.

```
// YOUR TIER
BUILD                         ← tier name, Mohave 600, neutral hairline underline draws in
We build the one thing you're missing — a custom module for your trade, on iOS
and web, wired straight into your live OPS.
[ you need one specific thing built — not the whole operation ]   ← driver clause

[ TALK TO THE FOUNDER ABOUT BUILD ]      ← PRIMARY action (accent CTA, white-on-accent)
see the build package ›                  ← secondary: scroll to + expand + highlight card

ALSO CONSIDER
  SETUP — if you'd rather get organized first and build custom later.
  ENTERPRISE — if discovery shows you need more than one module, or a migration.

‹ BACK            START OVER
```

- **The recommendation is stated plainly and first**: tier name, then the one-sentence
  reason, then the bracketed "because you said X." No hedging into uselessness.
- **Primary action lives in the result.** With `depositsEnabled` OFF, the primary CTA
  is `TALK TO THE FOUNDER ABOUT {tier}` → `/resources?tier={tier}&from=guide#contact`
  (tier pre-named, prefilled into the contact form). The card-scroll
  (`see the {tier} package ›`) is **secondary**. Rationale: the live `PackageCard`
  renders its features grid, examples, milestone bar, and subscription/retainer rows
  **before** its CTA — so "scroll to the card" spends peak intent on a contact link
  buried below ~5 blocks of detail. Co-locating a tier-named action with the
  reasoning is the single highest-confidence conversion fix in the review.
- **When `depositsEnabled` flips ON**, the same primary slot becomes the deposit
  action — `PAY {tier} DEPOSIT` wired through the card's existing `handleDeposit(tier)`
  (and, per § 13.1, optionally pre-selecting the tier into the Stripe session). The
  result panel is the structural home the deposits-ON future needs anyway.
- **Guard note (when `guarded`).** Instead of suppressing all reassurance, the result
  shows a short line that honors the stated ambition and explains the smaller
  recommendation (`guide.result.guardNote`): *"You said rebuild — but with nothing to
  migrate and a lean crew, Enterprise would be overkill. We start with Build and
  prove it. If discovery shows it's bigger, we move up."* This is the literal proof
  of "we don't default to the expensive one."
- **Also-consider is a genuine second door, not fine print.** Body in `--text-2`,
  the mono tier tag at readable weight, a clear hover/click affordance (the rows
  *are* clickable → scroll to that card) — but never louder than the primary action.
  Per § 3.2 step 4, the Enterprise row is **suppressed** on a Setup win with no
  structural signal.
- **Close call.** If `closeCall` (and not `guarded`), a single line appears above the
  primary CTA: "SETUP and BUILD both fit. Start with SETUP — if discovery shows you
  need BUILD, we move you up then." Rendered in `--tan` (attention), not accent.

### 5.3 Connection to the cards (the handoff)

The secondary `see the {tier} package ›` and each "also consider" row call
`gotoCard(tier)`:

1. Smooth-scroll the matching `PackageCard` into view. **On desktop, use
   `block: 'start'` with a top offset** (not `block: 'center'`) so the opened card
   sits at the top of the left rail clear of the fixed phone's visual mass; on mobile
   `block: 'center'` is fine. The exact offset is a build-time screenshot
   verification (§ 12.3 acceptance).
2. Expand that card (the existing `expandedTier` mechanism in `SpecPricing.tsx`).
3. Apply a held highlight to the card — the OPS BOARD selection treatment: 2px
   `--ops-accent` rail + `bg-ops-accent/[0.04]` tint — and, if the guided tier ≠
   `build`, swap the generic "RECOMMENDED" pill for "YOUR MATCH" (§ 4, § 12.3).

**Deposit behaviour.** Today the *primary* action is the tier-named contact CTA in
the result (§ 5.2); the card scroll is secondary. The guide does **not** auto-trigger
any payment. Once `depositsEnabled` is ON, the result's primary slot becomes the
deposit action; whether it also *pre-selects* the tier into the Stripe session is an
open question for Jackson (§13.1).

---

## 6. Copy

All strings drafted through `ops-copywriter` (Anti-Pitch framework — the reader is
skeptical that every quiz just says "Build," so the trust hook is *"we don't
default to the expensive one"*). OPS voice: terse, sentence case for content,
UPPERCASE for authority, `//` section prefixes, `[bracket]` micro-text, no emoji,
no exclamation points, numbers in mono.

The exact strings, with their dictionary keys, are the i18n table in §10. The
result narrative composes from these enumerated string groups:

- **Per-tier reason** (`guide.result.<tier>.reason`) — the tier's essence in one
  honest sentence. (The leading tier word is dropped — the 40px headline already
  says "BUILD"; the reason flows from it.)
- **Driver clause** (`guide.driver.<id>`) — the single bracketed "because you said
  X" line, selected per §3.2 step 6 (including the new `guarded` clause).
- **Guard note** (`guide.result.guardNote`) — shown only when `guarded`.
- **Also-consider line** (`guide.also.<tier>`) — the "choose this if…" for each
  surfaced non-recommended tier.

This composition is deterministic and fully translatable: there is **no
interpolation of the user's free text** — every visible phrase is a finite,
enumerated dictionary string. The only interpolated tokens are tier *names* (e.g.
`TALK TO THE FOUNDER ABOUT {tier}`), pulled from the existing `packages.<tier>.name`
keys.

---

## 7. Animation choreography

Routed through `animation-studio:animation-architect` → `web-animations`. The guide
**adopts the `SpecOpsBoard.tsx` selection and reduced-motion vocabulary, and adds
two guide-specific beats on the same easing curve and durations** (the per-question
camera-move and the result underline-draw have no board precedent). Single easing
`cubic-bezier(0.22, 1, 0.36, 1)` everywhere (the only authorized curve —
`theme.animation.easing`). No spring, no bounce. Durations from
`theme.animation.durations`. Framer Motion (the page imports `framer-motion`; match
that, not `motion/react`). `will-change` budget: only the actively-animating
element.

| Moment | Beat | Motion | Duration |
|---|---|---|---|
| Entry bar entrance | Entry | Part of the existing `SpecPricing` stagger (`opacity/y` whileInView). No special treatment. | 500ms (existing) |
| Expand the guide | Entry | Body height `0 → auto` + opacity `0 → 1`, crisp ease-out, no bounce. Mirrors `PackageCard` expand. | 350ms (`flip`) |
| Question → question | Transition | Outgoing prompt+options fade + slide up (`y: 0 → −8`, opacity → 0, 200ms); incoming fade + slide up (`y: 8 → 0`, opacity 0 → 1, 200–240ms). A camera-move, not a cut. `AnimatePresence mode="wait"`. (Optional craft upgrade, § 13.10: make it direction-aware — advance slides incoming from the right, BACK reverses — so motion carries spatial meaning.) | 200–240ms |
| Option select | Discovery + Commitment | Chosen row gets the 2px **accent** left-rail (the sanctioned board-selection accent use) + `bg-ops-accent/[0.04]` tint (200ms); siblings dim to `opacity 0.4` (200ms). Then auto-advance after the 360–420ms hold. | 200ms + ~390ms hold |
| Result reveal | **Achievement (restraint)** | Question block fades out (200ms); result fades + slides in (`y: 8 → 0`, 300ms). The tier name's 1px **neutral hairline** (`white/0.12`, *not* accent) **draws left-to-right** to the width of the name — a tactical "locked in" beat. **A stamp, not a parade.** No confetti, no scale-bounce. | 300ms reveal + 500ms underline |
| Scroll-to-card handoff | Transition | Native smooth-scroll (`block: 'start'`+offset on desktop, `'center'` on mobile); card expands (existing 350ms); accent rail fades in and holds (250ms). | 350ms |

**Token-fidelity rules (accent is CTA-fill + focus-ring ONLY — DESIGN.md §3):**

- Accent CTAs (entry `START`, result primary) are **`bg-ops-accent` + `text-white` +
  `rounded-[3px]`** — matching the live `PackageCard` recommended CTA
  (`PackageCard.tsx`), **not** the prototype's black-on-accent + 10px panel radius
  (which appears nowhere else on `/spec` and reads foreign next to the cards' CTA).
  The guide container, entry bar, and option rows also use `rounded-[3px]`, not the
  10px panel token.
- The **open-guide container** does **not** take an accent border. Use `--line`
  (`white/0.10`) like every other `/spec` surface; for an active cue brighten the
  hairline to `white/0.15` (the established neutral hover/active), never accent.
- The **progress number** is a contrast step (`--text` vs `--text-mute`), never
  accent (§ 5.1).
- The **result underline** is a neutral hairline (`white/0.12`), never accent (§ 5.2).
- **No ambient motion.** The OPS BOARD's "LIVE" pulse is the only ambient motion on
  `/spec` ([04_CUSTOMER_UX.md](04_CUSTOMER_UX.md) §3). The guide adds none.
- **Reduced motion** (`useReducedMotion()`, matching the board): every transition
  collapses to its instant final state with an opacity-only fade ≤200ms. The result
  underline renders at full width immediately (no draw). The scroll uses
  `behavior: 'auto'`. `globals.css` already enforces a `0.01ms` transition override
  under `prefers-reduced-motion`; the JS gates Framer values in addition, exactly as
  `SpecOpsBoard` does.

---

## 8. Wireframes

### 8.1 Desktop (real layout: `lg:w-[55%]` content column, fixed phone overlapping ~10% at right)

The guide's interactive content stays within the left ~720px safe area; the
scroll-to-card handoff (§ 5.3) clears the phone's right-edge mass.

**Canonical option-row anatomy (two-line stack — NOT inline).** Label and hint are
**block-level**, stacked, so the label never runs into the hint as one string:

```
┌─────────────────────────────────────────────┐
│▍ Set it up around how I work                 │  ← label: --text, 15px, block
│  My job already fits OPS. I need it shaped    │  ← hint: --text-3, 13px token step,
│  to my pipeline, my stages, my terms.         │     block, mt-1, line-height 1.4
└─────────────────────────────────────────────┘
   ▍ = 2px accent rail when selected; siblings dim to 0.4
```

**Variant 1 — entry collapsed (SSR state):**

```
// PACKAGES
┌──────────────────────────────────────────────────────────────┐
│ // NOT SURE WHICH ONE                                         │
│ We'll tell you which one's yours.                  [ START ]  │
│ [ three questions · no upsell · no signup ]                  │
└──────────────────────────────────────────────────────────────┘
┌─ SETUP ─────────────────────────────────────── $750 ─┐
┌─ BUILD ·RECOMMENDED· ───────────────────────── $2,125 ─┐   (pill yields to YOUR MATCH after guide runs)
┌─ ENTERPRISE ────────────────────────────────── $4,500 ─┐
```

**Variant 1 — question state (expanded inline; cards remain below):**

```
┌──────────────────────────────────────────────────────────────┐
│ // WHAT YOU NEED                                    01 / 03   │   (01 = --text, /03 = --text-mute)
│                                                              │
│ What do you need OPS to do?                                  │
│                                                              │
│ │▍ Set it up around how I work                              │  ← selected: accent rail + tint
│ │  My job already fits OPS. I need it shaped to my pipeline. │
│ ├─ Build something it doesn't do yet                         │
│ │  A tool or workflow made for my trade — OPS doesn't have.  │
│ ├─ Rebuild my whole operation on it                          │
│ │  Several custom pieces — and move me off what I run now.   │
│                                                              │
│ ‹ BACK                                                       │   (≥44px, enabled Q2/Q3)
└──────────────────────────────────────────────────────────────┘
[ SETUP card ] [ BUILD card ] [ ENTERPRISE card ]   ← unchanged below
```

**Variant 1 — result state:**

```
┌──────────────────────────────────────────────────────────────┐
│ // YOUR TIER                                                 │
│ BUILD                                                        │
│ ▔▔▔▔▔                            ← neutral hairline underline draws │
│ We build the one thing you're missing — a custom module for  │
│ your trade, on iOS and web, wired straight into your OPS.    │
│ [ you need one specific thing built — not the whole op ]     │
│                                                              │
│ [ TALK TO THE FOUNDER ABOUT BUILD ]   ← PRIMARY (white-on-accent)  │
│ see the build package ›               ← secondary (scroll to card) │
│                                                              │
│ ALSO CONSIDER                                                │
│  SETUP — if you'd rather get organized first…               │
│  ENTERPRISE — if discovery shows you need more…    (suppressed on Setup-win w/ no signal) │
│ ‹ BACK        START OVER                                     │
└──────────────────────────────────────────────────────────────┘
   secondary ↓ scrolls to + expands + highlights the BUILD card (block:'start'+offset on desktop)
```

### 8.2 Mobile (<768px)

Full-bleed single column. Entry bar stacks (CTA full-width below the copy). Option
rows are full-width two-line tap targets (≥44px). Progress stays top-right of the
prompt. The guide owns the whole column because the phone scene is `hidden lg:block`.

```
// PACKAGES
┌───────────────────────────┐    ┌───────────────────────────┐
│ // NOT SURE WHICH ONE     │    │ // WHAT YOU NEED   01 / 03 │
│ We'll tell you which      │    │                           │
│ one's yours.              │    │ What do you need OPS      │
│ [ three questions ·       │    │ to do?                    │
│   no upsell · no signup ] │    │ ┌───────────────────────┐ │
│ ┌───────────────────────┐ │    │ │▍Set it up around how  │ │
│ │        START          │ │    │ │  I work               │ │
│ └───────────────────────┘ │    │ │  My job already fits… │ │
└───────────────────────────┘    │ └───────────────────────┘ │
                                  │ ‹ BACK                    │
                                  └───────────────────────────┘
```

*Mobile flow is an open A/B question (§ 13.9): sequential auto-advance (above, with
the § 5.1 hardening) vs. a single combined screen (all three radiogroups stacked,
result on the third answer).*

---

## 9. SEO / SSR posture

The page's hero is the LCP element; the guide is well below the fold, text-only, no
images, no new fonts. It cannot regress LCP.

- **The entry bar + a static "how to choose" summary are server-rendered** inside
  the collapsed container (present in the initial HTML, visually collapsed). This
  mirrors the FAQ `<details>` decision in [04_CUSTOMER_UX.md](04_CUSTOMER_UX.md) §8:
  the *decision content* — "Not sure which? Setup configures OPS around you; Build
  builds one custom module; Enterprise rebuilds your operation and migrates you" —
  ships in the indexed HTML and is readable by SEO and LLM crawlers without
  executing JS. The questions' text is also in the SSR'd DOM.
- **The interactive questionnaire is progressive enhancement.** It hydrates on the
  client (`'use client'`); the scoring module is pure and tiny. With JS off, the
  static summary + the three cards still answer the question — no dead end.
- **No new JSON-LD required.** The existing `FAQPage` already carries a "which
  package" Q&A. Optionally, that FAQ answer can be updated to mention the guide, but
  that touches the shipped FAQ/dictionary and is a coordinated follow-up, not part
  of this self-contained feature.
- **Keywords earned for free:** "not sure which package," "Setup / Build /
  Enterprise," plus the named incumbents in Q2 hints (ServiceTitan, Buildertrend,
  AppFolio, Jobber, Housecall Pro, QuickBooks) — all AI-discovery hooks
  ([04_CUSTOMER_UX.md](04_CUSTOMER_UX.md) §SEO).

---

## 10. i18n — the full key set

New namespace `guide.*` added to **both** `src/i18n/dictionaries/en/spec.json` and
`src/i18n/dictionaries/es/spec.json`. Flat dot-keys, matching the existing file
convention. Option lists are arrays of `{id, label, hint}` objects (the `id` is
shared across locales and is what the scoring module keys on — reorder-safe;
`label`/`hint` translate). This mirrors how `packages.<tier>.examples` already
stores `{trade, desc}` arrays.

> **Drift guard.** The committed `en/spec.json` is currently missing the Phase-1
> package keys the components reference (`startFrom`, `headlineSub`,
> `milestoneAmount`, `packages.milestones.*`) — the dictionary-keys-dropped-in-a-
> merge incident. See § 12.0 — fixing that is a **hard precondition**, not a
> footnote. The **complete** `guide.*` key set is enumerated below for both
> locales; the build chip adds every key to both files in the same commit, with a
> `t()` raw-key canary in CI.

### 10.1 English (`en/spec.json`)

| Key | Value |
|---|---|
| `guide.entry.label` | `// NOT SURE WHICH ONE` |
| `guide.entry.headline` | `We'll tell you which one's yours.` |
| `guide.entry.subnote` | `[ three questions · no upsell · no signup ]` |
| `guide.entry.cta` | `START` |
| `guide.q1.kicker` | `// WHAT YOU NEED` |
| `guide.q1.prompt` | `What do you need OPS to do?` |
| `guide.q1.options` | `[ {id:"configure", label:"Set it up around how I work", hint:"My job already fits OPS. I need it shaped to my pipeline, my stages, my terms."}, {id:"build_one", label:"Build something it doesn't do yet", hint:"A tool or workflow made for my trade — something OPS doesn't have."}, {id:"rebuild", label:"Rebuild my whole operation on it", hint:"Several custom pieces — and move me off what I'm running now."} ]` |
| `guide.q2.kicker` | `// WHAT YOU RUN ON` |
| `guide.q2.prompt` | `What are you running on today?` |
| `guide.q2.options` | `[ {id:"manual", label:"Texts, paper, spreadsheets", hint:"Nothing to move over. Just what's in my head and my phone."}, {id:"one_tool", label:"One main app, plus the mess", hint:"Something like Jobber, Housecall Pro, or QuickBooks."}, {id:"heavy_system", label:"A heavy system I need off of", hint:"ServiceTitan, Buildertrend, AppFolio — with data and integrations to bring across."} ]` |
| `guide.q3.kicker` | `// HOW YOU'RE BUILT` |
| `guide.q3.prompt` | `How's your operation built?` |
| `guide.q3.options` | `[ {id:"solo", label:"One trade, one crew", hint:"Just me, or a single tight crew."}, {id:"multi_crew", label:"One trade, a few crews", hint:"Growing, but still one line of work."}, {id:"multi_division", label:"Multiple trades or divisions", hint:"Different divisions, subs to manage, or more than one location."} ]` |
| `guide.result.label` | `// YOUR TIER` |
| `guide.result.setup.reason` | `We shape OPS around the way you already work — your pipeline, your stages, your fields. Nothing new to learn. Just OPS, built to fit you.` |
| `guide.result.build.reason` | `We build the one thing you're missing — a custom module for your trade, on iOS and web, wired straight into your live OPS.` |
| `guide.result.enterprise.reason` | `Multiple custom modules, your data moved off the old system, your tools integrated. Your whole operation, rebuilt on OPS.` |
| `guide.driver.configure` | `[ you said your work already fits how OPS runs ]` |
| `guide.driver.build_one` | `[ you need one specific thing built — not the whole operation ]` |
| `guide.driver.migration` | `[ you're moving off a system that has to come with you ]` |
| `guide.driver.structure` | `[ you're running more than one crew, trade, or division ]` |
| `guide.driver.simple` | `[ your operation's lean enough to start light ]` |
| `guide.driver.guarded` | `[ you want the whole thing rebuilt — we start with one module and prove it ]` |
| `guide.result.guardNote` | `You said rebuild — but with nothing to migrate and a lean crew, Enterprise would be overkill. We start with Build and prove it. If discovery shows it's bigger, we move up.` |
| `guide.result.ctaPrimary` | `TALK TO THE FOUNDER ABOUT {tier}` |
| `guide.result.ctaPrimaryDeposit` | `PAY {tier} DEPOSIT` *(used only when depositsEnabled is ON; see § 5.2)* |
| `guide.result.ctaSecondary` | `See the {tier} package ›` |
| `guide.result.alsoLabel` | `ALSO CONSIDER` |
| `guide.also.setup` | `if you'd rather get organized first and build custom later.` |
| `guide.also.build` | `if one custom module would close most of the gap.` |
| `guide.also.enterprise` | `if discovery shows you need more than one module, or a migration.` |
| `guide.result.closeCall` | `{lower} and {higher} both fit. Start with {lower} — if discovery shows you need {higher}, we move you up then.` |
| `guide.back` | `‹ BACK` |
| `guide.restart` | `START OVER` |
| `guide.a11y.progress` | `Question {n} of {total}` |
| `guide.a11y.recommended` | `Recommended tier: {tier}` |

### 10.2 Spanish (`es/spec.json`) — faithful mirror

Translations are consistent with the existing `es/spec.json` register (e.g. it uses
"4 pagos"). Tactical voice preserved; `//`, `[ ]`, and the `id`s are identical to
EN. A native-voice polish pass is welcome, but the keys + meaning below are locked
so nothing can be dropped.

| Key | Value |
|---|---|
| `guide.entry.label` | `// ¿CUÁL ES LA TUYA?` |
| `guide.entry.headline` | `Te decimos cuál es la tuya.` |
| `guide.entry.subnote` | `[ tres preguntas · sin upsell · sin registro ]` |
| `guide.entry.cta` | `EMPEZAR` |
| `guide.q1.kicker` | `// QUÉ NECESITAS` |
| `guide.q1.prompt` | `¿Qué necesitas que haga OPS?` |
| `guide.q1.options` | `[ {id:"configure", label:"Configurarlo a mi manera de trabajar", hint:"Mi trabajo ya encaja en OPS. Solo necesito ajustarlo a mi flujo, mis etapas, mis términos."}, {id:"build_one", label:"Construir algo que todavía no hace", hint:"Una herramienta o flujo para mi oficio que OPS no tiene."}, {id:"rebuild", label:"Reconstruir toda mi operación en él", hint:"Varias piezas a medida — y migrarme de lo que uso ahora."} ]` |
| `guide.q2.kicker` | `// CON QUÉ TRABAJAS` |
| `guide.q2.prompt` | `¿Con qué trabajas hoy?` |
| `guide.q2.options` | `[ {id:"manual", label:"Mensajes, papel, hojas de cálculo", hint:"Nada que migrar. Solo lo que tengo en la cabeza y en el teléfono."}, {id:"one_tool", label:"Una app principal, más el desorden", hint:"Algo como Jobber, Housecall Pro o QuickBooks."}, {id:"heavy_system", label:"Un sistema pesado del que necesito salir", hint:"ServiceTitan, Buildertrend, AppFolio — con datos e integraciones que migrar."} ]` |
| `guide.q3.kicker` | `// CÓMO ESTÁS ARMADO` |
| `guide.q3.prompt` | `¿Cómo está armada tu operación?` |
| `guide.q3.options` | `[ {id:"solo", label:"Un oficio, una cuadrilla", hint:"Solo yo, o una cuadrilla."}, {id:"multi_crew", label:"Un oficio, varias cuadrillas", hint:"Creciendo, pero todavía una línea de trabajo."}, {id:"multi_division", label:"Varios oficios o divisiones", hint:"Distintas divisiones, subcontratistas, o más de una ubicación."} ]` |
| `guide.result.label` | `// TU PAQUETE` |
| `guide.result.setup.reason` | `Ajustamos OPS a tu forma de trabajar — tu flujo, tus etapas, tus campos. Nada nuevo que aprender. Solo OPS, hecho a tu medida.` |
| `guide.result.build.reason` | `Construimos lo único que te falta — un módulo a medida para tu oficio, en iOS y web, conectado directo a tu OPS.` |
| `guide.result.enterprise.reason` | `Varios módulos a medida, tus datos migrados del sistema viejo, tus herramientas integradas. Toda tu operación, reconstruida en OPS.` |
| `guide.driver.configure` | `[ dijiste que tu trabajo ya encaja con cómo funciona OPS ]` |
| `guide.driver.build_one` | `[ necesitas una cosa específica construida — no toda la operación ]` |
| `guide.driver.migration` | `[ estás saliendo de un sistema que tiene que venir contigo ]` |
| `guide.driver.structure` | `[ manejas más de una cuadrilla, oficio o división ]` |
| `guide.driver.simple` | `[ tu operación es lo bastante simple para empezar ligero ]` |
| `guide.driver.guarded` | `[ quieres reconstruirlo todo — empezamos con un módulo y lo probamos ]` |
| `guide.result.guardNote` | `Dijiste reconstruir — pero sin nada que migrar y con una cuadrilla, Enterprise sería demasiado. Empezamos con Build y lo probamos. Si discovery muestra que es más grande, subimos.` |
| `guide.result.ctaPrimary` | `HABLA CON EL FUNDADOR SOBRE {tier}` |
| `guide.result.ctaPrimaryDeposit` | `PAGAR DEPÓSITO {tier}` |
| `guide.result.ctaSecondary` | `Ver el paquete {tier} ›` |
| `guide.result.alsoLabel` | `TAMBIÉN CONSIDERA` |
| `guide.also.setup` | `si prefieres organizarte primero y construir a medida después.` |
| `guide.also.build` | `si un módulo a medida cubriría casi todo.` |
| `guide.also.enterprise` | `si discovery muestra que necesitas más de un módulo, o una migración.` |
| `guide.result.closeCall` | `{lower} y {higher} encajan las dos. Empieza con {lower} — si discovery muestra que necesitas {higher}, te subimos ahí.` |
| `guide.back` | `‹ ATRÁS` |
| `guide.restart` | `EMPEZAR DE NUEVO` |
| `guide.a11y.progress` | `Pregunta {n} de {total}` |
| `guide.a11y.recommended` | `Paquete recomendado: {tier}` |

---

## 11. Accessibility

- **Semantics.** Each question is a `radiogroup` (`aria-label` = the prompt); the
  three options are `role="radio"` with `aria-checked`. Native arrow-key navigation
  within the group; Space/Enter selects (and triggers auto-advance). The entry bar
  is a `button` with `aria-expanded` / `aria-controls`.
- **Focus ring (mandatory accent use — DESIGN.md §9/§15).** Every interactive
  element — entry bar, option rows, result primary + secondary CTAs, also-consider
  rows, `‹ BACK`, `START OVER` — gets a visible `:focus-visible` ring:
  `outline: 1.5px solid var(--ops-accent); outline-offset: 2px`. This is the one
  place accent is required; it must not be omitted (the prototype omitted it — a
  WCAG 2.4.7 failure the build must not reproduce).
- **Focus management.** On expand, focus moves to the first option of Q1. On
  advance, focus moves to the first option of the next question. On `‹ BACK`, focus
  returns to the previously chosen option. On result, focus moves to the result
  heading (`// YOUR TIER` region, `tabindex=-1`); the result `‹ BACK` returns to Q3
  with focus on the prior Q3 answer.
- **Screen-reader announcements.** Progress is announced via the
  `guide.a11y.progress` label ("Question 2 of 3"). The recommendation is announced
  through an `aria-live="polite"` region using `guide.a11y.recommended`
  ("Recommended tier: Build").
- **Selection is never color-alone.** Selected = accent rail **+** `aria-checked`
  **+** the dim of siblings; not hue alone. Meets WCAG 1.4.1.
- **Contrast.** All text uses the `theme` text ladder (`--text` 18.8:1, `--text-2`
  10.3:1, `--text-3` 5.4:1 — all AA+). The `--tan` close-call line on black is within
  AA for the 11px mono usage; if a contrast audit flags it, promote to `--text-2`.
- **Field-mis-tap hardening** per § 5.1 (gesture-guarded commit, ≥44px BACK, result
  BACK). **Reduced motion** per § 7. **Targets** ≥44px on mobile.
- **Keyboard-only** completes the entire flow (start → 3 selects → primary CTA).

---

## 12. Implementation plan

### 12.0 Hard precondition — base-dictionary reconciliation (BLOCKER)

**Before any `guide.*` keys are added, the Phase-1 `spec.json` drift must be fixed.**
The committed `en/spec.json` has **zero** occurrences of `startFrom`, `headlineSub`,
`milestoneAmount`, or `packages.milestones.*` — the exact keys `SpecPageContent.tsx`
and `PackageCard.tsx` read — while still carrying stale `packages.<tier>.price`,
`packages.<tier>.deposit`, and two "50%" strings. The guide's climactic moment is
"scroll to + expand the matching card"; that card is rendering raw keys / blank
milestone bars in production today. The guide must not be the feature that surfaces
the cards' broken state to a prospect.

Required, in both `en` and `es`, verified by rendering `/spec` in both locales with
a CI / `t()` raw-key canary that fails on any fallback:

1. Restore the missing Phase-1 package keys (`startFrom`, `headlineSub`,
   `milestoneAmount`, `packages.milestones.*`).
2. Strip the stale `packages.<tier>.price` / `.deposit` and "50%" copy.

This is a precondition on the guide build, but the fix itself is base-page hygiene
(a separate, coordinate-with-sibling-WIP concern — do not stomp parallel edits).

### 12.1 Pure logic module — `src/lib/spec/tier-guide.ts` (new)

The whole brain, framework-free and unit-testable. No React, no DOM, no network.

```ts
export type SpecTier = 'setup' | 'build' | 'enterprise';
export type Q1 = 'configure' | 'build_one' | 'rebuild';
export type Q2 = 'manual' | 'one_tool' | 'heavy_system';
export type Q3 = 'solo' | 'multi_crew' | 'multi_division';
export interface GuideAnswers { need: Q1; stack: Q2; shape: Q3 }
export interface GuideResult {
  winner: SpecTier;
  others: SpecTier[];          // "also consider" — Enterprise dropped on Setup-win w/ no signal (§3.2.4)
  runnerUp: SpecTier;
  closeCall: boolean;
  guarded: boolean;            // Enterprise→Build guard fired
  driver: 'configure'|'build_one'|'migration'|'structure'|'simple'|'guarded';
  scores: Record<SpecTier, number>;
}
export function recommendTier(a: GuideAnswers): GuideResult;  // §3.2
```

Ship with `__tests__/tier-guide.test.ts` covering every §3.3 worked case plus: the
guard branch, the tie-break, the Enterprise-also-row suppression, and the corrected
driver priority (assert a Setup winner never returns `migration`/`structure`). The
prototype's `recommend()` is the reference — port it, but note the prototype predates
the driver-priority fix and the also-row suppression; encode § 3.2 steps 4 & 6 as
written here, not the prototype's older logic.

### 12.2 Components — `src/components/spec/tier-guide/` (new)

| File | Responsibility |
|---|---|
| `SpecTierGuide.tsx` | `'use client'`. Owns flow state (`step`, `answers`, `phase: 'entry'\|'questions'\|'result'`). Renders entry bar, questions, result. Receives a typed `copy` prop (built in `SpecPageContent` from `t(dict,…)`, exactly like `SpecOpsBoardCopy`). Emits `onRecommend(result)` up to `SpecPricing` for the pill-override + card handoff. |
| `GuideQuestion.tsx` | One question: prompt, `01 / 03` (contrast not accent), three **two-line** option rows (§ 8.1 anatomy), `‹ BACK`. Selection + gesture-guarded auto-advance + Framer transitions (§7). |
| `GuideResult.tsx` | Tier name + neutral underline draw, reason, driver clause, guard note, close-call line, **primary action** (tier-named contact CTA → `/resources?tier={tier}&from=guide#contact`; or deposit when ON), secondary card-scroll, also-consider, `‹ BACK` + `START OVER`. |
| `tier-guide-copy.ts` | The `SpecTierGuideCopy` interface + the `t(dict,…)` assembly helper (parallels `SpecOpsBoardCopy`). |

The component tree is small and bounded — each file does one thing and is readable
in isolation. State lives only in `SpecTierGuide`; children are presentational.

### 12.3 Wiring into the page

- `SpecPageContent.tsx` — build a `SpecTierGuideCopy` object from the dictionary
  (same pattern as `boardCopy`) and pass it down. The guide is rendered **inside**
  the Packages block, above the cards. Cleanest seam: render `<SpecTierGuide>` at
  the top of `SpecPricing`'s output (so it shares the column and the `expandedTier`
  state lives in one place).
- `SpecPricing.tsx` — accept the guide copy; on `onRecommend(result)`:
  `setExpandedTier(null)` until the user clicks the secondary card-scroll, then
  `setExpandedTier(tier)`, set a transient `highlightTier`, and scroll its ref into
  view (`block:'start'`+offset on desktop, `'center'` on mobile — § 5.3). Track a
  `guidedTier` so the **pill override** (below) applies.
- `PackageCard.tsx` — add two optional, additive props (default off; no behavior
  change otherwise): `highlighted?: boolean` → the held accent rail; and
  `matchLabel?: string` → when set, render "YOUR MATCH" in place of the hardcoded
  "RECOMMENDED" pill. **Pill-override rule:** once the guide has run, suppress the
  generic `recommended` pill on the BUILD card whenever `guidedTier !== 'build'`, and
  show "YOUR MATCH" on the `guidedTier` card (§ 4).
- **Desktop acceptance:** screenshot-verify the scroll-to-card lands the opened card
  clear of the fixed phone (`block:'start'` + offset) and that the highlight rail
  reads against the phone's right-edge bleed.

### 12.4 i18n

Add the full §10 key set to `en/spec.json` **and** `es/spec.json` in the same
commit, **after** the § 12.0 reconciliation. Verify no `t()` fallback (raw key
shown) by rendering both locales.

### 12.5 Analytics

Client-side only — the guide is a soft engagement + qualification signal with no PII
and no server round-trip, so it uses `trackMarketingEvent(name, props)` from
`src/lib/marketing-analytics.ts` (fires `gtag` + Vercel `track`). It does **not**
use the server `sendConversionEvent()` outbox — that is reserved for the ad-platform
funnel (deposit click, checkout). Events:

| Event | When | Properties |
|---|---|---|
| `tier_guide_viewed` | entry bar enters viewport (IntersectionObserver, once) | `{ locale }` — **the START-rate denominator** |
| `tier_guide_started` | `START` clicked / guide expands | `{ locale }` |
| `tier_guide_answered` | each option select | `{ step, question_id, option_id }` |
| `tier_guide_completed` | result shown | `{ recommended_tier, guarded, close_call, driver }` |
| `tier_guide_to_contact` | result PRIMARY CTA clicked | `{ recommended_tier, driver, guarded, close_call, from:'tier_guide' }` |
| `tier_guide_card_opened` | secondary card-scroll / also-consider → card | `{ from_tier, to_tier }` |

- Persist a `from=guide` (+ `tier`) marker into the contact-form URL/state (and,
  once deposits are ON, into Stripe metadata) so guide-attributed conversions are
  reconstructable end-to-end. When deposits go live, map `tier_guide_to_contact` to
  the same Meta CAPI intermediate funnel step as `owner_approval_requested`.
- **Success metric — say it explicitly:** today, success is the
  `tier_guide_completed → tier_guide_to_contact` **ratio** (and the
  `recommended_tier` vs. where conversations actually land signal); later, it's
  `tier_guide_completed → stripe_checkout_completed`. **`tier_guide_completed` count
  alone is a vanity metric** and must not be used to declare success.

### 12.6 Build-complexity estimate

**Low–moderate. A single focused session** (the guide itself). The logic module is
~70 lines of pure TS + tests. The components are three small presentational files
plus one stateful container, all reusing existing motion/selection/card patterns
(`SpecOpsBoard` selection vocabulary, `PackageCard` expand, `theme` tokens, the
`t(dict,…)` copy-assembly pattern). No schema, no API, no migration, no new
dependency. The cross-file care points are the `SpecPricing` ↔ guide handoff
(`expandedTier`, `highlightTier`, the pill override) and the result's
primary-action wiring. **Note:** the § 12.0 dictionary reconciliation is separate
base-page work that must land first; treat it as its own task, not part of the
guide's effort estimate.

---

## 13. Open questions for Jackson

1. **Pre-select the tier into the deposit flow?** Today the result's primary action
   is the tier-named contact CTA; the card-scroll is secondary. Once
   `depositsEnabled` is ON, the result's primary slot becomes the deposit action —
   should completing the guide also *pre-select* the recommended tier into the
   Stripe session (one-tap), or just open the deposit for that tier?
   **Recommendation:** when deposits go live, pre-select the tier (the guide already
   knows it; it's the natural payoff) but never auto-charge.
2. **Show the upgrade-credit reassurance in the close-call / guard copy?** Per
   [01_BUSINESS_MODEL.md](01_BUSINESS_MODEL.md) §4, a pre-scope-signoff tier upgrade
   credits payments already made. That's a genuinely reassuring, *true* fact for the
   torn user, but it's a pricing/policy claim on a marketing surface. **Recommendation:**
   keep the conservative close-call / guard copy in §10 by default; add the
   upgrade-credit line only on Jackson's explicit OK.
3. **Soft regulated-workflow nudge?** The guide deliberately doesn't screen
   eligibility (Quebec / regulated workflows handled downstream, §2). Want a light
   "building something regulated? talk to the founder first" note on the Enterprise
   result, or keep eligibility entirely downstream? **Recommendation:** keep it
   downstream — a marketing quiz is the wrong place to raise HIPAA.
4. **Entry-bar prominence + a skip affordance.** Recommended placement is a slim bar
   at the *top* of `#packages` with a payoff-led headline. (a) Acceptable, or more
   assertive (a prompt in the section-label row, a deep-link from the FAQ "which
   package" answer)? (b) Add a quiet "skip — show the packages" link once expanded,
   so opening the guide feels low-commitment? **Recommendation:** slim payoff-led bar
   + add the skip link (it lowers the perceived cost of pressing START).
5. **Replace vs. coexist with the FAQ "which package" answer.** Keep the FAQ answer
   (SEO value, JS-off fallback) and point it at the guide, or rewrite it?
   **Recommendation:** keep it, add one sentence pointing to the guide. (Touches the
   shipped FAQ/dict — a coordinated follow-up, not part of this feature's core commit.)
6. *(reserved)*
7. **Q2 migration under-weighting.** A QuickBooks-integration solo
   (`configure + one_tool + multi_crew`) ties to Setup despite QB integration being
   §2 Enterprise scope. Split `one_tool` by "do you need that data/integration brought
   across?" (tighter accuracy, more complex Q2) or rely on the human discovery gate?
   **Recommendation:** rely on discovery for v1; revisit if telemetry shows
   integration-driven mis-tiering. *(Changes the question set — Jackson's call.)*
8. **Prove Q3 is load-bearing or fold to two questions.** Generate the 27-path truth
   table; count where Q3 *alone* flips the result. If non-trivial, keep Q3 and put
   the table in § 3; if trivial, fold structure into Q2 and ship two questions
   (fewer taps). **Recommendation:** run the table before build and decide on the
   evidence. *(Question-set change — Jackson's call.)*
9. **Mobile flow: sequential vs. single screen.** (A) sequential auto-advance (current
   design + § 5.1 hardening), (B) select-then-NEXT button (one extra tap, full
   control, matches the board's click-to-select grammar), or (C) a single combined
   screen (all three radiogroups stacked, result on the third answer — kills mis-tap
   abandonment, reads as a short form not a quiz; costs the one-at-a-time intimacy).
   **Recommendation:** ship (A) with hardening; A/B (C) against it on mobile — the
   mobile lens bets (C) converts best for a sunlit, gloved thumb.
10. **Answer-derived noun in the result + direction-aware transitions (craft).** (a)
    Name the captured incumbent / structure in the reason ("move you off Buildertrend,"
    "across your divisions") — fully enumerable, i18n-safe (finite phrase set, no
    free-text), but expands the dictionary. (b) Make the Q-to-Q transition
    direction-aware. **Recommendation:** both are real upgrades; do (a) if the
    personalization lift justifies the copy surface, (b) is cheap polish. Neither is
    required for v1.

**Considered and rejected (do not re-raise without new evidence):** gating the whole
build behind deposits ON (ship now as qualification, gated only on § 12.0); stripping
the `01 / 03` counter or the result underline as "quiz tells" (they are on-brand
tactical restraint — the only real issue was accent *hue*, fixed by recoloring).

---

## 14. Confirmation of scope

- No production code written. No shipped `/spec` component, route, dictionary, or
  `lib` file modified. The only artifacts produced are this design doc and the
  non-production prototype HTML under `specs/`.
- No flags flipped, nothing deployed, no `git push`.
- The design fits the existing `/spec` composition (Hero → HowItWorks → OPS BOARD →
  **Packages [+ guide]** → WhatsIncluded → Standing Behind The Work → FAQ →
  BottomCTA) and reuses its established interaction, motion, token, and i18n
  patterns rather than introducing new ones.
- Hardened 2026-06-13 by an 8-agent design + conversion review (§ 0). The honest
  framing it must ship under: an **engagement + qualification** feature today, a
  conversion lever once deposits are ON and the § 12.0 dictionary fix lands.
