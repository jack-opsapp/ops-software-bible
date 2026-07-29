# Migrations Graveyard

Archive of production artifacts that were **deliberately killed**. Each entry preserves the
last live source so the decision is auditable and reversible. Nothing in this directory is
deployed; these are historical records.

## 2026-07-29 — Edge function tombstones (SYSTEMS REPAIR W1-1, bug `ba6a5b79`)

`delete-user` and `terminate-employee` were replaced with `410 Gone` tombstones
(`verify_jwt=true`) on prod `ijeekuhbatykdomumfjx`. The Supabase management API has no
delete operation for edge functions — the tombstone IS the kill.

**Why killed, not hardened:**

- `delete-user` let ANY valid Supabase-auth session soft-delete ANY user row **and delete
  their Supabase Auth account**. No admin check, no company check. (`verify_jwt=false`,
  CORS `*`.)
- `terminate-employee` verified the caller was an admin of the **posted** `companyId` but
  never checked that the target user belonged to that company — an admin of company A could
  strip users in any tenant.
- Zero callers at kill time. Grepped `ops-ios/`, `ops-web/` (incl. `supabase/functions/`) and
  `ops-site/` locally, plus `try-ops` and `ops-learn` — which are GitHub-only and not checked
  out locally — by downloading each repo tarball via the GitHub API and grepping the extracted
  sources. No hits in any of the five. (GitHub's *code search* returns 0 for these private
  repos even for strings that demonstrably exist, so its empty result is not evidence and was
  not relied on; the tarball grep is. Control: `functions/v1` does hit in `ops-learn`
  — `src/app/api/checkout/route.ts:27`, `stripe-create-checkout-session` — proving both that
  the grep works and that ops-learn calls edge functions, just never these two.)
  Both flows have been superseded: user deletion via the web account-deletion route,
  termination via web team management.

**Archived sources (deployed v9 of both, retrieved via management API 2026-07-29):**

| File | Provenance |
|------|------------|
| `2026-07-29-edge-fn-delete-user.ts` | `delete-user` v9, ezbr_sha256 `eccff73476f54181d439c36711761eba36bb253630f45c014af405a988546b22` |
| `2026-07-29-edge-fn-terminate-employee.ts` | `terminate-employee` v9, ezbr_sha256 `6761eecd612402d5db2c0b0286237bfb8b06d2f65f756145b08aa93aa0503182` |
| `2026-07-29-edge-fn-_shared-supabase-client.ts` | shared module bundled with both (identical in each bundle) |
| `2026-07-29-edge-fn-_shared-cors.ts` | shared module bundled with both (identical in each bundle) |

Line endings normalized to LF on archive; the `ezbr_sha256` values above identify the exact
deployed bundles for byte-level provenance.

**Restore path (do not do this without fixing the auth holes):** redeploy from these sources
with proper target-membership + admin checks and `verify_jwt=true`.
