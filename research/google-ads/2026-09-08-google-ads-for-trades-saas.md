# Google Ads for Early-Stage Trades SaaS — 2025/2026 State of the Art

Research compiled 2026-09-08 for OPS (opsapp.co). Context: ~$4,800 CAD spent over 13 months,
paused since March 2026, ~6 paying customers, 2–7 signups/month, forward budget $1–3k/month,
Canada + US, free trial with no card, $90/$140/$190 per month tiers.

Every numeric claim carries a URL. Contradictions between sources are called out explicitly.

---

## 1. Campaign architecture for SaaS at <$3k/month

### 1.1 Search is the backbone; PMax is gated on conversion volume you do not have

The consensus across 2026 practitioner guides is that Search carries small B2B SaaS accounts and
Performance Max is a later-stage add-on, explicitly gated on conversion volume:

- PMax "requires at least 30–50 conversions per month to learn effectively, which most small
  accounts do not generate immediately" — [greenwebmedia.com](https://www.greenwebmedia.com/google-ads-performance-max-vs-search-campaigns-which-one-should-your-business-use-in-2026/)
- Triple Dart's six-campaign B2B SaaS framework assigns PMax **0–15% of budget, "only with 100+
  conversions/month"** and Demand Gen/YouTube 10–15%, with the explicit instruction: "Start with the
  first four campaigns. Add Demand Gen and PMax once your [conversion volume and CRM integration] are
  ready." — [tripledart.com](https://www.tripledart.com/blog/perfect-google-ads-campaign-structure)
