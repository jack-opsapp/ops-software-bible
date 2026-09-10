# The legacy Google Ads account — what it actually bought (2026-09-10)

Source: the account's full history pulled straight from Google (v25 `searchStream`, customer 4454506598,
2025-01-01 → 2026-09-09) — campaigns, conversion actions, keywords, ads, search terms, geography, months —
checked against OPS's own signup records (`trial_attributions`, `companies`). Raw pulls:
`ops-web/docs/artifacts/ads-engine/p2/legacy-analysis/`. The warehouse was not enough on its own: it never
backfilled keyword, ad or ad-group history, and its search-term table covers $995 of the $4,778 spent.

## The answer

**Nothing in the old account can be shown to have produced a customer.** It spent $4,777.80 between
February 2025 and March 2026 (nothing since), bought 8,495 clicks and reported 355 conversions — and not one
of those conversions was an OPS trial.

| What Google counted | Count | What it really was |
|---|---:|---|
| Join Ops SIgnup | 202 | A form on the retired Bubble page `opsapp.co/join_ops`, which now redirects to `/plans` |
| OPS APP First open | 129 | App installs opened once — not signups |
| Quiz Signup v2 | 18 | A lead-magnet quiz form |
| Homepage Signup | 6 | Old homepage form |

All four were removed or demoted by phase 1 (2026-09-09); the account now counts trial started, trial
activated and paid.

OPS's own records cannot fill the gap. Of 64 recorded trials, **none carries a Google click id** — click-id
capture did not exist until phase 1. Company and trial dates only begin in February 2026 (the migration
stamped older accounts), so the $2,247 spent February–April 2025 cannot be lined up against signups at all.
From April to August 2026 there were 15 trials with $0 of ad spend. One paying customer told us they came from
an "Internet Advertisement" (trial 2026-02-19, paid 2026-05-26), in a month when two Google campaigns ran — it
is the only customer who could have come from an ad, and it could as easily have been Meta.

## Where the money went

| Channel | Spend | Clicks | Reported conversions |
|---|---:|---:|---:|
| Search | $1,418 | 228 | 6 |
| Display | $1,344 | 4,824 | 130 |
| Performance Max | $1,356 | 1,626 | 90 |
| App install | $659 | 1,817 | 129 |

Display's click-through rates of 9–13% at $0.23–0.41 a click are the signature of accidental taps inside
mobile apps, not of intent. 16% of all spend landed outside Canada and the US — the UK, Sweden, South Africa,
Finland, Ireland, Australia and five more.

## Search, specifically — the only part comparable to what is built now

- **Broad match was $1,308 of the $1,418.** Exact match bought one click, for $110. Phrase bought nothing.
- **The keywords bought the wrong people.** The biggest spender was `electronic signature app` ($296, 85
  clicks). Next came `mobile service business software` ($239 for 8 clicks — $30 each) and homeowner searches
  such as `same day handyman service`, `same day cleaning service` and `small moving company`.
- **Single clicks cost $136 and $110.** `what is housecall pro` and `jobber free trial`, one click each, on
  broad match with no bid ceiling.
- **Two search terms "converted", into the dead form:** `signature generator` (3 — junk) and
  `apps similar to jobber` (3). The second is the one real signal in the account.
- **The copy made claims it could not back.** `Earns $400/Month For You`, `122% or more ROI Every Month`,
  `Saves 2.5+ Hours Weekly` (CTR 1.7%); elsewhere `[ Dominate Jobs. ]` and `OPS: Maximum Efficiency.`
  (CTR 1.3–1.9%). Every ad sent people to `opsapp.co/join_ops`.

## What this means for the account built on 2026-09-09

The history does not tell us whether search can produce trials at a price OPS can afford — the old account
never ran a test that could answer that. The rebuild is designed to be that test. What the history does do is
confirm each of the rebuild's defences against a failure it actually suffered:

| What went wrong before | What the rebuild does |
|---|---|
| Broad match bought e-signature and homeowner searches | Exact and phrase only; the planner rejects broad positive keywords |
| Single clicks at $110–136 | A ceiling of $9–12 on every campaign |
| 16% of spend abroad | Presence targeting, US and Canada only |
| Half the budget on display, app and Performance Max | Search only |
| Junk search terms | Five blocked-term lists seeded from exactly these terms |
| Unprovable ROI numbers in the ads | Copy rules reject any number that is not a published price |
| Every ad sent to a page that no longer exists | Seven pages, each matched to what its searcher typed |
| "Conversions" were form fills and app opens | Conversions are trials, activations and payments, tied to the click |

The one positive signal — `apps similar to jobber`, competitor-switching intent — is already a keyword in
`SWITCH · US`. No change to the blueprint follows from this review.

## The copy — what grabbed attention, line by line

Source: every legacy ad's text (`adText.json`) and Google's per-line results (`assetPerf.json`, 114 text
lines scored). The signal is attention, not sales — no line can be tied to a paying customer, search lines ran
on broad-match junk traffic, and in-app placements inflate app and display click rates. Read it as "what made
people look", nothing stronger.

**Concrete pain in the owner's own words won on every channel.**

| Line | Channel | Click rate | Impressions |
|---|---|---:|---:|
| Would you hire a crew member who pays for themselves? That's OPS. | Search | 18.2% | 203 |
| Eliminate status check calls. | App | 12.2% | 2,181 |
| No more "where's the job?" | App | 7.6% | 2,762 |
| Zero learning curve = Zero training cost (Tested on old-timers) | App | 7.4% | 4,104 |
| Cut The Slack. Get OPS. | Search | 6.4% | 373 |

**Maker credibility with specifics won too:** `Built By Trades, For Trades.` (8.9% app, 2.6% search), `Built by
necessity on actual job sites. Not VC-funded guesswork.` (6.9%), `Never Built In A Meeting Room` (6.1%, Google
rated BEST), `Every feature tested on real job sites. Overcomplicated ones got deleted.` (BEST).

**The military swagger lost everywhere.** Fourteen bracketed search headlines — `[ Dominate Jobs. ]`,
`[ Crush Inefficiency. ]`, `[ Zero Slack. All Results. ]`, `[ OPS: Maximum Efficiency. ]` — drew **zero clicks
across roughly 5,000 impressions**. In app ads, `Run an elite unit.` (2.3%), `Own your operation.` (1.3%) and the
`elite operators` descriptions were rated LOW.

**Money claims drew clicks but cannot be proven.** `Earns $400/Month For You.` (4.2%), `122% or more ROI Every
Month.` (3.5%), `2 Hours Saved Weekly = Saves you $4800 annually` (6.9%). The copy rules reject every one; the
honest form of the money angle is the published price.

**Naming the competitor worked when it said something:** `Jobber is overcomplicated.` 3.2% against
`Housecall Pro? OPS.` at 1.2%. (The first also breaks the trademark forms the copy rules allow.)

**Against the 2026-09-09 ads:** one legacy line survives verbatim (`Built by trades, for trades`). The new ads
lean on price (13 lines) and competitors (9), carry the crew-knows-where-to-go pain only in softer phrasing, and
use maker credibility twice. They carry none of the losing swagger. The proven pain and maker lines that pass
the copy rules — status check calls, "where's the job?", never built in a meeting room, tested on old-timers, a
crew member who pays for themselves — are the obvious challenger material.

## The app campaigns — cheapest attention, no proven customers

Three app-install campaigns spent $659 (December 2025 $401, January 2026 $247) for 1,817 clicks and 129 first
opens — $5.11 each, the cheapest result in the account. Decoding the creation time from each record's Bubble id
(the migration overwrote `created_at`): December 2025 was the busiest month for new users (44, against 21 in
November) but not for new companies — 11 in November with no app spend, 11 in December with it. **None of the 22
companies that joined in November–December 2025 is paying today.** January 2026: 4 new companies, 1 paying.

An app-install campaign would also send paid clicks to the App Store, which Jackson's locked call #2 rules out
(paid traffic lands on web signup), and the app is being refined before it meets paid traffic. Not added.
