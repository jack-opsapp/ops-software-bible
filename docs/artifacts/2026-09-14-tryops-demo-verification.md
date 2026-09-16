# Try OPS demo verification — September 14, 2026

> Subsequent release: both applications and the additive schema are live. See [the September 15 production release record](2026-09-15-tryops-production-release.md) for exact identities and live proof. The original local verification below is retained as historical evidence.

Local implementation; migration unapplied, applications unreleased. No production signup or email was performed.

## Exact source

- TryOps `262caad0a229a43ff2b007e8a7571a578adf7ef5`, integration branch `feat/tryops-demo-integration`, based on `1f069341c2fefe9d7b18489a7bd6664e68bab480`.
- OPS-Web `e26310f4c836868d19e4539965abb58172dd9a85`, integration branch `feat/tryops-demo-web-integration`, based on `b5b0cb59275f0addf923db608b1daeac4afca844`.
- Pending migration `20260915000120_tryops_demo_funnel.sql`, SHA-256 `1dddda94e7e3383ba6f9a5ed1402834acf56320d54d2d0b52929ce3a402a88b2`; byte-identical mirror under `migrations/pending/`.
- Remote main revisions were read back on September 15 at approximately 00:55 UTC and matched both integration bases. The integration commits have not been pushed or merged into shared main.

## Behavior and proof

One `/demo` uses a prefilled fictional siding-repair task. Assigning the sample crew reveals its address, note and before-work photo; a second explicit action completes that sample task. Back preserves sample truth; Restart resets it. Safe native trial/Exit links remain available during initialization and failure recovery. The optional landing link follows screenshot selectors, preserving early product proof and the primary direct-registration action.

TryOps passes 231 checks across 28 files and a production build on the stated revision. Built `/demo` is 5.22kB route size and 98.1kB first-load JS. These bundle figures do not establish customer load time or field Core Web Vitals.

The PM's five focused Web suites pass 35 checks; independent Web verification passes 75 checks including 40 welcome-service cases. Eighteen final registration/shared-button checks pass on the stated Web revision, including English/Spanish accessible invite controls, cancellation/reopen and provider-context behavior. Nine changed Web server files have zero focused type diagnostics. Whole-Web type checking reached the existing 4GB heap limit; no whole-Web build/type pass is claimed.

Eleven connected groups ran independently through the real source handlers, local HTTP/PostgREST and PostgreSQL 17. They cover service-only privileges/RLS, replay, expiry, immutable verified identity, actual canonical company/trial RPC behavior, delayed recovery, a queue with 110 invalid actors preceding a valid trial and concurrent unique welcome claims. Twenty-seven source inputs matched the PM integrated trees. Local fake Firebase identities isolate the test: this is not deployed OAuth/browser identity proof. The email sender was never called.

Built legacy-route verification passed 31 owner and 39 independent HTTP cases. A production-only `/download` redirect without Location was reproduced and fixed by making that route dynamic. The two suites overlap and must not be summed as unique checks. Later combined changes are landing presentation only.

All three demo states were inspected at 320×568, 390×844, 430×932, 844×390, 768×1024 and 1440×900; 375×667 also verifies the short-phone footer correction. Native navigation, same-task continuity, keyboard/focus, Back/Restart/reload, 44px targets and 52px demo primaries were reviewed. The separately authorized landing refinement received independent source/image acceptance on the combined revision.

The final registration correction was independently inspected at 320×568 and 390×844, collapsed and expanded. Document widths remain 314px/384px respectively, within the viewport. Submit remains 52px, reveal/Cancel 44×44px and input height 48px; named invite controls, autofocus, keyboard cancel and password toggle pass. PM inspected the corrected images; `qa/registration-evidence.json` pins the measurements. The equivalent QA Web preview revision is `af28d35c0`.

The project proof directory is `/Users/jacksonsweet/Projects/OPS/docs/artifacts/tryops-demo-build-2026-09-14/`: PM `report.md`, `integration/final-tests.txt`, `integration/tryops-build.txt`, `integration/register-final-tests.txt`, `integration/connected-source-match.json`, independent `qa/final-review.md`, `qa/browser-evidence.json`, `qa/connected-receipt.json`, `qa/http-acceptance.json`, and owner `funnel/rollout.md`. Each worker's `skills-used.md` records exact skill/reference use and supporting-material limitations.

## Release and rollback boundary

Required approval covers the exact additive migration and both application releases. Apply the migration to the existing OPS app database, read back four tables/five service-only functions and privileges, release OPS-Web, then TryOps, and verify deployed excluded routes. Existing experiment, generation and publication flags remain unchanged. Existing credentials and the daily 09:00 UTC authenticated cron are reused.

The migration has no destructive down step. For application rollback, retain safe legacy retirement and native canonical registration; do not restore the retired duplicate auth/messaging endpoints or false setup-ready page. Optional collection can be removed in a reviewed rollback build while preserving canonical account creation and truthful setup-save behavior. Any production grant revocation or rollback deployment needs its own explicit authority.

No new paid service or tier was introduced. Existing Vercel/Supabase traffic and storage usage can incur incremental charges according to plan allowances. No dollar estimate or free-use guarantee is established.

## Limits

No conversion lift, ordinary-user timing, completion rate, physical-phone/browser/OAuth custody, production account/trial or welcome delivery was measured. Reduced-motion and safe-area code exist, but actual preference changes, screen-reader speech and device font scaling were not exercised. Demo measurements are diagnostics, not real activation or first-value events.

Browser delivery retries are bounded and are not a durable offline queue. A database outage before successful staging can lose attribution; exhausted staging is logged. Recovery is bounded to 100 due bindings per existing daily cron invocation. Five minutes is only the earliest eligible retry timestamp, not a five-minute recovery promise.
