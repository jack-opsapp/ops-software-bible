# Keyword demand and bids — measured, not estimated (2026-09-09)

Source: Google Ads API `KeywordPlanIdeaService.GenerateKeywordIdeas` (v25) against customer 4454506598,
English, Google Search network, seeds chunked in tens (the API rejects >10 seed keywords per request).
Raw response: `2026-09-09-keyword-demand-ca-us.json` (1,050 CA ideas / 1,076 US ideas).
This replaces the manual Keyword Planner CSV the P2 plan asked Jackson to export — the API path works,
so no manual export is needed for this or any future pull.

## The finding that changes the plan

**Canada cannot absorb the locked budget.** Every term we would actually bid on totals
**1,520 searches/month in Canada** against **8,720 in the United States** (5.7x). Winning half of all
Canadian impressions at a 5% click rate is ~36 clicks/month, about **$470/month of spend**. The locked
$1,500/month has nowhere to go in Canada except broad-match waste.

**Bids are roughly double the planning assumption.** The trades-SaaS research planned against $4–8 CAD
per click. Weighted low top-of-page bids are **$12.90 CA / $16.13 US**, and the competitor lane runs
$21–102. Actual CPC will sit between our historical $6.22 Search average and those figures; plan on
$8–15, not $4–8. That roughly doubles cost per trial and pushes cost per paying customer well past the
$1,070 the research modelled — closer to $2,000–2,900 before landing-page and activation work.

## Seed demand (monthly searches; bid = low–high top of page)

| Term | CA vol | CA bid | US vol | US bid |
|---|---:|---|---:|---|
| jobber pricing | 1,000 | $12–77 | 4,400 | $10–60 |
| housecall pro pricing | 140 | $13–57 | 1,300 | $12–65 |
| cleaning business software | 90 | $8–43 | 880 | $17–110 |
| jobber alternative | 70 | $21–102 | 260 | $25–102 |
| landscaping business software | 50 | $6–84 | 480 | $14–138 |
| job management app | 30 | $21–158 | 140 | $16–71 |
| plumbing business software | 30 | — | 210 | $65–444 |
| servicetitan alternative | 20 | $28–56 | 90 | $28–86 |
| hvac scheduling software | 20 | $22–942 | 210 | $61–729 |
| roofing contractor software | 10 | — | 210 | $18–182 |
| housecall pro alternative | 10 | $22–70 | 140 | $50–116 |
| contractor scheduling app | 10 | $44–124 | 110 | $33–83 |
| contractor invoicing app | 10 | — | 110 | $23–83 |
| electrician scheduling software | 10 | — | 90 | $55–1369 |
| crew scheduling app | 10 | — | 70 | $15–63 |
| job management software for trades | 10 | $8–23 | 20 | $25–83 |
| *field service management software* | *1,000* | *$28–113* | *22,200* | *$55–119* |

Italic = the enterprise head term, still excluded: wrong buyer, highest bid in the set.

## Seven planned seeds have ZERO volume in both countries

`job tracking app for trades`, `work order app for small business`, `scheduling software for trades`,
`dispatch app for small crews`, `invoicing app for trades`, `quoting software for trades`,
`estimate app for small business`. The "…for trades" phrasing is how OPS talks, not how buyers search.
The P2 blueprint's Job management / Crew scheduling / Quotes & invoices ad groups were built on these
and must be rebuilt around the terms above.

## What the evidence supports

1. **The United States is the primary market, Canada the secondary one.** Only the US can absorb a
   readable budget. Canada stays on as a small home-market campaign, not the whole plan.
2. **Pricing-intent is the anchor, not category terms.** `jobber pricing` and `housecall pro pricing`
   are 5,400 US + 1,140 CA searches/month combined — larger than every other buyable term together.
   These are people pricing an incumbent, which is exactly the moment OPS's published prices matter.
3. **Trade-specific terms are real in the US and negligible in Canada**, which reverses the P2 plan's
   "add trades in month 2" sequencing for the US campaign.
4. **"Contractor" as a targeting word has real US volume** even though it is banned in ad copy. Bidding
   on it while never printing it is consistent: keywords are what buyers type, copy is what OPS says.

## Consequence for the day-90 gates

The research's stop rule (cost per trial above $250 with clean negatives → stop) is now much more likely
to be hit. That is information, not failure: it is exactly the number this phase exists to measure.
