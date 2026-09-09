# Google Ads Engine — Phase 2: Account Rebuild — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use `custom-skills:executing-plans` to implement this plan task-by-task. Read the design spec first: `ops-software-bible/specs/2026-09-08-google-ads-engine-design.md` (§2, §4, §5.5 are this phase). Prerequisite: Phase 1 landed on `feat/ads-engine-p1` with a green readiness probe (Task 1 of the P1 plan). Spawn title: `GOOGLE ADS ENGINE - P2-1`.

**Goal:** Rebuild the Google Ads account from a versioned blueprint: three Canada-only Search campaigns on capped Maximize Clicks, shared negative lists seeded from the historical junk, two voice-checked responsive search ads per ad group, five dedicated landing pages on try.opsapp.co whose single CTA is the web signup, and the legacy campaigns labelled and left paused. Everything is created PAUSED and validated; campaigns are enabled only by a separate, explicit route call after Jackson approves the ads.

**Architecture:** `ops-web/config/ads/blueprint.json` is the source of truth for structure. A pure planner diffs the blueprint against the entity snapshot (`ads_entities`, P1 Task 8) and emits mutate operations in dependency order (budgets → campaigns → campaign criteria → ad groups → keywords → ads → shared sets → labels). A CRON_SECRET-protected setup route applies the plan with `validateOnly` first. Copy rules live in one module (`src/lib/ads/copy-rules.ts`) that Phase 3's engine reuses unchanged. Landing pages reuse try-ops's section registry with page-specific configs.

