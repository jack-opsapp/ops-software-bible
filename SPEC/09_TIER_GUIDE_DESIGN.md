# SPEC — Tier Guide Design (2026-06-13)

Design spec + implementation plan for a **net-new** feature on the public `/spec`
marketing page: a short questionnaire ("the guide") that gives a prospect a straight
answer about what they actually need — **standard OPS (no paid build), or Setup,
Build, or Enterprise** — with a plain-English reason.

- **Status:** design only. No production code written. No shipped `/spec` file
  touched. This document is the brief a follow-up build chip executes from.
- **Vintage:** designed 2026-06-13, against SPEC Phase 1 as shipped to production
  (behind the `depositsEnabled` kill switch — currently OFF). Hardened across three
  multi-agent passes (see § 0); **v3 is the current design.**
- **Prototype:** [`specs/2026-06-13-spec-tier-guide-PROTOTYPE.html`](../specs/2026-06-13-spec-tier-guide-PROTOTYPE.html)
  — a throwaway, interactive, token-faithful artifact. Not production; § 7 / § 8 are
  canonical, not the HTML.

Primary sources: [01_BUSINESS_MODEL.md](01_BUSINESS_MODEL.md) (tiers, pricing, §4
upgrade mechanics), [04_CUSTOMER_UX.md](04_CUSTOMER_UX.md) (`/spec` composition,
voice, conversion-tracking), [07_ROLLOUT.md](07_ROLLOUT.md) § 3, plus the standard-OPS
capability research cited in § 2.1. Live component patterns: `SpecPageContent.tsx`,
`SpecPricing.tsx`, `PackageCard.tsx`, `SpecOpsBoard.tsx`, `lib/theme.ts`,
`lib/marketing-analytics.ts`, `lib/spec/conversion-events.ts`, `app/api/contact/route.ts`,
`components/resources/ContactForm.tsx`. **Signup URL (confirmed in code):** the free-
trial entry is `https://app.opsapp.co/register` (`ops-site/src/lib/seo-redirects.ts`
301s `/signup`, `/sign_up`, `/register` to it). The build reads it from a config
constant; the value is known, not guessed.

---

## 0. Review log + verdict (2026-06-13)

**Three multi-agent passes.**

- **Pass 1 (8 agents):** hardened the original 3-question / 3-outcome design — inline
  result action, surfaced Enterprise guard, token/focus/a11y fixes. Verdict (still
  holds): with `depositsEnabled` OFF this is an **engagement + qualification** feature,
  not a deposit lever; success = handoff ratio, never the `tier_guide_completed` count.
- **Pass 2 (research → designs → adversary):** added the **4th outcome `ops`** ("you
  don't need a paid build — start the free trial; set it up yourself"), grounded in the
  standard-OPS capability boundary (§ 2.1).
- **Pass 3 — THIS revision (v3): the branch.** Pass-2's questions asked a prospect to
  audit OPS's feature set ("does OPS have a box for X?", "do your stages differ from
  OPS's built-in eight?"). **A cold prospect who has never opened OPS cannot answer
  that.** Per Jackson: most `/spec` traffic is cold. v3 **branches on OPS experience**
  as the first screen, and the cold path asks only questions answerable about the
  prospect's *own business* — never about OPS internals. The feature-gap questions move
  to the existing-user path, where they're honest. Validated by a **14-persona
  war-game**: every persona can now answer every question shown and routes to its true
  best fit (14/14; **8 prior misroutes fixed**).

**v3 design decisions locked with Jackson (2026-06-13):**
- The cold "trade-shape" question (C4) does **not** assert an OPS limitation cold — a
  trade with permit/inspection-type stages stays on the **OPS / start-free** floor with
  Setup as a prominent also-door + an honest "most pipelines fit the built-in stages —
  start free and check first" note. (Resolves the open judgment call: no cold capability
  assertion.)
- **Anti-upsell guard accepted:** an anxious "do it for me" on a *trivial* profile
  headlines OPS/free with Setup as the also-door — deliberately diverting low-scope
  Setup intent into free trials.
- Signup URL confirmed (`app.opsapp.co/register`).

**v3.1 — the Data Setup add-on (2026-06-13).** A real, implemented product was missing
from the outcome space: the **Data Setup add-on** (**$399.00 CAD one-time**, confirmed live
in Stripe; done-for-you data migration, bought in-app, § 07). v3 routed "bring my history
across" to a **$3,000 Setup**
— a ~10× over-quote. Fixed: simple data migration → **OPS / start-free + the $399 Data
Setup add-on** (cold: a rider; existing: a headline outcome); SPEC **Setup** is now
reserved for done-for-you *configuration* + custom stages/fields; only **complex** migration
(incumbent + multi-division) escalates to Enterprise (§ 2.1, § 3.2 Step 4, § 3.4). The
stale "add-ons not implemented" note in `12_SUBSCRIPTION_MANAGEMENT.md` was corrected in
the same session.

---

## 1. Problem & intent

A prospect lands on `/spec`, sees three packages, and can't tell which is theirs — or
whether they need one. The guide answers actively: ask the fewest questions that
genuinely discriminate, **for the audience that can actually answer them**, then hand
back a confident, honest answer — up to and including "you don't need to buy anything."

**The v3 constraint that shapes everything:** `/spec` traffic is mostly **cold
prospects who have never used OPS.** They can answer about *their own world* — trade,
size, structure, current tools, pains, and whether they want help — but they **cannot**
evaluate OPS's feature set ("is OPS missing X?"). Only an **existing user** can. So the
guide's first move is to find out which audience it's talking to, then ask that audience
only what it can honestly answer.

Non-negotiables:
1. **No upsell-by-default.** The honest answer wins; ties resolve to the lower
   commitment; the Enterprise guard is surfaced.
2. **Sometimes the honest answer is "don't pay us."** If standard OPS covers them →
   point at the free trial, Setup offered as the *done-for-you* option, never required.
3. **Every question answerable by its audience.** A cold prospect is never asked to
   audit OPS. A question they'd have to guess at is cut or moved to the existing path.

---

## 2. The four outcomes

Lowest commitment first; honest default = **OPS**.

| Outcome | Price (total / P1 deposit) | What it is | Cold-diagnosable? |
|---|---|---|---|
| **OPS** | subscription only ($90–$190/mo, **30-day free trial**) | Nothing to build/pay extra; self-serve config in Settings. `START FREE` → `app.opsapp.co/register`. | **Yes — the default floor.** |
| **Data Setup add-on** | **$399.00 CAD one-time** (`STRIPE_PRICE_DATA_SETUP` = `price_1S6c4FE…`, confirmed live) | **Done-for-you data migration** — ops imports your old jobs/clients/history for you. Bought in-app (Subscription tab) after starting free; files a `data_setup_requests` ticket. Implemented end-to-end (§ 07 / `03`). | **Yes — the honest answer for simple "bring my data across."** |
| **Setup** | $3,000 / $750 | Done-for-you **configuration** + the two things OPS can't self-serve (new/renamed pipeline stages, custom fields). *(Data migration is the $399 add-on above — NOT Setup.)* | Partly — via a stated done-for-you-**config** preference with real scope; never a cold OPS-feature claim. |
| **Build** | $8,500 / $2,125 | One custom module OPS doesn't have. | **No** — can't prove OPS lacks a feature before using it. Cold: a warm founder-conversation only. Headlined only on the existing path. |
| **Enterprise** | $18,000 / $4,500 | Multiple modules + **complex** data migration off an incumbent + structural complexity. | Yes — only when **migration AND structure** co-occur. |

