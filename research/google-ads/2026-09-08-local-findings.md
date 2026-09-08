# Google Ads engine — local findings (2026-09-08)

## Account autopsy (live GAQL, customer 4454506598 "OPS", CAD, America/Vancouver, auto-tagging ON)

- 22 campaigns, ALL PAUSED. No spend since 2026-03-09. $4,777.80 CAD lifetime (2025-02 → 2026-03), 8,495 clicks, 355 "conversions".
- Spend by type: Display (join_ops page, CA/US/UK/AU + leaked to SE/ZA/FI/DK/NO/SG/HK/AE) ≈ $1,345; PMax ≈ $1,356; App campaigns ≈ $659; Search ≈ $1,418.
- Search was the worst lane: 228 clicks, 6 conv. CPCs $2–$29. HIRE OPS - WEB ($998, TARGET_SPEND, broad match on "same day cleaning service", "small moving company", "signature generator"…). OPS SEARCH CAMPAIGN CANADA ($309, 18 clicks, 0 conv, avg CPC ~$17). UK ($111, 9 clicks, 0 conv).
- Search terms that burned money: "what is housecall pro" $136/1 click; "jobber free trial" $110/1 click; "signature generator" $98/30 clicks/3 junk conv; "apps similar to jobber" $70/1 click/3 conv; "esign" family ≈ $80. ZERO negative keywords anywhere. 1,583 keywords (659 broad / 578 exact / 346 phrase), only 38 ever spent.
- RSA copy: POOR ad strength; off-brand register ("Crush Inefficiency", "lethal precision", "clean-handed nerds", "Hire OPS. Earns $400/Month", "122% or more ROI"). Unverifiable numbers, exclamation-adjacent tone.
- Display drove most "conversions" cheaply (9–13% CTR) but they were Bubble-page loads (`opsapp.co/join_ops`, MANY_PER_CLICK) — that page now 301s to /plans. Not customers.
- App campaigns: "OPS APP First open" 129 installs at ≈ $5 each (tCPA $5 worked). Installs did not become companies.
- try.opsapp.co received $489 / 654 clicks (PMax "TRY OPS 2026") and recorded 0 conversions: NO conversion action exists for the landing app's signup.
- Devices: 85% of spend + 96% of conv on MOBILE. Geo: CA ($2,142) and US ($1,843) dominate.
- Conversion actions ENABLED (6 of 56): Join Ops SIgnup / Homepage Signup / Quiz Signup v2 (WEBPAGE, Bubble era, dead), OPS APP First open (Firebase iOS first_open, primary), iOS sign_up (primary), iOS **login (primary — every login counts as a conversion; pollutes bidding)**. Nothing fires for app.opsapp.co/register or try.opsapp.co signup.
- Experiments: 0. Labels: 0. Shared set "Competitors" (BRANDS list, 4 members). Jackson's email is ADMIN on the account; SA authenticates for reads.

## Warehouse / attribution state (Supabase prod)

- ads_daily_account 229 rows, ads_daily_campaign 1,139, ads_daily_search_term 5,274 (Apr–Nov 2025), ads_daily_keyword 0 (by design). Daily sync cron 08:00 UTC healthy. ad_briefings 28 weekly rows (OpenAI + Tavily) — advisory only, generic, banned-register output ("Boost Productivity Today", "Start free trial!").
- trial_attributions: 64 rows, attributed_channel = unknown for all (63 null UTM, 1 chatgpt.com). first_paid_at set on 3. gclid never captured for any company.
- companies: 64. 44 created Feb-2026 (migration); then 5/2/4/7/0/2 per month Mar–Aug. Paying now: 6 (3 business, 1 team, 1 starter, 1 null). 20 on trial. 38 cancelled.
- Referral question answered by 7 companies (Instagram 2, Word of mouth 2, Other 2, Internet ad 1).

## Funnel surfaces

- opsapp.co (ops-site): every CTA → App Store. 39 industry pages, 8 compare pages, /plans ($0 trial, $90/$140/$190 by crew size, every feature every tier, no card, no contract). First-touch cookie `ops_attribution` on `.opsapp.co` captures UTM + gclid/fbclid (30d).
- try.opsapp.co (try-ops): ad landing app. AI-rotated A/B landing variants (OpenAI gpt-4o, daily cron), audience overrides keyed on utm/referrer (trade, competitor, intent). Signup: Firebase → sync-user → company setup → /download (deep link → App Store fallback, or web dashboard). Does NOT capture gclid/UTM into the shared cookie; no Google Ads conversion fires.
- app.opsapp.co: /register (new company web signup), /join (invite), /setup. trial_attributions seeded by trigger at company insert from the cookie; first_paid_at via billing_events trigger.
- iOS: Firebase → Google Ads (first_open, sign_up, login, purchase, create_first_project, complete_onboarding).

## Existing automation to reuse

- Instagram Cloud Routine pattern (LIVE 2026-09-07): claim/draft/release endpoints under `/api/internal/...` with bearer token injected by the cloud environment's API credential; routine authors, independent editor subagent, OPS validates deterministically (422 codes the routine can fix), holds drafts, `prepare`→`publish` policy mode, stall alarm, notifications.
- Agent queue `/agent/queue` (LIVE 2026-09-02): the single human approval gate for automation proposals (`agent_actions`, permission `agent.review`).
- Notification rail contract (standard/persistent, actionUrl/actionLabel).
- Google Ads client: REST v23, service-account auth, manager 5448339076 → client 4454506598 with login-customer-id; Basic access dev token (approved 2026-08-05).

## Persona → OPS-addressable pain clusters (30 personas, CA + US, ages 25–49, solo → 12 staff)

Trades: cleaning ×6 (res/commercial/window), HVAC ×2, plumbing ×2, electrical ×2, landscaping/lawn ×3, painting ×2, handyman ×2, pressure washing, concrete, snow removal, fencing, pool, roofing, auto detailing, appliance repair, tree service, pest control, flooring.

OPS can honestly address:
1. Pricing confidence / job costing / quotes (Marcus, Tyler, Cody, Amanda, Jorge, Derrick, Ashley, DJ, Dustin).
2. Payment protection: contracts, deposits, invoicing, collections, chargeback defence (Marcus, Cody, Chuy, Kim, Carlos, DJ, Brittany cancellations).
3. Scheduling + crew coordination + customer communication; "where am I going today" (Marcus, Daniela route, Brandon route, Jorge heat scheduling, Trevor).
4. Documentation: photos, scope, change orders, dispute evidence (Jorge, Ashley, Kim, Derrick, Brandon).
5. Cash-flow visibility (Keith, Amanda, Victor, DJ, Dustin).
6. Owner-independence / time off (Marcus, Janelle, Keith) — the emotional payload; "gives them back control".

OPS cannot: health insurance, hiring pipelines, immigration, succession, equipment financing. Ads never promise these.

## SEO / intent research already in repo (2026-06-07)

- Electrical = clearest organic wedge; tree service, chimney, snow removal, painting, water treatment show impressions.
- Highest intent: `[competitor] alternative`, `[competitor] pricing`, `switch from [competitor]`, `[trade] scheduling software`, `offline field service app`, `field service app no contract`.
- Keyword framework: Tier 1 buyer intent (alternatives/pricing/vs), Tier 2 problem-aware, Tier 3 vertical long-tail (blue ocean: pool, fencing, concrete, glass, painting, flooring).
