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
