# Google Ads API — Engineering Research for an Automated Ad-Iteration Engine

**Research date:** 2026-09-08
**Current API version:** **v25** (major, released 2026-07-22) / **v25.1** (minor, released 2026-08-19).
Prior majors: v24 (2026-04-22), v23, v22 (**sunsets 2026-10-07 — do not build on it**).
Source: [Release notes](https://developers.google.com/google-ads/api/docs/release-notes), [v22 sunset reminder](https://ads-developers.googleblog.com/2026/09/google-ads-api-v22-sunset-reminder.html)

> **Version policy:** Google ships a major roughly quarterly and sunsets each about 12–13 months after release. Pin `v25` in URLs/protos and budget one upgrade every ~9 months. Every field/enum below was verified against the **v25** reference.

**Target context for this report:** single small account (<$3k/month ad spend), today read-only via `GoogleAdsService.Search` GAQL, goal = LLM-driven loop that generates ads, pushes them, measures, A/B tests, iterates on a schedule.

---

## 1. ACCESS LEVELS, QUOTA, AND AUTH

### 1.1 The four developer-token access levels (v25, current)

There are **four** levels, not three. Source: [Access levels and permissible use](https://developers.google.com/google-ads/api/docs/access-levels) (page last updated 2026-08-19).

| Access level | Can access | Daily operation limit | Review time |
|---|---|---|---|
| **Test Account** | Test accounts only | 15,000 ops/day | automatic on signup |
| **Explorer** | Test **and production** | **2,880 ops/day** production; 15,000 ops/day test | automatic (sometimes) |
| **Basic** | Test and production | **15,000 ops/day** (both) | **5 business days** |
| **Standard** | Test and production | **Unlimited** for most services | **10 business days** |

Footnote, quoted verbatim: *"'Per day' is based on a sliding 24 hour time period in which API requests were made with your developer token."* It is a **rolling 24h window**, not a midnight-reset calendar day. Exceeding it returns `RESOURCE_EXHAUSTED`.

**The 15,000 ops/day Basic figure is confirmed.** Note the newer **Explorer** tier that sits below Basic at 2,880 ops/day — a token issued today may land there automatically.

### 1.2 What each level can actually do — mutates are NOT gated by level

**Critical correction to a common misconception: mutate access is not what separates Basic from Standard.** All of Explorer / Basic / Standard can mutate production accounts. The differences are (a) the daily operation ceiling and (b) which *services* are reachable.

**Explorer explicitly blocks these services** ([access-levels](https://developers.google.com/google-ads/api/docs/access-levels)):

| Restricted functionality | Blocked services |
|---|---|
| Account creation | `CustomerService.CreateCustomerClient` |
| User management | `CustomerUserAccessInvitationService`, `CustomerUserAccessService` |
| **Planning** | `KeywordPlanService`, **`KeywordPlanIdeaService`**, `KeywordPlanCampaignService`, `KeywordPlanCampaignKeywordService`, `KeywordPlanAdGroupService`, `KeywordPlanAdGroupKeywordService`, `AudienceInsightsService`, `ReachPlanService` |
| Billing/payments | `PaymentsAccountService`, `BillingSetupService`, `AccountBudgetProposalService`, `InvoiceService` |

So: **Explorer can create/pause ads, add keywords and negatives, change budgets and bids, run experiments, and upload conversions. It cannot do keyword research.**

### 1.3 Permissible use (Basic + Standard only)

Orthogonal to access level; set at application time. Quoted from the docs:

| Permissible use | Grants |
|---|---|
| **Ad creation / management** | *"access to all services of the API for creating and managing Google Ads campaigns, ad groups, ads, and keywords."* |
| **Reporting** | *"Only make `GoogleAdsService.Search` or `GoogleAdsService.SearchStream` requests, or read-only calls."* |
| **Researching keywords and recommendations** | *"Allow the developer token to access `RecommendationService`, `KeywordPlanIdeaService`, and `KeywordPlanService`."* |

**Action item:** an iterate-loop needs **Ad creation / management**. If it also does keyword discovery it needs **Researching keywords and recommendations** as well. These are checkboxes on the same application — request both in one pass or you will re-apply.

### 1.4 Is 15,000 ops/day enough? Yes — by two orders of magnitude.

Operation accounting ([API quotas](https://developers.google.com/google-ads/api/docs/best-practices/quotas)):

- A `Search` **or** `SearchStream` request = **1 operation**, *"irrespective of the number of batches"* — a streamed 50,000-row report is still **1 op**.
- Paginated follow-ups with a **valid** `next_page_token` are **not counted**. An expired/invalid token **is** counted (and errors).
- Each **mutate operation** (not request) counts. A single `MutateAdGroupAds` request with 20 operations = 20 ops.
- Requests that fail with a `GoogleAdsFailure` **still count**. Network-level failures do not.
- `ConversionUploadService.UploadClickConversions`, `UploadCallConversions`, `OfflineUserDataJobService.*`, `UserDataService.UploadUserData`, `BatchJobService.ListMutateJobResults` each count as **1 operation per request** (not per conversion).

**Realistic daily budget for this loop:**

| Activity | Ops/day |
|---|---|
| 10–20 GAQL reports (campaign, ad_group, ad_group_ad, asset view, search terms, geo, landing page) | 10–20 |
| Conversion upload (1 batched request, up to 2,000 conversions) | 1 |
| Mutates: create 2 RSAs, pause 2, add 20 negatives, adjust 2 budgets | ~30 |
| `validate_only` dry runs of the above | ~30 |
| **Total** | **~80/day** |

**~80 of 15,000 = 0.5% of Basic, ~3% of Explorer.** Even Explorer's 2,880/day is comfortable. Quota is a non-issue at this scale; **do not let it drive design**. The binding constraints are the Planning-service 1 QPS limit and Google's *learning-period* guidance (§9), not the daily cap.

Other hard limits worth encoding:

| Limit | Value | Error |
|---|---|---|
| Mutate operations per request | 10,000 | `TOO_MANY_MUTATE_OPERATIONS` |
| Action operations per request | 100 | `TOO_MANY_ACTION_OPERATIONS` |
| gRPC response size | 64 MB | `429 Resource Exhausted` |
| Conversions per upload request | 2,000 | `TOO_MANY_CONVERSIONS_IN_REQUEST` |
| Conversion adjustments per request | 2,000 | `TOO_MANY_ADJUSTMENTS_IN_REQUEST` |
| `KeywordPlanIdeaService.GenerateKeywordIdeas` / `GenerateKeywordHistoricalMetrics` / `GenerateKeywordForecastMetrics` | **1 QPS per CID** (*"60 requests per 60 seconds"*) | `RESOURCE_EXHAUSTED` |
| `KeywordPlanIdeaService.GenerateAdGroupTheme` | 2 QPS per CID | `RESOURCE_EXHAUSTED` |
| Billing / AccountBudget mutates | **1 operation per request** | `TOO_MANY_MUTATE_OPERATIONS` |

> **`validate_only` and quota:** the quotas page does **not** list validate-only requests as exempt, and they are dispatched as ordinary mutate requests. **Assume every dry run costs its full operation count.** Harmless here (§1.4 math), but do not build a validation loop that fans out thousands of probes.

**Two different exhaustion errors — do not conflate them** ([Rate limits](https://developers.google.com/google-ads/api/docs/best-practices/rate-limits)):

| Error | Cause | Retry? |
|---|---|---|
| `RESOURCE_EXHAUSTED` | **daily operation quota** blown | **No** — wait for the rolling 24h window |
| `RESOURCE_TEMPORARILY_EXHAUSTED` | **QPS rate limit** | **Yes** — exponential backoff |

Rate limiting is *"bucketed by queries per second (QPS) per client customer ID (CID) and developer token"* using a **Token Bucket** algorithm, so *"the exact limit will vary depending on the overall server load at any given time."* There is no published QPS number to code against — implement client-side throttling and backoff. Google's recommended mitigations, in order: limit concurrent tasks, batch operations into single requests, client-side rate limiters, queueing. **A single-account cron loop will never approach this**; just retry `RESOURCE_TEMPORARILY_EXHAUSTED` with backoff and cap concurrency at 1–2.

### 1.5 Is a manager account (MCC) required?

**Yes, to obtain the developer token.** From [Obtain your developer token](https://developers.google.com/google-ads/api/docs/get-started/dev-token): you must *"select or create a Google Ads manager account"* — the token lives on a manager account and **cannot** be obtained from a test manager account or a plain customer account.

The MCC does **not** have to manage the ad account, but this is the clean setup: create an MCC, link the existing <$3k/month account to it, take the token from the MCC.

Developer-token application requirements:
- Company name + **functioning website URL** — *"If the website is not live, Google might not be able to process your application and reject it."*
- A **regularly monitored** API contact email (compliance may reach out; a dead address blocks the application).
- Solo developers: company name `Individual` plus a GitHub/LinkedIn URL. Generic placeholder domains are rejected.
- Token format: a **22-character alphanumeric string**.
- **Brand verification** of the associated Google Cloud project is *optional* but used as a signal to speed up Basic approval.

### 1.6 OAuth2 and request headers

Required headers ([Call structure](https://developers.google.com/google-ads/api/docs/concepts/call-structure)):

| Header | Value | When |
|---|---|---|
| `Authorization` | `Bearer <access_token>` | always |
| `developer-token` | 22-char token | always |
| `login-customer-id` | MCC customer ID, **digits only, no hyphens** | **required** when access is via a manager account |
| `linked-customer-id` | customer ID of the account with a product link | only for third-party partners acting on linked accounts |

Quoted: *"If your access to the customer account is through a manager account, this header is required and must be set to the customer ID of the manager account."* Omitting it in an MCC setup yields `AuthorizationError.USER_PERMISSION_DENIED` — the single most common first-integration failure.

- OAuth scope: `https://www.googleapis.com/auth/adwords`
- REST base: `https://googleads.googleapis.com/v25/customers/{customerId}/...`
- gRPC is the default for official client libraries; REST is fully supported.

See §7 for the refresh-token and consent-screen gotchas that actually bite in a serverless cron.

---

## 2. MUTATE CAPABILITIES FOR THE LOOP

### 2.1 Responsive Search Ads

**Structure** — `ResponsiveSearchAdInfo` ([v25 ref](https://developers.google.com/google-ads/api/reference/rpc/v25/ResponsiveSearchAdInfo)) has exactly four fields:

| Field | Type | Notes |
|---|---|---|
| `headlines[]` | `AdTextAsset` | **min 3, max 15** |
| `descriptions[]` | `AdTextAsset` | **min 2, max 4** |
| `path1` | `string` | display-URL path, 15 chars |
| `path2` | `string` | only settable if `path1` is set |

Minimums are documented in [Create responsive search ads](https://developers.google.com/google-ads/api/docs/responsive-search-ads/create-responsive-search-ads): *"Minimum 3 headlines, minimum 2 descriptions, minimum 1 final URL."* Maximums (15/4) and character limits (**headline 30**, **description 90**) come from [About responsive search ads](https://support.google.com/google-ads/answer/7684791).

**`AdTextAsset`** ([v25 ref](https://developers.google.com/google-ads/api/reference/rpc/v25/AdTextAsset)) — four fields, and two of them are gold for the loop:

| Field | Type | Notes |
|---|---|---|
| `text` | `string` | the copy |
| `pinned_field` | `ServedAssetFieldType` | pin to a slot |
| `asset_performance_label` | `AssetPerformanceLabel` | **per-asset rating, readable straight off the ad** |
| `policy_summary_info` | `AdAssetPolicySummary` | **per-asset policy status** |

> **High-value finding:** `asset_performance_label` and `policy_summary_info` hang off each `AdTextAsset` *inside* `ad_group_ad.ad.responsive_search_ad.headlines`. You can read every headline's performance label and policy state in the **same** `ad_group_ad` query you already run — no join to `ad_group_ad_asset_view` needed for the label itself. Use the asset view only when you want **metrics** per asset.

**Pinning** — `pinned_field` takes `ServedAssetFieldType` ([v25 ref](https://developers.google.com/google-ads/api/reference/rpc/v25/ServedAssetFieldTypeEnum.ServedAssetFieldType)). Relevant values: `HEADLINE_1`, `HEADLINE_2`, `HEADLINE_3`, `DESCRIPTION_1`, `DESCRIPTION_2` (plus `HEADLINE`/`DESCRIPTION` for single-slot ad types, and many PMax/display values).

Semantics, quoted: *"This restricts the asset to only serve within this field. Multiple assets can be pinned to the same field. An asset that is unpinned or pinned to a different field will not serve in a field where some other asset has been pinned."*

**Consequence for A/B design:** pinning one headline to `HEADLINE_1` **removes every unpinned headline from slot 1**. Pin nothing, or pin ≥2–3 assets to the same slot so they rotate against each other. A single pin per slot destroys the combinatorial testing you are trying to run and tanks Ad Strength. If you must guarantee a brand/legal line, pin **2+ variants** to that slot.

### 2.2 Are RSAs immutable? **No — and this is widely gotten wrong.**

Authoritative, quoted from [Ad types](https://developers.google.com/google-ads/api/docs/ads/ad-types):

> *"You can mutate your ads without losing their performance data by using `AdService`. Not all ad types are mutable... If an ad type is not mutable, it must be removed and recreated to affect changes. Performance data for the removed ad will continue to be available, but will no longer be updated."*

**RSAs are mutable.** Mutable types via `AdService`: `ResponsiveSearchAd`, `ExpandedTextAd`, `ResponsiveDisplayAd`, `ShowcaseAd`, `MultiAssetResponsiveDisplayAd`. The "ads are immutable, delete and recreate" advice is **legacy AdWords API guidance** and no longer applies to RSAs.

**Two distinct services — use the right one** ([Mutate ads](https://developers.google.com/google-ads/api/docs/ads/mutate-ads)):

| Service | Method | Use for |
|---|---|---|
| `AdService` | `MutateAds` | editing the **creative** — headlines, descriptions, final URLs, paths. Requires `update_mask`. |
| `AdGroupAdService` | `MutateAdGroupAds` | **create** an ad in an ad group; change **status** (ENABLED/PAUSED/REMOVED); labels |

To pause: *"set the status of the `AdGroupAd` to which it belongs to `PAUSED`"* via `AdGroupAdService` — you do **not** touch `AdService`.

`AdService.MutateAds` requires an `AdOperation` with `update` set to an `Ad` carrying `resource_name` (`customers/{cid}/ads/{adId}`) **and** an `update_mask` listing the fields you set. Omitting the mask is the classic silent no-op.

**The critical caveat for an iterate loop:** editing an RSA in place **keeps the same ad ID and keeps accumulating stats on it**. That is great for URL/typo fixes — and **fatal for A/B analysis**, because pre-edit and post-edit performance are blended into one row with no segmentation to separate them. There is no "stats reset" and no edit-version segment.

**Therefore:**
- **Edit in place** for: final URL changes, typo/compliance fixes, adding an asset to an under-filled ad. Cheap, preserves history, no re-review of untouched assets.
- **Create a new ad + pause the old one** for: any change you intend to *measure*. This is the only way to get a clean per-variant row. Tag the cohort with a label (§2.6) and diff by `ad_group_ad.ad.id`.

### 2.3 Ad policy: detecting disapproval via API

Read `ad_group_ad.policy_summary`:
- `ad_group_ad.policy_summary.approval_status` — `PolicyApprovalStatus`
- `ad_group_ad.policy_summary.review_status` — `PolicyReviewStatus`
- `ad_group_ad.policy_summary.policy_topic_entries` — the specific violations

**`PolicyApprovalStatus`** ([v25 ref](https://developers.google.com/google-ads/api/reference/rpc/v25/PolicyApprovalStatusEnum.PolicyApprovalStatus)). Docs note severity order is `DISAPPROVED` > `AREA_OF_INTEREST_ONLY` > `APPROVED_LIMITED` > `APPROVED`, and *"the most severe one will be used"*:

| Value | Meaning (quoted) |
|---|---|
| `APPROVED` | *"Serves without restrictions."* |
| `APPROVED_LIMITED` | *"Serves with restrictions."* |
| `AREA_OF_INTEREST_ONLY` | *"Will not serve in targeted countries, but may serve for users who are searching for information about the targeted countries."* |
| `DISAPPROVED` | *"Will not serve."* |
| `UNKNOWN` / `UNSPECIFIED` | response-only / unset |

**`PolicyReviewStatus`** ([v25 ref](https://developers.google.com/google-ads/api/reference/rpc/v25/PolicyReviewStatusEnum.PolicyReviewStatus)):

| Value | Meaning (quoted) |
|---|---|
| `REVIEW_IN_PROGRESS` | *"Currently under review."* |
| `REVIEWED` | *"Primary review complete. Other reviews may be continuing."* |
| `ELIGIBLE_MAY_SERVE` | *"The resource is eligible and may be serving but could still undergo further review."* |
| `UNDER_APPEAL` | *"The resource has been resubmitted for approval or its policy decision has been appealed."* |

**Loop logic:** treat `DISAPPROVED` as hard-fail → pause the ad, feed `policy_topic_entries[].topic` back to the LLM, regenerate. Treat `AREA_OF_INTEREST_ONLY` as effectively dead for a geo-targeted local advertiser. Treat `APPROVED_LIMITED` as *serving but handicapped* — log it, do not compare its metrics against unrestricted variants. Do **not** evaluate performance while `review_status = REVIEW_IN_PROGRESS`.

**Policy exemptions** ([Policy exemption overview](https://developers.google.com/google-ads/api/docs/policy-exemption/overview)) — two different mechanisms:

| Entity | Error surfaced | Resubmit with |
|---|---|---|
| **Ads** | `PolicyFindingError` → `policy_finding_details` | `PolicyValidationParameter.ignorable_policy_topics` |
| **Keywords/criteria** | `PolicyViolationError` → `policy_violation_details` | `PolicyValidationParameter.exempt_policy_violation_keys` |

Flow: submit → catch the policy error → extract topic keys → check they are exemptible → resubmit with the exemption parameter. **Only some topics are exemptible**; verify before blindly resubmitting or you will loop.

### 2.4 Keywords and negatives

**Positive keywords + ad-group negatives** — `AdGroupCriterionService.MutateAdGroupCriteria`.
`AdGroupCriterion` ([v25 ref](https://developers.google.com/google-ads/api/reference/rpc/v25/AdGroupCriterion)) key fields: `ad_group` (immutable), `keyword` (`KeywordInfo{text, match_type}`), `negative` (bool, immutable once set), `status` (`ENABLED`/`PAUSED`/`REMOVED`), `cpc_bid_micros`, `labels[]`, `final_urls[]`, `quality_info`, `primary_status`, `primary_status_reasons[]`, `approval_status`, `disapproval_reasons[]`.

Match types (`KeywordMatchType`): `EXACT`, `PHRASE`, `BROAD`.

**Campaign-level negatives** — `CampaignCriterionService.MutateCampaignCriteria` with `negative = true` and a `keyword`.

**Shared negative lists** (the right structure for an automated loop) — three services ([Shared sets](https://developers.google.com/google-ads/api/docs/targeting/shared-sets)):

1. `SharedSetService.MutateSharedSets` → create a `SharedSet` with `type = NEGATIVE_KEYWORDS`
2. `SharedCriterionService.MutateSharedCriteria` → add each negative as a `SharedCriterion`
3. `CampaignSharedSetService.MutateCampaignSharedSets` → attach the set to campaigns

**Recommendation:** maintain **one shared negative list** written by the bot. It gives a single reviewable surface, applies across campaigns, and avoids scattering thousands of ad-group negatives that no human can audit. Negatives are the safest mutate in the whole loop — they are reversible and cannot overspend.

**Feeding it:** query `search_term_view` ([v25 fields](https://developers.google.com/google-ads/api/fields/v25/search_term_view)) — fields `search_term`, `ad_group`, `status`, `resource_name`. `status` is `SearchTermTargetingStatus` (`ADDED`, `EXCLUDED`, `ADDED_EXCLUDED`, `NONE`) so you can skip terms already handled. Note the doc caveat: *"This view does not include Performance Max data"* — use `campaign_search_term_view` for PMax.

### 2.5 Budgets, bids, schedules, geo

**Budgets** — `CampaignBudgetService.MutateCampaignBudgets`. `CampaignBudget` ([v25 ref](https://developers.google.com/google-ads/api/reference/rpc/v25/CampaignBudget)) fields: `amount_micros` (**micros: $1.00 = 1,000,000**), `delivery_method` (`STANDARD`/`ACCELERATED`), `explicitly_shared` (bool), `period` (`DAILY`), `status`, `type`, `reference_count`, plus read-only `recommended_budget_amount_micros` and `recommended_budget_estimated_change_weekly_clicks` / `_cost_micros` / `_interactions` / `_views` — free forecast data for budget decisions, no extra call.

**Gotcha:** if `explicitly_shared = true` the budget is shared across campaigns; changing `amount_micros` moves money for **all** of them. Check `reference_count > 1` before touching a budget.

**Bidding strategy** — set on `Campaign` via `CampaignService.MutateCampaigns`: either a portfolio `bidding_strategy` resource name or a campaign-level strategy (`target_cpa`, `target_roas`, `maximize_conversions`, `maximize_conversion_value`, `manual_cpc`, `target_spend`). **Changing the strategy type resets Smart Bidding learning — see §9.**

**Ad schedules and geo** — both are `CampaignCriterion` (`CampaignCriterionService.MutateCampaignCriteria`):
- Ad schedule: `AdScheduleInfo{day_of_week, start_hour, start_minute, end_hour, end_minute}` + `bid_modifier`
- Geo: `LocationInfo{geo_target_constant}` + `bid_modifier`; negative geo via `negative = true`
- Proximity: `ProximityInfo`

Criteria are largely **immutable** — to change a schedule or geo you **remove and re-add**, you do not update in place. Only `bid_modifier` and `status` are updatable.

### 2.6 Labels — the cohort-tagging mechanism

`LabelService.MutateLabels` creates `Label{name, description, text_label{background_color, description}}`. Attach via:
- `AdGroupAdLabelService.MutateAdGroupAdLabels` (ads)
- `AdGroupCriterionLabelService` (keywords), `CampaignLabelService`, `AdGroupLabelService`

Label links are **create/remove only — not updatable**. To re-tag, remove the link and add a new one.

**This is the backbone of the iterate loop.** Since Google gives you no experiment metadata on individual ads, labels are how you tag cohorts: `bot-gen-2026-09-08`, `variant-A`, `hypothesis-urgency`. Then filter reports with `WHERE ad_group_ad.labels CONTAINS ANY ('customers/123/labels/456')`. Without labels you cannot reconstruct which ads belonged to which generation.

### 2.7 `validate_only` — dry-run mode

Every mutate request carries a `validate_only` boolean (REST: `validateOnly`). When true the request is fully processed and validated but **nothing is written** ([Validate ad sample](https://developers.google.com/google-ads/api/docs/samples/validate-ad)).

It still raises real errors — including `PolicyFindingError` with populated `policy_topic_entries`. **This is the single most valuable safety feature for LLM-generated copy:** you can validate character limits, editorial violations, and trademark findings *before* anything reaches the account.

**Mandatory pattern:** every LLM-generated ad goes through `validate_only: true` first. Only on a clean pass do you re-send with `validate_only: false`.

Caveats: not a policy *guarantee* — validate-only catches deterministic violations, but full review happens post-creation asynchronously (`review_status`), so you must still poll. And it costs quota (§1.4).

**`partial_failure`** ([Partial failures](https://developers.google.com/google-ads/api/docs/best-practices/partial-failures)) — set `partial_failure: true` so valid operations commit while failed ones return errors in `partial_failure_error`. Supported wherever the request message has a `partial_failure` field. **Do not use it for interdependent operations** that reference each other by temp ID (e.g. building a campaign). For batch negatives and independent ad creates it is exactly right — one bad keyword should not drop 19 good ones.

---

## 3. EXPERIMENTS

### 3.1 Services and lifecycle

`ExperimentService` methods ([v25 ref](https://developers.google.com/google-ads/api/reference/rpc/v25/ExperimentService)):
`MutateExperiments`, `ScheduleExperiment`, `PromoteExperiment`, `GraduateExperiment`, `EndExperiment`, `ListExperimentAsyncErrors`.

Plus `ExperimentArmService.MutateExperimentArms`.

**Four workflows** ([Experiments overview](https://developers.google.com/google-ads/api/docs/experiments/overview)):

| Workflow | ExperimentTypes | What it does |
|---|---|---|
| **System-managed** | `SEARCH_CUSTOM`, `DISPLAY_CUSTOM`, `HOTEL_CUSTOM`, `YOUTUBE_CUSTOM`, `PMAX_REPLACEMENT_SHOPPING` | separate treatment campaign vs control campaign |
| **Intra-campaign** | `ADOPT_AI_MAX`, `ADOPT_BROAD_MATCH_KEYWORDS`, `PMAX_TEXT_CUSTOMIZATION_FINAL_URL_EXPANSION` | splits traffic *within* one campaign |
| **Asset optimization** | `OPTIMIZE_ASSETS` | asset combinations in PMax |
| **Campaign Mix** | `COMPARE_CAMPAIGNS` | multi-variable across campaign types |

**`SEARCH_CUSTOM` is the one that matters here.**

**`ExperimentStatus`** ([v25 ref](https://developers.google.com/google-ads/api/reference/rpc/v25/ExperimentStatusEnum.ExperimentStatus)): `SETUP`, `INITIATED`, `ENABLED`, `GRADUATED`, `HALTED`, `PROMOTED`, `REMOVED`, `UNKNOWN`, `UNSPECIFIED`.

### 3.2 Building a SEARCH_CUSTOM experiment

Source: [System-managed experiments](https://developers.google.com/google-ads/api/docs/experiments/system-managed) (v25 samples).

**Step 1 — create the `Experiment`** ([v25 ref](https://developers.google.com/google-ads/api/reference/rpc/v25/Experiment)). No campaigns named yet.

| Field | Notes |
|---|---|
| `name` | required, unique per customer, 1–1024 chars |
| `type` | `SEARCH_CUSTOM` |
| `status` | set `SETUP` on create |
| `suffix` | appended to treatment campaign names, e.g. `[experiment]` |
| `description` | optional, 1–2048 chars |
| `start_date` / `end_date` | `YYYY-MM-DD`, customer's timezone. Defaults: starts now-or-campaign-start; ends on campaign end date |
| `sync_enabled` | **immutable, create-time only.** True = changes to the base campaign propagate to trial campaigns; direct trial edits are preserved |
| `goals[]` | `MetricGoal` |
| `experiment_id`, `promote_status`, `long_running_operation`, `lift_measurement_config` | output only |

**Step 2 — create `ExperimentArm`s.** *"All arms must be created in a single request."* Exactly **one control arm** and **one or more treatment arms**.

`ExperimentArm` ([v25 ref](https://developers.google.com/google-ads/api/reference/rpc/v25/ExperimentArm)): `name` (required, unique per experiment), `control` (bool), `experiment` (immutable), `campaigns[]` (*"The max length is one"*), `traffic_split` (**1–100; must total 100 across arms**), `in_design_campaigns[]` (output only), `asset_testing_info`, `asset_groups[]`.

- **Control arm:** `control = true`, `campaigns = [existing campaign resource name]`
- **Treatment arm:** `control = false`, `campaigns` **left empty** — the API auto-generates a draft campaign you then modify

Set `response_content_type = MUTABLE_RESOURCE` on the request to get the draft campaign IDs back immediately. Otherwise re-query with `experiment_arm.control = false`.

**Step 3 — modify the treatment draft campaign.** This is where you vary things. **Query gotcha, quoted:** *"Draft campaigns are only returned if you add the `include_drafts=true` parameter to your query."*

**Step 4 — `ScheduleExperiment`.** Asynchronous — materializes in-design campaigns into real ones. Poll `long_running_operation`; check `ListExperimentAsyncErrors`.

**Step 5 — complete:**

| Method | Effect | Sync? |
|---|---|---|
| `EndExperiment` | *"treatment campaigns stop serving, but are not removed"* | synchronous |
| `PromoteExperiment` | *"copies changes from the treatment arm to the control campaign and stops the treatment arm from serving"* | **asynchronous** |
| `GraduateExperiment` | *"converts the treatment campaign into a standard, independent campaign"*; control unmodified | synchronous |

`PMAX_REPLACEMENT_SHOPPING` **cannot be promoted**.

### 3.3 What can be varied

Because the treatment arm is a **full draft campaign copy**, you can vary essentially anything campaign-scoped: **ads/RSA copy, bids and bidding strategy, keywords and match types, landing pages (final URLs), budgets, geo targeting, ad schedules, audiences**. This is a campaign-level A/B — everything below the campaign is copied and independently editable.

### 3.4 Minimum durations and traffic split

Google publishes **no API-enforced minimum duration**. Guidance:

- Google's own doc note for `PMAX_REPLACEMENT_SHOPPING`: *"It is recommended to discard the first 7 days of statistics from your evaluation to give the campaign time to finish its ramp-up and learning phase."* Treat **7 days as a universal blackout window** at the start of any experiment.
- [Set up a custom experiment](https://support.google.com/google-ads/answer/6261395) and industry consensus: run **≥2–3 weeks**; low-traffic accounts need **4–6 weeks**.
- **50/50 split** reaches significance fastest and is Google's recommendation. (The doc's sample uses 40/60 purely to show non-equal splits are legal.)
- The Google Ads **UI** shows a confidence indicator; look for **95%**. See §4.5 — this is **not** exposed via the API.

> **Blunt assessment for a <$3k/month account:** at ~$100/day, a Search campaign might see a few hundred clicks and single-digit-to-low-double-digit conversions per month. Split 50/50 across two arms and each arm gets half of that. **A conversion-based campaign experiment will not reach 95% significance in any reasonable window.** Formal experiments are the wrong primary tool at this spend. Use them sparingly for big structural bets (new landing page, bidding strategy change) with a 4–6 week horizon and CTR (not conversions) as the readout, since CTR accumulates enough samples to move. Do the *routine* iteration with in-ad-group RSA rotation and per-asset labels (§3.6), which Google's own ML optimizes continuously without any significance math on your side.

### 3.5 Ad Variations — **NOT creatable via the API**

`AD_VARIATION` **is** a value in the `ExperimentType` enum ([v25 ref](https://developers.google.com/google-ads/api/reference/rpc/v25/ExperimentTypeEnum.ExperimentType)) — *"This is an ad variation experiment."*

**But it is absent from every one of the four supported workflows** in the [experiments overview](https://developers.google.com/google-ads/api/docs/experiments/overview) workflow table and absent from the API→UI mapping table. Google's developer support confirms: **creating and managing ad variations is not supported in the Google Ads API** — it is a UI-only feature. The enum value exists for **read-back** of variations created in the UI.

Detection: an ad created by the UI's ad-variations feature has `ad.system_managed_resource_source = AD_VARIATIONS`. Use this to **exclude** such ads from your bot's mutate set — never let the loop edit or pause a human's UI experiment.

**Conclusion:** you cannot automate Ad Variations. For automated ad-copy testing your options are (a) multiple RSAs in one ad group with labels, (b) `SEARCH_CUSTOM` campaign experiments, or (c) per-asset rotation inside one RSA. **(a) and (c) are the practical choices at this spend.**

### 3.6 Per-asset analysis — `ad_group_ad_asset_view`

Source: [v25 fields](https://developers.google.com/google-ads/api/fields/v25/ad_group_ad_asset_view). Supports **App Ads, Demand Gen, and Responsive Search Ads**; explicitly **not** Responsive Display Ads.

**Resource fields:** `ad_group_ad`, `asset`, `enabled`, `field_type`, `performance_label`, `pinned_field`, `policy_summary`, `resource_name`, `source`

**Attributed resources** (joinable in SELECT/WHERE without segmenting): `ad_group`, `ad_group_ad`, `asset`, `campaign`, `customer`

**Segments:** `date`, `day_of_week`, `week`, `month`, `quarter`, `year`, `device`, `ad_network_type`, `ad_sub_network_type`, `ad_format_type`, `slot`, **`conversion_action`**, **`conversion_action_name`**

**Metrics — the full performance set (33):** `impressions`, `clicks`, `ctr`, `cost_micros`, `average_cpc`, `average_cpm`, `average_cpe`, `average_cost`, `conversions`, `conversions_value`, `conversions_from_interactions_rate`, `conversions_value_per_cost`, `cost_per_conversion`, `value_per_conversion`, `all_conversions`, `all_conversions_value`, `all_conversions_from_interactions_rate`, `all_conversions_value_per_cost`, `cost_per_all_conversions`, `value_per_all_conversions`, `cross_device_conversions`, `view_through_conversions`, `interactions`, `interaction_rate`, `interaction_event_types`, `engagements`, `engagement_rate`, `biddable_app_install_conversions`, `biddable_app_post_install_conversions`, `video_trueview_views`, `video_trueview_view_rate`, `trueview_average_cpv`

**`AssetPerformanceLabel`** ([v25 ref](https://developers.google.com/google-ads/api/reference/rpc/v25/AssetPerformanceLabelEnum.AssetPerformanceLabel)) — quoted:

| Value | Meaning |
|---|---|
| `BEST` | *"Best performing assets."* |
| `GOOD` | *"Good performing assets."* |
| `LOW` | *"Worst performing assets."* |
| `LEARNING` | *"The asset has started getting impressions but the stats are not statistically significant enough to get an asset performance label."* |
| `PENDING` | *"This asset does not yet have any performance information. This may be because it is still under review."* |
| `NOT_APPLICABLE` | *"Performance label cannot be assigned to this asset."* |
| `UNKNOWN` / `UNSPECIFIED` | — |

**Note the caller's list was slightly off:** the enum is `BEST`/`GOOD`/`LOW`/`LEARNING`/`PENDING`/`NOT_APPLICABLE` — there is **no `UNRATED`**. `PENDING` and `NOT_APPLICABLE` fill that role.

**This is the engine of the practical loop.** Google computes the significance for you. The rule writes itself: replace `LOW` assets, keep `BEST`, leave `LEARNING`/`PENDING` alone until they resolve.

**Caveat:** asset metrics are *served-impression* attribution — a conversion is credited to every asset present in the winning combination, not causally isolated. Use them for **relative ranking within an ad**, never as an incrementality measurement.

### 3.7 `ad_group_ad_asset_combination_view` — nearly useless for optimization

Source: [v25 fields](https://developers.google.com/google-ads/api/fields/v25/ad_group_ad_asset_combination_view). *"Now we only support AdGroupAdAssetCombinationView for Responsive Search Ads, with more ad types planned for the future."*

- **Resource fields:** `enabled`, `resource_name`, `served_assets`
- **Attributed resources:** `ad_group`, `ad_group_ad`, `campaign`, `customer`
- **Segments:** `date`, `day_of_week`, `week`, `month`, `quarter`, `year`, `ad_network_type`, `ad_sub_network_type`, `slot`
- **Metrics: `impressions` — and nothing else.**

> **Hard finding:** the combination view exposes **only `impressions`**. No clicks, no CTR, no cost, no conversions. You can see *which headline/description combinations Google chose to serve and how often*, but you **cannot** tell which combination performed. It is a diagnostic of Google's rotation behavior, not an optimization input. **Do not build the loop on it.** Use `ad_group_ad_asset_view` (§3.6) for anything performance-related.

### 3.8 Ad Strength

`ad_group_ad.ad_strength`, enum `AdStrength` ([v25 ref](https://developers.google.com/google-ads/api/reference/rpc/v25/AdStrengthEnum.AdStrength)):

`PENDING` (*"currently pending"*), `POOR`, `AVERAGE`, `GOOD`, `EXCELLENT`, `NO_ADS` (*"No ads could be generated."*), `UNKNOWN`, `UNSPECIFIED`.

Also available: `ad_group_ad.action_items` — Google's specific textual suggestions for raising Ad Strength. **Feed these straight into the LLM prompt**; they are free, targeted, machine-readable creative direction.

**Judgment:** Ad Strength measures *asset diversity and quantity*, not business outcomes — it is not a performance metric and correlates with it only loosely. Use it as a **generation-time guardrail** (refuse to ship `POOR`; aim `GOOD`+) rather than an optimization target. Note the tension with §2.1: heavy pinning reliably drives Ad Strength down.

---

## 4. REPORTING FOR THE LOOP

### 4.1 Read methods

Both live on `GoogleAdsService` ([Streaming](https://developers.google.com/google-ads/api/docs/reporting/streaming)):

| | `SearchStream` | `Search` |
|---|---|---|
| Response | continuous stream of `GoogleAdsRow` | paged |
| Round trips | one | many |
| Quota | **1 op regardless of batches** | 1 op; valid-token pages free |
| Best for | **everything in this loop** | interactive paging |

**Use `SearchStream` for all reporting.** One request, one operation, no pagination bookkeeping.

### 4.2 GAQL resources for the iterate loop (all verified present in v25)

| Resource | Purpose | Key fields |
|---|---|---|
| `campaign` | spend, strategy, status | `bidding_strategy_type`, `campaign_budget`, `status`, `primary_status`, `optimization_score` |
| `campaign_budget` | budget + Google's own recommendations | `amount_micros`, `recommended_budget_amount_micros`, `recommended_budget_estimated_change_weekly_clicks`, `explicitly_shared`, `reference_count` |
| `ad_group` | grouping, bids | `status`, `cpc_bid_micros`, `primary_status` |
| **`ad_group_ad`** | **the core creative table** | `ad.id`, `ad_strength`, `action_items`, `policy_summary.*`, `status`, `labels`, `ad.responsive_search_ad.headlines[]{text,pinned_field,asset_performance_label,policy_summary_info}`, `ad.system_managed_resource_source` |
| **`ad_group_ad_asset_view`** | **per-asset performance** | `performance_label`, `field_type`, `pinned_field`, `policy_summary`, `enabled` + full metrics |
| `ad_group_ad_asset_combination_view` | which combos served | `served_assets`, `enabled` — **`impressions` only** |
| `keyword_view` | keyword performance | metrics; join `ad_group_criterion.*` for `quality_info`, bids, match type |
| **`search_term_view`** | **negative-keyword mining** | `search_term`, `status`, `ad_group` |
| `geographic_view` | geo performance | `country_criterion_id`, `location_type` |
| `landing_page_view` | landing-page performance | `unexpanded_final_url` |
| `conversion_action` | conversion config | `type`, `category`, `status`, `primary_for_goal`, `value_settings` |
| `campaign_criterion` | geo/schedule/negatives | `keyword`, `location`, `ad_schedule`, `negative`, `bid_modifier` |
| `experiment` / `experiment_arm` | experiment state | `status`, `traffic_split`, `control` |
| `recommendation` | Google's suggestions | `type`, per-type payloads |

### 4.3 Data freshness — the real numbers

Source: [About data freshness](https://support.google.com/google-ads/answer/2544985).

| Data | Freshness |
|---|---|
| Clicks, impressions, cost, and **last-click** conversions | **1-hour SLO** (refreshed hourly) |
| **Non-last-click** conversions | **~15 hours** (next-day, e.g. Sunday's data ready 3:00 PM Monday PST) |
| **Search terms**, geographic, automatic placements | **next day** (Sunday's data ready 6:00 AM Monday PST) |
| Search impression share / auction insights | **~3 days** (Sunday's data ready 4:00 PM Wednesday PST) |
| Search click share | 3-day delay |
| Reach/frequency | daily |
| GA-imported goals/transactions | 12h (last-click) / 24h (other models) |

Data retention: **~11 years**.

### 4.4 The "data may change for 3 days" question

**Verdict: the specific "3 days" figure is folklore, but the underlying instability is real and documented.** Google names three causes of retroactive change ([data freshness](https://support.google.com/google-ads/answer/2544985), quoted):

- **Invalid traffic:** *"Google systems detect and remove invalid traffic, such as bot activity or accidental clicks retroactively."*
- **Late-arriving conversions:** *"Some conversions may occur several days after the initial ad interaction, especially for advertisers with longer conversion windows."*
- **End-of-month adjustments:** billing corrections for overdelivery/credits.

The real bound on conversion backfill is **your conversion action's `click_through_lookback_window_days`** (up to 90), not a fixed 3 days. A 30-day window means today's number for a date can keep rising for 30 days.

**Engineering rules:**
1. **Never make an irreversible decision on data <3 days old.** Exclude the trailing 2–3 days from every optimization window.
2. **Re-fetch, don't append.** Treat every stored metric row as mutable; upsert on (date, entity), never `INSERT`-only.
3. Use `segments.conversion_or_adjustment_lag_bucket` to measure your account's *actual* lag distribution and set the exclusion window from evidence.
4. Ad Strength and asset performance labels are recomputed by Google on their own cadence — don't expect same-day movement after an edit.

### 4.5 Segments

Common: `segments.date`, `segments.week`, `segments.month`, `segments.quarter`, `segments.year`, `segments.day_of_week`, `segments.device` (`MOBILE`/`DESKTOP`/`TABLET`/`CONNECTED_TV`/`OTHER`), `segments.ad_network_type` (`SEARCH`/`SEARCH_PARTNERS`/`CONTENT`/`YOUTUBE`/`MIXED`), `segments.conversion_action`, `segments.conversion_action_name`, `segments.conversion_action_category`, `segments.slot`, `segments.conversion_or_adjustment_lag_bucket`.

**Warning:** selecting `segments.conversion_action*` restricts the row set to conversion metrics and **changes the meaning of `conversions`** (it becomes per-action, and non-conversion metrics like `impressions` are unavailable or misleading). Run conversion-segmented queries **separately** from headline performance queries and join in your own store. Segmenting also multiplies rows — a common source of double-counted spend in naive pipelines.

### 4.6 Significance testing helpers — **confirmed: none**

**There is no statistical-significance field anywhere in the Google Ads API.** No confidence interval, no p-value, no lift measurement on `campaign`, `ad_group_ad`, `experiment`, or `experiment_arm`. The `Experiment` resource has a `lift_measurement_config` field but it is **output only** and unrelated to ordinary A/B significance. The **95% confidence indicator shown in the Google Ads UI experiments dashboard is not exposed via the API.**

The only significance-like signal Google gives you is `AssetPerformanceLabel`, where `LEARNING` explicitly means *"the stats are not statistically significant enough to get an asset performance label"* (§3.6). That is Google doing the math internally and handing you a verdict, not a number.

**Implication:** you must implement significance yourself — a two-proportion z-test on CTR, or Bayesian beta-binomial on conversion rate — or lean on `AssetPerformanceLabel`. At <$3k/month, **lean on the labels**; your own tests will almost never clear a real threshold on conversions, and acting on noise is worse than not acting.

---

## 7. CLIENT LIBRARIES — NODE.JS IN 2026

### 7.1 Official libraries: six, none of them Node

Google ships **Java, .NET, PHP, Python, Ruby, Perl** ([Client libraries](https://developers.google.com/google-ads/api/docs/client-libs)). **There is no official Node.js/TypeScript library and never has been.** Google's own page lists the community Node option with an explicit disclaimer:

> *"We are aware of several libraries that are maintained by the open source community... We don't test, contribute to, or maintain these libraries; **use them at your own risk.**"*

### 7.2 `google-ads-api` (Opteo) — the de-facto Node library

| Field | Value |
|---|---|
| **Latest version** | **24.1.0** |
| **Published** | **2026-06-15** |
| **Weekly downloads** | **~311,000** |
| **Google Ads API version** | **v24.1 only** |
| **Supports v25?** | **No** |
| License / TS | MIT / first-class TypeScript, ships `.d.ts` |
| Repo | [Opteo/google-ads-api](https://github.com/Opteo/google-ads-api) — 339 stars, 60 open issues, not archived |

**The v25 gap is structural, not incidental.** The library hard-pins the version at compile time — [`src/version.ts`](https://github.com/Opteo/google-ads-api/blob/master/src/version.ts):

```ts
export const googleAdsVersion = "v24";
```

and [`src/protos/index.ts`](https://github.com/Opteo/google-ads-api/blob/master/src/protos/index.ts) binds `resources`, `services`, and `errors` to the `v24` proto namespace. **There is no config option to point 24.1.0 at v25.**

**Maintenance read:** release cadence historically tracked Google's versions, and 24.1.0 was a substantive release (real fixes to `getFieldMask()`, service-cache TTL, stream teardown). But v25 shipped 2026-07-22 and ~7 weeks later there is **no v25 release and no `v25` branch** (the repo uses per-version branches: `v22`, `v23`, `v24.1`), no push since 2026-06-15, and the two most recent issues have **zero maintainer comments**. Opteo maintains this for their own product on their own schedule — it works, but you inherit a 1–3 month lag with no SLA.

**Transport is a hybrid**, contrary to the README's "Uses REST" claim: reads (`query`/`report`/`reportStream`) go over **REST via axios**; mutates and per-service calls go over **gRPC via `google-gax`**. An [open issue](https://github.com/Opteo/google-ads-api/issues/547) reports unusable gRPC channels *hanging* — in a cron that surfaces as a timeout, not an error.

### 7.3 `google-ads-api` usage

```ts
import { GoogleAdsApi } from "google-ads-api";

const client = new GoogleAdsApi({ client_id, client_secret, developer_token });
const customer = client.Customer({
  customer_id: "1234567890",
  login_customer_id: "<MCC-ID>",   // omitted -> header not sent
  refresh_token: "<REFRESH-TOKEN>",
});

const rows = await customer.query(`
  SELECT campaign.id, campaign.name, metrics.cost_micros, metrics.clicks
  FROM campaign WHERE campaign.status = "ENABLED" LIMIT 20
`);
```

**Atomic cross-service mutate with temporary resource names** (negative IDs link operations):

```ts
import { resources, enums, toMicros, ResourceNames, MutateOperation } from "google-ads-api";

const budgetResourceName = ResourceNames.campaignBudget(customer.credentials.customer_id, "-1");

const operations: MutateOperation<resources.ICampaignBudget | resources.ICampaign>[] = [
  { entity: "campaign_budget", operation: "create",
    resource: { resource_name: budgetResourceName, name: "Budget",
                delivery_method: enums.BudgetDeliveryMethod.STANDARD,
                amount_micros: toMicros(500) } },
  { entity: "campaign", operation: "create",
    resource: { name: "Campaign", campaign_budget: budgetResourceName, /* ... */ } },
];

await customer.mutateResources(operations, {
  validate_only: true,      // snake_case in options
  partial_failure: false,
});
```

`MutateOptions` is `Omit<services.IMutateGoogleAdsRequest, "customer_id" | "mutate_operations">`, so the keys are **snake_case**: `validate_only`, `partial_failure`, `response_content_type`. Partial-failure decoding is automatic — the library unpacks the base64 `GoogleAdsFailure` from `partial_failure_error.details`. **This is its single biggest value-add over hand-rolled REST.**

Errors: everything except transport failures is a `errors.GoogleAdsFailure` with an `errors[]` array of `GoogleAdsError` carrying `error_code.<category>`, `message`, `trigger`, `location`.

> **Known defect** ([issue #548](https://github.com/Opteo/google-ads-api/issues/548), open, unanswered since 2026-08-24): `getGoogleAdsError` **crashes decoding a REST-style structured error** (e.g. `SERVICE_DISABLED`), *masking the real error*. Since reads go over REST, a misconfigured GCP project surfaces as a decode crash rather than the actual cause.

### 7.4 Other Node options

| Package | Version | Weekly DL | Verdict |
|---|---|---|---|
| `google-ads-api` (Opteo) | 24.1.0 | ~311k | The default. **v24.1 only.** |
| `google-ads-node` (Opteo) | 24.1.0 | ~391k | Generated proto/gRPC layer *under* the above. Not ergonomic. |
| `google-ads-api-report-fetcher` (gaarf) | 4.3.0 | ~422 | **Google-maintained** ([google/ads-api-report-fetcher](https://github.com/google/ads-api-report-fetcher), Apache-2.0), actively updated. **Reporting/ETL only — no mutates.** |
| `@openpromo/google-ads` | 0.13.0 | ~40 | Only package claiming **v25**. 0.x, ~zero adoption. Too risky. |
| `@htdangkhoa/google-ads` | 0.25.0 | ~766 | Independent gRPC client, MIT. Small bus factor. |
| `googleapis` | 178.x | — | **Does NOT cover Google Ads — confirmed.** |
| `google-auth-library` / `gaxios` | 11.x / 8.x | — | **Building blocks for the DIY REST path.** Google-maintained. |

**`googleapis` confirmed negative:** enumerating `src/apis/` in [google-api-nodejs-client](https://github.com/googleapis/google-api-nodejs-client/tree/main/src/apis) yields **334 APIs, none named `googleads`**. Confusing neighbours: `adsense`, `admob`, `adexchangebuyer2`, and **`searchads360`** (a different product). Reason: `googleapis` is generated from the standard Discovery index, which the Google Ads API is not published in.

**Bottom line: there is no maintained, production-grade Node library on v25.** The choice is *Opteo on v24.1* or *hand-rolled REST on v25*.

### 7.5 Calling REST directly

Endpoints verified against the **v25 discovery document** (`https://googleads.googleapis.com/$discovery/rest?version=v25`, revision `20260831`) and by live probe (real routes return **401**, bogus ones **404**):

| Method | Path |
|---|---|
| POST | `/v25/customers/{customerId}/googleAds:search` |
| POST | `/v25/customers/{customerId}/googleAds:searchStream` |
| POST | `/v25/customers/{customerId}/googleAds:mutate` |
| POST | `/v25/customers/{customerId}/adGroupAds:mutate` |
| POST | `/v25/customers/{customerId}/campaigns:mutate` |
| GET | `/v25/customers:listAccessibleCustomers` |

**`customerId` is digits only, no hyphens.**

> **Minor versions are NOT URL segments.** `POST /v25.1/...` returns **404**. v25.1 features are served under `/v25/`. Also: `/v26/` already answers 401 (route pre-provisioned) while appearing nowhere in the docs — **pin `v25`, do not chase v26.**

**Generic vs per-service mutate:** `googleAds:mutate` takes `mutateOperations[]` where each element is a **oneof wrapper** (64 operation types: `campaignOperation`, `adGroupAdOperation`, `assetOperation`, …). Use it for **cross-service atomicity** and **temporary resource names**. `adGroupAds:mutate` takes a flat `operations[]` — simpler, single resource type.

**Required headers:**
```
Authorization: Bearer ACCESS_TOKEN
developer-token: DEVELOPER_TOKEN
login-customer-id: MANAGER_CUSTOMER_ID     # only when calling via a manager account
linked-customer-id: LINKED_CUSTOMER_ID     # only for third-party linked accounts
Content-Type: application/json
```
Responses carry a `request-id` header — **log it**; it is what Google support asks for.

#### The casing gotcha — GAQL is snake_case, JSON is lowerCamelCase

The single biggest REST footgun, and it is official ([JSON mappings](https://developers.google.com/google-ads/api/rest/design/json-mappings)): *"Identifiers are transformed from snake_case (in protocol buffers) to lowerCamelCase in JSON."*

**You use both conventions in one request:**

```jsonc
{
  // GAQL string: snake_case. It is an opaque query language, NOT JSON.
  "query": "SELECT campaign.id, campaign_budget.amount_micros, metrics.cost_micros FROM campaign WHERE segments.date DURING LAST_7_DAYS",
  "pageToken": "..."   // envelope: lowerCamelCase
}
```

The response comes back camel-cased and **does not match the field names you selected**:

```jsonc
{
  "results": [{
    "campaign": { "resourceName": "customers/123/campaigns/111", "id": "111" },
    "campaignBudget": { "amountMicros": "50000000" },  // you queried campaign_budget.amount_micros
    "metrics": { "costMicros": "12345000" }            // you queried metrics.cost_micros
  }],
  "fieldMask": "campaign.id,campaignBudget.amountMicros,metrics.costMicros",
  "nextPageToken": "..."
}
```

Opteo's library papers over exactly this with a `decamelizeKeys` step. **Hand-rolling REST means you own that mapping** (or commit to camelCase end-to-end). Also note resource names use **`resourceName`, not `name`** — deliberately, to avoid colliding with `campaign.name`.

#### Serialization rules (proto3 canonical JSON)

- **Enums → bare uppercase strings**: `"status": "ENABLED"`. Never integers.
- **int64/uint64 → JSON *strings***, not numbers. Micros arrive as `"50000000"`. Values can exceed `Number.MAX_SAFE_INTEGER` — parse deliberately.
- Field masks → comma-joined string.

#### `validateOnly` / `partialFailure` in REST

Both are **plain top-level booleans in the request body**, lowerCamelCase — not query params, not headers.

```bash
curl -X POST "https://googleads.googleapis.com/v25/customers/1234567890/adGroupAds:mutate" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "developer-token: $DEV_TOKEN" \
  -H "login-customer-id: 9876543210" \
  -H "Content-Type: application/json" \
  -d '{
    "operations": [{
      "update": { "resourceName": "customers/1234567890/adGroupAds/55555~66666", "status": "PAUSED" },
      "updateMask": "status"
    }],
    "partialFailure": true,
    "validateOnly": false,
    "responseContentType": "RESOURCE_NAME_ONLY"
  }'
```

`partialFailure` defaults to **false** (all-or-nothing transaction). **`updateMask` is mandatory on updates** — omit it and the mutate silently no-ops. `SearchGoogleAdsRequest` also accepts `validateOnly`; **`SearchGoogleAdsStreamRequest` does not**.

#### Partial-failure response shape

```jsonc
{
  "results": [
    { "resourceName": "customers/123/adGroupAds/55555~66666" },
    {}                                   // failed op -> empty object, index preserved
  ],
  "partialFailureError": {
    "code": 3, "message": "...",
    "details": [{ "@type": "type.googleapis.com/google.ads.googleads.v25.errors.GoogleAdsFailure", ... }]
  }
}
```

**Map a failure back to its operation via `GoogleAdsError.location.field_path_elements[0].index`** — the 0-based operation index. Results and errors are positional.

> **This is the strongest argument for a library over raw REST.** Decode `details[]` defensively: check `@type`, tolerate both expanded-JSON and base64 `value` forms, and never let a decode failure swallow the original HTTP status.

#### `searchStream` returns an ARRAY of chunks

Confirmed by docs and empirically — the raw body for `searchStream` begins `[{`, whereas `search` begins `{`:

```jsonc
[
  { "results": [ /* rows */ ], "fieldMask": "...", "requestId": "..." },
  { "results": [ /* more rows */ ], "fieldMask": "...", "requestId": "..." }
]
```

**No `nextPageToken`** — streaming is unpaginated by design.

#### Pagination — the `pageSize` trap

**Do not send `pageSize`.** It remains in the v25 schema but its description is unambiguous: *"This field is deprecated... Google Ads API returns a `PAGE_SIZE_NOT_SUPPORTED` error if this field is set in the request body."*

Page size is **fixed at 10,000 rows** (v19+). Loop on `pageToken` ← `nextPageToken`. **Terminate on the absence of `nextPageToken`, not on an empty `results` array.** Note the docs' prose says `page_token` while the **JSON keys are `pageToken`/`nextPageToken`** — the casing gotcha inside Google's own documentation.

### 7.6 OAuth2 gotchas

**Scope:** exactly one — `https://www.googleapis.com/auth/adwords`.

**The 7-day refresh-token expiry is real and verified verbatim** ([Using OAuth 2.0](https://developers.google.com/identity/protocols/oauth2)):

> *"A Google Cloud Platform project with an OAuth consent screen configured for an **external** user type and a publishing status of **'Testing'** is issued a refresh token **expiring in 7 days**, unless the only OAuth scopes requested are a subset of name, email address, and user profile."*

`adwords` is emphatically not in that exempt subset. **A cron built on a Testing-status consent screen dies silently every 7 days with `invalid_grant`.** Fix: **publish the consent screen** ("In production"). Other documented revocation causes: token unused for **six months**, user revoked access, password change, max-refresh-tokens exceeded, admin policy.

**Client type:** for a single-account backend use a **Desktop app** OAuth client — it permits the loopback/installed-app flow so you can mint a refresh token once from your laptop with no hosted redirect URI. A **Web application** client is right only for multi-tenant SaaS.

**Service accounts — the long-standing "Workspace domain-wide delegation only" rule appears to have been dropped.** The [current service-accounts page](https://developers.google.com/google-ads/api/docs/oauth/service-accounts) no longer mentions delegation, Workspace, impersonation, or `subject`. It now says:

> *"A service account is an account that belongs to your app instead of to an individual end user. Service accounts employ an OAuth 2.0 flow that **doesn't require human authorization**, using instead a key file that only your app can access."*

Documented setup: create the service account → **add its email as a user in the Google Ads account** (Admin → Access and security) → point the client at the key file. The [OAuth overview](https://developers.google.com/google-ads/api/docs/oauth/overview) now routes by scenario, recommending the service-account workflow for managing your own accounts with single-user auth as a *"fallback."* Documented limit: **20 Google Ads accounts per email address** (attach the SA to a manager account to scale past it).

> **Caveat, stated plainly:** this reverses years of guidance and most community material still describes the old DWD requirement. This was verified against the *documentation*, not a live token exchange. **Try the direct service-account path first; keep the desktop-flow refresh token as a proven fallback.**

**Token refresh in serverless/cron:** access tokens live **1 hour**. Never mint per request — cache in **module scope** (Opteo caches 50 min) so warm containers reuse it. Store the refresh token in a secret manager. **With a service account you skip all of this** — `google-auth-library` mints and rotates JWT-based tokens itself, with no refresh token to expire or leak. That is the decisive operational advantage.

### 7.7 Recommendation

**Hand-roll a thin REST client on `v25` using `google-auth-library`, authenticated with a service account.**

`google-ads-api` is genuinely good, but for this workload it is the wrong trade:

1. **It cannot speak v25**, and the version is compiled in. No v25 branch ~7 weeks post-release; recent issues unanswered. You would adopt a dependency you cannot upgrade on your own schedule.
2. **The surface you need is tiny** — daily reads plus a few dozen mutates touches ~3 endpoints. The library's value is concentrated in machinery you will not use.
3. **Weight and cold starts** — 4.6 MB unpacked, pulling `google-gax`, `@grpc/grpc-js`, protobufjs, axios, `stream-json`. gRPC in a serverless container is a liability (see the hanging-channel issue).
4. **Its reads already go over REST** to the exact URL you would construct yourself. You give up no superior transport.

Concretely:
- **Auth:** service account + `google-auth-library`; fall back to Desktop-app OAuth with a **published** consent screen.
- **Pin `v25`** in one constant — not `v25.1` (404 in path), not `v26`.
- **Reads:** `googleAds:searchStream` — one request, no pagination, no `pageSize` risk. Body is an **array of chunks**.
- **Mutates:** `googleAds:mutate` with `partialFailure: true`, behind a `validateOnly: true` pass first.
- **Types:** generate from the discovery doc (1,480 schemas) rather than hand-writing.
- **Write once, carefully:** a camel↔snake response mapper, an int64-string parser, a defensive `partialFailureError.details[]` decoder. Log `request-id` on every call.

```ts
import { GoogleAuth } from "google-auth-library";

const API = "https://googleads.googleapis.com/v25";
const auth = new GoogleAuth({ scopes: ["https://www.googleapis.com/auth/adwords"] });
let client: any; // module scope: survives warm invocations

async function headers() {
  client ??= await auth.getClient();
  const { token } = await client.getAccessToken();  // library handles caching + rotation
  return {
    Authorization: `Bearer ${token}`,
    "developer-token": process.env.GOOGLE_ADS_DEVELOPER_TOKEN!,
    ...(process.env.GOOGLE_ADS_LOGIN_CUSTOMER_ID && {
      "login-customer-id": process.env.GOOGLE_ADS_LOGIN_CUSTOMER_ID,
    }),
    "Content-Type": "application/json",
  };
}

/** searchStream returns an ARRAY of chunks; flatten it. */
export async function searchStream<T>(customerId: string, query: string): Promise<T[]> {
  const res = await fetch(`${API}/customers/${customerId}/googleAds:searchStream`, {
    method: "POST", headers: await headers(),
    body: JSON.stringify({ query }),   // GAQL snake_case; envelope lowerCamelCase
  });
  const body = await res.json();
  if (!res.ok) throw new GoogleAdsRestError(res, body);
  return (body as Array<{ results?: T[] }>).flatMap((c) => c.results ?? []);
}

export async function mutate(customerId: string, mutateOperations: unknown[], validateOnly = false) {
  const res = await fetch(`${API}/customers/${customerId}/googleAds:mutate`, {
    method: "POST", headers: await headers(),
    body: JSON.stringify({ mutateOperations, partialFailure: true, validateOnly }),
  });
  const body = await res.json();
  if (!res.ok) throw new GoogleAdsRestError(res, body);
  // Map failures: partialFailureError.details[].errors[].location.field_path_elements[0].index
  return body;
}
```

**If you would rather not own that code:** use `google-ads-api@24.1.0` on **v24**, accept being one version behind, and diarize a review before v24's ~May 2027 sunset. A legitimate choice — just make it knowingly.

