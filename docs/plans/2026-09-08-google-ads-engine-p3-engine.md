# Google Ads Engine — Phase 3: The Engine — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use `custom-skills:executing-plans` to implement this plan task-by-task. Read the design spec first: `ops-software-bible/specs/2026-09-08-google-ads-engine-design.md` (§5, §6, §7 are this phase) and the Instagram routine contract it mirrors: `ops-web/docs/social/cloud-editorial-operations.md`, `ops-web/docs/social/cloud-authoring-routine.md`, `ops-web/src/lib/social/editorial/handoff.ts`, `ops-web/supabase/migrations/20260907004500_create_social_editorial_assignments.sql`. Spawn title: `GOOGLE ADS ENGINE - P3-1`. Can run in parallel with Phase 1 on its own worktree; Tasks 7–9 need Phase 1's warehouse and Phase 2's copy rules to exist on the branch you merge into.

**Goal:** A daily Claude Cloud Routine claims a brief from OPS, proposes typed changes, OPS validates them deterministically, Jackson approves them on the admin ads page, OPS applies them to Google with `validateOnly` first, labels every change, and computes test verdicts and change outcomes from the warehouse.

**Architecture:** Same shape as the Instagram editorial handoff: a lease-based `claim`, a typed submit endpoint returning fixable 422 codes, a `release`, a settings row with per-kind modes, a worker cron that promotes approved work, notifications on the operator rail, and a stall alarm. Proposals live in their own table (`agent_actions` is company-scoped and cannot carry OPS-internal work). Pure handlers with injected repositories so the boundary is proved without a database, exactly like `tests/unit/social/editorial/handoff.test.ts`.

**Tech Stack:** as Phase 1; Zod for payload schemas; the PG17 SQL harness; one Claude Cloud Routine (`claude-opus-5`, tools `Bash, Read, Write, Edit, Agent`, no repositories, no connectors, environment `Default` with an API credential for host `app.opsapp.co`).

**Design System:** `ops-web/.interface-design/system.md` + `ops-design-system/project/DESIGN.md`. Proposal cards reuse the agent-queue card grammar (`src/components/agent/queue-row.ts` tag variants, `reject-dialog.tsx`, `queue-filter-chips.tsx` trigger) — same look, different data. Agent provenance palette (`agent-*` tokens) is allowed only on the routine-authored copy inside a proposal card (spec: lavender is reserved for Claude-authored surfaces).