**Honest-default rule:** every tie resolves to the lower tier; uncertainty routes to the
**free** product, never a paid engagement; the free OPS door is mandatorily surfaced
first on every Setup result that wasn't forced by a hard capability lock.

### 2.1 Standard OPS vs. paid Setup — the honest boundary (research-grounded)

Source: 00_EXECUTIVE_SUMMARY L90–138/223–261; 01_PRODUCT_REQUIREMENTS L1118–1148;
03_DATA_ARCHITECTURE permissions; 12_SUBSCRIPTION_MANAGEMENT L79–136; SPEC/01_BUSINESS_MODEL §2.

**Free + self-serve in standard OPS:** 30-day free trial (10 seats), self-serve signup;
all core features, no feature paywalls (scheduling, crew, the 8-stage pipeline CRM,
estimates, invoices, catalog, inventory, notes, calendar, email import, QuickBooks/Sage
OAuth connect); self-serve config of stage **colors / thresholds / follow-up rules /
win-probability**, lead sources, tags, roles, catalog, tax.

**Not self-serve — but split across two products (the v3.1 fix):**
- **Done-for-you data migration** (importing old jobs/clients/history) → the **Data
  Setup add-on ($399 one-time)**, bought in-app after starting free (§ 07). Connecting
  QuickBooks/Sage *going forward* is free; importing *history* is this add-on.
- **Custom configuration OPS can't self-serve** — (1) renaming/adding pipeline stages
  beyond the fixed eight, (2) custom fields — plus done-for-you workflow configuration →
  **SPEC Setup ($3,000)**.

Conflating these is the trap v3.1 closes: a prospect who just needs their data brought in
is a **$399 add-on**, not a $3,000 Setup. Everything else Setup sells is done-for-you
convenience, not a locked capability.

**Positioning is signed off (§ 0); the Data Setup price is confirmed at $399.00 CAD (§ 13.1).**

---

## 3. The branch + question paths

### 3.0 Branch — first screen (shared, answerable by anyone)

**`// WHERE YOU'RE AT` — "Where are you with OPS today?"**

| id | label | hint | leads to |
|---|---|---|---|
| `cold` | Haven't tried it yet — I'm just sizing it up | "Never logged in. I want to know what I'd need before I start." | **Cold path** (§ 3.1) — the default lane. |
| `existing` | I'm in OPS right now and something's blocking me | "Logged in, using it, and I've hit a wall I can't get past." | **Existing path** (§ 3.3). |

The hint wording is load-bearing: "in OPS right now / logged in" keeps a prospect who
hit a wall in their *old* tool (never logged into OPS) out of the existing lane. This
question asks about the visitor's relationship to OPS, not about OPS internals — so it
is answerable by everyone, and it is the only thing that lets each path ask audience-
appropriate questions.

### 3.1 Cold path questions (every one about the prospect's own world)

Up to five questions; **C2 is conditional** (skipped when C1 = `manual` — a paper shop
has nothing to migrate). So a manual-stack prospect answers 4, a tool-user 5.

**C1 `// WHAT YOU RUN ON` — "What are you running your business on right now?"**

| id | label | hint | signal |
|---|---|---|---|
| `manual` | Texts, paper, whiteboard, spreadsheets | "Nothing in a real system yet." | no tool → skip C2; ops/setup-lean. |
| `light_tool` | One or more apps — Jobber, Housecall, QuickBooks, AppFolio, ServiceTitan, anything | "Whatever you use today, light or heavy." | has a tool. **Weight is NOT read here** — migration is asked separately in C2. |

*Why this shape:* splitting tool-presence from migration kills the v2 misroutes where a
heavy-incumbent option was the only home for AppFolio (over-charged a no-data shop) and
where "my tool isn't on the list" stalled people. Naming incumbents = AI-discovery SEO.

**C2 `// YOUR HISTORY` — "Do you need your old history brought across into OPS, or are you fine starting clean?"** *(shown only if C1 ≠ manual)*

| id | label | hint | signal |
|---|---|---|---|
| `start_clean` | Fine starting clean — connecting going forward is enough | "I don't need the old records moved." | no migration. |
| `bring_history` | I need my history moved across — I can't lose it | "Years of jobs/clients/records that have to come over, not just connect from here." | **migrationSignal** (Setup floor; Enterprise with multi-division). |

*Why:* the tool-agnostic migration axis. A fact about *their data*, not about OPS. Copy
explicitly separates the **free** forward-connect from the **paid** history-move (the
QuickBooks trap: connecting QB is free; moving years of QB history is Setup-or-up).

**C3 `// HOW YOU'RE BUILT` — "How's your operation built?"**

| id | label | hint | signal |
|---|---|---|---|
| `solo` | One trade, one crew | "Just me, or a single tight crew." | neutral. |
| `multi_crew` | One trade, a few crews | "Growing, but still one line of work." | neutral — growth never inflates the tier. |
| `multi_division` | Multiple trades, divisions, subs, or locations | "Different divisions, subs to manage, or more than one location." | **structuralSignal** — escalates to Enterprise **only** when it co-occurs with `bring_history`. Never pulls a self-server off the free floor alone. |

**C4 `// YOUR TRADE` — "Does your trade run on stages or details a generic tool wouldn't know about?"** *(about HIS trade, never OPS)*

| id | label | hint | signal |
|---|---|---|---|
| `standard_flow` | No — lead, quote, schedule, invoice covers how I work | "A pretty standard flow." | none. |
| `special_stages` | Yes — my work moves through stages most CRMs don't have — permits, inspections, rough-in, draws, approvals | "Stages a generic pipeline wouldn't ship with." | **stagesSignal** — a *soft* nudge, **not** a cold Setup verdict (see routing). |
| `whole_capability` | Yes — there's a whole job a general tool just doesn't do — claims/supplements, takeoffs, route density, something specific to my trade | "A capability, not just a stage." | **buildLean** — surfaces the founder-escape; never a cold Build headline. |

*Why answerable cold:* it asks whether *his trade* has unusual needs — a thing a roofer
or restoration GC knows cold — without ever asking "does OPS have X." Per the v3 decision,
`special_stages` does **not** assert OPS can't do it; it keeps him on the free floor and
adds a Setup nudge + "most pipelines fit the built-in stages — start free and check first."

