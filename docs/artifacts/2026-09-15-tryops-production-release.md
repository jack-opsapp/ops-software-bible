# Try OPS coordinated release — 2026-09-15 UTC

Jackson explicitly approved deployment. The release reuses the existing OPS database, Vercel projects, credentials and recovery schedule. It introduces no paid vendor or subscription tier; existing traffic and storage remain subject to ordinary usage charges. Experiment, generation and publication flags are unchanged.

## Exact source and deployment identity

| Surface | Accepted source | Production state |
|---|---|---|
| TryOps | `29679e5a818e35b69fcfa4cef23040c32b024cac` | READY deployment `dpl_AMSkhLy4Ya4y9tNoHKMqyAWbQdrX`, alias `try.opsapp.co` |
| OPS-Web | `e26310f4c836868d19e4539965abb58172dd9a85` | READY deployment `dpl_ARcDA9dFLFEndpgyDo8vQa6dUhrt`, alias `app.opsapp.co` |
| Database | `20260915000120_tryops_demo_funnel.sql`, SHA-256 `1dddda94e7e3383ba6f9a5ed1402834acf56320d54d2d0b52929ce3a402a88b2` | Applied to `ijeekuhbatykdomumfjx` under ledger `20260915032402` |

The released migration mirror is `migrations/20260915032402_tryops_demo_funnel.sql`. Independent production inspection matched all 25 columns, 25 validated constraints, 12 valid indexes and five exact function bodies/signatures. The four tables have RLS enabled and zero policies; anonymous/authenticated/public access is absent, while service access matches the source. All five RPC signatures are exposed by PostgREST. Advisors reported no new-object warning or error.

OPS-Web passed its cloud production build, full type check and 484 generated pages. Four excluded live HTTP checks passed: registration responds with its client-rendered shell; missing required fields at sync-user/setup-progress/setup-complete return their precise HTTP400 validation responses. Initial probe assumptions about server-rendered form text and HTTP401 were corrected against source and retained in the evidence folder; no product change was needed. The canonical browser visit reached registration and then redirected the existing signed-in session to the dashboard as expected. The immutable deployment URL requires Vercel login. The signed-out form was therefore not re-inspected on production; its source-matched local browser acceptance and 18 focused checks remain the form evidence. No logout or new account was performed.

TryOps passed all 31 excluded live HTTP checks across eight landing pages, demo entry/handoff, legacy redirects, retired APIs and the protected cron. The initial demo probe expected hydrated task text in server HTML; source returns the native-link loading view until hydration. The probe now checks that actual server contract, while the browser independently verified the rendered task. The initial receipt is preserved.

Live browser verification covered the phone landing and all three demo states, the native trial handoff to canonical registration, desktop landing and restored completion, and Back preserving the completed task. Screenshots match the accepted presentation; desktop completion measures 1436px document width within 1440px viewport and a 52px primary control. No new TryOps runtime error/fatal log was returned in the postrelease scan at 03:52 UTC. Both exact release SHAs were read back from their READY Vercel deployments and canonical aliases.

## Visual source and local acceptance

The final TryOps release passes 234 tests across 29 files and its production build, with 46 static pages. The demo route is 49.3kB and 143kB first-load JavaScript. These are build measurements, not customer performance measurements.

The refinement changes five files relative to `262caad`: the demo view, its CSS, three motion checks and two existing test typing corrections. Landing presentation, native destinations, funnel/state code and migration source remain unchanged. Independent final geometry covers all three states at 320×568, 375×667, 390×844, 430×932, 768×1024, 844×390, 1280×720 and 1440×900, with no horizontal overflow or control below the 44px minimum. Primary demo controls are 52px.

Source-matched build, tests, screenshots and motion frames are under `/Users/jacksonsweet/Projects/OPS/docs/artifacts/tryops-demo-visual-2026-09-14/`. Production deployment/readback/probe evidence is under `/Users/jacksonsweet/Projects/OPS/docs/artifacts/tryops-release-2026-09-14/`.

## Verification boundary

Release probes use explicit QA exclusion and do not create an account, company, trial, demo ledger session or outbound message. Production OAuth, real signup/trial creation, welcome delivery, physical-device behavior and conversion lift are not established by this release verification. Existing connected local proof remains recorded in [the implementation receipt](2026-09-14-tryops-demo-verification.md).

Application rollback must retain safe retirement of the duplicate acquisition auth/messaging endpoints and the canonical signup handoff. Preserve the additive schema and any records; do not apply a destructive down migration.
