# Email inquiry boundary production release — 2026-09-09 local

Jackson explicitly approved releasing the tested correction in this task. Release completed September 9 in Edmonton, September 10 UTC. No new schema migration was needed.

## Released code and build

- Parent production commit: `78b0cff88d5932f342094487165102ebd60fa78b`.
- Published correction: `5b12d9823afee4c715d1a7e3d0a5b768ef893bd2`.
- Vercel deployment: `dpl_Gv56toLk2MK1WCosoGYgS7sZeBVu`.
- Customer URL: `https://app.opsapp.co`.
- READY: `2026-09-10T05:04:16.692Z`. A separate lookup of the customer alias returned this exact deployment and commit.
- Production compilation succeeded; full type validation passed; static generation and deployment completed. The build reported existing image-route/runtime warnings and skipped lint, so lint evidence comes from the focused local run.

The current production history was fetched and integrated in the existing isolated worktree, preserving the unrelated dirty shared checkout. The runtime source and tests are identical to the integrated, tested tree. Because the GitHub repository is public, the publishable package was committed directly over the current production parent with customer-identifying audit details omitted; the earlier private implementation/merge commits were not pushed. No shared history was rewritten or force-pushed.

## Verification

All 320 tests in 20 affected files passed again after integration, and the scoped TypeScript check passed. Exact source/test comparison between the tested integration and the published correction was empty. The earlier default-heap full local TypeScript failure is superseded for release validation by the completed Vercel production type check; it is not relabeled as a local pass.

The existing production `route_email_work_correspondence_as_system(uuid,uuid,uuid,text,text,uuid,uuid,boolean)` still has body MD5 `8df411f6c91e91901107ad2e55d56a32`, SECURITY INVOKER, empty search path, service-role execute access, and no anon/authenticated execute access. No database changes were applied.

After deployment, the already-signed-in browser reloaded `https://app.opsapp.co/pipeline?review=email`. The Pipeline and Email Review panel loaded with its authorized empty state. The existing account belongs to a different company from the audited mailbox; this proves published rendering/navigation, not access to that mailbox's messages. No account/company settings were changed.

## Read-only post-release audit

At `2026-09-10T05:06:05.256497Z`, the audited company had **zero new leads since this release** and **zero additional leads after the previously identified Wix false lead**. The mailbox remained active and sync-enabled, last synced at `2026-09-10T04:44:39.169Z`. No historical lead/client record, email state, or notification was repaired or deleted.

Regular mailbox polling uses `4-59/20 13-23,0-4 * * *` (UTC) in `ops-web/vercel.json`; the observation happened after that polling window ended. No sync was forced to manufacture evidence. There is therefore no fresh inbound-message production canary yet; zero new leads does not by itself prove classifier accuracy.

The exact deployment's error/fatal log scan covered `2026-09-10T05:04:16.692Z` through `2026-09-10T05:06:06.038Z`. It returned one catalog-preparation `CATALOG_IDEMPOTENCY_CONFLICT` on `/api/mcp` with HTTP 200, outside the changed email paths. No email-related error appeared in this short observation window. This is not a claim of a globally error-free deployment.

The correction's controlled fixtures, full production build, verified alias, read-only data check, and UI check are complete. Live classification of the next genuine incoming message remains unobserved.
