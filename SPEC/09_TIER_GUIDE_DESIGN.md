# SPEC — Tier Guide Design (2026-06-13)

Design spec + implementation plan for a **net-new** feature on the public `/spec`
marketing page: a short questionnaire ("the guide") that recommends Setup, Build,
or Enterprise to a prospect who does not know which tier they need, with a
plain-English reason.

- **Status:** design only. No production code written. No shipped `/spec` file
  touched. This document is the brief a follow-up build chip executes from.
- **Vintage:** designed 2026-06-13, against SPEC Phase 1 as shipped to production
  (behind the `depositsEnabled` kill switch — currently OFF).
- **Not in the original Phase 1 plan.** This is an additive enhancement to the
  live page. The passive handling it replaces: the FAQ entry "What if I am not
  sure which package I need?" → "Start with Setup; discovery will tell you," plus
  the OPS BOARD defaulting to BUILD.
- **Prototype:** [`specs/2026-06-13-spec-tier-guide-PROTOTYPE.html`](../specs/2026-06-13-spec-tier-guide-PROTOTYPE.html)
  — a throwaway, interactive, token-faithful artifact. It implements the real
  scoring logic and the full flow. Not production; a reference for the build chip
  and a thing for Jackson to click.

Primary sources this design is derived from:
[01_BUSINESS_MODEL.md](01_BUSINESS_MODEL.md) (tier definitions, pricing, §4 upgrade
mechanics), [04_CUSTOMER_UX.md](04_CUSTOMER_UX.md) (`/spec` composition, voice,
numbers rules, conversion-tracking contract), [07_ROLLOUT.md](07_ROLLOUT.md) § 3
(page-revision history). Component patterns read from the live `ops-site` tree:
`SpecPageContent.tsx`, `SpecPricing.tsx`, `PackageCard.tsx`, `SpecOpsBoard.tsx`,
`SpecFAQ.tsx`, `lib/theme.ts`, `lib/marketing-analytics.ts`,
`lib/spec/conversion-events.ts`.

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
   ambition alone (§3, the corroboration guard).
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

**Why exactly three.** Q1 covers the definitional axis; Q2 and Q3 are the two
override axes that catch self-misjudgment in the only direction that matters
(under-estimating real complexity). A fourth question would be padding: regulated
workflows are an eligibility disqualifier (handled downstream), budget is not a
discriminator (the deposit is the friendly entry number, not a filter), and
timeline is the OPS BOARD's job. Three questions, each load-bearing.

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
   `multi_division` was chosen), drop the recommendation to **Build**. Enterprise
   ($18k) is never recommended on a Q1 self-report alone — it requires a real
   migration or a real multi-division structure. This is the anti-upsell rule made
   mechanical. (Enterprise still appears in "also consider.")
4. Winner = top of the (possibly guarded) ranking. The other two tiers become
   "also consider," ordered by score.