**C5 `// SETTING IT UP` — "Once you know what you need — set it up yourself, or have us do it?"** *(symmetric, free option first, has a not-sure landing)*

| id | label | hint | signal |
|---|---|---|---|
| `show_me` | Show me where things are, then I run with it | "A quick walkthrough or starter template — fast and free." | leans ops (guided self-start). |
| `myself` | I'll set it up myself | "Me or my admin. Settings are self-serve and free." | ops. |
| `not_sure` | Not sure yet — point me the right way | "I just know what I have isn't working." | **defer → ops** (uncertainty never monetized). |
| `do_for_me` | Rather you set it up for me, done right | "A done-for-you option, if you want it — not required." | done-for-you preference (only headlines Setup with a real scope signal — see routing). |

*Why de-weaponized:* the free option is listed first (scan-bias), `myself` is framed as
fast/free (not labor), `not_sure` restores the honest "send the unsure owner to the free
trial" case, and `do_for_me` no longer auto-charges a tiny shop.

### 3.2 Cold routing (deterministic; outcomes {ops, setup, enterprise}; Build = warm escape)

Inputs: `c1∈{manual,light_tool}`, `c2∈{start_clean,bring_history,na}`, `c3∈{solo,multi_crew,multi_division}`,
`c4∈{standard_flow,special_stages,whole_capability}`, `c5∈{show_me,myself,not_sure,do_for_me}`.
Ladder `ops < setup < enterprise`; **all ties resolve down.**

```
migrationSignal  = (c2 == bring_history)
structuralSignal = (c3 == multi_division)
stagesSignal     = (c4 == special_stages)
buildLean        = (c4 == whole_capability)
doneForYou       = (c5 == do_for_me)
configScope      = stagesSignal || structuralSignal   // a real reason to pay for done-for-you CONFIG

STEP 1 — Enterprise (complex migration is in-scope here, not the add-on):
  IF migrationSignal AND structuralSignal → ENTERPRISE (driver=migration).
     Result shows a DUAL affordance: "start the trial now / we'll scope your migration."
STEP 2 — Setup headline ($3,000 — done-for-you CONFIG only, NEVER migration):
  ELSE IF doneForYou AND configScope → SETUP (driver = stagesSignal ? trade_stages : structure).
STEP 3 — OPS floor (everything else) → OPS / START FREE:
  driver = fits_oob (myself, no signals) | guided_self (show_me) | deferred_unsure (not_sure)
  Setup also-door: ALWAYS present, leading the also-list; prominent when doneForYou (trivial profile).
  stagesSignal → add the Setup nudge note ("most pipelines fit the built-in stages — start free
     and check first; if they don't, that's Setup").
  buildLean → add the founder-escape (PRE-trial) + the Build hedge.
  headsUp = true when a lone signal sits unresolved (e.g. multi_division alone) → keep OPS, note.
STEP 4 — DATA SETUP rider (the v3.1 migration fix; orthogonal to the config outcome above):
  IF migrationSignal AND NOT structuralSignal → attach the **Data Setup add-on ($399)** to
     whatever the result is (OPS or Setup): "start free, then add Data Setup to bring your
     history in." dataSetupRider = true. Simple migration NO LONGER routes to $3,000 Setup.
```

**Key properties:** `light_tool` never inflates the tier (connecting forward is free).
**Simple "bring my history across" → OPS / start-free + the $399 Data Setup add-on rider,
not a $3,000 Setup** (the v3.1 fix; complex migration + multi-division is the only thing
that escalates to Enterprise). `do_for_me` on a trivial profile lands **OPS headline +
Setup prominent also-door** — not an auto-charge. `special_stages` is a nudge, never a cold
capability assertion. `not_sure` → free trial.

