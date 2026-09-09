# OPS Google Ads engine (Cloud Routine)

Status (2026-09-09): routine **created on Jackson's claude.ai account, DISABLED, never run** (`trig_01LroGoQJLg9GCPEAK3SD4dg`, connectors cleared). Enable only after the phase 1 warehouse and phase 2 campaigns are live, the ops-web release with the engine routes is deployed, `ADS_ENGINE_TOKEN` is set in Vercel Production, the environment API credential exists, and Jackson gives the go.

| Field | Value |
|---|---|
| Routine id | `trig_01LroGoQJLg9GCPEAK3SD4dg` (created 2026-09-09 05:38 UTC, disabled) |
| Name | `OPS Google Ads engine` |
| Schedule | `0 15 * * *` UTC (08:00 Vancouver, daily) — after the 08:04 UTC warehouse sync and one minute after the 14:59 UTC worker tick |
| Model | `claude-opus-5` |
| Environment | `Default` with an API credential for host `app.opsapp.co` (Bearer `ADS_ENGINE_TOKEN`) |
| Repositories / connectors | none / none (cleared after creation; `RemoteTrigger create` attaches every connector by default) |
| Tools | `Bash, Read, Write, Edit, Agent` |
| Prompt | canonical copy in `ops-web/docs/ads/engine-routine.md`, version `ads-routine-2026-09-10-v2`; edit there first, then `/schedule update` |

What it does per run: claims today's brief over `POST /api/internal/ads/engine/claim` (duties, entity snapshot, 7/28-day metrics, funnel, tests, ledger, pending and rejected proposals, guardrails, the copy rules and brand facts, the negative-list taxonomy, the weekly market digest — `ops-web/docs/ads/engine-brief-contract.md`), works the duties OPS named (hygiene daily; creative per ad group every four weeks; structure monthly; bidding ladder on the trial-start trigger), runs an independent editor subagent on every ad it writes, files typed proposals to `…/runs/{id}/proposals`, fixes the server's fixable rejections (three submissions per proposal), and releases with a one-line-per-proposal summary. It never reaches Google: OPS validates, Jackson approves on `/admin/google-ads`, OPS applies with `validateOnly` first and labels every change. Usage draws the subscription; a refused run leaves the day's duties for tomorrow and OPS raises `ADS ENGINE STALLED` after 50 hours of silence while ads are live.

Rehearsed locally on 2026-09-08 (`ops-web/docs/artifacts/ads-engine/p3/local-e2e-2026-09-08/README.md`): the exact prompt, handed to a local Opus session against a disposable database and the worktree dev server, claimed a brief and released twice. Run 1 (prompt v1) filed four negative lists and two observations but dropped every challenger because the editor subagent never saw the brand facts; prompt v2 fixed that and run 2 filed three challengers, honoured the structural cap and the pending list, and repaired a deliberate `COPY_REJECTED` on resubmission. Approvals in the console reached Google's real account through `validateOnly` and came back `RESOURCE_NOT_FOUND` on the fixture ids, as expected; the happy path waits for phase 2's real campaigns.

Manual run: `/schedule run OPS Google Ads engine` or **Run now** at claude.ai/code/routines. Debug: `/schedule why did OPS Google Ads engine do nothing` (lists runs, reads logs). Local rehearsal recipe: `ops-web/docs/artifacts/ads-engine/p3/` (the Instagram rehearsal stack with the engine migration, a seeded warehouse fixture, and `ADS_ENGINE_REHEARSAL=1`).