- A separate source puts the PMax gate for B2B SaaS at **60+ conversions/month on Search first**
  — [groas.com](https://www.groas.com/post/google-ads-budget-allocation-strategy-2026-search-pmax-demand-gen)

**Contradiction to note:** the PMax entry threshold is quoted as 30–50, 60, and 100+ conversions/month
by three different sources. None of them are below 30. At 2–7 signups/month OPS is an order of
magnitude below the *lowest* of these thresholds, so the disagreement is academic — PMax is out.

Demand Gen has the same problem in reverse: it is an audience/interruption channel with no query
intent, and at $1–3k/month it competes with the only campaign type that can capture people actively
searching for job-management software. Thin evidence exists for Demand Gen at sub-$3k budgets
specifically; the budget-allocation sources all treat it as a scaling layer, not a starting layer.

### 1.2 Triple Dart's B2B SaaS reference structure (84+ accounts)

| Campaign | Match types | Bidding | Budget share |
|---|---|---|---|
| Brand | Exact | tCPA | 10–15% |
| Competitor | Exact + phrase | tCPA | 15–20% |
| Category High Intent | Phrase + broad | tCPA / tROAS | 30–40% |
| Category Broad Discovery | Broad | tCPA | 15–20% |
| Demand Gen / YouTube | Audience | Max Conversions | 10–15% |
| Performance Max | tROAS + offline conv. | — | 0–15% (100+ conv/mo only) |

Source: [tripledart.com](https://www.tripledart.com/blog/perfect-google-ads-campaign-structure)

**Caveat for OPS:** this structure is calibrated for accounts that can feed six campaigns. At
$1,500/month total it fragments budget into ~$150–600/month slices, several of which would never
accumulate enough clicks to leave learning. See §1.5.

### 1.3 SKAG is dead; "1 ad group = 1 landing page URL" is the current rule

Triple Dart states the shift away from single-keyword ad groups directly: **"1 ad group = 1 URL. This
will allow more volume and more variety of queries per ad group, while still staying on-theme."**
Mirror the site structure so the ML has coherent groupings.
— [tripledart.com](https://www.tripledart.com/blog/perfect-google-ads-campaign-structure)

Their minimum viable ad-group size: **3,000+ impressions per ad group per week**, and **50+
conversions per campaign per month**. Restructure triggers: CPA plateau for 4+ weeks, >30% irrelevant
queries in the search-term report, campaigns under 30 conversions/month, or more than 10 fragmented
Search campaigns. — same source.

The reason SKAG died is mechanical, not fashionable: close variants mean an exact-match keyword now
matches a wide semantic neighbourhood, so one-keyword groups no longer isolate anything — they just
starve each group of data and split identical queries across auctions.

### 1.4 Match type in 2026: broad match is now coupled to Smart Bidding by policy, not just advice

- Google's own broad-match campaign setting is **"only available if the campaign is using conversion
  based smart bidding,"** and campaigns using the campaign-level broad match setting **auto-upgrade
  starting September 2026** — [support.google.com](https://support.google.com/google-ads/answer/13389795?hl=en)
- Google's cited stat, repeated by Triple Dart: advertisers using RSAs *plus* broad match *plus*
  Smart Bidding see **"an average of 20% more conversions at a similar cost per action."**
  — [tripledart.com](https://www.tripledart.com/blog/perfect-google-ads-campaign-structure)

That 20% figure is Google's own marketing number and should be treated as an upper bound. The
independent AI Max data below is the corrective.

### 1.5 AI Max for Search: the single most important 2026 finding for a small lead-gen account

AI Max is Google's new query-expansion + creative-customization layer for Search campaigns, launched
May 2025. Google's claims vs. independent data diverge sharply, and the divergence is worst in exactly
OPS's situation (low-volume B2B lead gen).

**Google's claims:**
- 14% more conversions/conversion value at similar CPA/ROAS on average
- 27% for campaigns that were heavily exact/phrase match
— reported in [ppc.live](https://www.ppc.live/post/google-s-ai-max-for-search-what-the-data-actually-shows-in-2026)

**Independent data (SMEC, 250+ campaigns):**
- Median revenue lift **13%** (matches Google)
- Median **CPA increase of 16%** (directly contradicts the "similar CPA" claim)
- ROAS outcomes ranged from **42% above to 35% below** baseline
- **Only 22% hit their original ROAS target**; 78% significantly over- or under-performed
— [ppc.live](https://www.ppc.live/post/google-s-ai-max-for-search-what-the-data-actually-shows-in-2026)

**A documented B2B lead-gen test — the closest analogue to OPS:**
- Before AI Max: CPC ~$13, CPL $493
- After: clicks nearly **tripled**, CPC **dropped 59%**, conversions **fell 38%**, CPL nearly
  **doubled to $850**
- Worse: a post-deactivation hangover — the campaign kept favouring cheap high-volume traffic and
  **CPL stayed above $800 even after AI Max was turned off**
— [ppc.live](https://www.ppc.live/post/google-s-ai-max-for-search-what-the-data-actually-shows-in-2026)

**Where the expansion actually comes from** (SMEC, 1M+ impressions): ~**80% from exact match, 20%
phrase, <1% broad** — i.e. AI Max loosens your *tight* keywords, it does not mainly widen your broad
ones. Overlap with existing broad-match queries ran **49–63%** in some accounts, and one account saw
**69% of impressions land on competitor brand terms**. — same source.

**Search Partners risk:** one account logged **half a million monthly Search Partner impressions at a
0.07% conversion rate vs 3% on Google Search proper** — a ~43x gap.
— [ppc.live](https://www.ppc.live/post/google-s-ai-max-for-search-what-the-data-actually-shows-in-2026)

**Budget floor:** one source claims that **below $750/day** AI Max cannot allocate enough impression
volume to discover new query patterns — [growthspreeofficial.com](https://www.growthspreeofficial.com/blogs/ai-max-search-vs-performance-max-b2b-saas-2026).
That is ~$22,500/month, roughly 10–20x OPS's entire budget. Treat this specific number as a single
un-corroborated vendor claim, but the direction is consistent with the SMEC variance data: AI Max is a
volume-hungry, high-variance system.

**Counter-evidence:** Brainlabs (23 tests, 16 mature accounts) found all three AI Max features enabled
gave a **40% higher success rate** than baseline matching alone, and text customization lifted Quality
Score from **6.8 to 7.3** — [ppc.live](https://www.ppc.live/post/google-s-ai-max-for-search-what-the-data-actually-shows-in-2026).
Note the qualifier: *mature accounts*.

**Also relevant:** Google plans to **deprecate Dynamic Search Ads**, folding the functionality into
AI Max, on roughly a one-year timeline from announcement.
— [ppc.live](https://www.ppc.live/post/google-s-ai-max-for-search-what-the-data-actually-shows-in-2026)

**Verdict for OPS: leave AI Max off.** The one published B2B lead-gen case study shows the exact
failure mode a trades-SaaS account is most exposed to — a flood of cheap, low-qualification clicks
that look like efficiency in the CPC column and destroy CPL — plus a persistent hangover after
disabling.

### 1.6 Negative keywords: the highest-ROI manual work in the account

Recommended day-one exclusions for B2B SaaS: **"free," "open source," "tutorial," "course," "jobs,"
"salary"** — terms that "eat budget without producing pipeline" and can waste **15–25% of spend**.
Weekly negative reviews are the recommended cadence. Google now supports **campaign-level negative
keywords, up to 10,000 per campaign** (launched 2025).
— [tripledart.com](https://www.tripledart.com/blog/perfect-google-ads-campaign-structure)

For a trades-SaaS account the list is longer and more specific than the generic SaaS list, because the
keyword space is polluted by three distinct non-buyer populations:
1. **Job seekers** — "electrician jobs," "HVAC apprenticeship," "plumber salary," "hiring"
2. **Homeowners looking for a tradesperson**, not software — "plumber near me," "hire an electrician,"
   "deck builder quote," "cost to build a deck"
3. **Students / trainees** — "course," "certification," "red seal," "training," "exam," "ticket"

Population 2 is the dangerous one: those queries share almost every noun with the buyer queries and
will absorb budget silently under broad match.

### 1.7 Quality Score economics

Triple Dart's portfolio data: improving Quality Score from **5 to 8 reduces CPC by 28%**
— [tripledart.com](https://www.tripledart.com/blog/perfect-google-ads-campaign-structure).
At small budgets this is one of the few levers that multiplies available click volume without more
money, and it is driven by the ad-group-to-ad-to-landing-page message chain (see §4).

### 1.8 Small-budget structural principle: consolidate, don't fragment

- **$20–50/day ($600–1,500/month)** is described as a reasonable starting test range
  — [get-ryze.ai](https://www.get-ryze.ai/blog/google-ads-minimum-budget-guide-2026)
- The repeated rule for small budgets: **"concentrate your budget in one place until you have data"**
  and **"don't spread a small budget across every campaign type — pick one or two, get them
  profitable, then expand."** With ~$50/day the recommendation is **one primary campaign** on
  highest-intent keywords. — [get-ryze.ai](https://www.get-ryze.ai/blog/google-ads-minimum-budget-guide-2026)
- Counter-argument from the same body of sources: separate campaigns (not just ad groups) give
  independent budget control, separate bid strategies, and clean per-intent reporting; lumping
  everything into one campaign loses visibility into which intent tier drives results. — same source.

**This is a real contradiction and it resolves on budget size.** Below roughly $2k/month, budget
control is not the binding constraint — *data density* is, because Smart Bidding cannot learn from a
campaign that produces two conversions a month. Above that, separation starts paying for itself. The
practical compromise: separate *brand* (which must never be starved and must never bid against
non-brand) from *everything else*, and keep the non-brand side as few campaigns as the geo/language
split allows.

### 1.9 Geo, language, device, schedule

Concrete published guidance here is thin; the following are structural facts rather than benchmarked
findings.

- **Geo:** Canada and the US should be **separate campaigns**, not one campaign with two locations.
  Currency, CPC levels, competitor density and seasonality all differ, and a single campaign will let
  Smart Bidding pool spend into whichever geo looks cheaper — which is usually the one with the worse
  buyers. Always set location targeting to **"Presence: people in your targeted locations,"** not the
  default presence-or-interest, which lets people merely *searching about* Canada trigger ads.
- **Language:** English targeting only. Note that Google's language targeting keys on the user's
  interface/content language, not the query language, so it is a weak filter — for Canada this means
  Quebec French traffic will still appear and is best handled with negatives and geo exclusions rather
  than language settings alone.
- **Device:** OPS is a mobile-first iOS product but the *purchase* decision is a business-owner
  decision often made on desktop in the evening. Do not exclude either. Do report on device split
  weekly — if mobile clicks convert at a fraction of desktop and the landing page is the cause, that
  is a landing-page fix, not a bid-modifier fix.
- **Ad schedule:** a 2026 platform change affects how budget pacing interacts with ad scheduling
  — [techwyse.com](https://www.techwyse.com/news/platform-updates/google-ads-budget-pacing-change-ad-scheduling-2026).
  At $1–3k/month the correct default is **all hours, all days**, because dayparting on a small budget
  removes auctions before you have the data to know which hours are bad. Trades owners search early
  morning (before 7am), at lunch, and late evening — the opposite of an office-hours schedule.

**Thin evidence** on published device/schedule benchmarks specific to field-service SaaS; the above is
structural reasoning, flagged as such.

---

## 2. Bidding for low-volume accounts

### 2.1 The hard thresholds

| Requirement | Number | Source |
|---|---|---|
| tCPA hard minimum (campaign, last 30 days) | **15 conversions** | [keywordme.io](https://www.keywordme.io/blog/how-many-conversions-do-google-ads-need-to-optimize) |
| tCPA recommended for good performance | **30 conversions / 30 days** | [Google Ads Help — Target CPA](https://support.google.com/google-ads/answer/6268632?hl=en) |
| Below which Manual CPC or Max Clicks is "the practical starting point" | **<15 conversions/month** | [storegrowers.com](https://www.storegrowers.com/google-ads-bid-strategy/) |
| Point at which Smart Bidding "almost always outperforms manual" | **15–30 conversions / 30 days** | [storegrowers.com](https://www.storegrowers.com/google-ads-bid-strategy/) |
| PMax entry | 30–50 / 60 / 100+ conv/month (sources disagree) | §1.1 |
| SQL as primary conversion action | **30–50 SQLs/month** | [groas.com](https://www.groas.com/post/google-ads-for-saas-2026-complete-strategy-guide-b2b-lead-generation-trial-acquisition) |

Google's own Target CPA doc adds two things worth knowing:
- **"Target CPA recommendations can still appear for low-volume campaigns if strong simulation data
  indicates good performance"** — i.e. Google will *suggest* tCPA to an account that has no business
  running it. Do not take the in-platform recommendation as evidence you qualify.
- Device bid adjustments under tCPA **modify the target, not the bid**: "If your Target CPA is $10
  USD, setting a bid adjustment of +40% for mobile will increase your Target CPA to $14 USD on mobile."
- Be prepared to spend **up to 2x your average daily budget** on any given day.
— all [Google Ads Help](https://support.google.com/google-ads/answer/6268632?hl=en)

### 2.2 Where OPS actually sits

At 2–7 signups/month total (across all channels, not just paid), OPS is below every threshold in the
table. This is the single most important constraint in the entire account and it dictates almost
every other decision:

- **tCPA is not available in any meaningful sense.** Even if the platform lets you set it, a strategy
  fed 1–3 conversions a month is not learning; it is sampling noise.
- **Maximize Conversions without a target** has the same problem in a subtler form — it will spend the
  full budget chasing a signal it cannot model, and will typically consolidate onto whichever few
  queries happened to convert once.
- **Maximize Clicks with a CPC cap** is the honest starting strategy: "When launching a new campaign
  with no conversion history, Max Clicks can be the fastest way to generate initial traffic data. Run
  it for two to four weeks with a bid cap to prevent runaway CPCs, accumulate conversion data, and
  then transition." — [storegrowers.com](https://www.storegrowers.com/google-ads-bid-strategy/)
- The documented danger, stated plainly by the same source: **"Max Clicks optimizes purely for the
  highest volume of clicks within your budget. It has no conversion signal whatsoever… Google will
  find you the cheapest clicks possible, which are rarely the most valuable."**

The resolution is the CPC cap plus tight keyword/negative discipline. Max Clicks is safe *only* when
the keyword set is narrow enough that any click inside it is acceptable. That is exactly why §1.8's
"concentrate on highest-intent keywords" and §2.2's bidding choice are the same decision.

**Contradiction to note:** groas.com argues against tCPA as a default entirely — **"Target CPA is the
default bidding strategy most SaaS advertisers reach for, and it is the most common source of wasted
spend in B2B accounts"** — and pushes value-based bidding (Maximize Conversion Value + tROAS) instead
— [groas.com](https://www.groas.com/post/google-ads-for-saas-2026-complete-strategy-guide-b2b-lead-generation-trial-acquisition).
But value-based bidding needs *more* data than tCPA, not less. Their advice is written for accounts
with a CRM feeding pipeline values, not for a 6-customer account. For OPS, the useful half of their
argument is the diagnosis, not the prescription: tCPA on a shallow conversion action optimizes for the
cheapest possible version of that action.

Their exact framing of the failure mode: **"If your primary conversion action is 'form fill' or 'free
trial signup' and you have not built a feedback loop that tells Google which of those form fills
actually became qualified leads, Target CPA will optimize for the cheapest possible form fill."**
And: **"A campaign generating 100 leads per month at $50 each is worthless if only 2 of those leads
are actually qualified."** — same source.

### 2.3 2026 platform changes to Smart Bidding

- **June 2026:** "Maximize conversions with a Target CPA" is renamed simply **"Target CPA"** (and the
  tROAS equivalent likewise) — labelling change, not behavioural
  — [almcorp.com](https://almcorp.com/news/google-smart-bidding-update-target-cpa-roas-august-2026/)
- **August 17, 2026:** Google updated bidding systems "to deliver more consistent performance for
  **budget-constrained campaigns**"; campaigns on tCPA or tROAS "may cause temporary performance and
  traffic fluctuations" — same source. This is directly relevant: a $1–3k/month account is
  budget-constrained by definition, and any tCPA/tROAS performance read from around that date is
  contaminated.

### 2.4 Conversion action design for a trial-led SaaS

The funnel for OPS has at least five distinguishable events:

1. Click → landing page
2. **Signup started** (email entered / form opened)
3. **Trial started** (account + company created)
4. **Activated trial** (a real job created, a crew member invited, a quote sent — the aha moment)
5. **Paid** (card entered at end of trial)

Published guidance is consistent on the principle — **"Set your primary conversion action to the
deepest meaningful event you have enough volume to support"**
— [groas.com](https://www.groas.com/post/google-ads-for-saas-2026-complete-strategy-guide-b2b-lead-generation-trial-acquisition)
— and on the supporting mechanic: intermediate actions that "predict eventual purchase and happen
within days of the first click" — specifically named as **"trial signups with company email domains,
users who complete the onboarding flow, users who perform the key activation event within the product"**
— give "the algorithm faster feedback while you build toward importing offline conversion data."
— [groas.com](https://www.groas.com/post/google-ads-for-saas-2026-complete-strategy-guide-b2b-lead-generation-trial-acquisition)

**Applied to OPS:**
- **Primary = Trial started (#3).** It is the deepest event with any hope of volume, it is
  unambiguous, and it fires within minutes of the click.
- **Secondary (observation only, not bid-eligible) = Signup started (#2), Activated trial (#4),
  Paid (#5).** #2 tells you whether the landing page or the signup form is the leak. #4 and #5 tell
  you which keywords produce real businesses — that is your *reporting* truth even while #3 is your
  *bidding* truth.
- Marking only one action "Primary / include in Conversions" is essential; multiple primaries at this
  volume double-count and further dilute an already-thin signal.

### 2.5 Enhanced conversions and offline conversion import

- **Enhanced conversions for leads** is the mechanism that lets a hashed email captured at signup be
  matched back to the ad click, so that a later event (paid conversion, or a manual "this one became a
  customer" upload) can be attributed. It is listed as step 1 on the AI Max pre-activation checklist —
  "Ensure conversion tracking hygiene; implement Enhanced Conversions"
  — [ppc.live](https://www.ppc.live/post/google-s-ai-max-for-search-what-the-data-actually-shows-in-2026)
- **Offline conversion import via GCLID** is the standard B2B fix. Claimed effect: importing MQL/SQL
  events back into Google Ads **"typically reduces cost per SQL by 25–40% within 60 days"**
  — [groas.com](https://www.groas.com/post/google-ads-for-saas-2026-complete-strategy-guide-b2b-lead-generation-trial-acquisition).
  Treat 25–40% as a vendor claim with no methodology attached.

**The honest read for OPS:** offline conversion import *cannot* drive bidding at 1–3 paid conversions
a month — there is no volume to optimize on. But the plumbing is still worth building immediately,
for two reasons that have nothing to do with Smart Bidding: (a) it is the only way to answer "which
keyword produced a paying customer," which at 6 customers is a question you can answer *individually*;
and (b) it is a prerequisite that takes weeks to become useful, so building it at volume 0 means it is
ready when volume arrives. Capturing and storing GCLID at signup costs almost nothing and is
irreversible if skipped.

### 2.6 Conversion window

Default 30-day windows "miss a significant portion of SaaS conversions." Recommended: **90 days for
enterprise, 30–60 days for SMB SaaS.**
— [groas.com](https://www.groas.com/post/google-ads-for-saas-2026-complete-strategy-guide-b2b-lead-generation-trial-acquisition)

For OPS: trial-start is a fast event (same session to a few days), but *paid* is trial-length plus
deliberation. Set the trial-start conversion window to **30 days** and the paid conversion window to
**60–90 days**. Note that a longer window inflates apparent recent performance and makes
week-over-week comparisons unreliable — a real cost of the longer window, rarely mentioned.

### 2.7 Value-based bidding

Not applicable yet, but the value assignment is trivial to define in advance because OPS pricing is
fixed and tiered: $90 / $140 / $190 per month. Annualized first-year values of roughly $1,080 /
$1,680 / $2,280 give clean conversion values to attach whenever value-based bidding becomes viable.
The prerequisite is the offline import from §2.5, not the bidding strategy itself.

---

## 3. Responsive Search Ads: what drives performance, and how testing actually works

### 3.1 Ad Strength does not predict conversions — and the sources agree

This is one of the few points on which every 2026 source converges:

- **"Ad Strength measures the diversity and completeness of your assets, not actual conversion
  performance. An 'Excellent' Ad Strength rating does not guarantee high conversions."**
  — [omologist.com](https://omologist.com/google-ads/responsive-search-ads/) / [spiresdigital.com](https://spiresdigital.com/blog/responsive-search-ads-best-practices/)
- **"An 'Excellent' ad strength rating means Google believes your RSA has enough diverse, relevant
  components to test effectively. It does not mean your ad will convert better than one rated
  'Good.'"** — [groas.com](https://www.groas.com/post/google-ads-responsive-search-ads-2026-headlines-ad-strength-optimization)
- **"Target Good Ad Strength, not Excellent at any cost — padding headlines to chase Excellent
  actively harms performance, with Good being the practical ceiling to optimise toward."**
  — [search-south.com](https://www.search-south.com/2026/02/21/responsive-search-ads-best-practice-in-2026/)

Judge on **CTR, conversion rate and cost per conversion** instead
— [groas.com](https://www.groas.com/post/google-ads-responsive-search-ads-2026-headlines-ad-strength-optimization).

Note what nobody produced: a published dataset showing Ad Strength correlating with conversion rate.
The claims are all directional. **Thin evidence** either way — but the *absence* of a supporting study
after four years of the metric existing is itself informative, and Google positions Ad Strength as a
diagnostic, not a KPI.

### 3.2 Pinning: the 2026 consensus is a hybrid, not "never pin"

The 2021-era advice was "never pin, you'll hurt Ad Strength." The 2026 advice has moved:

- **"Pin two or three headlines to the same position rather than pinning a single headline"** — this
  preserves combinatorial flexibility while locking the message
  — [groas.com](https://www.groas.com/post/google-ads-responsive-search-ads-2026-headlines-ad-strength-optimization)
- The fuller hybrid: **pin 2–3 keyword-relevant headlines to Position 1** to guarantee relevance,
  **optionally pin a CTA headline to Position 3**, and **leave Position 2 entirely unpinned**
  — [roa-marketing.com](https://roa-marketing.com/blog/responsive-search-ads-best-practices-google-ads-2026/) / [omologist.com](https://omologist.com/google-ads/responsive-search-ads/)

Why this matters for OPS specifically: with an unpinned RSA, Google will assemble headline
combinations that can read as generic SaaS. A brand with a deliberate voice — terse, tactical,
understated — loses that voice entirely to random assembly. Pinning position 1 to a small set of
on-message headlines is how you keep the ad sounding like the product. That is a brand-integrity
argument, not a CTR argument, and it is the strongest reason to pin here.

### 3.3 Asset counts and slots

- **15 headline slots** (30 characters each), **4 description slots** (90 characters each)
  — [groas.com](https://www.groas.com/post/google-ads-responsive-search-ads-2026-headlines-ad-strength-optimization)
- Recommended headline categories to cover: keyword match, value prop with a number, social proof,
  clear CTA, differentiator — same source.
- **Contradiction:** groas says use all 15 slots "strategically"; search-south says padding headlines
  to chase Ad Strength "actively harms performance." These reconcile as: fill the slots only with
  headlines you would be happy to see served. A slot filled with filler is a slot that will eventually
  be shown.

### 3.4 Asset performance labels

Labels are **Best / Good / Low / Learning**. No source states the impression threshold at which
labels appear (**thin evidence** — Google does not publish it; practitioner consensus is roughly
5,000+ impressions per asset, unverified). Recommended handling:
- Keep "Best" headlines
- Replace "Low" performers
- **Monitor "Learning" assets for at least two weeks** before judging
— [groas.com](https://www.groas.com/post/google-ads-responsive-search-ads-2026-headlines-ad-strength-optimization)

2026 change worth knowing: **asset-level reporting now gives click and conversion data per individual
headline and description**, not just labels — "changing the optimization playbook from passive
rotation to data-driven asset management"
— [search-south.com](https://www.search-south.com/2026/02/21/responsive-search-ads-best-practice-in-2026/)

**Reality check for a $1–3k account:** at, say, 400 clicks/month spread across 15 headlines and
several thousand possible combinations, most assets will sit in "Learning" indefinitely. Asset labels
will not be a usable optimization signal at OPS's volume for many months. Plan copy iteration on
judgment and message-match logic, not on label chasing.

### 3.5 Rotation cadence

**Refresh every 4 to 8 weeks**, replacing "Low"-rated assets and retaining "Best"
— [groas.com](https://www.groas.com/post/google-ads-responsive-search-ads-2026-headlines-ad-strength-optimization).

### 3.6 Why classic A/B testing is broken for RSAs — and what replaced it

The mechanical problem: an RSA is not one ad, it is a generator that assembles from 15 headlines and
4 descriptions. Two RSAs in an ad group are not two treatments — Google serves the one it predicts
will win, so the split is neither random nor 50/50, and the combination space inside each ad is
changing while the test runs. There is no clean unit of comparison.

The tooling response:

- **Ad Variations**: bulk-apply a change (copy edit, or find-and-replace across final URLs) and run it
  against the original with a controlled split
  — [datafeedwatch.com](https://www.datafeedwatch.com/blog/ab-test-responsive-search-ads)
- **Custom experiments**: compare multiple variables across one or more campaigns with a real split
  — [almcorp.com](https://almcorp.com/blog/google-ads-experiment-center-guide/)
- **Experiment Center** — launched **January 2026**, consolidating A/B experiments and lift studies
  into one dashboard — [almcorp.com](https://almcorp.com/blog/google-ads-experiment-center-guide/)

### 3.7 The statistical reality at low volume — the section that matters most for OPS

- **"You need enough conversions in both groups to detect a meaningful difference. For most PPC tests,
  this means hundreds of conversions per variant, not dozens."**
  — [pageduel.com](https://pageduel.com/blog/ab-test-google-ads-campaigns)
- **"Most experiments need at least 4–6 weeks and 100+ conversions per variant to produce reliable
  results."** — [pageduel.com](https://pageduel.com/blog/ab-test-google-ads-campaigns)
- **"Do not declare a winner in any test until the result has reached at least 95 per cent statistical
  significance. Acting on results below this threshold is, statistically speaking, indistinguishable
  from guessing."** — [pageduel.com](https://pageduel.com/blog/ab-test-google-ads-campaigns)
- **"Low-traffic campaigns may require extended test durations or may not be suitable for
  experimentation."** — [almcorp.com](https://almcorp.com/blog/google-ads-experiment-center-guide/)
- Splits: 50/50 for fastest results, 70/30–80/20 for riskier tests; one variable per experiment; run
  2–4 weeks minimum to cover weekly cycles
  — [pageduel.com](https://pageduel.com/blog/ab-test-google-ads-campaigns)
- For RSA copy specifically: **"Allow 2 to 4 weeks and several hundred clicks before drawing
  conclusions"** on a meaningful test (≥5 headline swaps)
  — [groas.com](https://www.groas.com/post/google-ads-responsive-search-ads-2026-headlines-ad-strength-optimization)

**The arithmetic for OPS is brutal and needs stating plainly.** At 100+ conversions per variant and
200+ conversions per test, a trial-signup A/B test at OPS's likely 5–20 trials/month would need
**roughly 1.5 to 3 years** to reach significance. Conversion-level ad testing is not available to this
account at this budget, and any tool or agency claiming otherwise is selling noise as insight.

**What is available instead, in descending order of reliability:**
1. **CTR tests.** Clicks arrive ~30–100x more often than conversions. A CTR difference between two
   ads can reach significance in weeks, not years. CTR is a real signal about message resonance even
   though it is not a conversion signal.
2. **Landing-page conversion-rate tests on all traffic** (organic + direct + paid pooled), which
   multiplies the sample far beyond paid alone.
3. **Judgment-driven copy iteration** against a documented hypothesis, reviewed monthly, changed only
   when the reasoning changes — explicitly *not* presented as a test.
4. **Qualitative evidence**: search-term reports, what the 6 existing customers actually said, sales
   call language. At this volume, n=6 interviews beats n=200 clicks.

---

## 4. Landing pages for paid search SaaS

### 4.1 Dedicated landing page vs homepage — the numbers

- **Landing pages ~6.6% vs homepages 2–3%** for paid campaigns
  — [phenyx.co](https://www.phenyx.co/post/landing-page-vs-homepage)
- **"Dedicated landing pages convert 2–3x higher than generic product pages for paid traffic because
  they match the ad's specific message and remove navigation distractions."**
  — [coreppc.com](https://coreppc.com/blog/landing-page-conversion-rate-benchmarks-2026/)
- SaaS & technology **median for dedicated landing pages: 3.8%**; broad B2B SaaS site average
  **~1.1%** — [saashero.net](https://www.saashero.net/strategy/b2b-saas-conversion-rate-benchmarks/)

**Caution on these figures:** the 6.6% vs 2–3% comparison is confounded. Landing-page traffic is
campaign-selected and intent-matched; homepage traffic includes everything. The 2–3x direction is
almost certainly real, the exact multiple is not measured cleanly anywhere I found. Treat "materially
better, roughly 2x" as the defensible claim.

### 4.2 Conversion benchmarks by offer type (B2B SaaS landing pages)

| Offer | Median | Top quartile |
|---|---|---|
| Self-serve free trial / PLG signup | **8%** | **12%+** |
| Demo request / sales-assisted | **1.5–4%** | **4.8%** |

By traffic source: direct ~3.3%, organic ~2.7%, email 5–20%+, paid search "varies significantly by
keyword intent."
— all [saashero.net](https://www.saashero.net/strategy/b2b-saas-conversion-rate-benchmarks/)

**This is a strong argument for OPS's existing choice.** A no-card free trial converts at roughly
**2–5x the rate of a demo request** on the landing page. For a $90–190/month product, a demo gate
would be economically incoherent anyway — the sales cost exceeds the ACV.

### 4.3 Page mechanics with documented effect sizes

- **Single CTA vs multiple CTAs: 13.5% vs 10.5%** — a **+29% relative lift** for single-CTA pages
- **Personalized CTAs: 202% better** than generic
- **Social proof placed adjacent to the CTA: 68% conversion lift** in documented tests
- **Page load: bounce probability rises 123% going from 1s to 10s**
— all [saashero.net](https://www.saashero.net/strategy/b2b-saas-conversion-rate-benchmarks/)

The "202% better personalized CTAs" figure traces back to an old HubSpot smart-CTA study that has
been recycled for years; treat it as folklore, not evidence. The single-CTA and social-proof-adjacency
numbers are more consistently reproduced across sources.

### 4.4 Free trial with no card: what OPS gains and what it costs

OPS runs a no-card trial. The benchmark data says exactly what that trades away:

| Trial type | Trial→paid conversion | Source |
|---|---|---|
| Opt-in (no card) | **8–22%, median 14%** | [shno.co](https://www.shno.co/marketing-statistics/free-trial-conversion-statistics) |
| Opt-out (card required) | **35–55%, median 44%** | [shno.co](https://www.shno.co/marketing-statistics/free-trial-conversion-statistics) |
| Opt-in (ChartMogul, 200 products) | **8.9%** | [growthspreeofficial.com](https://www.growthspreeofficial.com/blogs/b2b-saas-trial-to-paid-conversion-rate-benchmarks-2026-by-trial-type-acv-length-credit-card) |
| Opt-out (ChartMogul) | **31.4%** | same |
| Opt-in (First Page Sage, 86 companies) | **18.2%** | [growthspreeofficial.com](https://www.growthspreeofficial.com/blogs/b2b-saas-trial-to-paid-conversion-rate-benchmarks-2026-by-trial-type-acv-length-credit-card) |
| Opt-out (First Page Sage) | **48.8%** | same |

The cleanest framing, per 1,000 visitors (ChartMogul):
- **No card: 45 signups → 3.6 paying customers**
- **Card required: 35 signups → 10.5 paying customers**
— [growthspreeofficial.com](https://www.growthspreeofficial.com/blogs/b2b-saas-trial-to-paid-conversion-rate-benchmarks-2026-by-trial-type-acv-length-credit-card)

**That is a ~2.9x difference in paying customers from identical traffic.** Opt-out trials convert
3–4x higher but capture **30–50% lower top-of-funnel volume** — same source.

"Good" targets for SMB SaaS: **no-card trial 4–6% good, 10–15% great**; **card-required 25–35% good,
50–60% great** — [kirro.io](https://kirro.io/free-trial-conversion-rate)

**What this means for the ad account, which is the point here:** the no-card trial makes the paid-media
math roughly 3x harder per dollar, because you pay for ~3x more trials to get the same customer. It
does *not* follow that OPS should add a card gate — the no-card trial is very likely correct for a
distrustful, burned-before trades audience, and it is a real brand promise. But the ads account must
be planned around the honest number: **budget against cost-per-paying-customer, not cost-per-trial**,
and expect roughly 8–14% of paid trials to become customers. This is a product/taste decision worth
surfacing to Jackson explicitly, with the 3.6 vs 10.5 number attached — not a decision to make inside
the ad account.

### 4.5 App Store as destination vs web signup — do not send paid search to the App Store

OPS is mobile-first iOS plus web. The temptation is to send ads to the App Store. The measurement
consequences are severe:

- **SKAdNetwork attribution "is initiated by a Google Mobile Ads SDK ad click only if the click lands
  directly or indirectly in the Apple App Store"**, and it reports only **aggregated** data
  — [Google Analytics Help](https://support.google.com/analytics/answer/13168376?hl=en)
- **"Standard last-click attribution, which depends on matching a device identifier between the ad
  network and the advertiser's SDK, simply does not work for most iOS users."**
  — [adlibrary.com](https://adlibrary.com/posts/skadnetwork)
- As of 2026, **Meta, Google and Snap are still largely on SKAN 3**; only TikTok has moved
  meaningfully to SKAN 4 — [adlibrary.com](https://adlibrary.com/posts/skadnetwork)
- Apple **skipped SKAdNetwork 5.0 entirely** and replaced it with **AdAttributionKit**, which gained
  major capabilities in **iOS 18.4** — [rockpapermarketing.io](https://rockpapermarketing.io/blog/ios-att-skadnetwork-mobile-marketers-guide)
- Many UA teams now use **blended attribution** — correlating overall app trends with campaign
  activity rather than per-channel attribution — [moburst.com](https://www.moburst.com/blog/mobile-attribution-in-2026-what-marketers-actually-need-to-know/)

**The practical verdict:** at 2–7 signups/month, aggregated and privacy-thresholded attribution is
worthless — SKAN's aggregation thresholds mean low-volume campaigns often report *nothing at all*.
Send every paid click to a **web landing page with a web signup**, where a first-party conversion tag
fires with a GCLID and you know exactly which keyword produced which trial. Offer the iOS app as the
*next step after signup* (or via a post-signup link/QR), not as the ad destination. The signup can
still be mobile-web-first and take 60 seconds; it just needs to happen on your domain.

Secondary benefit: a web signup lets you capture the GCLID needed for §2.5's offline import. An App
Store click destroys that link permanently.

### 4.6 What converts a trades-business owner specifically

**Thin evidence** — no published CRO study specific to field-service software buyers surfaced in this
research. What follows is reasoned from the benchmark mechanics above plus the competitor landing-page
patterns in §6, and is flagged as inference rather than data:

- **Pricing on the page, in dollars.** Every major competitor gates or obscures pricing to force a
  sales conversation (§6). A trades owner who has been quoted "call us for pricing" by three vendors
  reads visible pricing as respect. OPS has an unusually strong hand here: $90/$140/$190, every
  feature in every tier, no per-seat surprise. That flat-tier simplicity is the differentiator most
  worth putting above the fold.
- **No card, stated as a promise, not a footnote.** "No credit card" is the single most repeated
  friction-remover in the free-trial literature and it is the thing this audience scans for.
- **Proof that it works with gloves-off reality**: offline capability, works with a bad signal, works
  for a 3-person crew. Not feature lists.
- **Social proof adjacent to the CTA** (68% lift, §4.3) — but at 6 customers, fabricating scale ("Join
  10,000+ contractors") is both dishonest and detectable. Use specifics instead: a named trade, a
  named town, a real sentence from a real owner. One true testimonial beats an invented number, and
  invented social proof from a 6-customer company is the fastest way to lose a skeptical trades buyer.
- **Single CTA** (+29%, §4.3). One button, repeated. Not "Start trial" competing with "Book a demo"
  competing with "Download on the App Store."
- **Speed.** Bounce probability +123% from 1s to 10s (§4.3), and this audience is on rural LTE.

---

## 5. Benchmarks 2025–2026

### 5.1 Cross-industry baselines (for orientation only)

| Metric | Value | Source |
|---|---|---|
| All-industry Search CTR | **6.64%** | [webtonic.io](https://www.webtonic.io/blog/google-ads-benchmarks) |
| All-industry CPC | **$5.42** | [webtonic.io](https://www.webtonic.io/blog/google-ads-benchmarks) |
| All-industry conversion rate | **8.18%** | [webtonic.io](https://www.webtonic.io/blog/google-ads-benchmarks) |
| All-industry CPL | **$66.69** | [webtonic.io](https://www.webtonic.io/blog/google-ads-benchmarks) |
| Alternative all-industry Search CPC | **$2.96** (up ~12% from $2.64 in 2025) | [get-ryze.ai](https://www.get-ryze.ai/blog/average-cpc-by-industry-google-ads-2026) |
| Alternative all-industry CTR range | **3.52–6.11%** | [digitalapplied.com](https://www.digitalapplied.com/blog/google-ads-benchmarks-2026-cpc-ctr-cvr-industry) |

**Contradiction:** all-industry CPC is quoted as $5.42, $5.26 and $2.96 by three sources, and CTR as
6.64% vs 3.52–6.11%. These are different panels with different campaign mixes (the $2.96 figure
likely includes far more low-CPC ecommerce). **Cross-industry benchmarks are not usable for
decision-making here** — they are noise. Use them only to sanity-check that a number is not absurd.

### 5.2 B2B SaaS benchmarks — the relevant tier

Two independent 2026 datasets, and they disagree substantially on CPC:

**Dataset A — Growthspree (SaaS, aggregate):**

| Metric | Median | Top quartile | Bottom quartile |
|---|---|---|---|
| CPC (non-brand search) | **$8.50–$14.00** | $5.00–$8.50 | $14.00–$25.00+ |
| CTR (non-brand search) | **2.8–3.5%** | 4.0–6.5% | 1.2–2.0% |
| Landing page conversion | **2.5–4.0%** | 5.0–8.0% | 0.8–2.0% |
| Cost per lead (form fill) | **$180–$350** | $80–$180 | $350–$800+ |
| Cost per SQL | **$800–$2,500** | $400–$800 | $2,500–$8,000+ |
| **Wasted spend** | **25–40%** | 10–18% | 40–60% |

— [growthspreeofficial.com](https://www.growthspreeofficial.com/blogs/saas-google-ads-benchmarks-2026-cpc-cpl-ctr-conversion-rate-by-vertical)

**Dataset B — Kampaio / Involve Digital (500+ campaigns, 65+ accounts):**

| Metric | Value |
|---|---|
| Non-branded CPC | **$5.34**, up **29% YoY** |
| CPC — SMB segment | **$3.33–$5.34** |
| CPC — mid-market | $5.34–$7.00 |
| CPC — enterprise | $7.00–$12.00+ |
| CPC — brand terms | **$0.50–$2.00** |
| CTR — brand keywords | **22.2%** |
| CTR — non-brand keywords | **3.6%** |
| Search click-to-trial/demo conversion | **3–5%** |
| CPL — SMB SaaS | **$87–$200** |
| CPL — blended, 24-mo avg | **$84** (brand $34, non-brand **$207**) |
| Trial-to-paid, opt-in (no card) | **18–25%** |
| 7-day vs 14-day trial | **7-day converts higher** |

— [kampaio.com](https://www.kampaio.com/blog/b2b-saas-google-ads-benchmarks-2026)

**The CPC contradiction matters and resolves on segment.** Growthspree's $8.50–$14.00 median is
skewed by enterprise verticals (cybersecurity $18.00, fintech $16.00). Kampaio explicitly segments and
puts **SMB SaaS at $3.33–$5.34**. OPS sells a $90–190/month product to owner-operators — squarely SMB.
**Plan against $4–8 CAD non-brand CPC**, with the caveat below.

The closest published verticals to OPS:
- **ERP/Operations: CPC $12.00, CTR 2.8%, CVR 2.8%, CPL $290, cost/SQL $1,600**
- **Project Management: CPC $9.00, CTR 3.8%, CVR 4.2%, CPL $170, cost/SQL $900**
— [growthspreeofficial.com](https://www.growthspreeofficial.com/blogs/saas-google-ads-benchmarks-2026-cpc-cpl-ctr-conversion-rate-by-vertical)

Project Management is the better analogue (SMB, self-serve, low ACV) and its **$9.00 CPC / $170 CPL**
is a reasonable pessimistic planning case.

The **most useful single number in this section** is Growthspree's **wasted spend: 25–40% median, 40–60%
bottom quartile.** On a $1,500/month budget that is $375–$600/month burned on queries that cannot buy.
Negative keyword work is not housekeeping; it is the single largest available efficiency gain.

### 5.3 ACV-based spend guidance — and why it does not fit OPS

Growthspree's recommended monthly spend starts at **$10K–$30K/mo for a $5K–$15K ACV**
— [growthspreeofficial.com](https://www.growthspreeofficial.com/blogs/saas-google-ads-benchmarks-2026-cpc-cpl-ctr-conversion-rate-by-vertical).

OPS's ACV is **$1,080–$2,280** (12 × $90–$190), *below the bottom of their lowest band*, and the
budget is $1–3k/month, *below the bottom of their lowest recommendation*. The honest reading: OPS is
outside the range these B2B SaaS benchmarks were built from. The right comparison set is SMB/PLG SaaS
and local software, not the B2B pipeline-marketing world these tables describe.

**Implication that must be stated plainly:** at a $1,080–$2,280 first-year ACV, a viable CAC is
roughly **$300–$700** if you expect payback inside a year (and OPS's retention, unknown at 6
customers, is the number that would justify going higher). Working backwards at a $6 CPC, 4% landing
page conversion and 14% trial→paid: $6 ÷ 0.04 = **$150 per trial**; ÷ 0.14 = **~$1,070 per paying
customer.** That is roughly a year of revenue on the middle tier — breakeven at best, and only if
churn is low. **This arithmetic is the central finding of the whole report.** Every recommendation in
§8 exists to move one of those three numbers.

### 5.4 Adjacent market: home services CPCs (what OPS competes with for attention, not for clicks)

| Segment | CPC | Source |
|---|---|---|
| Home services, all trades average | **$7.85** | [builtrightdigital.com](https://builtrightdigital.com/google-ads-cost-for-home-services/) |
| Painting | **$13.74** | same |
| HVAC | **$29.52** | same |
| Restoration | **$52.30** | same |
| Pool service | **$27.26** | same |
| Landscaping | **$8.74** | same |
| Mobile mechanic | $3.93 | same |
| Home services CPC YoY change | **up for 75% of businesses, +10.51% avg** (LocaliQ, 3,211 US campaigns, 2025) | [localiq.com](https://localiq.com/blog/home-services-search-advertising-benchmarks/) |

These are *homeowner-intent* CPCs (someone searching "HVAC repair"), not software-buyer CPCs. They
matter for two reasons: (1) they are the CPCs OPS's *customers* pay, which is a powerful piece of
landing-page and sales-conversation context; (2) they mark the queries OPS must aggressively exclude —
an HVAC query costing $29.52 that lands on a software page is the most expensive possible mistake in
this account.

Also relevant: **"a realistic starting budget typically ranges between $1,500 and $3,000 per month"**
for local home service businesses — [builtrightdigital.com](https://builtrightdigital.com/google-ads-cost-for-home-services/).
OPS's budget matches what its own customers spend on ads. That is a coincidence, but a useful reframe:
this is a small-business ad budget being spent in a B2B software auction.

### 5.5 Keyword-level CPC and volume for the specific terms requested

**Thin evidence — and this is a genuine gap, not a search failure.** Keyword-level CPC and search
volume for terms like "contractor scheduling app," "job management software," "invoicing app for
contractors," "field service management software," "Jobber alternative," "Housecall Pro alternative,"
"ServiceTitan alternative," "HVAC scheduling software" and "electrician scheduling app" are **not
published in any accessible text source.** Multiple searches returned only vendor comparison pages.
One source states this explicitly: this metric class "isn't typically included in general web content"
and requires Ahrefs / Semrush / Google Keyword Planner
— [general search result set](https://www.getjobber.com/academy/housecall-pro-competitors/).

**What can be said with confidence, and what must be measured directly:**

*Structural inferences (not benchmarked):*
- **"field service management software"** is the most enterprise-contested head term in this space —
  ServiceTitan, Salesforce Field Service, IFS, Praxedo, Zuper all bid it. Expect the highest CPC of
  the set and the worst fit: the searcher is often researching enterprise FSM, not a 3-person crew.
  This is a term to *avoid*, not to win.
- **Competitor-alternative terms** ("Jobber alternative," "Housecall Pro alternative") are the
  classic small-challenger play: low volume, very high intent, and the searcher has already been sold
  on the category and is shopping on price or fit. Note that Jobber and Housecall Pro **rank their own
  content on each other's alternative terms** — getjobber.com publishes "Housecall Pro Competitors"
  and housecallpro.com publishes "Best Jobber Alternatives"
  ([getjobber.com](https://www.getjobber.com/academy/housecall-pro-competitors/),
  [housecallpro.com](https://www.housecallpro.com/resources/best-jobber-alternatives/)) — so the SERP
  is already crowded with well-funded competitors defending and attacking. Expect high CPCs relative
  to volume, but the *intent* is the best available.
- **"ServiceTitan alternative"** is a trap for OPS: ServiceTitan targets **$2M+ revenue operations**
  ([getjobber.com](https://www.getjobber.com/academy/servicetitan-competitors/)) — someone leaving
  ServiceTitan is not an owner-operator, they are an enterprise buyer priced out or frustrated. Wrong
  audience.
- **Trade-specific long-tail** ("electrician scheduling app," "HVAC scheduling software") is where a
  $1–3k budget can actually win auctions: lower competition, unambiguous intent, and it lets the ad
  and landing page name the trade — the single strongest message-match lever available.

*The correct action:* pull the real numbers from **Google Keyword Planner** (free with an active
account) for Canada and the US separately before committing budget. That is a 30-minute task inside
the platform that no amount of web research substitutes for. Segment-level competitor positioning to
carry into it: **Jobber targets $100K–$1M revenue contractors, Housecall Pro $50K–$500K,
ServiceTitan $2M+** — [contractorplus.app](https://contractorplus.app/blog/housecall-pro-vs-jobber-vs-servicetitan).
OPS's owner-operator ICP overlaps Housecall Pro's floor and sits below Jobber's core.

---

## 6. Competitor messaging: what the incumbents actually say

**Method note:** Google's Ads Transparency Center is not reliably fetchable as text, and per the hard
rules no ad-creative images were retrieved. What follows is from competitor **landing pages and
pricing pages**, which is where the ad copy leads and which competitors align their ad copy to. Actual
served ad headlines are **thin evidence** in this report.

### 6.1 Side-by-side

| | Headline | CTA | Trial | Pricing visible on home | Social proof |
|---|---|---|---|---|---|
| **Jobber** | "Run a stronger service business" | "Start Free Trial" / "Find Your Plan" | **"No credit card required"** (stated 2x) | No | 400,000+ service pros; 100K+ businesses; 92M+ jobs; 4.8 (13,861 App Store reviews); "44% revenue growth on average in first year"; "12 hours+ saved per week" |
| **Housecall Pro** | "Everything to run and grow your business" | "Start free trial" | **"No credit card required"**, no length stated | No | 200K+ pros; 100M+ jobs; "35% avg. pro revenue growth"; "8+ avg. hours saved per week"; 30,000+ reviews, 4.7 stars |
| **Tradify** | "#1 Rated Job Management Software — The Best Tool to Run Your Business" | "Start Free Trial" / "TRY TRADIFY FREE!" | **"14-day free trial, no credit card required"** | No | 4.8/5 from 9,000+ ratings; named testimonial (James Brunton, JJ Electrical) |
| **Workiz** | "AI growth engine for home service businesses" | "Book a demo" **and** "Start free trial" | Free trial, no details | No | "Trusted by 120K+ home service pros in US and Canada" |
| **FieldPulse** | "Turn Chaos into Predictable Growth" | **"Get Demo" / "Book a demo"** | **No free trial offered** | No | 4.8/5.0, 2,537 reviews; customer logos |

Sources: [getjobber.com](https://www.getjobber.com/), [housecallpro.com](https://www.housecallpro.com/),
[tradifyhq.com](https://www.tradifyhq.com/), [workiz.com](https://www.workiz.com/),
[fieldpulse.com](https://www.fieldpulse.com/)

### 6.2 Jobber's pricing — the number OPS is actually competing against

| Plan | Annual price | Users included |
|---|---|---|
| Core | **$29/mo** (billed annually) | 1 |
| Connect | **$99/mo** | 1 |
| Grow | **$149/mo** | 1 |
| Plus | **$399/mo** | 15 |
| **Each additional user** | **+$29/mo** | — |

Add-ons: Marketing Suite **$99/mo**, AI Receptionist **$29/mo**, Pipeline **$49/mo**.
Trial: **"14 days… full access to all of Jobber's features on the Grow plan—no credit card required."**
Annual prepay saves **up to 25%** vs monthly (Core is $49/mo month-to-month vs $29/mo annual).
— [getjobber.com/pricing](https://www.getjobber.com/pricing/)

**This is the most commercially important finding in Section 6.** Jobber's headline "$29/mo" is for
**one user, billed annually**. A 5-person crew on Connect is $99 + 4×$29 = **$215/mo**, on Grow
$149 + 4×$29 = **$265/mo** — before add-ons, and only at the annual-prepay rate. OPS's $90/$140/$190
by crew size with **every feature in every tier** is genuinely cheaper for a real crew and radically
simpler to understand.

But note the trap: on a comparison SERP, **"$29/mo" beats "$90/mo"** to a scanning eye. OPS cannot win
a headline-price fight; it wins a **total-price-for-my-actual-crew** fight and a **no-add-on-upsell**
fight. That is a landing-page comparison-table job and an ad-copy job ("one price, whole crew, every
feature"), not a price cut.

### 6.3 Patterns worth copying

1. **Everyone runs a no-card free trial except FieldPulse.** Four of five competitors lead with
   "Start free trial" and three state "no credit card required" explicitly on the homepage. OPS's
   no-card trial is table stakes, not a differentiator — it must be *stated* (because its absence is
   noticed) but cannot be *the* pitch.
2. **Nobody shows pricing on the homepage.** All five route to a pricing page. **This is OPS's
   opening.** For an audience that has been burned by "call for pricing," putting three real numbers
   above the fold is a differentiator every incumbent has declined to take.
3. **Quantified outcome claims are the standard currency**: "44% revenue growth in first year"
   (Jobber), "35% avg. pro revenue growth" (Housecall Pro), "12 hours+ saved per week" (Jobber),
   "8+ avg. hours saved per week" (Housecall Pro). OPS at 6 customers **cannot and must not
   manufacture these.** Attempting to match them with invented numbers is both dishonest and, against
   a skeptical trades buyer who can check, actively counterproductive.
4. **Scale proof is the incumbent moat**: 400K pros (Jobber), 200K pros (Housecall Pro), 120K
   (Workiz). This is unwinnable and should not be contested. Contest on the axis where being small is
   an *advantage*: the founder answers the phone, the product is built for a 3-person crew and not
   retrofitted down from enterprise, no upsell ladder.
5. **"AI" is now the incumbent headline** — Workiz leads "AI growth engine," Housecall Pro leads
   "Powered by AI built from 100M+ jobs." That means the AI position is crowded and undifferentiated,
   which independently supports OPS's rule of never leading with "AI" in marketing copy. Describing
   the behaviour is now also the *contrarian* move, not just the on-brand one.
6. **FieldPulse's demo-gate is the outlier and the anti-pattern for OPS.** They are pushing upmarket
   ("partners with growing field service businesses"). A demo gate converts at **1.5–4% vs 8% for
   self-serve trial** (§4.2). At a $90–190/month ACV a demo gate cannot pay for itself.
7. **Tradify's headline is the closest structural analogue to OPS's opportunity**: it names the
   category ("Job Management Software"), states the trial terms in the same breath ("14-day free
   trial, no credit card required"), and uses a *named tradesperson* testimonial rather than an
   aggregate number. That is a pattern a 6-customer company can execute honestly today.

### 6.4 What this implies for OPS's ad copy angles

Testable angles that are true, specific, and unclaimed by the incumbents:

- **Total price honesty** — "One price for your whole crew. No per-user math." (Direct counter to
  Jobber's +$29/user and the add-on ladder.)
- **Every feature in every tier** — no competitor offers this; all five ladder features by tier.
- **Built for the phone, in the field** — mobile-first is claimed by all, but OPS is genuinely
  iOS-native rather than a web app in a wrapper. This is only worth saying if the landing page proves
  it.
- **Named-trade specificity** — "Deck builders," "Electricians," etc. in the headline of a
  trade-specific ad group. Incumbents run generic "home service pros."

---

## 7. LLM-driven ad iteration in practice

### 7.1 What practitioners actually use LLMs for — and where they refuse to

The most credible practitioner account (PPCChat, Nov 2025) draws a sharp line:

**Good uses:**
- **Writing Google Ads Scripts** — using the model as "a translator that speaks machine" to turn
  strategic intent into executable monitoring code. Example given: budget-pacing monitoring across
  200 accounts with different billing cycles, previously manual and error-prone.
- **Logic development** for repetitive monitoring.

**Explicitly bad uses:**
- **Ad copy.** Early attempts "produced generic garbage."
- **Pasting account data into public tools.** "I never pasted client data into ChatGPT" — instead
  "use AI to write logic that processes your data locally."

— all [officialppcchat.com](https://officialppcchat.com/2025/11/10/beyond-the-ai-hype-how-to-give-your-google-ads-workflow-superpowers-with-llms/)

**The "generic garbage" finding deserves weight.** It is the single most consistent failure mode: an
LLM asked for ad copy with no constraints regresses to the mean of all SaaS ad copy on the internet —
which is precisely the voice OPS's brand rules forbid. LLM copy generation is useful only when the
prompt carries hard constraints (voice rules, banned words, the actual differentiator, character
limits) and the output is *selected from*, not shipped.

### 7.2 Guardrails the practitioners use

1. **Preview mode first** — scripts "simulate execution without making real changes," showing exactly
   what would happen before commitment.
2. **Notification-only automation to start** — build "scripts that don't make campaign changes,"
   keeping humans in the decision loop.
3. **Heavy commenting + Logger statements** so the human can audit each step.
4. **Specific prompt template**: *"Write a Google Ads script that [specific goal]. If true, send an
   email to [address] with [details]. Include heavy commenting and error handling."* Specificity
   "prevents hallucinations and ensures reproducible results."
5. **Explicit rejection of black-box control**: they reject "handing over strategic control blindly"
   to either platform recommendations or AI systems.

Stated warning, verbatim: **"LLMs can sound brilliant and still be wrong. In live accounts with
meaningful spend, confident mistakes are expensive."**
— [officialppcchat.com](https://officialppcchat.com/2025/11/10/beyond-the-ai-hype-how-to-give-your-google-ads-workflow-superpowers-with-llms/)

### 7.3 Google's stance on automated management via API

- **As of mid-2026 there is no official Google-built ChatGPT integration for managing Google Ads** —
  only "third-party GPTs and connectors of varying quality and security posture."
  — [useadstudio.com](https://useadstudio.com/blog/can-chatgpt-manage-your-google-ads)
- Tools that do this properly wrap the Google Ads API in **deterministic code components**, create
  **campaigns in paused status by default** for human review, and apply **built-in rate limiting "to
  keep accounts safe from bans."** — [useadstudio.com](https://useadstudio.com/blog/can-chatgpt-manage-your-google-ads)
- The recommended pattern is **"reviewable output before applying changes"**
  — [adspirer.com](https://www.adspirer.com/blog/chatgpt-prompts-google-ads)

The rate-limiting note is the operative one: the Google Ads API enforces request quotas and the
platform's automated-activity policies apply to API clients. An LLM agent looping on an account
without rate limits is a real account-suspension risk, not a theoretical one. **Thin evidence** on any
explicit Google policy statement about LLM-authored ads specifically — the applicable rules are the
existing Ads policies on the *content* of ads, which apply regardless of who or what wrote them.

### 7.4 Iteration cadence and the mathematics of over-iterating

This is where LLM-driven iteration collides hardest with how the platform works.

**Learning period:**
- **2–6 weeks**, "depending on your conversion volume, budget, and bidding strategy"
  — [groas.com](https://www.groas.com/post/google-ads-smart-bidding-learning-period-2026-how-long-resets-shorten)

**What resets it:**
- Changing tCPA/tROAS by **more than 15–20%**
- Significant daily budget increase or decrease
- Pausing and restarting campaigns
- Changing conversion action or counting method
- Adding/removing large audience segments
- Restructuring ad groups or campaigns
— [groas.com](https://www.groas.com/post/google-ads-smart-bidding-learning-period-2026-how-long-resets-shorten)

**Budget-change reset threshold — sources disagree:**

| Threshold quoted | Source |
|---|---|
| **>15%** | [dotidot.io](https://www.dotidot.io/post/google-ads-learning-period-tips-to-avoid-resets) |
| **>20%** ("$100 → $130 or → $75 crosses it") | [groas.com](https://www.groas.com/post/google-ads-smart-bidding-learning-period-2026-how-long-resets-shorten) |
| **under 10–20% may not reset**; doubling will | [tkist.com](https://tkist.com/blog/google-ads-2026) |
| **~30% or more** triggers a reset | [tkist.com](https://tkist.com/blog/google-ads-2026) |

Nobody outside Google knows the true threshold and it is very likely not a fixed number. **The safe
operating rule is the strictest one: keep any single change under 15%.**

**Other hard numbers:**
- **"Wait at least one to two weeks between adjustments"** after a target change
- **"Your daily budget should be at least three to five times your target CPA"** for efficient learning
- 30+ conversions/week is "optimal for fastest learning exit"; **campaigns under 15 conversions/month
  should consider portfolio strategies**
— [groas.com](https://www.groas.com/post/google-ads-smart-bidding-learning-period-2026-how-long-resets-shorten)

**The 3–5x rule is worth pausing on.** If OPS's daily budget is $50 and the rule holds, the implied
maximum workable target CPA is **$10–$17 per conversion**. A realistic cost per *trial* is $100–200
(§5.3). The rule and the reality are irreconcilable — which is another independent confirmation that
target-based Smart Bidding is unavailable to this account, arrived at from a completely different
direction than §2.1's conversion thresholds. Two independent lines of evidence, same conclusion.

**The batching rule — the single most actionable operational finding:**
> "Rather than optimizing daily with small tweaks, plan your significant changes for one session per
> week, making all changes at once to trigger one learning period instead of multiple ones."
> — [tkist.com](https://tkist.com/blog/google-ads-2026)

And the diagnosis of the common failure:
> "Most account managers intervene too frequently during the learning phase, interpreting normal
> algorithmic variance as campaign failure and making changes that restart learning repeatedly."
> — [tkist.com](https://tkist.com/blog/google-ads-2026)

### 7.5 Why over-iteration is specifically dangerous at OPS's volume

Combine three findings:
1. Learning takes **2–6 weeks** (§7.4)
2. Detecting a real conversion-rate difference needs **100+ conversions per variant** (§3.7)
3. OPS will produce roughly **5–20 trials/month** from paid

An LLM that can generate 40 headline variants in a minute creates an *irresistible* temptation to
change something weekly. At this volume, weekly copy changes mean the account is **permanently in a
learning phase, permanently reading noise as signal, and permanently unable to accumulate a comparable
period.** The productivity of the LLM is precisely the hazard.

**The correct division of labour:**

| Task | Cadence | Who/what |
|---|---|---|
| Search-term review + negative keywords | **Weekly** | Human, LLM-assisted classification |
| Budget/bid/structure changes | **One batched session per week, max** | Human |
| Ad copy generation (candidate pool) | Any time — offline, not published | LLM with hard voice constraints |
| Ad copy *publishing* | **Every 4–8 weeks** (§3.5) | Human |
| Landing page copy tests | Continuous (pooled traffic) | Human + LLM |
| Conversion/structure/strategy changes | Monthly review, quarterly change | Human |

Note the asymmetry: **negative keywords can and should be reviewed weekly** — adding negatives is
low-risk relative to budget/bid changes and is where the 25–40% wasted spend (§5.2) is recovered. This
is also the task LLMs are genuinely well-suited to: hand it 300 search terms and ask it to classify
each as buyer / job-seeker / homeowner / student / unclear, then a human approves the exclusions. That
is classification with human review, not autonomous account management — exactly the pattern §7.2
endorses.

---

## 8. What this means for a $1–3k/month trades-SaaS account

### 8.1 First, a reframe on the $4,800 already spent

$4,800 over 13 months is **~$370/month**. Run that through benchmark rates (§5.2, SMB SaaS CPC
$3.33–$5.34; landing page CVR 2.5–4%; trial→paid 8.9–18.2%):

- $370 ÷ $6 CPC ≈ **60 clicks/month**
- × 4% landing page conversion ≈ **2.4 trials/month**
- × 14% trial→paid ≈ **0.34 customers/month** ≈ **4–5 customers over 13 months**

OPS has 6 paying customers. Without the actual channel attribution this is suggestive, not proof —
but the prior spend appears to have performed **roughly at benchmark**. The problem was never that
Google Ads "didn't work." The problem is that $370/month buys a sample size indistinguishable from
zero: at that spend, no campaign, ad, keyword or landing page can ever be evaluated, and every month
looks like a coin flip.

**The strategic implication: $370/month is worse than $0/month**, because it costs real money and buys
no learning. Either commit to a budget that produces a readable signal, or don't run search at all.
The floor for readability is roughly **$1,500/month** ($50/day → ~250 clicks/month → ~10 trials/month
→ a quarterly sample worth reading).

### 8.2 The uncomfortable unit economics, stated plainly

| | Pessimistic | Benchmark | Optimistic (target) |
|---|---|---|---|
| Non-brand CPC (CAD) | $9 | $6 | $4 |
| Landing page → trial | 2.5% | 4% | 8% |
| Cost per trial | **$360** | **$150** | **$50** |
| Trial → paid (no card) | 9% | 14% | 20% |
| **Cost per paying customer** | **$4,000** | **$1,070** | **$250** |
| First-year revenue ($140 tier) | $1,680 | $1,680 | $1,680 |
| **Year-1 payback** | **No (2.4x under)** | **Marginal (~breakeven)** | **Yes (6.7x)** |

Inputs: CPC [kampaio.com](https://www.kampaio.com/blog/b2b-saas-google-ads-benchmarks-2026);
landing page CVR [saashero.net](https://www.saashero.net/strategy/b2b-saas-conversion-rate-benchmarks/) /
[growthspreeofficial.com](https://www.growthspreeofficial.com/blogs/saas-google-ads-benchmarks-2026-cpc-cpl-ctr-conversion-rate-by-vertical);
trial→paid [growthspreeofficial.com](https://www.growthspreeofficial.com/blogs/b2b-saas-trial-to-paid-conversion-rate-benchmarks-2026-by-trial-type-acv-length-credit-card) /
[shno.co](https://www.shno.co/marketing-statistics/free-trial-conversion-statistics)

**At benchmark performance, paid search on a $1,080–$2,280 ACV is roughly breakeven in year one and
only profitable on retention.** That is not a reason to skip it — SaaS is a retention business and a
customer who stays three years is worth $3,200–$6,800. It *is* a reason to (a) know your churn before
scaling spend, and (b) treat the three levers in the table as the actual work. Google Ads is the
delivery mechanism; the levers are the product.

**The three levers, in order of controllability:**
1. **Landing page conversion 2.5% → 8%** — biggest multiplier, entirely under your control, testable
   with pooled traffic (§3.7). Doubling this halves CAC.
2. **Trial→paid 9% → 20%** — an onboarding/activation problem, not an ads problem. This is where the
   product team earns the ad budget.
3. **CPC $9 → $4** — via keyword selection (long-tail trade-specific over head terms), Quality Score
   (5→8 = **−28% CPC**, [tripledart.com](https://www.tripledart.com/blog/perfect-google-ads-campaign-structure)),
   and ruthless negatives (25–40% wasted spend is the median, §5.2).

### 8.3 Recommended starting structure — $1,500/month CAD ($50/day)

**Geography: Canada only for the first 90 days.** Rationale: concentrating $50/day in one market wins
auctions where splitting it across two markets wins neither; Canada is the home market with the
existing customer evidence and testimonials; US Search is where every well-funded incumbent spends.
Add the US as a **separate campaign** only after Canada produces a known cost per trial. Set location
targeting to **"Presence: people in your targeted locations."**

**Three campaigns. Not six.**

| # | Campaign | Match types | Bidding | Daily | % |
|---|---|---|---|---|---|
| 1 | `BRAND – CA` | Exact only | Manual CPC, low cap (~$2) | **$3** | 6% |
| 2 | `CORE – CA` | **Phrase + Exact** | **Max Clicks, CPC cap $8** | **$32** | 64% |
| 3 | `COMPETITOR – CA` | **Exact + Phrase** | **Max Clicks, CPC cap $10** | **$15** | 30% |

**No broad match. No Performance Max. No Demand Gen. No AI Max. No Search Partners. No Display
Network.**

The broad-match exclusion is not conservatism, it is a logical consequence: Google's campaign-level
broad match setting "is only available if the campaign is using conversion based smart bidding"
([Google Ads Help](https://support.google.com/google-ads/answer/13389795?hl=en)), and OPS cannot run
conversion-based smart bidding at 2–7 conversions/month (§2.1). **Broad match plus Maximize Clicks is
the single worst combination available** — the widest possible net optimized for the cheapest possible
click. Uncheck "Include Google search partners" and "Include Google Display Network" at campaign
creation; both default to on and both are pure leakage at this budget (recall the 0.07% vs 3%
conversion-rate gap on Search Partners, §1.5).

**Brand campaign caveat:** "OPS" is a generic three-letter string; a brand campaign here can only
safely target `opsapp`, `ops app`, `opsapp.co`, `ops job management` and similar — **exact match
only**, tightly negatived. Volume will be near zero. Keep it anyway: it is cheap ($0.50–$2.00 CPC per
[kampaio.com](https://www.kampaio.com/blog/b2b-saas-google-ads-benchmarks-2026)), it converts at
~22.2% CTR vs 3.6% non-brand (same source), and it stops competitors buying the name once OPS is worth
buying. Budget it at $3/day and expect to underspend.

### 8.4 Ad groups — intent-themed, one landing page per group

**`CORE – CA`** (one ad group = one URL, per §1.3):

| Ad group | Seed keywords (phrase/exact) | Landing page |
|---|---|---|
| `Job Management` | job management software for trades, job management app, job tracking app for contractors, work order app for small business | `/job-management` |
| `Crew Scheduling` | crew scheduling app, scheduling software for contractors, dispatch app for small crews, schedule app for trades | `/scheduling` |
| `Quoting & Invoicing` | invoicing app for contractors, quoting software for trades, estimate app for contractors, invoice app for tradesmen | `/quotes-invoices` |

**`COMPETITOR – CA`**:

| Ad group | Seeds | Landing page |
|---|---|---|
| `Jobber Alt` | jobber alternative, alternative to jobber, jobber competitors, jobber pricing | `/compare/jobber` |
| `Housecall Alt` | housecall pro alternative, housecall pro competitors, housecall pro pricing | `/compare/housecall-pro` |

**Deliberately excluded:** `field service management software` (enterprise-contested head term, wrong
buyer, highest CPC in the set — §5.5) and `servicetitan alternative` (ServiceTitan targets **$2M+
operations**, [getjobber.com](https://www.getjobber.com/academy/servicetitan-competitors/) — that
person is not an owner-operator).

**Trade-specific ad groups** (`electrician scheduling app`, `HVAC job software`, `deck builder
software`) are the highest-value expansion, because they permit exact trade naming in the headline —
the strongest message-match lever available. **Add them in month 2–3, one trade at a time, starting
with the trades where OPS already has a customer to quote.** Adding them all at launch fragments
$32/day into unreadable slices.

**Before any of this goes live: pull real volume and CPC from Google Keyword Planner for Canada.**
The keyword-level numbers do not exist in public sources (§5.5) and this list is a hypothesis until
checked. Expect to cut a third of it for zero volume.

### 8.5 Negative keywords — day-one lists

Build these as **shared negative lists** applied to all campaigns.

**`NEG – Job Seekers`** (phrase): jobs, hiring, career, careers, salary, wage, apprentice,
apprenticeship, resume, employment, recruiter, "how to become"

**`NEG – Homeowner Intent`** (phrase — the dangerous one): near me, hire, cost to, how much does,
repair, install, emergency, replacement, "best plumber", "best electrician", contractor near me,
quotes for, get a quote

**`NEG – Training`** (phrase): course, training, certification, exam, ticket, red seal, school,
license, licensing, tutorial, "how to"

**`NEG – Generic SaaS Waste`** (phrase, per [tripledart.com](https://www.tripledart.com/blog/perfect-google-ads-campaign-structure)):
free, open source, crack, torrent, template, excel, spreadsheet, pdf, reddit, "vs", review, github

**`NEG – Wrong Segment`** (phrase): enterprise, erp, fleet, franchise, "50 employees", servicetitan
(in CORE only), salesforce, sap

Two notes: (a) exclude `free` in CORE but **not** in COMPETITOR — "free alternative to jobber" is a
real buyer; (b) `vs` and `review` are excluded from CORE but belong *in* COMPETITOR. Review search
terms **weekly** — this is where the 25–40% median wasted spend (§5.2) is recovered, and it is the
one weekly change that does not risk a learning reset (§7.5).

### 8.6 Bidding plan and the escalation ladder

**Now (0–15 conv/month): `Maximize Clicks` with a maximum CPC bid limit.**
Justification: "If your campaigns generate fewer than 15 conversions per month, Manual CPC or
Maximize Clicks is the practical starting point"
— [storegrowers.com](https://www.storegrowers.com/google-ads-bid-strategy/). The CPC cap is not
optional — without it Max Clicks has "no conversion signal whatsoever" and will buy the cheapest
clicks available (same source). The cap plus the phrase/exact-only keyword set is what makes it safe.

**Escalation ladder — do not skip steps:**

| Trigger | Move to |
|---|---|
| 15+ trial-starts/month sustained 2 months | **Maximize Conversions** (no target) |
| 30+ trial-starts/month sustained 2 months | **Target CPA**, target set at trailing 30-day actual CPA |
| 30–50 *paid* conversions/month | Consider tROAS / value-based bidding with the §2.7 values |
| 60–100+ conversions/month | Only then consider PMax (§1.1) |

Never accept Google's in-platform tCPA recommendation before hitting the trigger — Google will offer
it to campaigns that do not qualify ("Target CPA recommendations can still appear for low-volume
campaigns", [Google Ads Help](https://support.google.com/google-ads/answer/6268632?hl=en)).

**When you do move to tCPA:** change the target by **no more than 15–20% at a time** and **wait 1–2
weeks between adjustments** — [groas.com](https://www.groas.com/post/google-ads-smart-bidding-learning-period-2026-how-long-resets-shorten).

### 8.7 Conversion actions to build before spending a dollar

| Action | Type | Purpose |
|---|---|---|
| `Trial Started` (account + company created) | **Primary — the only one in "Conversions"** | Bidding target |
| `Signup Started` | Secondary / observation | Diagnoses landing-page vs form leak |
| `Trial Activated` (first job created / crew invited / quote sent) | Secondary / observation | Quality signal; future primary |
| `Paid` (card entered) | Secondary / observation | Truth; future value-based bidding |

**Also required at launch:**
- **Enhanced conversions for leads** enabled (hashed email at signup) — step 1 on every 2026 tracking
  checklist ([ppc.live](https://www.ppc.live/post/google-s-ai-max-for-search-what-the-data-actually-shows-in-2026))
- **GCLID captured and stored on the signup record.** This costs an afternoon of engineering and is
  irreversible if skipped — every trial that signs up without it is permanently unattributable. It
  cannot drive bidding at this volume (§2.5), but at 6 customers you can answer "which keyword bought
  this customer" *individually*, which is more valuable than any aggregate.
- Conversion windows: **trial-start 30 days**, **paid 60–90 days**
  ([groas.com](https://www.groas.com/post/google-ads-for-saas-2026-complete-strategy-guide-b2b-lead-generation-trial-acquisition))
- **Web signup only. Never send paid search to the App Store** (§4.5) — SKAN reports aggregated data
  that is thresholded to nothing at this volume, and an App Store click destroys the GCLID link
  permanently. Offer the iOS app after signup.

### 8.8 Landing pages

Three dedicated pages, one per CORE ad group, plus two comparison pages. Not the homepage — dedicated
pages convert roughly 2x better on paid traffic (§4.1).

Every page: **single CTA repeated** (+29%, §4.3), **real pricing above the fold** (no competitor does
this — §6.3), **"no credit card" stated as a promise**, **one named real customer quote adjacent to
the CTA** (68% lift, §4.3 — and a named tradesperson beats an invented aggregate, §6.3), **sub-2s
load** (+123% bounce from 1s→10s, §4.3), and **headline matching the ad group's keyword theme**.

The comparison pages carry the §6.2 arithmetic explicitly: Jobber's Connect at $99/mo is one user;
five users is $215/mo before add-ons. OPS is $140/mo for the crew, every feature. That table is the
single most persuasive asset available and it is simply true.

### 8.9 Cadence

| Cadence | Activity |
|---|---|
| **Weekly** (one session, ~45 min) | Search-term report → add negatives. Check spend pacing. **No other changes.** |
| **Bi-weekly** | Landing page copy/layout iteration (pooled traffic, not a "test") |
| **Every 4–8 weeks** | RSA asset refresh: replace Low, keep Best (§3.5) |
| **Monthly** | Full review: cost per trial, trial→paid, keyword-level P&L, geo/device split |
| **Quarterly** | Structure decisions: add US, add trade ad groups, escalate bidding |
| **Never** | Daily tweaking. It is the documented top failure mode (§7.4) and it guarantees permanent learning-phase residence at this volume. |

Batch all significant changes into **one session per week** to trigger one learning period instead of
several — [tkist.com](https://tkist.com/blog/google-ads-2026).

### 8.10 What to expect, and the decision gates

**Projected at $1,500/month, benchmark rates:** ~250 clicks/month → **~10 trials/month** →
**~1.4 paying customers/month**. That would roughly **triple** the current 2–7 signups/month and take
OPS from 6 customers to ~20 in a year from paid alone.

**Commit for 90 days minimum.** Two learning periods (2–6 weeks each, §7.4) plus a 30-day trial cycle
plus a 60–90 day paid conversion window means **nothing is readable before day 90.** Pausing at week
3 — which is what a $370/month account is forced into — is what produced 13 months of no information.

**Gates at day 90:**

| Result | Action |
|---|---|
| Cost/trial < $120 **and** trial→paid > 12% | **Scale to $3,000/month.** Add US as a separate campaign. |
| Cost/trial < $120, trial→paid < 8% | **Do not scale.** The problem is onboarding, not ads. Hold spend, fix activation. |
| Cost/trial $120–250 | Hold at $1,500. Work the three levers (§8.2), especially landing page CVR. |
| Cost/trial > $250 with clean negatives | **Stop.** Google Search is not viable for this ACV at current CPCs. Redirect budget to trade associations, supplier partnerships, and the founder's network. |

That last row is a real possible outcome and worth naming in advance, because deciding the stopping
rule while spending is how $4,800 becomes $10,000 with the same amount of information.

### 8.11 Three decisions that belong to Jackson, not the ads account

1. **The no-card trial.** Benchmarks say card-required produces **~2.9x more paying customers from
   identical traffic** (10.5 vs 3.6 per 1,000 visitors, §4.4). That is the difference between paid
   search being marginal and being clearly profitable. It also contradicts the brand promise to a
   distrustful audience. This is a taste and positioning call with a large, quantified cost attached —
   not an optimization.
2. **Budget commitment.** $1,500/month for 90 days ($4,500) with no guaranteed return, versus not
   running paid search at all. $370/month is not on the menu.
3. **Churn.** The entire case for paid acquisition rests on retention, and at 6 customers nobody knows
   it. If customers stay 3+ years, benchmark CAC is fine. If they churn at 12 months, it is not.
   Knowing this is a prerequisite to scaling spend, not a nice-to-have.

---

## Sources

- [Triple Dart — Google Ads campaign structure 2026](https://www.tripledart.com/blog/perfect-google-ads-campaign-structure)
- [PPC Live — AI Max for Search: what the data shows in 2026](https://www.ppc.live/post/google-s-ai-max-for-search-what-the-data-actually-shows-in-2026)
- [Google Ads Help — broad match keywords campaign setting](https://support.google.com/google-ads/answer/13389795?hl=en)
- [Google Ads Help — About Target CPA bidding](https://support.google.com/google-ads/answer/6268632?hl=en)
- [Greenwebmedia — PMax vs Search 2026](https://www.greenwebmedia.com/google-ads-performance-max-vs-search-campaigns-which-one-should-your-business-use-in-2026/)
- [Groas — budget allocation across Search, PMax, Demand Gen](https://www.groas.com/post/google-ads-budget-allocation-strategy-2026-search-pmax-demand-gen)
- [Growthspree — AI Max vs PMax for B2B SaaS](https://www.growthspreeofficial.com/blogs/ai-max-search-vs-performance-max-b2b-saas-2026)
- [Ryze — Google Ads minimum budget guide 2026](https://www.get-ryze.ai/blog/google-ads-minimum-budget-guide-2026)
- [Ryze — average CPC by industry 2026](https://www.get-ryze.ai/blog/average-cpc-by-industry-google-ads-2026)
- [Store Growers — Google Ads bid strategies 2026](https://www.storegrowers.com/google-ads-bid-strategy/)
- [KeywordMe — how many conversions Google Ads needs](https://www.keywordme.io/blog/how-many-conversions-do-google-ads-need-to-optimize)
- [Groas — Google Ads for SaaS 2026 complete strategy guide](https://www.groas.com/post/google-ads-for-saas-2026-complete-strategy-guide-b2b-lead-generation-trial-acquisition)
- [ALM Corp — Smart Bidding update Aug 2026](https://almcorp.com/news/google-smart-bidding-update-target-cpa-roas-august-2026/)
- [Groas — RSA headlines / Ad Strength 2026](https://www.groas.com/post/google-ads-responsive-search-ads-2026-headlines-ad-strength-optimization)
- [Search South — RSA best practice 2026](https://www.search-south.com/2026/02/21/responsive-search-ads-best-practice-in-2026/)
- [Omologist — RSA 2026 best practice guide](https://omologist.com/google-ads/responsive-search-ads/)
- [Spires Digital — RSA best practices 2026](https://spiresdigital.com/blog/responsive-search-ads-best-practices/)
- [ROA Marketing — RSA best practices 2026](https://roa-marketing.com/blog/responsive-search-ads-best-practices-google-ads-2026/)
- [ALM Corp — Experiment Center guide](https://almcorp.com/blog/google-ads-experiment-center-guide/)
- [PageDuel — A/B testing Google Ads 2026 playbook](https://pageduel.com/blog/ab-test-google-ads-campaigns)
- [DataFeedWatch — A/B testing RSAs](https://www.datafeedwatch.com/blog/ab-test-responsive-search-ads)
- [Phenyx — landing page vs homepage](https://www.phenyx.co/post/landing-page-vs-homepage)
- [CorePPC — landing page conversion benchmarks 2026](https://coreppc.com/blog/landing-page-conversion-rate-benchmarks-2026/)
- [SaaSHero — B2B SaaS landing page conversion benchmarks 2026](https://www.saashero.net/strategy/b2b-saas-conversion-rate-benchmarks/)
- [Shno — free trial conversion statistics 2026](https://www.shno.co/marketing-statistics/free-trial-conversion-statistics)
- [Growthspree — trial-to-paid benchmarks 2026](https://www.growthspreeofficial.com/blogs/b2b-saas-trial-to-paid-conversion-rate-benchmarks-2026-by-trial-type-acv-length-credit-card)
- [Kirro — free trial conversion rate](https://kirro.io/free-trial-conversion-rate)
- [Google Analytics Help — SKAdNetwork for iOS app measurement](https://support.google.com/analytics/answer/13168376?hl=en)
- [AdLibrary — SKAdNetwork explained, 2026 iOS attribution reality](https://adlibrary.com/posts/skadnetwork)
- [Rock Paper — iOS attribution 2026: ATT, SKAN, AdAttributionKit](https://rockpapermarketing.io/blog/ios-att-skadnetwork-mobile-marketers-guide)
- [Moburst — mobile attribution in 2026](https://www.moburst.com/blog/mobile-attribution-in-2026-what-marketers-actually-need-to-know/)
- [Web Tonic — Google Ads benchmarks 2026](https://www.webtonic.io/blog/google-ads-benchmarks)
- [Digital Applied — Google Ads benchmarks 2026](https://www.digitalapplied.com/blog/google-ads-benchmarks-2026-cpc-ctr-cvr-industry)
- [Growthspree — SaaS Google Ads benchmarks by vertical 2026](https://www.growthspreeofficial.com/blogs/saas-google-ads-benchmarks-2026-cpc-cpl-ctr-conversion-rate-by-vertical)
- [Kampaio — B2B SaaS Google Ads benchmarks 2026](https://www.kampaio.com/blog/b2b-saas-google-ads-benchmarks-2026)
- [BuiltRight Digital — home services Google Ads CPC benchmarks 2026](https://builtrightdigital.com/google-ads-cost-for-home-services/)
- [LocaliQ — 2025 home services search ad benchmarks](https://localiq.com/blog/home-services-search-advertising-benchmarks/)
- [Jobber homepage](https://www.getjobber.com/) · [Jobber pricing](https://www.getjobber.com/pricing/) · [Jobber — Housecall Pro competitors](https://www.getjobber.com/academy/housecall-pro-competitors/) · [Jobber — ServiceTitan competitors](https://www.getjobber.com/academy/servicetitan-competitors/)
- [Housecall Pro homepage](https://www.housecallpro.com/) · [Housecall Pro — best Jobber alternatives](https://www.housecallpro.com/resources/best-jobber-alternatives/)
- [Tradify homepage](https://www.tradifyhq.com/) · [Workiz homepage](https://www.workiz.com/) · [FieldPulse homepage](https://www.fieldpulse.com/)
- [ContractorPlus — Housecall Pro vs Jobber vs ServiceTitan](https://contractorplus.app/blog/housecall-pro-vs-jobber-vs-servicetitan)
- [PPCChat — giving your Google Ads workflow superpowers with LLMs](https://officialppcchat.com/2025/11/10/beyond-the-ai-hype-how-to-give-your-google-ads-workflow-superpowers-with-llms/)
- [AdStudio — can ChatGPT manage your Google Ads](https://useadstudio.com/blog/can-chatgpt-manage-your-google-ads)
- [Adspirer — ChatGPT prompts for Google Ads](https://www.adspirer.com/blog/chatgpt-prompts-google-ads)
- [Groas — Smart Bidding learning period 2026](https://www.groas.com/post/google-ads-smart-bidding-learning-period-2026-how-long-resets-shorten)
- [Dotidot — Google Ads learning period, avoiding resets](https://www.dotidot.io/post/google-ads-learning-period-tips-to-avoid-resets)
- [Tkist — Google Ads in 2026: what changed](https://tkist.com/blog/google-ads-2026)
- [TechWyse — budget pacing change affects scheduled campaigns](https://www.techwyse.com/news/platform-updates/google-ads-budget-pacing-change-ad-scheduling-2026)