**Build, handled cold (three mechanisms, no false certainty):** (1) C4 `whole_capability`
is a cold-answerable *trade fact* that surfaces a **talk-to-the-founder escape** on the
OPS result (a self-aware domain expert talks to the founder *now*, not after a churned
trial); (2) every OPS result carries the Build hedge in copy ("start free — if it
genuinely can't do the one thing your trade needs, that's a Build; you'll know within
the trial"); (3) the escape is tagged `tier_guide_cold_build` **only** when `buildLean`
— a stages/migration need is never mislabeled Build.

### 3.3 Existing-user path questions (they can audit OPS — feature-gap questions are honest here)

**E1 `// THE WALL` — "What's the wall?" (MULTI-SELECT — check everything blocking you; explicit `CONTINUE`)**

| id | label | hint | signal |
|---|---|---|---|
| `setting` | A setting I couldn't find — colors, follow-up timing, win odds, lead sources, tags, roles, catalog, tax | "All self-serve — we'll point you to the exact screen." | ops-eligible. |
| `stages` | I need stages my work has that the app doesn't — permits, inspections, approvals — added or renamed | "Adding/renaming stages isn't self-serve. Setup does it." | setup (stages). |
| `fields` | I need custom fields on jobs or clients OPS has no box for | "Custom fields aren't self-serve. Setup adds them." | setup (fields). |
| `data` | I need old jobs/clients/history brought in from another system | "We bring it in for you — the Data Setup add-on. Scope decides the price." | migration → E2 (Data Setup add-on, or Enterprise if complex). |
| `missing` | A whole thing OPS just doesn't do — a feature or module that isn't in the app at all | "If OPS genuinely can't do it, that's a custom Build." | build-candidate → disconfirm → E3. |

Multi-select so co-occurring locks (stages **and** fields) both register. Resolve by
**max-commitment** across checked items; ties down. Phrased as *his* need (permits/
inspections), not "beyond the built-in eight" jargon.

**Missing-disconfirm interstitial** *(only if `missing` checked, before any Build verdict):*
"Before we call this a Build — a lot of 'OPS can't do this' turns out to be a setting. Is
what you need any of these? [auto follow-up reminders / stage colors / win-probability /
lead sources / tags / roles]." → **Yes** = re-route to `ops` (setting); **No, genuinely
not in the app** = proceed to E3. (Catches a wrong-but-certain "OPS won't do X" belief
before an $8.5k verdict.)

**E2 `// YOUR HISTORY` migration scope** *(only if `data`)*: `simple` (spreadsheet/one tool,
one business) → **Data Setup add-on ($399)**; `incumbent_simple` (off a full platform, one
business) → **Data Setup add-on ($399)**; `incumbent_complex` (full platform AND multiple
divisions) → **Enterprise**. *(Simple/mid migration is the cheap done-for-you add-on, not a
$3,000 Setup — § 2.1.)*

**E3 `// HOW BIG` build breadth** *(only if `missing` survived disconfirm)*: `one_module`
(one thing, rest fits) → **Build**; `several` (several missing, or module + migration +
multi-division) → **Enterprise**.

### 3.4 Existing routing (outcomes {ops, setup, build, enterprise})

Resolve E1 multi-select by max-commitment after the disconfirm; ties down. (1) only
`setting` → **OPS** — and the result **names the exact screen** per symptom (stage-color
picker; `autoFollowUpDays`/stale threshold in `pipeline_stage_configs`; etc.) so the free
verdict is *believed*, not a generic "check settings." Free QB/Sage forward-connect folds
here. (2) `stages`/`fields` (no migration/missing) → **SETUP**, driver lists **all**
checked locks (result + inquiry payload carry every lock, not one). (3) `data` → E2
(**simple/mid → Data Setup add-on $399; complex → Enterprise**). (4)
`missing` survives → E3. (5) multi-lock (e.g. `fields` + `missing`) → E3; `one_module` →
Build (fields folds into scope, surfaced); `several` → Enterprise. A single clean gap is
never inflated; co-occurring locks resolve up honestly.

### 3.5 Worked cases (14-persona war-game — scorecard 14/14)

Every persona answers every question shown **and** routes to its true best fit. The 8
fixes prove the v3 reframe works:

| Persona | Path · answers → outcome | What it proves |
|---|---|---|
| Dwayne — solo, paper, anxious do-for-me | cold · manual/–/solo/standard/do_for_me → **OPS** + Setup door | trivial-profile guard: anxious tap isn't monetized *(fixed: was Setup)* |
| Priya — multi-crew, one app, DIY | cold · light/start_clean/multi_crew/standard/myself → **OPS** | clean free floor |
| Rob — multi-crew, permit/rough-in stages, DIY | cold · light/start_clean/multi_crew/special_stages/myself → **OPS** + Setup nudge | C4 stays a nudge, no cold capability claim *(v3 decision)* |
| Frank — solo, QuickBooks **with history** | cold · light/bring_history/solo/standard/myself → **OPS / start free + Data Setup add-on ($399)** | simple history-move is the cheap add-on, not a $3k Setup *(v3.1 fix — a 10× over-quote removed)* |
| Sandra — solo, AppFolio, no data to move | cold · light/start_clean/solo/standard/myself → **OPS** | no-data shop not over-charged *(fixed: was Setup)* |
| Aaron — solo, paper, unsure | cold · manual/–/solo/standard/not_sure → **OPS** (deferred_unsure) | uncertainty → free trial *(fixed: was Setup — a blocker)* |
| Hector — multi-crew, needs a supplement *module*, DIY | cold · light/start_clean/multi_crew/whole_capability/myself → **OPS** + **founder-escape (pre-trial)** | a true cold Build need is captured warm, not churned *(fixed)* |
| Denise — solo, paper, wants a module, do-for-me | cold · manual/–/solo/whole_capability/do_for_me → **SETUP** + Build surfaced + escape | Build seen even on a Setup result *(fixed)* |
| Tina — multi-crew, paper, genuine do-for-me | cold · manual/–/multi_crew/standard/do_for_me → **OPS** headline + Setup prominent also-door | Setup is one deliberate click, not an auto-charge *(more robust)* |
| Gerald — GC, off Buildertrend **+ multi-division** | cold · light/bring_history/multi_division/standard/myself → **ENTERPRISE** + dual affordance | migration+structure overrides DIY; no dead-end |
| Olivia — multi-division, migrating, wants a module | cold · light/bring_history/multi_division/whole_capability/do_for_me → **ENTERPRISE** + Build in also-row | fully corroborated |
| Marcus — multi-crew, paper | cold · manual/–/multi_crew/standard/show_me → **OPS** | guided self-start |
| Bryce — **existing** user, "OPS won't auto-remind me" | existing · E1 missing → disconfirm catches it → **OPS** w/ deep screen-pointer | wrong-Build belief self-corrects to free *(fixed)* |
| Camille — **existing** user, needs stages **and** fields | existing · E1 [stages, fields] → **SETUP** carrying both locks | multi-select scopes fully *(fixed: was under-scoped)* |

---

## 4. Placement

Unchanged from prior: a slim SSR'd entry bar at the top of `#packages`, expanding inline
above the cards (Variant 1; takeover/section/right-rail rejected — the right 55% of the
desktop viewport is the fixed phone scene). Once the guide runs, **its result owns
"recommended" for the session** — suppress the hardcoded BUILD pill when the winner ≠
build, show "YOUR MATCH" on the matched card; on an **OPS** win suppress the pill
entirely (no paid tier is recommended) and there is no card handoff (the action is the
free trial). Keep the guide's interactive content in the left ~720px safe area
(`lg:w-[55%]` content column overlaps the fixed phone ~10% at the right).

---

## 5. Interaction & flow

```
[entry] → BRANCH → ┬─ cold: C1 → (C2?) → C3 → C4 → C5 → [result]
                   └─ existing: E1(multi)+CONTINUE → (disconfirm?) → (E2?/E3?) → [result]
```

- **Branch is the first screen** after expand. Single-select, auto-advance.
- **Cold path:** single-select auto-advance (≥44px BACK from C1, gesture-guarded commit
  ~360–420ms). C2 is skipped when C1 = `manual`. Progress counter reflects the *actual*
  length of the chosen path (4 or 5 cold steps after the branch; `02 / 05` style).
- **Existing path:** E1 is a **checkbox multi-select with an explicit `CONTINUE`** (no
  auto-advance; `setting`…`missing` are independent). The disconfirm interstitial and
  E2/E3 appear conditionally.
- **Result:** states the outcome plainly (name + one-line reason + bracketed "because you
  said X"). Primary action diverges:
  - **OPS** → `START FREE — 30 DAYS` → `app.opsapp.co/register` (config constant; routes
    through the same Quebec/regulated screening as normal signup — no bypass). Fires
    `tier_guide_trial_started`. Carries the Setup also-door, the stages-nudge / Build-
    hedge / headsUp notes as applicable, the founder-escape when `buildLean`, and — when
    `dataSetupRider` — the **Data Setup add-on note + `ADD DATA SETUP` affordance** ($399,
    "bring your history in once you're set up").
  - **Setup / Enterprise** → the inline pre-contextualized **inquiry form** (§ 12.7) —
    name/phone/email + a pre-filled "what do you need?" submitting the lead + the full
    answer payload to `/api/contact` (extended). Enterprise also shows a `START FREE`
    secondary (dual affordance). Setup leads its also-list with the free OPS door (unless
    forced by a hard lock on the existing path).
  - **Build** (existing path only) → the inquiry form pre-set to Build. Cold "build"
    intent is the founder-escape, never a headline.
- **Guard/heads-up/disconfirm notes** render as short `--tan`-railed lines, never hidden.
- **Back/restart** throughout; result carries a quiet `‹ BACK` (to the last question) +
  `START OVER`.

---

## 6. Copy

All strings via `ops-copywriter` before ship (Anti-Pitch; trust hooks "we don't default
to the expensive one" and "you might not need to pay us at all"). Terse, sentence-case
content / UPPERCASE authority, `//` + `[bracket]`, no emoji/exclamations, mono numbers.
The result composes from enumerated dictionary strings (no free-text interpolation; only
outcome *names* interpolate). **Honesty rules (load-bearing):** cold copy never asserts
an OPS feature gap (no unqualified "stages"/"fields" as self-serve or as a cold "OPS
can't"); the OPS reason scopes only to the free self-serve surface; visible copy uses no
internal stage-slug names.

---

## 7. Animation choreography

Routed through `animation-studio:animation-architect` → `web-animations`. Adopts the
`SpecOpsBoard.tsx` selection + reduced-motion vocabulary. Single easing
`cubic-bezier(0.22,1,0.36,1)`, no spring/bounce, durations from `theme.animation`,
Framer Motion, `will-change` only on the active element. Beats: expand (height 0→auto,
350ms); branch/question transition (fade + 8px slide, 200–240ms, `AnimatePresence
mode="wait"`); single-select commit (2px **accent** rail + `bg-ops-accent/[0.04]`,
~390ms hold → advance); E1 checkbox toggle (150ms, **no** auto-advance); result reveal
(fade + slide 300ms, neutral hairline underline draws 500ms — a stamp, not a parade).
**Accent = CTA-fill + focus-ring ONLY** (container uses `--line`, progress is a contrast
step, underline is neutral). No ambient motion. Reduced motion → instant final state,
opacity-only ≤200ms, `behavior:'auto'` scroll.

---

## 8. Wireframes

**Branch (first screen):**
```
┌──────────────────────────────────────────────┐
│ // WHERE YOU'RE AT                            │
│ Where are you with OPS today?                 │
│ │▍ Haven't tried it yet — just sizing it up   │
│ ├─ I'm in OPS right now and something's       │
│ │  blocking me                                │
└──────────────────────────────────────────────┘
```

**Cold question (single-select, two-line rows, conditional C2):**
```
┌──────────────────────────────────────────────┐
│ // WHAT YOU RUN ON                   01 / 05  │
│ What are you running your business on now?    │
│ │▍ Texts, paper, whiteboard, spreadsheets     │   (→ skips C2)
│ ├─ One or more apps — Jobber, QuickBooks, …   │
│ ‹ BACK                                        │
└──────────────────────────────────────────────┘
```

**Existing E1 (multi-select + CONTINUE):**
```
┌──────────────────────────────────────────────┐
│ // THE WALL                          01 / …   │
│ What's the wall? (check everything)           │
│ [ ] A setting I couldn't find — colors, …     │
│ [✓] Stages my work has the app doesn't —      │
│     permits, inspections, approvals           │
│ [✓] Custom fields OPS has no box for          │
│ [ ] Old history brought in from another system│
│ [ ] A whole thing OPS just doesn't do         │
│ ‹ BACK                          [ CONTINUE ]  │
└──────────────────────────────────────────────┘
```

**Result — OPS (free):**
```
// YOUR MOVE
OPS  ▔▔▔
Standard OPS already covers you. Start the 30-day free trial — set your colors,
follow-up timing, lead sources, roles, catalog and tax yourself, in an afternoon.
You don't pay us a cent past your subscription.
[ everything you need is already in OPS — you just make it yours ]
The only things you can't switch on yourself are new/renamed pipeline stages and
custom fields — if you ever need those, that's Setup.            (carve-out)
most pipelines fit the built-in stages — start free and check first.   (stages nudge, if special_stages)
start free — if it genuinely can't do the one thing your trade needs, that's a Build.  (hedge / founder-escape if buildLean)
bringing your history? the Data Setup add-on imports it for you — $399, one-time.  (rider, if dataSetupRider)
[ START FREE — 30 DAYS ]   → app.opsapp.co/register
rather we set it up for you? → Setup       ·       [ ADD DATA SETUP ]  (if dataSetupRider)
```

**Result — Setup / Enterprise / Build:** headline + reason + driver; `[ START YOUR
{tier} ]` → inline inquiry form (Enterprise also shows `START FREE` secondary); Setup
also-list leads with the free OPS door.

---

## 9. SEO / SSR posture

Below the fold, text-only → no LCP impact. The entry bar + a static "how to choose"
summary ("Most people just need OPS — start free; if you're switching with history, the
$399 Data Setup add-on brings it in. Setup configures it for you; Build adds a custom
module; Enterprise rebuilds + migrates.") are SSR'd in the collapsed
container (indexed, JS-off fallback). The questionnaire hydrates as progressive
enhancement. Keywords: the named incumbents (Jobber/Housecall/QuickBooks/AppFolio/
ServiceTitan/Buildertrend) and the four outcomes. No new JSON-LD required.

---

## 10. i18n — the key set

New `guide.*` namespace in **both** `en/spec.json` and `es/spec.json`, flat dot-keys,
option arrays of `{id,label,hint}` (ids shared, scoring keys on them), added in the same
commit as the § 12.0 base fix, behind the `t()` raw-key CI canary. **All copy passes
ops-copywriter before ship.** EN below is the complete set; the ES mirror is generated
alongside the ops-copywriter pass at build (faithful, same ids, `//`/`[ ]` preserved,
"4 pagos" register) — the design locks the keys + meaning so nothing is dropped.

### 10.1 Branch + cold path (EN)

| Key | Value |
|---|---|
| `guide.entry.label` | `// NOT SURE WHICH ONE` |
| `guide.entry.headline` | `We'll tell you which one's yours — or if you even need us.` |
| `guide.entry.subnote` | `[ a few questions · no upsell · no signup ]` |
| `guide.entry.cta` | `START` |
| `guide.branch.kicker` | `// WHERE YOU'RE AT` |
| `guide.branch.prompt` | `Where are you with OPS today?` |
| `guide.branch.options` | `[ {id:"cold", label:"Haven't tried it yet — I'm just sizing it up", hint:"Never logged in. I want to know what I'd need before I start."}, {id:"existing", label:"I'm in OPS right now and something's blocking me", hint:"Logged in, using it, and I've hit a wall I can't get past."} ]` |
| `guide.c1.kicker` | `// WHAT YOU RUN ON` |
| `guide.c1.prompt` | `What are you running your business on right now?` |
| `guide.c1.options` | `[ {id:"manual", label:"Texts, paper, whiteboard, spreadsheets", hint:"Nothing in a real system yet."}, {id:"light_tool", label:"One or more apps — Jobber, Housecall, QuickBooks, AppFolio, ServiceTitan, anything", hint:"Whatever you use today, light or heavy."} ]` |
| `guide.c2.kicker` | `// YOUR HISTORY` |
| `guide.c2.prompt` | `Do you need your old history brought across into OPS, or are you fine starting clean?` |
| `guide.c2.options` | `[ {id:"start_clean", label:"Fine starting clean — connecting going forward is enough", hint:"I don't need the old records moved."}, {id:"bring_history", label:"I need my history moved across — I can't lose it", hint:"Years of jobs/clients/records that have to come over, not just connect from here."} ]` |
| `guide.c3.kicker` | `// HOW YOU'RE BUILT` |
| `guide.c3.prompt` | `How's your operation built?` |
| `guide.c3.options` | `[ {id:"solo", label:"One trade, one crew", hint:"Just me, or a single tight crew."}, {id:"multi_crew", label:"One trade, a few crews", hint:"Growing, but still one line of work."}, {id:"multi_division", label:"Multiple trades, divisions, subs, or locations", hint:"Different divisions, subs to manage, or more than one location."} ]` |
| `guide.c4.kicker` | `// YOUR TRADE` |
| `guide.c4.prompt` | `Does your trade run on stages or details a generic tool wouldn't know about?` |
| `guide.c4.options` | `[ {id:"standard_flow", label:"No — lead, quote, schedule, invoice covers how I work", hint:"A pretty standard flow."}, {id:"special_stages", label:"Yes — my work moves through stages most CRMs don't have — permits, inspections, rough-in, draws, approvals", hint:"Stages a generic pipeline wouldn't ship with."}, {id:"whole_capability", label:"Yes — there's a whole job a general tool just doesn't do — claims, takeoffs, route density, something specific to my trade", hint:"A capability, not just a stage."} ]` |
| `guide.c5.kicker` | `// SETTING IT UP` |
| `guide.c5.prompt` | `Once you know what you need — set it up yourself, or have us do it?` |
| `guide.c5.options` | `[ {id:"show_me", label:"Show me where things are, then I run with it", hint:"A quick walkthrough or starter template — fast and free."}, {id:"myself", label:"I'll set it up myself", hint:"Me or my admin. Settings are self-serve and free."}, {id:"not_sure", label:"Not sure yet — point me the right way", hint:"I just know what I have isn't working."}, {id:"do_for_me", label:"Rather you set it up for me, done right", hint:"A done-for-you option, if you want it — not required."} ]` |

### 10.2 Existing path (EN)

| Key | Value |
|---|---|
| `guide.e1.kicker` | `// THE WALL` |
| `guide.e1.prompt` | `What's the wall?` |
| `guide.e1.subprompt` | `[ check everything that's blocking you ]` |
| `guide.e1.continue` | `CONTINUE` |
| `guide.e1.options` | `[ {id:"setting", label:"A setting I couldn't find — colors, follow-up timing, win odds, lead sources, tags, roles, catalog, tax", hint:"All self-serve — we'll point you to the exact screen."}, {id:"stages", label:"I need stages my work has that the app doesn't — permits, inspections, approvals — added or renamed", hint:"Adding/renaming stages isn't self-serve. Setup does it."}, {id:"fields", label:"I need custom fields on jobs or clients OPS has no box for", hint:"Custom fields aren't self-serve. Setup adds them."}, {id:"data", label:"I need old jobs/clients/history brought in from another system", hint:"Bringing history across isn't self-serve. Scope decides the tier."}, {id:"missing", label:"A whole thing OPS just doesn't do — a feature or module that isn't in the app at all", hint:"If OPS genuinely can't do it, that's a custom Build."} ]` |
| `guide.disconfirm.prompt` | `Before we call this a Build — a lot of "OPS can't do this" turns out to be a setting. Is what you need any of these?` |
| `guide.disconfirm.options` | `[ {id:"is_setting", label:"Yes — one of those", hint:"auto follow-up reminders · stage colors · win-probability · lead sources · tags · roles"}, {id:"genuinely_missing", label:"No — genuinely not in the app", hint:"I've looked. It isn't there."} ]` |
| `guide.e2.kicker` | `// YOUR HISTORY` |
| `guide.e2.prompt` | `What are you bringing across?` |
| `guide.e2.options` | `[ {id:"simple", label:"A spreadsheet or one simple tool, one business", hint:"Straightforward to move."}, {id:"incumbent_simple", label:"Off a full platform, one business", hint:"A real migration, one operation."}, {id:"incumbent_complex", label:"Off a full platform, and multiple divisions or branches", hint:"A real migration across a complex operation."} ]` |
| `guide.e3.kicker` | `// HOW BIG` |
| `guide.e3.prompt` | `How much is missing?` |
| `guide.e3.options` | `[ {id:"one_module", label:"One thing — the rest of OPS fits how I work", hint:"A single custom module."}, {id:"several", label:"Several things — or a module plus migration and multiple divisions", hint:"More than one custom piece."} ]` |

### 10.3 Results + drivers (EN)

| Key | Value |
|---|---|
| `guide.result.label` | `// YOUR MOVE` |
| `guide.result.ops.reason` | `Standard OPS already covers you. Start the 30-day free trial — you (or your office admin) set your pipeline colors, follow-up timing, stale-deal thresholds, win-odds, lead sources, tags, team and roles, catalog and tax, yourself, in an afternoon. You don't pay us a cent past your subscription.` |
| `guide.result.ops.carveout` | `The only things you can't switch on yourself are renaming or adding pipeline stages beyond the built-in eight, and custom fields on your jobs or clients — if you ever need those, that's Setup.` |
| `guide.result.ops.stagesNudge` | `Heads up — your trade may want stages OPS doesn't ship. Most pipelines fit the built-in ones, so start free and check first; if they don't, that's a quick Setup.` |
| `guide.result.ops.buildHedge` | `Start free — if OPS genuinely can't do the one thing your trade needs, that's a Build, and you'll know within the trial.` |
| `guide.result.ops.headsUpMigration` | `One heads-up — if you've got history to move over, that's where Setup earns its keep. Start free; we're here if you hit that.` |
| `guide.result.ops.setupAlt` | `Rather we set it up around your workflow for you? That's Setup — two discovery sessions, we map OPS to how your jobs run, deploy it to staging for you to check, then a recorded walkthrough. $3,000, four milestones, 30-day money-back. The done-for-you version of what you'd otherwise do free.` |
| `guide.result.ops.founderEscape` | `Sounds like you already know you need something custom. Skip the guessing — tell the founder what you're after.` |
| `guide.result.setup.reason` | `We shape OPS around the way you already work — your pipeline, your stages, your fields, dialed to your business. Nothing for you to learn. Just OPS, built to fit.` |
| `guide.result.build.reason` | `We build the one thing you're missing — a custom module for your trade, on iOS and web, wired straight into your live OPS.` |
| `guide.result.enterprise.reason` | `Multiple custom modules, your data moved off the old system, your tools integrated. Your whole operation, rebuilt on OPS.` |
| `guide.result.enterprise.dualNote` | `No reason to wait — start the trial today while we scope your migration.` |
| `guide.result.dataSetup.rider` | `Bringing your history with you? Once you're in, the Data Setup add-on imports your old jobs, clients and records for you — $399, one-time. Connecting going forward is free; moving the history across is the add-on.` |
| `guide.result.dataSetup.reason` | `You've got history to bring across — that's the Data Setup add-on. Once you're set up, we import your old jobs, clients and records for you. $399, one-time, and we handle the move.` |
| `guide.result.ctaDataSetup` | `ADD DATA SETUP` |
| `guide.driver.data_setup` | `[ you've got history to bring in — that's the Data Setup add-on, not a custom build ]` |
| `guide.driver.fits_oob` | `[ everything you need is already in OPS — you just make it yours ]` |
| `guide.driver.guided_self` | `[ a quick walkthrough and you're running — nothing to build or buy ]` |
| `guide.driver.deferred_unsure` | `[ not sure yet? start free — it's the fastest way to find out ]` |
| `guide.driver.done_for_you` | `[ you'd rather we set it up for you — that's exactly what Setup is ]` |
| `guide.driver.trade_stages` | `[ your trade runs on stages a generic tool doesn't ship ]` |
| `guide.driver.data_migration` | `[ you've got history to bring across — that's Setup, not a free connect ]` |
| `guide.driver.setting` | `[ what's blocking you is a setting — here's the exact screen ]` |
| `guide.driver.build_one` | `[ one custom thing OPS doesn't do — the rest fits ]` |
| `guide.driver.migration` | `[ you're moving off a system that has to come with you ]` |
| `guide.driver.structure` | `[ multiple trades, divisions, or locations ]` |
| `guide.driver.several` | `[ several custom pieces — that's the full build ]` |
| `guide.result.ctaTrial` | `START FREE — 30 DAYS` |
| `guide.result.ctaPrimary` | `START YOUR {tier}` |
| `guide.result.ctaPrimaryDeposit` | `PAY {tier} DEPOSIT` |
| `guide.result.ctaFounder` | `TELL THE FOUNDER` |
| `guide.result.opsSetupLink` | `rather we set it up for you? → Setup` |
| `guide.result.alsoLabel` | `ALSO CONSIDER` |
| `guide.also.ops` | `you can set all this up yourself, free — start the trial.` |
| `guide.also.setup` | `if you'd rather we configure it around your workflow for you.` |
| `guide.also.build` | `if one custom module would close the gap.` |
| `guide.also.enterprise` | `if it's several pieces, or a migration.` |
| `guide.back` | `‹ BACK` |
| `guide.restart` | `START OVER` |
| `guide.a11y.progress` | `Question {n} of {total}` |
| `guide.a11y.recommended` | `Your match: {outcome}` |

*(Inquiry-form keys `guide.inquiry.*` — heading, name/phone/email/message, per-tier
summary + prefill, submit/sending/success/error — carry over from § 12.7 unchanged.)*

---

## 11. Accessibility

- **Branch + cold questions:** `radiogroup`/`role=radio` + `aria-checked`, arrow-key nav,
  Space/Enter selects + auto-advances. **E1 is a `group` of native checkboxes** + explicit
  `CONTINUE` (Tab/Space, no auto-advance); the disconfirm + E2/E3 are radiogroups.
- **Focus ring (mandatory accent):** `:focus-visible → outline:1.5px solid var(--ops-accent);
  outline-offset:2px` on every interactive element incl. the OPS free-trial CTA, the
  founder-escape, and `CONTINUE`.
- **Focus management:** expand → branch; branch → first option of the chosen path; advance
  → next question's first control; `‹ BACK` → prior answer; result → heading (`tabindex=-1`).
- **Announce** progress (`guide.a11y.progress`) and outcome (`aria-live=polite`,
  `guide.a11y.recommended`). Never color-alone (rail + `aria-checked` + dim). `theme`
  contrast ladder. ≥44px targets. Reduced motion per § 7. Keyboard-only completes both
  paths incl. the E1 checkbox group → CONTINUE and the disconfirm.

---

## 12. Implementation plan

### 12.0 Hard precondition — base-dictionary reconciliation (BLOCKER)

Before any `guide.*` keys land, fix the Phase-1 `spec.json` drift: `en/spec.json` is
missing `startFrom`, `headlineSub`, `milestoneAmount`, `packages.milestones.*` (read by
`SpecPageContent.tsx`/`PackageCard.tsx`) while carrying stale `packages.<tier>.price`/
`.deposit` + "50%" copy — so the cards the guide points at render raw keys in prod today.
Restore the missing keys + strip the stale ones in both locales, verified by a `t()`
raw-key CI canary. Separate base-page hygiene; coordinate with sibling WIP.

### 12.1 Pure logic module — `src/lib/spec/tier-guide.ts` (new)

```ts
export type Outcome = 'ops' | 'data_setup' | 'setup' | 'build' | 'enterprise';
//  'data_setup' = the $399 Data Setup add-on. A headline outcome on the existing path
//  (E1 'data' alone); on the cold path simple migration rides as `dataSetupRider` on an
//  OPS/Setup result rather than as its own winner.
export type Branch = 'cold' | 'existing';
// cold answers
export interface ColdAnswers {
  c1: 'manual' | 'light_tool';
  c2: 'start_clean' | 'bring_history' | 'na';   // 'na' when c1==='manual'
  c3: 'solo' | 'multi_crew' | 'multi_division';
  c4: 'standard_flow' | 'special_stages' | 'whole_capability';
  c5: 'show_me' | 'myself' | 'not_sure' | 'do_for_me';
}
// existing answers
export interface ExistingAnswers {
  walls: Array<'setting' | 'stages' | 'fields' | 'data' | 'missing'>;  // multi-select
  disconfirm?: 'is_setting' | 'genuinely_missing';                     // only if 'missing'
  e2?: 'simple' | 'incumbent_simple' | 'incumbent_complex';            // only if 'data'
  e3?: 'one_module' | 'several';                                       // only if 'missing' survived
}
export interface GuideResult {
  branch: Branch;
  winner: Outcome;
  also: Outcome[];
  driver: string;
  founderEscape: boolean;     // cold buildLean → show TELL THE FOUNDER
  setupNudge: boolean;        // cold special_stages on an OPS win
  buildHedge: boolean;        // OPS win, surface the "if it can't, that's a Build" line
  headsUp: boolean;           // lone unresolved signal
  dualAffordance: boolean;    // cold Enterprise → also show START FREE
  dataSetupRider: boolean;    // cold simple migration → $399 Data Setup add-on note + CTA
  settingPointer?: string;    // existing 'setting' win → exact screen id
}
export function recommendCold(a: ColdAnswers): GuideResult;       // §3.2
export function recommendExisting(a: ExistingAnswers): GuideResult; // §3.4
```

Ship `__tests__/tier-guide.test.ts` covering all 14 § 3.5 personas **plus**: `light_tool`
never inflates; `do_for_me` trivial-profile → ops; `special_stages` never headlines Setup
cold; `not_sure` → ops; cold Enterprise requires migration AND structure; the existing
disconfirm reroutes `missing`→`setting`; multi-lock max-commitment; and the **firewall**
(no cold answer can produce `build` as a winner).

### 12.2 Components — `src/components/spec/tier-guide/` (new)

`SpecTierGuide.tsx` (branch + path state), `GuideQuestion.tsx` (single-select), 
`GuideWallQuestion.tsx` (E1 checkbox multi-select + CONTINUE), `GuideDisconfirm.tsx`,
`GuideResult.tsx` (four outcomes + the OPS notes/escape vs the inquiry form),
`GuideInquiry.tsx` (§ 12.7), `tier-guide-copy.ts` (`t(dict,…)` assembly). Small,
presentational; state only in the container.

### 12.3 Wiring into the page

Render `<SpecTierGuide>` at the top of `SpecPricing`. On a **paid** `onRecommend`:
`setExpandedTier` + `highlightTier` + scroll (desktop `block:'start'`+offset) + pill
override (suppress hardcoded BUILD pill when winner≠build; "YOUR MATCH" on the matched
card). On an **OPS** win: suppress the pill, no card handoff, render the free-trial CTA.
Screenshot-verify the desktop scroll clears the fixed phone.

### 12.4 i18n

Add the § 10 key set to `en` + `es` in one commit after § 12.0, behind the canary.

### 12.5 Analytics

Client-side `trackMarketingEvent` (gtag + Vercel), no PII; the inquiry submit is the one
server touch (§ 12.7).

| Event | When | Properties |
|---|---|---|
| `tier_guide_viewed` | entry in viewport (once) | `{ locale }` — START denominator |
| `tier_guide_started` | START clicked | `{ locale }` |
| `tier_guide_branched` | branch answered | `{ branch }` |
| `tier_guide_answered` | each select (E1 fires on CONTINUE with the array) | `{ step, question_id, option_id(s) }` |
| `tier_guide_completed` | result shown | `{ lane, recommended_outcome, driver, setup_nudge, build_hedge, heads_up, dual_affordance }` |
| `tier_guide_trial_started` | OPS / Enterprise `START FREE` clicked | `{ lane, driver }` |
| `tier_guide_cold_build_escape` | founder-escape clicked (cold buildLean) | `{ driver:'whole_capability' }` |
| `tier_guide_missing_disconfirm_recovered` | existing `missing`→`setting` reroute | `{}` |
| `tier_guide_setup_downresolved` | trivial-profile guard suppressed a Setup headline | `{}` |
| `tier_guide_inquiry_opened` / `_submitted` | paid primary CTA / form submit | `{ recommended_tier, driver, lane, source:'tier_guide' }` |

**Success metric:** the split funnel — OPS/Enterprise completions → `trial_started`
(free-signup intent); Setup/Build/Enterprise completions → `inquiry_submitted` (later →
`stripe_checkout_completed`). The `recommended_outcome` distribution is itself a signal:
a healthy honest guide sends a real share to `ops`. `tier_guide_completed` count alone is
vanity. New diagnostics: `setup_downresolved` (anxiety-monetization prevented),
`missing_disconfirm_recovered` (wrong-Build beliefs caught), `cold_build_escape` (warm
Build leads captured pre-trial).

### 12.6 Build-complexity estimate

**Moderate, one focused session for the guide** + the separate § 12.0 dictionary fix +
the § 12.7 `/api/contact` extension (small). Two routing functions (~140 lines pure TS) +
a thorough test suite (the routing guards are the risk surface — test all 14 personas).
The E1 multi-select + disconfirm are the only genuinely new UI patterns; the rest reuses
existing selection/card/motion patterns.

### 12.7 Inquiry submission — the one server touch (reuses existing backend)

Paid results submit via the existing `POST /api/contact` → `contact_messages` (+ newsletter
upsert). **Extend, don't rebuild:** accept optional `{ phone, company?, tier, lane,
guide:<answer payload>, source:'tier_guide' }`; store context in a new `metadata jsonb`
column (schema change → mirror migration to `migrations/`, update `03_DATA_ARCHITECTURE.md`,
verify the live table via Supabase MCP first); notify Jackson via the existing
`notifications.ts`/email-outbox path tagged `source:tier_guide`; `GuideInquiry.tsx`
mirrors `ContactForm.tsx` styling/states, pre-fills from `guide.inquiry.prefill.<tier>`,
confirms inline. The OPS outcome does **not** hit this route — it links
`app.opsapp.co/register`. The cold founder-escape posts here tagged `tier_guide_cold_build`.

---

## 13. Open questions for Jackson

The structural calls, the signup URL, and positioning are resolved (§ 0). **Resolved
2026-06-13:** positioning sign-off — *yes*, accept the deliberate leak of low-scope Setup
intent into the free trial; the migration→Data-Setup-add-on rework (§ 2.1, § 3.2 Step 4);
the §12 bible correction. Remaining:

1. **Data Setup price — RESOLVED.** Confirmed live in Stripe 2026-06-13: **$399.00 CAD,
   one-time** (`STRIPE_PRICE_DATA_SETUP` = `price_1S6c4FEooJoYGoIwIHx3gzQA`, `prod_T2hTzqU8jtkKtU`,
   `livemode`). Copy now reads "$399". *Build should still render the live
   `/api/stripe/addon/prices` amount rather than hardcode it, so a Stripe price change never
   leaves the guide stale.*
2. **`do_for_me` guard threshold (minor).** A one-app solo, standard flow, no migration who
   taps "do it for me" down-resolves to OPS + Setup door. *Rec:* keep (don't charge $3k for
   20 min of config). Confirm, or let `light_tool` + do_for_me headline Setup.
3. **"Up to 3 custom configurations"** — confirm whether Setup's published cap is firm "3"
   or an approximation (the canonical model says "stages + fields" without a number).
4. **Soft regulated-workflow nudge** on a Build/Enterprise result that sounds regulated?
   *Rec:* keep eligibility downstream; the free-trial path already routes through screening.
5. **Mobile:** sequential single-screen-per-question (rec) vs. a combined screen.

**Considered and rejected (do not re-raise without new evidence):** asking cold prospects
to audit OPS's feature set (the v2 flaw v3 exists to fix); a single unbranched funnel
(cold and existing users cannot answer the same questions); gating the build behind
deposits ON (ship now as qualification + the instant free-trial path, gated only on § 12.0);
a scored trade/crew/urgency personalizer (cut — padding + misroute risk; rides only on the
inquiry form, firewalled from the score).

---

## 14. Confirmation of scope

- No production code written; no shipped `/spec` component, route, dictionary, or `lib`
  file modified. Only this design doc + the non-production prototype under `specs/`.
- No flags flipped, nothing deployed, no `git push`.
- Reuses the existing `/spec` composition, interaction/motion/token/i18n patterns, the
  existing `/api/contact` backend (extended), and the confirmed `app.opsapp.co/register`
  signup entry.
- Validated by a 14-persona war-game (14/14 answerable + correctly routed). The honest
  framing it ships under: a **qualification + honest-routing** feature — it sends fit
  prospects to paid SPEC, unfit ones to the free trial, and captures genuine cold custom-
  build intent as a warm founder lead. Real conversion proof arrives once deposits are ON
  and § 12.0 lands; the `ops`/free-trial path is the one honestly-instant outcome today.