5. **Close-call flag.** If the runner-up is within 1 point of the winner (and the
   winner wasn't produced by the guard), set `closeCall = true` → the result adds a
   one-line "both fit, start lower" nudge (§6 copy).
6. **Driver clause.** Pick the single dominant reason for the result, by priority:
   `heavy_system` → `migration`; else `multi_division` → `structure`; else by
   winning tier (`setup`→`configure`|`simple`, `build`→`build_one`,
   `enterprise`→`structure`). The result renders this as the bracketed "because
   you said X" line so the recommendation can always explain *why*.

### 3.3 Worked cases (the design's honesty test)

| Scenario | Q1 / Q2 / Q3 | Scores S/B/E | Result | Why it's right |
|---|---|---|---|---|
| Solo operator who wants to get organized | configure / manual / solo | 5 / 0 / 0 | **Setup** | The canonical no-upsell case. Lower tier wins cleanly. |
| Deck builder needs a measurement tool | build_one / manual / multi_crew | 1 / 4 / 0 | **Build** | One custom module, simple structure → Build. |
| GC off Buildertrend, multi-trade, QB integration | rebuild / heavy_system / multi_division | 0 / 0 / 7 | **Enterprise** | Migration + multi-division + rebuild all agree. |
| **Under-estimator** | configure / heavy_system / multi_division | 3 / 0 / 4 | **Enterprise** | Said "just set me up," but is migrating off a heavy system and runs multiple divisions. The override axes catch it; the driver clause explains it (`migration`). |
| **Over-estimator** (ambitious solo) | rebuild / manual / solo | 1 / 0 / 3 | **Build** (guard fires) | Raw winner Enterprise, but no structural signal → guard drops to Build. We do not sell $18k to a solo paper operator on a feeling. Enterprise stays in "also consider." |
| Torn between Setup and Build | configure / one_tool / multi_crew | 4 / 2 / 0 | **Setup** + close-call note | Setup wins; Build is within range → "both fit, start with Setup." |

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
below it. On result, the guide shows the recommendation inline **and** the matching
card below scrolls into view, expands, and takes the accent rail.

Rationale:

- **In the scan path, not buried.** The unsure user meets the guide at the exact
  moment of indecision; a route or modal would hide it and break SEO continuity.
- **Inline, not modal.** A modal fights the page and reads as an interruption —
  wrong for the "lifeline" tone. Inline keeps the user in the flow.
- **Respects the user who already knows.** The cards are never hidden or blocked.
  Someone who knows their tier ignores the bar and reads the cards. The guide is an
  offer, not a gate.
- **Reuses the page's own interaction grammar.** The guide's output *is* a
  selection in the existing card system — same accent-rail vocabulary as the OPS
  BOARD row selection and the same card-expand the cards already do.

---

## 5. Interaction & flow

### 5.1 States

```
[collapsed entry bar]  →  Q1  →  Q2  →  Q3  →  [result]
        ▲                 │     │     │           │
        └───────── START OVER ──┴─────┴───────────┘   (restart, clears answers)
                          ◄ BACK (Q2,Q3 only)
```

- **One question at a time.** Three steps, not a wall of form fields. This suits
  the "someone who knows is asking you three things" framing and keeps cognitive
  load near zero for a stressed user. Each step is one prompt + three option rows.
- **Auto-advance on select.** Choosing an option commits it (selection feedback,
  §7) and advances ~260ms later. No per-step "Next" button — less friction, fewer
  taps (3 taps to a result). Answers are revisable via `‹ BACK`.
- **Progress is tactical, not playful.** `01 / 03` in mono, accent on the current
  number. No progress bar, no percent, no "you're almost there!" The number *is*
  the progress.
- **Back / restart.** `‹ BACK` on Q2/Q3 returns to the prior question with the
  prior answer pre-selected. `‹ START OVER` on the result clears all answers and
  returns to Q1.

### 5.2 The result

```
// YOUR TIER
BUILD                         ← tier name, Mohave 600, accent underline draws in
We build the one thing you're missing — a custom module for your trade, on iOS
and web, wired straight into your live OPS.
[ you need one specific thing built — not the whole operation ]   ← driver clause

[ SEE THE BUILD PACKAGE ]     ← primary CTA → scroll to + expand + highlight card

ALSO CONSIDER
  SETUP — if you'd rather get organized first and build custom later.
  ENTERPRISE — if discovery shows you need more than one module, or a migration.

‹ START OVER
```

- The recommendation is stated plainly and *first*: tier name, then the one-sentence
  reason, then the bracketed "because you said X." No hedging into uselessness.
- "Also consider" shows the other two tiers without apology, each with a one-line
  "choose this if…" so the user can overrule us with eyes open.
- If `closeCall`, a single tan line appears above the CTA: "SETUP and BUILD both
  fit. Start with SETUP — if discovery shows you need BUILD, we move you up then."

### 5.3 Connection to the cards (the handoff)

The primary CTA and each "also consider" row call `gotoCard(tier)`:

1. Smooth-scroll the matching `PackageCard` into view (`block: 'center'`).
2. Expand that card (the existing `expandedTier` mechanism in `SpecPricing.tsx`).
3. Apply a held accent left-rail highlight to the card (the OPS BOARD selection
   treatment: 2px `--ops-accent` rail + `bg-ops-accent/[0.04]` tint).

**Deposit behaviour.** The guide **recommends and routes — it does not auto-trigger
the deposit.** It scrolls to and opens the right card; the user takes the deposit
action themselves from the card they now understand. This is both the correct tone
(not pushy) and the correct engineering today: `depositsEnabled` is OFF, so the
card's CTA is currently "Talk to the founder," and there is no deposit to pre-fill.
Whether completing the guide should *pre-select* the tier for the eventual Stripe
flow (once deposits are on) is an open question for Jackson (§13).

---

## 6. Copy

All strings drafted through `ops-copywriter` (Anti-Pitch framework — the reader is
skeptical that every quiz just says "Build," so the trust hook is *"we don't
default to the expensive one"*). OPS voice: terse, sentence case for content,
UPPERCASE for authority, `//` section prefixes, `[bracket]` micro-text, no emoji,
no exclamation points, numbers in mono.

The exact strings, with their dictionary keys, are the i18n table in §10. The
result narrative composes from three string groups:

- **Per-tier reason** (`guide.result.<tier>.reason`) — the tier's essence in one
  honest sentence.
- **Driver clause** (`guide.driver.<id>`) — the single bracketed "because you said
  X" line, selected per §3.2 step 6.
- **Also-consider line** (`guide.also.<tier>`) — the "choose this if…" for each
  non-recommended tier.

This composition is deterministic and fully translatable: there is **no
interpolation of the user's free text** — every visible phrase is a finite,
enumerated dictionary string. The only interpolated tokens are tier *names* (e.g.
`SEE THE {tier} PACKAGE`), pulled from the existing `packages.<tier>.name` keys.

---

## 7. Animation choreography

Routed through `animation-studio:animation-architect` → `web-animations`. The guide
adopts the `SpecOpsBoard.tsx` motion vocabulary exactly so it reads as native to
the page. Single easing `cubic-bezier(0.22, 1, 0.36, 1)` everywhere (the only
authorized curve — `theme.animation.easing`). No spring, no bounce. Durations from
`theme.animation.durations`. Framer Motion (the page imports `framer-motion`; match
that, not `motion/react`). `will-change` budget: only the actively-animating
element.

| Moment | Beat | Motion | Duration |
|---|---|---|---|
| Entry bar entrance | Entry | Part of the existing `SpecPricing` stagger (`opacity/y` whileInView). No special treatment. | 500ms (existing) |
| Expand the guide | Entry | Body height `0 → auto` + opacity `0 → 1`, crisp ease-out, no bounce. Mirrors `PackageCard` expand. | 350ms (`flip`) |
| Question → question | Transition | Outgoing prompt+options fade + slide up (`y: 0 → −8`, opacity → 0, 200ms); incoming fade + slide up (`y: 8 → 0`, opacity 0 → 1, 200–240ms). A camera-move, not a cut. `AnimatePresence mode="wait"`. | 200–240ms |
| Option select | Discovery + Commitment | Chosen row gets the 2px accent left-rail + `bg-ops-accent/[0.04]` tint (200ms); siblings dim to `opacity 0.4` (200ms). Then auto-advance. | 200ms + 260ms hold |
| Result reveal | **Achievement (restraint)** | Question block fades out (200ms); result fades + slides in (`y: 8 → 0`, 300ms). The tier name's 1px accent underline **draws left-to-right** to the width of the name — a tactical "locked in" beat. **A stamp, not a parade.** No confetti, no scale-bounce. | 300ms reveal + 500ms underline |
| Scroll-to-card handoff | Transition | Native smooth-scroll (`block: 'center'`); card expands (existing 350ms); accent rail fades in and holds (250ms). | 350ms |

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

### 8.1 Desktop (≤720px content column, left of the phone scene)

**Variant 1 — RECOMMENDED — entry collapsed (SSR state):**

```
// PACKAGES
┌──────────────────────────────────────────────────────────────┐
│ // NOT SURE WHICH ONE                                         │
│ Tell us three things. We'll point you to the right tier.   [ START ] │
│ [ 2 min · no email · we don't default to the expensive one ] │
└──────────────────────────────────────────────────────────────┘
┌─ SETUP ─────────────────────────────────────── $750 ─┐
┌─ BUILD ·RECOMMENDED· ───────────────────────── $2,125 ─┐
┌─ ENTERPRISE ────────────────────────────────── $4,500 ─┐
```

**Variant 1 — question state (expanded inline; cards remain below):**

```
┌──────────────────────────────────────────────────────────────┐
│ // WHAT YOU NEED                                    01 / 03   │
│                                                              │
│ What do you need OPS to do?                                  │
│                                                              │
│ │▍ Set it up around how I work               ◄ selected rail │
│ │  My job already fits OPS. I need it shaped to my pipeline. │
│ ├─ Build something it doesn't do yet                         │
│ │  A tool or workflow made for my trade — OPS doesn't have.  │
│ ├─ Rebuild my whole operation on it                          │
│ │  Several custom pieces — and move me off what I run now.   │
│                                                              │
│ ‹ BACK                                                       │
└──────────────────────────────────────────────────────────────┘
[ SETUP card ] [ BUILD card ] [ ENTERPRISE card ]   ← unchanged below
```

**Variant 1 — result state:**

```
┌──────────────────────────────────────────────────────────────┐
│ // YOUR TIER                                                 │
│ BUILD                                                        │
│ ▔▔▔▔▔                                ← accent underline draws │
│ We build the one thing you're missing — a custom module for  │
│ your trade, on iOS and web, wired straight into your OPS.    │
│ [ you need one specific thing built — not the whole op ]     │
│                                                              │
│ [ SEE THE BUILD PACKAGE ]                                    │
│                                                              │
│ ALSO CONSIDER                                                │
│  SETUP — if you'd rather get organized first…               │
│  ENTERPRISE — if discovery shows you need more…             │
│ ‹ START OVER                                                 │
└──────────────────────────────────────────────────────────────┘
   ↓ scrolls to + expands + accent-rails the BUILD card
```

### 8.2 Mobile (<768px)

Full-bleed single column. Entry bar stacks (CTA goes full-width below the copy).
Option rows are full-width tap targets (≥44px tall, comfortably). Progress stays
top-right of the prompt. Everything else identical; the guide never needs the phone
scene's column because the phone scene is `hidden lg:block`.

```
// PACKAGES
┌───────────────────────────┐    ┌───────────────────────────┐
│ // NOT SURE WHICH ONE     │    │ // WHAT YOU NEED   01 / 03 │
│ Tell us three things.     │    │                           │
│ We'll point you to the    │    │ What do you need OPS      │
│ right tier.               │    │ to do?                    │
│ [ 2 min · no email ]      │    │ ┌───────────────────────┐ │
│ ┌───────────────────────┐ │    │ │▍Set it up around how  │ │
│ │        START          │ │    │ │  I work               │ │
│ └───────────────────────┘ │    │ └───────────────────────┘ │
└───────────────────────────┘    │ ┌───────────────────────┐ │
                                  │ │ Build something…      │ │
                                  │ └───────────────────────┘ │
                                  │ ‹ BACK                    │
                                  └───────────────────────────┘
```

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
> merge incident. To prevent a repeat, the **complete** `guide.*` key set is
> enumerated below for both locales. The build chip adds every key to both files in
> the same commit; CI/`t()` fallback returning the raw key is the canary.

### 10.1 English (`en/spec.json`)

| Key | Value |
|---|---|
| `guide.entry.label` | `// NOT SURE WHICH ONE` |
| `guide.entry.headline` | `Tell us three things. We'll point you to the right tier.` |
| `guide.entry.subnote` | `[ 2 min · no email · we don't default to the expensive one ]` |
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
| `guide.result.setup.reason` | `Setup. We shape OPS around the way you already work — your pipeline, your stages, your fields. Nothing new to learn. Just OPS, built to fit you.` |
| `guide.result.build.reason` | `Build. We build the one thing you're missing — a custom module for your trade, on iOS and web, wired straight into your live OPS.` |
| `guide.result.enterprise.reason` | `Enterprise. Multiple custom modules, your data moved off the old system, your tools integrated. Your whole operation, rebuilt on OPS.` |
| `guide.driver.configure` | `[ you said your work already fits how OPS runs ]` |
| `guide.driver.build_one` | `[ you need one specific thing built — not the whole operation ]` |
| `guide.driver.migration` | `[ you're moving off a system that has to come with you ]` |
| `guide.driver.structure` | `[ you're running more than one crew, trade, or division ]` |
| `guide.driver.simple` | `[ your operation's lean enough to start light ]` |
| `guide.result.cta` | `SEE THE {tier} PACKAGE` |
| `guide.result.alsoLabel` | `ALSO CONSIDER` |
| `guide.also.setup` | `if you'd rather get organized first and build custom later.` |
| `guide.also.build` | `if one custom module would close most of the gap.` |
| `guide.also.enterprise` | `if discovery shows you need more than one module, or a migration.` |
| `guide.result.closeCall` | `{lower} and {higher} both fit. Start with {lower} — if discovery shows you need {higher}, we move you up then.` |
| `guide.back` | `‹ BACK` |
| `guide.restart` | `‹ START OVER` |
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
| `guide.entry.headline` | `Dinos tres cosas. Te decimos cuál te conviene.` |
| `guide.entry.subnote` | `[ 2 min · sin correo · no te empujamos a la más cara ]` |
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
| `guide.result.setup.reason` | `Setup. Ajustamos OPS a tu forma de trabajar — tu flujo, tus etapas, tus campos. Nada nuevo que aprender. Solo OPS, hecho a tu medida.` |
| `guide.result.build.reason` | `Build. Construimos lo único que te falta — un módulo a medida para tu oficio, en iOS y web, conectado directo a tu OPS.` |
| `guide.result.enterprise.reason` | `Enterprise. Varios módulos a medida, tus datos migrados del sistema viejo, tus herramientas integradas. Toda tu operación, reconstruida en OPS.` |
| `guide.driver.configure` | `[ dijiste que tu trabajo ya encaja con cómo funciona OPS ]` |
| `guide.driver.build_one` | `[ necesitas una cosa específica construida — no toda la operación ]` |
| `guide.driver.migration` | `[ estás saliendo de un sistema que tiene que venir contigo ]` |
| `guide.driver.structure` | `[ manejas más de una cuadrilla, oficio o división ]` |
| `guide.driver.simple` | `[ tu operación es lo bastante simple para empezar ligero ]` |
| `guide.result.cta` | `VER EL PAQUETE {tier}` |
| `guide.result.alsoLabel` | `TAMBIÉN CONSIDERA` |
| `guide.also.setup` | `si prefieres organizarte primero y construir a medida después.` |
| `guide.also.build` | `si un módulo a medida cubriría casi todo.` |
| `guide.also.enterprise` | `si discovery muestra que necesitas más de un módulo, o una migración.` |
| `guide.result.closeCall` | `{lower} y {higher} encajan las dos. Empieza con {lower} — si discovery muestra que necesitas {higher}, te subimos ahí.` |
| `guide.back` | `‹ ATRÁS` |
| `guide.restart` | `‹ EMPEZAR DE NUEVO` |
| `guide.a11y.progress` | `Pregunta {n} de {total}` |
| `guide.a11y.recommended` | `Paquete recomendado: {tier}` |

---

## 11. Accessibility

- **Semantics.** Each question is a `radiogroup` (`aria-label` = the prompt); the
  three options are `role="radio"` with `aria-checked`. Native arrow-key navigation
  within the group; Space/Enter selects (and triggers auto-advance). The entry bar
  is a `button` with `aria-expanded` / `aria-controls`.
- **Focus management.** On expand, focus moves to the first option of Q1. On
  advance, focus moves to the first option of the next question. On `‹ BACK`, focus
  returns to the previously chosen option. On result, focus moves to the result
  heading (`// YOUR TIER` region, `tabindex=-1`).
- **Screen-reader announcements.** Progress is announced via the
  `guide.a11y.progress` label ("Question 2 of 3"). The recommendation is announced
  through an `aria-live="polite"` region using `guide.a11y.recommended`
  ("Recommended tier: Build").
- **Selection is never color-alone.** Selected = accent rail **+** `aria-checked`
  **+** the dim of siblings; not hue alone. Meets WCAG 1.4.1.
- **Contrast.** All text uses the `theme` text ladder (`--text` 18.8:1, `--text-2`
  10.3:1, `--text-3` 5.4:1 — all AA+). The tan close-call line on black is within
  AA for the 11px mono usage; if a contrast audit flags it, promote to `--text-2`.
- **Reduced motion** per §7. **Targets** ≥44px on mobile.
- **Keyboard-only** completes the entire flow (start → 3 selects → CTA → card).

---

## 12. Implementation plan

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
  others: SpecTier[];          // ordered, the two "also consider"
  runnerUp: SpecTier;
  closeCall: boolean;
  guarded: boolean;            // Enterprise→Build guard fired
  driver: 'configure'|'build_one'|'migration'|'structure'|'simple';
  scores: Record<SpecTier, number>;
}
export function recommendTier(a: GuideAnswers): GuideResult;  // §3.2
```

Ship with `__tests__/tier-guide.test.ts` covering every §3.3 worked case plus the
guard and tie-break branches. (The prototype's `recommend()` is the reference
implementation — port verbatim.)

### 12.2 Components — `src/components/spec/tier-guide/` (new)

| File | Responsibility |
|---|---|
| `SpecTierGuide.tsx` | `'use client'`. Owns flow state (`step`, `answers`, `phase: 'entry'\|'questions'\|'result'`). Renders entry bar, questions, result. Receives a typed `copy` prop (built in `SpecPageContent` from `t(dict,…)`, exactly like `SpecOpsBoardCopy`). Emits `onRecommend(tier)` up to `SpecPricing` for the card handoff. |
| `GuideQuestion.tsx` | One question: prompt, `01 / 03`, three option rows, `‹ BACK`. Selection + auto-advance + Framer transitions (§7). |
| `GuideResult.tsx` | Tier name + underline draw, reason, driver clause, close-call line, CTA, also-consider, `‹ START OVER`. |
| `tier-guide-copy.ts` | The `SpecTierGuideCopy` interface + the `t(dict,…)` assembly helper (parallels `SpecOpsBoardCopy`). |

The component tree is small and bounded — each file does one thing and is readable
in isolation. State lives only in `SpecTierGuide`; children are presentational.

### 12.3 Wiring into the page

- `SpecPageContent.tsx` — build a `SpecTierGuideCopy` object from the dictionary
  (same pattern as `boardCopy`) and pass it down. The guide is rendered **inside**
  the Packages block, above the cards. Cleanest seam: render `<SpecTierGuide>` at
  the top of `SpecPricing`'s output (so it shares the 720px column and the
  `expandedTier` state lives in one place), with `SpecPricing` exposing a way to set
  `expandedTier` + a highlight flag from the guide's `onRecommend`. Alternative:
  render the guide as a sibling in `SpecPageContent` and lift `expandedTier`/scroll
  into a small shared controller. **Recommended:** put the guide inside
  `SpecPricing` and reuse its existing `expandedTier` state for the handoff — least
  new plumbing, the card-expand mechanism already exists there.
- `SpecPricing.tsx` — accept the guide copy; on `onRecommend(tier)`: `setExpandedTier(tier)`,
  set a transient `highlightTier`, and scroll its ref into view. The `PackageCard`
  gets an optional `highlighted` prop → renders the held accent rail.
- `PackageCard.tsx` — add an optional `highlighted?: boolean` that applies the
  accent-rail treatment (additive; default false; no behavior change otherwise).

### 12.4 i18n

Add the full §10 key set to `en/spec.json` **and** `es/spec.json` in the same
commit. Verify no `t()` fallback (raw key shown) by rendering both locales.

### 12.5 Analytics

Client-side only — the guide is a soft engagement signal with no PII and no server
round-trip, so it uses `trackMarketingEvent(name, props)` from
`src/lib/marketing-analytics.ts` (fires `gtag` + Vercel `track`). It does **not**
use the server `sendConversionEvent()` outbox — that is reserved for the ad-platform
funnel (deposit click, checkout). Events:

| Event | When | Properties |
|---|---|---|
| `tier_guide_started` | `START` clicked / guide expands | `{ locale }` |
| `tier_guide_answered` | each option select | `{ step, question_id, option_id }` |
| `tier_guide_completed` | result shown | `{ recommended_tier, guarded, close_call, driver }` |
| `tier_guide_card_opened` | result CTA / also-consider → card | `{ from_tier, to_tier }` |

`tier_guide_completed.recommended_tier` is the conversion-relevant signal — it lets
us measure which tier the guide steers prospects toward and whether that matches
where deposits actually land, once deposits are on.

### 12.6 Build-complexity estimate

**Low–moderate. A single focused session.** The logic module is ~60 lines of pure
TS + tests. The components are three small presentational files plus one stateful
container, all reusing existing motion/selection/card patterns already in the tree
(`SpecOpsBoard` selection vocabulary, `PackageCard` expand, `theme` tokens, the
`t(dict,…)` copy-assembly pattern). No schema, no API, no migration, no new
dependency. The only cross-file care is the `SpecPricing` ↔ guide handoff
(`expandedTier` + highlight), which is a small, contained change. Risk surface is
essentially the i18n key completeness (§10 mitigates) and the a11y focus
choreography (§11 specifies it).

---

## 13. Open questions for Jackson

1. **Pre-select the tier into the deposit flow?** Today the guide recommends and
   scrolls to the card; the user takes the deposit action themselves. Once
   `depositsEnabled` is ON, should completing the guide *pre-select* the
   recommended tier so the eventual "Pay Deposit" is one tap (passing the tier into
   `handleDeposit`/the Stripe session), or stay recommend-only? **Recommendation:**
   recommend-only now (deposits are off; auto-arming a $750–$4,500 action from a
   quiz is pushy and off-brand); revisit when deposits go live.
2. **Show the upgrade-credit reassurance in the close-call copy?** Per
   [01_BUSINESS_MODEL.md](01_BUSINESS_MODEL.md) §4, a pre-scope-signoff tier upgrade
   credits payments already made ("Customer pays new tier − payments made;
   discovery counts toward the new tier"). That's a genuinely reassuring, *true*
   fact for the torn user ("start lower, upgrading later doesn't waste money"). It's
   also a pricing/policy claim on a marketing surface. **Recommendation:** keep the
   conservative close-call copy in §10 by default; add the upgrade-credit line only
   on Jackson's explicit OK.
3. **Soft regulated-workflow nudge?** The guide deliberately doesn't screen
   eligibility (Quebec / regulated workflows handled downstream, §2). Do you want a
   light "building something regulated? talk to the founder first" note on the
   Enterprise result, or keep eligibility entirely downstream? **Recommendation:**
   keep it downstream — a marketing quiz is the wrong place to raise HIPAA.
4. **Entry-bar prominence.** Recommended placement is a slim bar at the *top* of
   `#packages`. Acceptable, or do you want it more assertive (e.g. a one-line
   prompt inside the section label row, or a second entry from the FAQ "which
   package" answer linking down to it)? **Recommendation:** slim bar at top of
   `#packages`; optionally also deep-link the existing FAQ answer to it.
5. **Replace vs. coexist with the FAQ "which package" answer.** The guide
   supersedes that FAQ entry's job. Keep the FAQ answer (SEO value, JS-off
   fallback) and point it at the guide, or rewrite it? **Recommendation:** keep it,
   add one sentence pointing to the guide. (Touches the shipped FAQ/dict — a
   coordinated follow-up, not part of this feature's core commit.)

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
