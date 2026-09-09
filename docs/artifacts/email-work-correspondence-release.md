# Existing-job correspondence production release — 2026-09-09

Jackson explicitly approved applying the database migration and releasing the fix in this task.

## Database

- Supabase project: `ijeekuhbatykdomumfjx`.
- Applied migration name: `email_existing_job_correspondence`; production journal version: `20260909061758`.
- Canonical source: ops-web `supabase/migrations/20260909051427_email_existing_job_correspondence.sql` (the source filename retains its CLI generation time).
- Function-body MD5 `8df411f6c91e91901107ad2e55d56a32` independently matches the deployed function's `pg_proc.prosrc`.
- Function is SECURITY INVOKER with empty search path. Execute permission: service_role yes; anon no; authenticated no.
- 21 isolated PostgreSQL checks passed, including current notification nullability/uniqueness and shared-mailbox recipient absence. An initial attempt hit temporary local process exhaustion and was rerun successfully.

## Production database canary

A service-role canary used the reported source's exact current customer/subcontact/project relationship. Disposable probe activities exercised project routing, uncertain review, notification idempotence and acknowledgement replay through the deployed function and real production triggers. The existing lead-owned source was rejected by the ownership guard.

All probe activity, notification, attachment-scan and revision-trigger writes were rolled back in a caught subtransaction before verifying zero residue. No provider calls, customer messages, lead cleanup or persistent customer-record mutations occurred. This is database runtime proof; it does not claim a new incoming provider message was processed end-to-end.

## Web

- Refreshed production main at `27ee6d8ad`, merged cleanly, and pushed only the isolated repair plus that existing production ancestry.
- Release commit: `d86d5664b479d6ea8dfe1ae334a03645aa137efb` (includes initial implementation `61a806b4e`).
- Vercel deployment: `dpl_93Q6ULmXZax9TYDNzFxck6Utxp36`.
- Production build compiled successfully, completed full type validation and deployed in approximately seven minutes. Deployment READY at `2026-09-09T06:26:16Z`. A separate lookup of `app.opsapp.co` resolves to this exact deployment/commit.
- Before release: 333 distinct Vitest tests across 11 relevant suites passed; targeted TypeScript and changed-source lint passed. Lint reported 14 existing console warnings.

## Verification limits

The overnight schedule does not currently run the email-sync cron, so no production cron was forced to manufacture runtime evidence. The existing incorrect lead remains unchanged. The application release addresses future creation/routing; any historical cleanup requires its own exact scope.

## Published UI and observability

After the customer alias switched, the signed-in browser was reloaded at `https://app.opsapp.co/pipeline?review=email`. EMAIL REVIEW opened with NEEDS REVIEW selected and the account-scoped empty state. This smoke test used the browser's existing account in a different company, so it verifies published navigation/rendering, not access to Canpro's correspondence. No account, company, lead or mailbox settings were changed.

The exact deployment's runtime error/fatal log scan from `06:26:16Z` to `06:27:14Z` returned no matching logs. The affected route error-cluster scan was also clear. This is a short release observation window, not a claim of perpetual error-free operation or a new incoming-message canary. All verification probes were rolled back and customer history remained intact.