**Required Skills:** `custom-skills:executing-plans`, `custom-skills:interface-design`, `ops-design`, `animation-studio:data-visualization` (funnel and test readouts), `ops-copywriter:ops-copywriter` (every label, empty state, notification string, and the routine prompt's voice section), `custom-skills:audit-design-system`, `superpowers:test-driven-development`, `superpowers:verification-before-completion`, `schedule` (creating the routine, at the very end, disabled).

**Worktree:** `/Users/jacksonsweet/Projects/OPS/ops-web-ads-engine-p3` on branch `feat/ads-engine-p3` off `feat/ads-engine-p1` (so P1's client and warehouse are present). Own `npm ci`; `cp -L` the env file.

**Hard rules:** the routine never reaches Google; OPS does, and only after approval (or in `auto` mode for a kind Jackson has flipped); `validateOnly` before every real mutate; every applied change carries labels `engine`, `gen-<run_id>`, and `role-*`; proposals expire after 14 days; the routine is created DISABLED and never enabled by the agent; no push.

---

## Task 1: Migration — engine tables, RPCs, notification function

**Files:**
- Create: `ops-web/supabase/migrations/20260910120000_ads_engine.sql` (+ bible mirror)
- Create: `ops-web/tests/sql/ads-engine-runtime.mjs`

**Tables (service-role only, RLS deny-all + revokes):**

- `ads_engine_settings` (single row `id = true`): `modes jsonb` (per kind: `propose|auto|off`, default all `propose`), `monthly_cap numeric default 1500`, `daily_cap numeric default 60`, `max_budget_change_pct integer default 15`, `budget_cooldown_days integer default 14`, `max_structural_per_run integer default 3`, `lease_minutes integer default 40`, `stall_hours integer default 50`, `heartbeat_at timestamptz`, `updated_at`.
- `ads_engine_runs`: `id uuid pk`, `state text check in ('claimed','released','expired')`, `worker text`, `claim_token uuid`, `lease_until timestamptz`, `duties text[]`, `brief_version text`, `summary text`, `outcome text`, `proposals_accepted int default 0`, `proposals_rejected int default 0`, `created_at`, `released_at`.
- `ads_proposals`: `id uuid pk`, `run_id uuid references ads_engine_runs`, `kind text check in ('add_negatives','pause_keyword','add_keywords','create_rsa_challenger','promote_challenger','pause_ad','adjust_budget','adjust_cpc_cap','set_bidding_strategy','add_ad_group','observation')`, `payload jsonb`, `evidence jsonb`, `rationale text`, `state text check in ('proposed','approved','rejected','applied','failed','expired') default 'proposed'`, `mode_at_submit text`, `google_validation jsonb`, `reviewed_by uuid`, `review_notes text`, `reviewed_at timestamptz`, `applied_at timestamptz`, `applied_resource_names text[]`, `label text`, `error text`, `expires_at timestamptz default now() + interval '14 days'`, `created_at`, `updated_at`.
- `ads_changes`: `id uuid pk`, `proposal_id uuid references ads_proposals`, `kind text`, `resource_names text[]`, `before jsonb`, `after jsonb`, `applied_at timestamptz`, `measure_from date`, `measure_to date`, `pre_metrics jsonb`, `post_metrics jsonb`, `verdict text check in ('pending','better','worse','flat','no_verdict')`, `verdict_at timestamptz`.
- `ads_tests`: `id uuid pk`, `ad_group_id text`, `control_ad_id text`, `challenger_ad_id text`, `started_at timestamptz`, `min_days int default 14`, `min_impressions int default 2000`, `max_days int default 56`, `state text check in ('running','control_won','challenger_won','no_verdict','cancelled')`, `stats jsonb` (both arms' impressions/clicks/ctr, z, p, trials), `verdict_at`, `created_at`.

**RPCs** (security invoker, `set search_path=''`, `for update skip locked`, mirroring the social ones): `claim_ads_engine_run(p_token uuid, p_worker text)` — expires overdue runs, refuses when any run is live or settings mode is all `off`, inserts a claimed run with `lease_until = now() + lease_minutes`, bumps `heartbeat_at`; `release_ads_engine_run(p_id, p_token, p_summary, p_outcome)`; `expire_ads_proposals()`; `notify_ads_engine(p_user_id text, p_company_id text)` — inserts rail rows exactly like `notify_social_editorial` (type `ads_engine`; titles `ADS PROPOSALS READY · n` standard with `action_url='/admin/google-ads#proposals'`, `AD DISAPPROVED` persistent, `ADS ENGINE STALLED` persistent once per Vancouver day with `dedupe_key='ads-engine:stalled:<date>'`, `ADS BUDGET PACING` standard) using `on conflict do nothing`; `check_ads_engine_stall(p_stale_hours int)` returns boolean when campaigns are ENABLED and `heartbeat_at` is older than the threshold.

**Harness assertions:** claim → second claim returns nothing → release → claim works again; lease expiry via `now()` injection (set `lease_until` in the past and re-claim); proposal expiry; notification dedupe (same day twice → one row); privileges.

**Commit** `feat(ads): engine tables, claim lease, and rail notifications`; mirror; apply to prod after the harness passes (verify by object).

---

## Task 2: Guardrails + validators (pure)

**Files:** `ops-web/src/lib/ads/engine/guardrails.ts`, `ops-web/src/lib/ads/engine/proposal-schemas.ts` (Zod per kind, `.strict()`), `ops-web/src/lib/ads/engine/validate-proposal.ts`, tests `tests/unit/ads/engine/validate-proposal.test.ts`

`validateProposal(proposal, ctx): { ok: true, normalized } | { ok: false, code, issues }` where `ctx` carries settings, the entity snapshot, the 28-day metrics, open tests, the change ledger, and the copy rules (`validateRsa` from P2). Codes: `SCHEMA_INVALID`, `UNKNOWN_ENTITY`, `INSUFFICIENT_DATA`, `TERM_PRODUCED_TRIAL`, `TERM_NOT_IN_REPORT`, `BROAD_MATCH_REJECTED`, `THEME_MISMATCH`, `BUDGET_CAP`, `DAILY_CAP`, `COOLDOWN`, `CHANGE_TOO_LARGE`, `LADDER_NOT_MET`, `TEST_NOT_CONCLUDED`, `URL_NOT_ALLOWED`, `STRUCTURAL_LIMIT`, plus every `CopyIssueCode` (returned as `code: "COPY_REJECTED"`, `issues: CopyIssue[]`). Rules are the spec §5.2 table and §5.6 verbatim (thresholds read from settings, never hard-coded twice).

**Tests:** one accepted fixture per kind; one failing fixture per code.

**Commit** `feat(ads): deterministic proposal validators and money guardrails`.

---

## Task 3: Brief builder

**Files:** `ops-web/src/lib/ads/engine/brief.ts`, `tests/unit/ads/engine/brief.test.ts`, `ops-web/docs/ads/engine-brief-contract.md`

`buildBrief(db, now)` returns `{ version, duties: DutyKey[], settings, snapshot, metrics7d, metrics28d, funnel, tests, ledger90d, proposals: { pending, rejectedWithReasons }, copyRules: { brandFacts, allowedUrls, rules }, negativeTaxonomy, marketDigest }`. Duties: `hygiene` every run; `creative` for any ad group whose control is ≥ 28 days old and has no running test; `structure` on the first run of the month; `bidding_ladder` when a ladder trigger is met (≥ 15 trial starts in each of the last two 30-day windows, or ≥ 30). Trailing 3 days are excluded from every metric window. `marketDigest` reuses the existing Tavily steps (`src/lib/admin/briefing-steps/competitor-research.ts`, `market-sentiment.ts`) once a week and caches the text in `ads_sync_status` row `id='market-digest'`.

**Commit** `feat(ads): assemble the engine brief from the warehouse`.

---

## Task 4: Handoff handlers + routes

**Files:** `ops-web/src/lib/ads/engine/handoff.ts` (pure handlers with injected repository, `now`, `loadCopyRules`), `ops-web/src/lib/ads/engine/handoff-runtime.ts`, `ops-web/src/lib/ads/engine/repository.ts`, routes `src/app/api/internal/ads/engine/claim/route.ts`, `.../runs/[id]/proposals/route.ts`, `.../runs/[id]/release/route.ts`, tests `tests/unit/ads/engine/handoff.test.ts` (copy the social test's structure: forbidden-import spies for the Ads mutate module and the notification module, so the submit path can never reach Google)

Contract (spec §5.1): bearer `ADS_ENGINE_TOKEN` (≥ 32 chars, `503 ADS_ENGINE_NOT_CONFIGURED`, `401 ADS_ENGINE_INVALID`), `405` on non-POST, 200 KB body cap, `claim` `{worker}` → `{ run: { id, claim_token, lease_until, current_time }, brief }` or `{ run: null, reason: "idle" | "engine_off" | "run_active" }`; `proposals` `{ claim_token, proposals: [...] }` → per item `{ index, accepted: true, id }` or `{ index, accepted: false, code, issues }` with a 3-resubmission cap per index (`429 SUBMISSIONS_EXHAUSTED`); `release` `{ claim_token, summary, outcome: "done" | "error" | "nothing_to_do" }`. `409 CLAIM_NOT_OWNED` when the token or lease is wrong. Accepted proposals are stored `proposed` with `mode_at_submit`; when the kind's mode is `auto`, the worker (Task 6) applies them without review.

**Commit** `feat(ads): routine handoff routes for claim, proposals, and release`.

---

## Task 5: Apply service + labels + Google validation

**Files:** `ops-web/src/lib/ads/engine/apply.ts`, `tests/unit/ads/engine/apply.test.ts`

`applyProposal(proposal, deps)` per kind → `MutateOperation[]` (negatives → `sharedCriterionOperation` on the named shared set; pause keyword → `adGroupCriterionOperation.update status PAUSED`; add keywords → `adGroupCriterionOperation.create` phrase/exact; create RSA challenger → `adGroupAdOperation.create` (ENABLED) + `adGroupAdLabelOperation` × 3 + open an `ads_tests` row; promote challenger → pause the loser + relabel roles + close the test; pause ad; adjust budget → `campaignBudgetOperation.update amountMicros`; adjust cpc cap → `campaignOperation.update maximizeClicks.cpcBidCeilingMicros`; set bidding strategy → `campaignOperation.update` along the ladder; add ad group → the P2 planner's ad-group subtree). Always `validateOnly` first; a `POLICY_FINDING` on an RSA marks the proposal `failed` with `google_validation` and the topic, and the next brief carries it back to the routine. On success write `ads_changes` with `before` (from the snapshot) and `after`, `measure_from = applied_at + 1 day`, `measure_to = +14 days`, and refresh the entity snapshot.

**Commit** `feat(ads): apply approved proposals to Google with validateOnly and labels`.

---

## Task 6: Worker cron, verdicts, outcomes, stall alarm

**Files:** `ops-web/src/lib/ads/engine/stats.ts` (two-proportion z-test on CTR with impressions as n; `verdict(control, challenger, rules)`), `ops-web/src/lib/ads/engine/worker.ts`, `src/app/api/cron/ads-engine/route.ts` (`53 14 * * *` UTC — after the 08:04 sync; check `vercel.json` for the free minute at hour 14 first), tests `tests/unit/ads/engine/stats.test.ts` (known z/p fixtures; below-minimum data → `no_verdict`; conversion veto), `tests/unit/ads/engine/worker.test.ts`

Worker duties per run: expire proposals; apply `auto`-mode proposals; conclude tests whose rule is met (spec §5.4) and open the follow-up `promote_challenger` proposal in `propose` mode (never auto-promote in v1); compute `ads_changes` verdicts whose `measure_to` has passed (CTR delta ± 10% → better/worse, else flat; `no_verdict` under 500 impressions); pause any `DISAPPROVED` ad immediately and raise `AD DISAPPROVED`; detect budget pacing (campaign `metrics.search_budget_lost_impression_share > 0.3` three days running) → `ADS BUDGET PACING`; call `notify_ads_engine`; check the stall rule → `ADS ENGINE STALLED`.

**Commit** `feat(ads): engine worker with CTR verdicts, outcomes, and alarms`.

---

## Task 7: Admin routes for review

**Files:** `src/app/api/admin/google-ads/engine/proposals/route.ts` (GET list with `state` filter, `withAdmin`), `.../proposals/[id]/route.ts` (`POST` `{ decision: "approve" | "reject", notes? }` → `approved` then `applyProposal` synchronously with a 25 s budget, or `rejected` with notes; returns the resulting state and any Google validation), `.../settings/route.ts` (GET/PATCH modes and caps; PATCH refuses `auto` for `create_rsa_challenger`, `adjust_budget`, `adjust_cpc_cap`, `set_bidding_strategy`, `add_ad_group` — those stay human in v1), `.../tests/route.ts`, `.../changes/route.ts`, `.../funnel/route.ts` (reads `ads_funnel_by_keyword`), `.../health/route.ts`; tests per route (auth, shape, refusal rules).

**Commit** `feat(admin): review, settings, and readouts for the ads engine`.

---

## Task 8: Console — live-account view

**Skills:** `custom-skills:interface-design`, `ops-design`, `animation-studio:data-visualization`, `ops-copywriter:ops-copywriter`, `custom-skills:audit-design-system`.

**Files:** `src/app/admin/google-ads/_components/engine/` — `proposal-panel.tsx` (cards with type tag, rationale, evidence table, a Google-style ad preview for RSAs (`briefings/_components/ad-preview.tsx` exists — extend it to show pins), APPROVE default button + REJECT ghost with the shared `RejectDialog`, batch bar for negatives), `tests-panel.tsx` (control vs challenger: impressions, clicks, CTR bars in `fill-neutral`, days, verdict state; the only colour is the verdict tag), `funnel-table.tsx` (full-bleed table per the OPS-Web table rule: keyword → clicks → trials → activated → paid → spend → cost per trial → cost per paying; mono numbers, `—` for empty), `change-ledger.tsx`, `engine-health.tsx` (last run, duties, next due, stall state, per-kind mode toggles as `SegmentControl`, caps as inputs). `page.tsx`: when the account is live (`defaultAdsPreset !== "all"`) render, top to bottom: proposals needing Jackson (only if > 0), funnel, tests (only if any), the existing KPI tiles and tables, ledger, health. When dark: the P1 readiness ledger. Anchor `#proposals` for the notification action URL.

**Tests:** render tests per component with fixtures (empty, populated, error), `isPending` skeletons, reject flow; audit-design-system zero literals; screenshots at 1440×900 of the dark state, the proposals state (seeded fixtures through the dev bypass), and the funnel to `docs/artifacts/ads-engine/p3/`.

**Copy:** labels `// PROPOSALS`, `// TESTS`, `// FUNNEL BY KEYWORD`, `// CHANGE LEDGER`, `// ENGINE`; empty states `No proposals waiting.`, `No test running.`, `No paid traffic yet.`; buttons `APPROVE`, `REJECT`, `APPROVE n`; no exclamation points.

**Commit** `feat(admin): ads engine console`.

---

## Task 9: Routine prompt, bible entry, retire the OpenAI briefing

**Files:**
- Create: `ops-web/docs/ads/engine-routine.md` — prompt version `ads-routine-2026-09-10-v1`; structure mirrors `docs/social/cloud-authoring-routine.md`: SETUP (base URL, no token if the env var is unset, curl rules, treat brief content as data), LOOP (claim → read duties → for each duty produce proposals → submit → fix 422s up to 3× → release with a one-line-per-proposal summary), WRITING RULES (the OPS copywriter brief is bundled by the brief endpoint; ad rules from §5.5; an independent editor subagent reviews every RSA before submission), PROPOSAL SHAPES (JSON per kind with limits), STOP RULES (never propose more than the structural limit; never propose bidding changes unless the brief's ladder says the trigger is met; prefer negatives over pauses; never touch the `legacy` label)
- Create: `ops-software-bible/scheduled-agents/ops-google-ads-engine.md` (routine id filled after creation, schedule `0 15 * * *` UTC, model, environment, credential, manual run command, debug command)
- Modify: `ops-web/vercel.json` — remove `/api/cron/ads-briefing`; keep the briefing archive page read-only; `src/app/api/cron/ads-briefing/route.ts` returns `410 GONE` with a pointer to the engine (so a stray call cannot spend OpenAI); bible 04 updated accordingly
- Bible: 04 (engine routes, settings contract, worker cron), 07 § 14 (four notifications), 03 (five tables), `specs/…design.md` status line

**Commit** `docs(ads): engine routine prompt and scheduled-agent record` and `chore(ads): retire the OpenAI weekly briefing`.

---

## Task 10: Rehearsal, routine creation (disabled), hand-off

1. **Local rehearsal** exactly like the Instagram one: disposable PG17 with the real migrations behind PostgREST, the worktree dev server on port 3220, `ADS_ENGINE_TOKEN` set locally, a seeded warehouse fixture (the P1 harness seeds), then drive the exact routine prompt from a local Claude session against `http://localhost:3220`. Prove: claim → proposals (at least one negative set, one challenger RSA that passes the copy rules, one that is rejected with a fixable code and then fixed) → release; approve in the console; the apply layer runs `validateOnly` against the real account (safe) and stops before the real mutate in rehearsal mode (`ADS_ENGINE_REHEARSAL=1` makes `applyProposal` return after validation — add the flag, test it). Transcript and JSON to `docs/artifacts/ads-engine/p3/local-e2e-<date>/`.
2. **Create the routine DISABLED** with the `schedule` skill: name `OPS Google Ads engine`, cron `0 15 * * *`, model `claude-opus-5`, environment `Default`, tools `Bash, Read, Write, Edit, Agent`, then `update { clear_mcp_connections: true }` (creation attaches every connector by default). Record the routine id in the bible entry. Do not enable it. Do not run it.
3. **Jackson's actions (list them plainly in the hand-off):** `openssl rand -hex 32` → Vercel Production `ADS_ENGINE_TOKEN`; the environment API credential for host `app.opsapp.co` with that token; un-pause the routine after the P2 campaigns are enabled; read the daily routine allowance.
4. **Shadow week:** with campaigns enabled (P2) and the routine enabled, every proposal stays in `propose`; after seven days Jackson decides which kinds (negatives, loser pauses) flip to `auto`.
5. **Verification before "done":** all unit suites green, both SQL harnesses PASS, `tsc` at baseline, screenshots, the rehearsal transcript, and the routine visible at `https://claude.ai/code/routines/<id>` as disabled.

**Do not:** enable the routine; push; merge; apply any real mutate during rehearsal; put OPS-internal proposals into `agent_actions`.

---

## Phase 4 (not planned yet, on purpose)

Landing-page variant ↔ ad group linkage (utm_content = ad id; try-ops `ab_events` joined to `ads_click_map`), US campaigns as separate campaigns, trade-specific ad groups added by evidence, value-based bidding once the ladder allows, and folding the try-ops OpenAI rotation into the routine. These depend on 90 days of measured data and Jackson's day-90 decision (research §8.10); planning them now would be speculation.