**Tech Stack:** as Phase 1. Google Keyword Planner data arrives as a CSV export committed under `ops-web/config/ads/` (the API's `KeywordPlanIdeaService` needs the "Researching keywords" permissible use; do not block on it).

**Design System:** try-ops uses its own kit (`try-ops/tailwind.config.ts`, `# OPS LANDING PAGE - IMPLEMENTATION.txt`, `.claude/animation-studio.local.md`) — every colour/spacing/radius must come from that config's tokens; the ops-web console is untouched in this phase.

**Required Skills:** `custom-skills:executing-plans`, `ops-copywriter:ops-copywriter` (every ad asset, every landing-page string), `ops-design`, `frontend-design:frontend-design` (landing pages), `custom-skills:ui-ux-pro-max`, `animation-studio:animation-architect` (only if any motion is added; the existing `HeroAnimation` is reused as is), `custom-skills:audit-design-system`, `superpowers:test-driven-development`, `superpowers:verification-before-completion`.

**Repos and worktrees:** ops-web: continue on `/Users/jacksonsweet/Projects/OPS/ops-web-ads-engine-p1` branch `feat/ads-engine-p1` (P2 commits land on the same branch so P3 can build on both); try-ops: branch `feat/paid-landing-pages` off `feat/first-touch-capture`.

**Hard rules:** no campaign is ever created `ENABLED`; `validateOnly` before every real mutate; broad match is rejected by the planner; every number in ad copy must be in the brand-facts allowlist; competitor names only in the competitor campaign in `<Brand> alternative` / `Switching from <Brand>?` form; no push; no `Co-Authored-By`.

**Facts (verified 2026-09-08):** customer `4454506598` CAD, timezone `America/Vancouver`; a `BRANDS` shared set "Competitors" (id `11814032032`, 4 members) exists — leave it; 22 legacy campaigns, all PAUSED (one REMOVED), no labels, no negative keyword shared sets; ops-site `/plans` prices are $0 trial / $90 / $140 / $190 per month, "No credit card. No contract.", every feature at every tier; try-ops section registry (`lib/ab/registry.ts`) has `Hero, PainSection, SolutionSection, TestimonialsSection, RoadmapSection, PricingSection, FAQSection, ClosingCTA, DesktopDownload, InlineSignupForm, Starburst, FounderQuote`; `LandingPageClient` hard-codes the App Store URL for the primary CTA and routes the secondary CTA to the tutorial; `PricingSection` keeps tier data hard-coded.

---

## Task 1: Copy rules module (shared with Phase 3)

**Files:**
- Create: `ops-web/src/lib/ads/copy-rules.ts`
- Create: `ops-web/config/ads/brand-facts.json`
- Create: `ops-web/tests/unit/ads/copy-rules.test.ts`

**Brand facts allowlist** (`brand-facts.json`): numbers `["$90", "$140", "$190", "90", "140", "190", "1", "10", "30"]` with their permitted contexts; phrases `["every feature, every tier", "no credit card", "free to start", "built by trades, for trades", "crews of one to ten", "works offline"]`; competitor names `["Jobber", "Housecall Pro", "ServiceTitan"]` with allowed forms `["{brand} alternative", "Switching from {brand}?", "Tired of {brand}?"]`; banned words copied verbatim from the OPS copywriter brief (`leverage, synergy, paradigm, ecosystem, revolutionary, disruptive, cutting-edge, state-of-the-art, best-in-class, world-class, enterprise-grade, seamless, frictionless, holistic, empower, solution, platform, stakeholders, facilitate, optimize, maximize, robust`), plus `contractor`/`contractors`, and `AI` as a leading token.

**API:**

```ts
export interface RsaCandidate { headlines: Array<{ text: string; pinnedField?: "HEADLINE_1" | "HEADLINE_2" | "HEADLINE_3" }>; descriptions: Array<{ text: string; pinnedField?: "DESCRIPTION_1" | "DESCRIPTION_2" }>; path1?: string; path2?: string; finalUrl: string }
export interface CopyContext { campaignKind: "brand" | "core" | "competitor"; allowedFinalUrls: string[] }
export type CopyIssue = { code: CopyIssueCode; field: string; message: string }
export type CopyIssueCode = "HEADLINE_TOO_LONG" | "DESCRIPTION_TOO_LONG" | "TOO_FEW_HEADLINES" | "TOO_MANY_HEADLINES" | "TOO_FEW_DESCRIPTIONS" | "TOO_MANY_DESCRIPTIONS" | "DUPLICATE_ASSET" | "EXCLAMATION" | "EMOJI" | "REPEATED_PUNCTUATION" | "ALL_CAPS" | "BANNED_WORD" | "CONTRACTOR" | "LEADS_WITH_AI" | "UNSUPPORTED_NUMBER" | "TRADEMARK_FORM" | "TRADEMARK_CAMPAIGN" | "URL_NOT_ALLOWED" | "PATH_TOO_LONG" | "PIN_PLAN"
export function validateRsa(candidate: RsaCandidate, ctx: CopyContext): CopyIssue[]
```

Rules (spec §5.5): headline ≤ 30 chars, description ≤ 90; 8–12 headlines, 3–4 descriptions; case-insensitive duplicate or near-duplicate (Levenshtein ≤ 2 after lowercasing) → `DUPLICATE_ASSET`; `!` anywhere → `EXCLAMATION`; any emoji/pictograph → `EMOJI`; `!!`, `??`, `...` → `REPEATED_PUNCTUATION`; any all-caps word longer than 3 letters other than `OPS` → `ALL_CAPS`; banned words as whole words; `contractor(s)` → `CONTRACTOR`; a headline or description whose first token is `AI` → `LEADS_WITH_AI`; any digit sequence not in the allowlist → `UNSUPPORTED_NUMBER`; competitor name outside the allowed forms → `TRADEMARK_FORM`, or in a non-competitor campaign → `TRADEMARK_CAMPAIGN`; `finalUrl` not in `allowedFinalUrls` → `URL_NOT_ALLOWED`; path fields > 15 chars → `PATH_TOO_LONG`; pin plan must be exactly 2–3 headlines pinned to `HEADLINE_1` and nothing else pinned → `PIN_PLAN`.

**Steps:** write one failing test per code (a good candidate returns `[]`; each rule has a minimal failing fixture) → implement → green → commit `feat(ads): deterministic copy rules for responsive search ads`.

---

## Task 2: Blueprint schema + planner

**Files:**
- Create: `ops-web/config/ads/blueprint.json`
- Create: `ops-web/src/lib/ads/blueprint.ts` (zod schema + loader)
- Create: `ops-web/src/lib/ads/blueprint-planner.ts`
- Create: `ops-web/tests/unit/ads/blueprint-planner.test.ts`

**Blueprint shape (zod, `.strict()`):**

```json
{
  "version": "2026-09-09-v1",
  "customerId": "4454506598",
  "currency": "CAD",
  "sharedNegativeLists": [{ "name": "NEG · Job seekers", "keywords": [{ "text": "jobs", "matchType": "BROAD" }, ...] }, ...],
  "labels": ["engine", "legacy", "role-control", "role-challenger"],
  "campaigns": [
    {
      "name": "BRAND · CA", "kind": "brand", "status": "PAUSED",
      "budget": { "name": "BRAND · CA budget", "amountMicros": "3000000", "deliveryMethod": "STANDARD" },
      "bidding": { "type": "MANUAL_CPC", "cpcBidCeilingMicros": "2000000" },
      "network": { "targetGoogleSearch": true, "targetSearchNetwork": false, "targetContentNetwork": false },
      "geo": { "locations": ["geoTargetConstants/2124"], "positiveGeoTargetType": "PRESENCE" },
      "languages": ["languageConstants/1000"],
      "negativeLists": ["NEG · Job seekers", "NEG · Homeowner intent", "NEG · Training", "NEG · Generic waste", "NEG · Wrong segment"],
      "adGroups": [{ "name": "Brand", "finalUrl": "https://try.opsapp.co/", "keywords": [{ "text": "opsapp", "matchType": "EXACT" }, ...], "ads": [] }]
    },
    { "name": "CORE · CA", "kind": "core", "budget": { "amountMicros": "32000000" }, "bidding": { "type": "MAXIMIZE_CLICKS", "cpcBidCeilingMicros": "8000000" }, "adGroups": [ {"name": "Job management", "finalUrl": "https://try.opsapp.co/job-management", ...}, {"name": "Crew scheduling", "finalUrl": "https://try.opsapp.co/scheduling", ...}, {"name": "Quotes & invoices", "finalUrl": "https://try.opsapp.co/quotes-invoices", ...} ] },
    { "name": "COMPETITOR · CA", "kind": "competitor", "budget": { "amountMicros": "15000000" }, "bidding": { "type": "MAXIMIZE_CLICKS", "cpcBidCeilingMicros": "10000000" }, "adGroups": [ {"name": "Jobber alternative", "finalUrl": "https://try.opsapp.co/compare/jobber", ...}, {"name": "Housecall Pro alternative", "finalUrl": "https://try.opsapp.co/compare/housecall-pro", ...} ] }
  ]
}
```

Negative lists are the spec §4.3 lists; `free` is excluded from `NEG · Generic waste` on the competitor campaign by a per-campaign `negativeListExclusions` field; `servicetitan` sits in `NEG · Wrong segment` and is applied to BRAND and CORE only. `ads[]` entries are `RsaCandidate` objects (Task 3 fills them). Per-campaign `campaignNegatives` allow campaign-level negative keywords.

**Planner:** `planBlueprint(blueprint, snapshot: AdsEntitySnapshot): PlannedOperation[]` where each `PlannedOperation = { stage: 1..8, op: MutateOperation, temporaryId?: string, describe: string }`. Uses negative temporary resource names (`customers/4454506598/campaignBudgets/-1`) so one `googleAds:mutate` call creates the whole tree; diffs by name against `snapshot` so re-running is idempotent (existing objects produce `update` ops only when a tracked field differs; nothing is ever removed). Rejects any keyword with `matchType: "BROAD"` in `keywords[]` (negatives may be broad). Emits `label` assignments (`campaignLabelOperation`) for `engine` on every new campaign and `legacy` on every campaign in the snapshot not in the blueprint. Emits `campaignSharedSetOperation` links for negative lists.

**Tests:** empty snapshot → full create tree in stage order with temporary ids wired parent→child; snapshot equal to the blueprint → `[]`; a changed budget → one `update` with `updateMask: "amountMicros"`; broad positive keyword → throws `BROAD_MATCH_REJECTED`; legacy campaigns get the `legacy` label exactly once.

**Commit** `feat(ads): account blueprint schema and idempotent planner`.

---

## Task 3: Keyword Planner pull + seed keywords + first ad pairs

**Files:**
- Create: `ops-web/config/ads/keyword-planner-ca-2026-09.csv` (Jackson exports from Google Ads → Tools → Keyword Planner → Canada → "Get search volume and forecasts" for the candidate list below; if the developer token later gains the research permissible use, replace with a `KeywordPlanIdeaService` pull — not now)
- Modify: `ops-web/config/ads/blueprint.json` (keywords per ad group, pruned to terms with non-zero volume)
- Create: `ops-web/docs/ads/keyword-candidates-2026-09.md` (the candidate list with the source of each: historical search terms, SEO research 2026-06-07, competitor-alternative lane)
- Modify: `ops-web/config/ads/blueprint.json` `ads[]` — two RSAs per ad group

**Candidate seeds** (phrase + exact unless noted): Job management → `job management software for trades`, `job management app`, `job tracking app for trades`, `work order app for small business`, `job management app for small crews`; Crew scheduling → `crew scheduling app`, `scheduling software for trades`, `dispatch app for small crews`, `crew scheduling software small business`; Quotes & invoices → `invoicing app for trades`, `quoting software for trades`, `estimate app for small business`, `quote and invoice app`; Jobber alternative → `jobber alternative`, `jobber alternatives`, `jobber competitors`, `jobber pricing`, `switch from jobber`; Housecall Pro alternative → `housecall pro alternative`, `housecall pro alternatives`, `housecall pro pricing`, `housecall pro competitors`; Brand (exact only) → `opsapp`, `ops app`, `opsapp.co`, `ops job management`. Deliberately excluded: `field service management software`, anything `servicetitan`, anything with `contractor` as the buyer word.

**Ads:** invoke `ops-copywriter:ops-copywriter` and write, per ad group, a control and a challenger RSA: 8–12 headlines with 2–3 keyword-matched headlines pinned to `HEADLINE_1`, 3–4 descriptions, path fields (`trades/jobs`, `crews/schedule`, `quotes/invoices`, `jobber/alternative`, `housecall/alternative`), final URL = the ad group's landing page. Run every candidate through `validateRsa` in a test (`tests/unit/ads/blueprint-copy.test.ts` loads the blueprint and asserts zero issues for every ad). Voice: product register, terse, sentence case except `OPS`; price and "no credit card" from the allowlist; the challenger differs in angle (e.g. control = crew-first, challenger = price-first), not in wording alone.

**Commit** `feat(ads): seed keywords from Keyword Planner and the first ad pairs`.

---

## Task 4: Blueprint apply route + enable route

**Files:**
- Create: `ops-web/src/app/api/internal/ads/setup/blueprint/route.ts` (`POST ?validateOnly=1|0`; CRON_SECRET; loads the blueprint, refreshes the entity snapshot first (P1 `syncEntitySnapshot`), plans, applies in stage order in one `mutateGoogleAds` call with `partialFailure: false` so a rejected ad fails the whole tree, records `{ blueprintVersion, operations, failures, requestId }` to `ads_sync_status` row `id='blueprint-apply'` and returns it)
- Create: `ops-web/src/app/api/internal/ads/setup/enable/route.ts` (`POST` body `{ campaigns: ["CORE · CA", ...], confirm: "ENABLE" }`; CRON_SECRET; refuses unless every named campaign carries the `engine` label and has ≥ 2 ENABLED ads with `approval_status = APPROVED`; sets `status: ENABLED` with `validateOnly` first; records the result; this is the only path that ever enables a campaign)
- Tests: `tests/unit/ads/setup-routes.test.ts` (handlers built with an injected client, as the social handoff tests do): 401 without bearer, 405 on GET, validateOnly passthrough, enable refuses without approved ads, enable refuses a campaign without the `engine` label

**Run (after tests green):** dev server on port 3210 → `validateOnly=1` → save `docs/artifacts/ads-engine/p2/blueprint-validate.json` → fix any `POLICY_FINDING` by rewriting the offending asset (through the copy rules) → real apply → save `blueprint-apply.json` → re-run validate → expect zero operations. Then wait for policy review: query `ad_group_ad.policy_summary.approval_status` daily via the P1 sync; record the approval date.

**Commit** `feat(ads): apply the account blueprint and gate campaign enablement`.

---

## Task 5: Landing pages on try-ops

**Skills:** `frontend-design:frontend-design`, `ops-design`, `ops-copywriter:ops-copywriter`, `custom-skills:ui-ux-pro-max`, `custom-skills:audit-design-system`.

**Files (try-ops):**
- Create: `lib/landing/page-configs.ts` — five `VariantConfig`-shaped configs keyed by route, each a strict subset of the registry sections in this order: `Hero` (headline matched to the ad group; `heroMode: 'phone3d'` reused), `PricingSection` (moved up: prices above the fold on desktop, second screen on mobile), `FounderQuote`, `SolutionSection` (three features relevant to the group), `TestimonialsSection` only if a real named customer quote is supplied by Jackson (otherwise omitted — never invented), `FAQSection` (3 questions), `ClosingCTA`
- Create: `app/(paid)/job-management/page.tsx`, `app/(paid)/scheduling/page.tsx`, `app/(paid)/quotes-invoices/page.tsx`, `app/(paid)/compare/jobber/page.tsx`, `app/(paid)/compare/housecall-pro/page.tsx` — server components rendering `<LandingPageClient config={...} variantId="paid:<slug>" ctaMode="web-signup" />`
- Modify: `components/ab/LandingPageClient.tsx` — add `ctaMode?: "app-store" | "web-signup"`; in `web-signup` mode the primary CTA and `StickyCTA` link to `https://app.opsapp.co/register` (full navigation; the `.opsapp.co` cookie travels), the secondary CTA is removed (single CTA rule), the roadmap fetch is skipped, and `trackABClick` still fires with `variantId`
- Create: `components/landing/CompareTable.tsx` — the honest per-crew arithmetic for the two compare pages (Jobber Connect $99/month is one user, +$29 per user, five users = $215/month before add-ons; Housecall Pro from its published tiers with the same per-crew framing; OPS $140/month for the crew, every feature) as a static table; every figure sourced in a comment with the URL and the date checked; registry entry `CompareTable`
- Modify: `middleware.ts` matcher (P1 already covers the paths; verify)
- Tests: `tests/page-configs.test.ts` (every config validates against `VariantConfigSchema`; every string passes a local port of the copy rules: no `!`, no banned words, no `contractor`, no leading `AI`; every page has exactly one CTA section besides the sticky bar), `tests/landing-page-client.test.tsx` (web-signup mode renders the register URL and no App Store link)

**Copy** via `ops-copywriter`: hero headlines in uppercase Mohave, 5–10 words (`JOB MANAGEMENT YOUR CREW WILL ACTUALLY USE` is the proven baseline for the job-management page; scheduling and quotes pages get their own), subtext with the real price and "no credit card" as a promise, FAQ in the Anti-Pitch frame.

**Verification:** `npm run build` clean; Lighthouse or `curl -w %{time_total}` on the built pages under 2 s locally; screenshots of all five at 390×844 and 1440×900 to `try-ops/docs/artifacts/paid-landing/`; audit-design-system on the touched components (tokens only).

**Commit** `feat(landing): dedicated paid-search pages with web signup as the single CTA`.

---

## Task 6: Legacy labelling, bible, runbook, hand-off

- The planner already labels legacy campaigns; confirm in the entity snapshot that all 21 paused legacy campaigns carry `legacy` and none carry `engine`.
- Bible: `04_API_AND_INTEGRATION.md` (setup routes, blueprint contract, enable gate), `research/google-ads/` gets `2026-09-09-keyword-candidates.md` (copy of the ops-web doc), `specs/2026-09-08-google-ads-engine-design.md` §4 status line "BUILT <date>, campaigns PAUSED pending Jackson's ad approval".
- Runbook: how to change the blueprint (edit → validate → apply), how to enable, how to pause everything (`enable` route accepts `confirm: "PAUSE"`), the policy-review wait.
- Evidence: validate/apply JSON, the entity snapshot showing PAUSED campaigns with APPROVED ads, landing-page screenshots, test output.
- Hand-off to Jackson (plain language): the account is rebuilt and paused; here are the ten ads to approve (rendered as text previews in the message); on his GO the enable route turns on the three campaigns at $50/day; the day-90 gates from the research §8.10.

**Do not:** enable anything without Jackson's explicit GO in chat; push; touch the legacy campaigns beyond the label.
