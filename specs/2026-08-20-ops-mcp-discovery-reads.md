# OPS MCP Discovery Reads — Customer and Job Resolution

**Status:** Approved product contract; implementation authorized on 2026-08-20. Local build, database migration, production exposure, and runtime acceptance remain separate gates. No write capability is introduced by this specification.

**Parent architecture:** `specs/2026-08-07-ops-agent-control-plane-mcp-foundation.md`

**Production baseline:** The remote OPS MCP endpoint is live at `https://app.opsapp.co/api/mcp` with nine read-only capabilities. Those reads are exact-reference or bounded-list tools. They do not let an operator begin with ordinary language such as “find Acme” or “the Cedar Street job.”

## 1. Decision

Add exactly two read-only capabilities:

1. `search_customers`
2. `search_jobs`

These are discovery tools. They return small, safe, source-provenanced identity cards and stable OPS references. Existing exact-reference reads remain responsible for detail.

Do not add a global search tool, a generic database query, arbitrary filters, raw SQL, or a broad entity browser.

The intended flows are:

```text
"Find Acme"
  -> search_customers
  -> list_customer_jobs
  -> get_job_summary / get_job_communication_context

"Find the Cedar Street deck job"
  -> search_jobs
  -> get_job_summary / search_job_history
```

## 2. Product behavior

### 2.1 Customer discovery

`search_customers` supports three closed lookup modes:

- `name`: ordinary client or sub-client name discovery;
- `exact_email`: exact normalized email lookup;
- `exact_phone`: exact normalized North American phone lookup.

Email and phone are lookup keys only. The result never returns an email address or phone number. Exact contact lookup requires the additional `ops.customer_contacts.read` OAuth scope. Name lookup does not.

Partial, fuzzy, prefix, domain-only, or substring email/phone lookup is forbidden. A caller cannot search `@gmail.com`, the last four phone digits, or a partial address. This prevents contact data from becoming an enumeration surface.

### 2.2 Job discovery

`search_jobs` discovers visible opportunities and projects by:

- job title;
- job address;
- lifecycle state;
- opportunity stage;
- project status;
- created or updated time window;
- visible assignment scope already carried by the actor's current permission.

Customer-name discovery composes through `search_customers` followed by `list_customer_jobs`. `search_jobs` does not independently search customer names or contact data, because a jobs-only grant must not inherit customer-contact authority.

The result may return the safe job title and address already available through the job-summary boundary. It does not return descriptions, notes, correspondence, crew details, financials, contact channels, or document/media contents.

Converted opportunity/project pairs follow the Task 13 identity rule: filter each source first, pair only a current reciprocal same-client pair, and return one canonical project card. If only one side is visible or qualifies, return that side with the matching non-leaking `linked_*_not_returned` state.

## 3. Input contracts

### 3.1 Shared query rules

Every free-text discovery query is:

- Unicode NFKC normalized;
- trimmed and whitespace-collapsed;
- 2–200 Unicode scalar values after normalization;
- at most eight tokens;
- at most 64 characters per token;
- rejected if it contains C0/C1 controls, bidi override/isolate controls, an unpaired surrogate, or a NUL;
- interpreted literally. `%`, `_`, `\\`, regex characters, quotes, SQL metacharacters, and prompt-like text have no wildcard or instruction semantics.

The shared discovery normalizer preserves business words and non-ASCII letters. It must not reuse duplicate-detection normalization that strips suffixes such as “Construction” or “Ltd.”

### 3.2 `search_customers`

```ts
type SearchCustomersInput =
  | {
      lookup: "name";
      query: string;
      customer_kinds?: ("client" | "sub_client")[];
      cursor?: string;
      limit?: number;
    }
  | {
      lookup: "exact_email";
      query: string;
      customer_kinds?: ("client" | "sub_client")[];
      cursor?: string;
      limit?: number;
    }
  | {
      lookup: "exact_phone";
      query: string;
      customer_kinds?: ("client" | "sub_client")[];
      cursor?: string;
      limit?: number;
    };
```

- `customer_kinds` defaults to both kinds and must be unique.
- `limit` defaults to 10 and is bounded to 1–25.
- `cursor` is a signed opaque operational-read cursor, maximum 512 characters.
- Email is lowercased and syntax-validated before exact comparison.
- Phone accepts a ten-digit NANP number or `+1` plus ten digits after punctuation removal. Any other country code, extension, alphabetic vanity form, or digit count is rejected in v1 rather than guessed.

### 3.3 `search_jobs`

```ts
type SearchJobsInput = {
  query?: string;
  query_fields?: ("title" | "address")[];
  job_kinds?: ("opportunity" | "project")[];
  lifecycle_states?: ("active" | "terminal" | "archived")[];
  opportunity_stages?: OpportunityStage[];
  project_statuses?: ProjectStatus[];
  date_window?: {
    field: "created_at" | "updated_at";
    from: Rfc3339UtcTimestamp;
    to_exclusive: Rfc3339UtcTimestamp;
  };
  cursor?: string;
  limit?: number;
};
```

- At least one of `query`, lifecycle/status filters, or `date_window` is required.
- `query_fields` defaults to title and address, is unique, and is invalid without `query`.
- `job_kinds` defaults to opportunity and project.
- Opportunity/project filters are valid only when the matching kind is selected.
- The date window is positive and no longer than 365 days.
- `limit` defaults to 10 and is bounded to 1–25.
- No caller-controlled rank threshold, sort expression, column name, or direction exists.

## 4. Output contracts

Both tools return the standard strict `AgentResult` envelope, one mandatory collection proof even for an empty result, one projection evidence atom per retained match, bounded source versions/evidence, and the shared untrusted-business-data directive.

### 4.1 Customer match

```ts
type CustomerDiscoveryMatch =
  | {
      customer_ref: { kind: "client"; id: UUID };
      display_name: string;
      relationship: { kind: "primary_client" };
      match_basis: {
        ranking_revision: "customer-discovery-ranking:v1";
        kind:
          | "exact_name"
          | "prefix_name"
          | "all_tokens_name"
          | "exact_email"
          | "exact_phone";
      };
      content_kind: "untrusted_business_data";
      visibility_reason: "current_actor_authorized";
      evidence_ids: [OpaqueId];
    }
  | {
      customer_ref: { kind: "sub_client"; id: UUID };
      display_name: string;
      relationship: {
        kind: "sub_client";
        parent_client_ref: { kind: "client"; id: UUID };
        parent_display_name: string;
      };
      match_basis: CustomerMatchBasis;
      content_kind: "untrusted_business_data";
      visibility_reason: "current_actor_authorized";
      evidence_ids: [OpaqueId];
    };
```

The customer result contains `matches`, `returned_match_count`, `result_budget_omitted_count`, and fixed gaps. It never contains contact values, addresses, notes, relationship totals, match scores, or hidden-record counts.

### 4.2 Job match

```ts
type JobDiscoveryMatch = {
  job_ref: CurrentJobRef;
  anchor_refs: CurrentJobRef[];
  display_title: string;
  address: string | null;
  lifecycle_state: NormalizedJobLifecycleState;
  status: JobStatus;
  dates: JobDates;
  conversion: Task13Conversion;
  match_basis: {
    ranking_revision: "job-discovery-ranking:v1";
    kind:
      | "filter_only"
      | "exact_title"
      | "prefix_title"
      | "all_tokens_title"
      | "exact_address"
      | "prefix_address"
      | "all_tokens_address";
    field: "none" | "title" | "address";
  };
  content_kind: "untrusted_business_data";
  visibility_reason: "current_actor_authorized";
  evidence_ids: [OpaqueId];
};
```

The job result contains `matches`, `returned_match_count`, `result_budget_omitted_count`, and fixed gaps. A result is not evidence that an inaccessible alias or linked record exists.

### 4.3 Bounds and completeness

- The ordered authorized candidate set is hard-capped with a 501st-row sentinel; no unbounded exact total is computed and the sentinel produces a fixed query-bound state.
- Each page uses `limit + 1` (at most 26 rows) to prove whether another page exists.
- At most 25 matches are returned.
- At most 26 projection source versions/evidence atoms are retained: 25 children plus one collection proof.
- The public serialized result is at most 60,000 characters.
- Reduction is one deterministic ordered prefix. Match and proof are removed atomically.
- `result_budget_omitted_count` reports only claims removed by the 60,000-character service bound.
- Source oversize/malformed state is a fixed, proof-bound gap or fixed typed error; it is never silently treated as complete.

## 5. Ranking and pagination

### 5.1 Ranking

Ranking is deterministic and versioned, not a confidence score:

1. exact normalized value;
2. normalized prefix;
3. every normalized query token occurs literally;
4. source-kind tie break;
5. normalized display value under bytewise `C` collation;
6. UUID under bytewise ordering.

The all-token-contains tier is eligible only when every query token is at least three characters. Two-character queries remain useful through exact and normalized-prefix matching, which the bytewise prefix index can prove without a tenant-wide scan. One-character tokens are rejected. This is a performance and enumeration boundary, not silent query reinterpretation.

For jobs, title precedes address at the same textual tier. Filter-only results order by the selected date field descending, then kind and UUID. SQL assigns the final ordered, actor-visible candidate set a stable `rank_ordinal` only after applying a hard 501-candidate materialized gate. A 501st candidate produces the fixed query-bound state instead of false pagination completeness.

Phase 1 deliberately excludes typo similarity, phonetic matching, stemming, synonym expansion, embeddings, LLM ranking, and caller-selected weights. Those techniques can silently reinterpret customer identity and require separate evidence.

### 5.2 Cursor

Extend the existing nominal operational cursor with customer-discovery and job-discovery claim variants. Every cursor binds:

- capability ID, capability schema revision, manifest revision, and ranking revision;
- actor, company, permission snapshot, and source revision;
- canonical cursor-free input hash;
- read-as-of database time;
- the exact last retained `rank_ordinal` plus source kind and UUID identity guard;
- issued/expiry times under the existing maximum one-hour TTL.

A changed query, actor, company, permission snapshot, source revision, ranking revision, or result order invalidates the cursor. The next page recomputes the bounded ranking only under the unchanged source revision/read time and resumes after the stored ordinal. This avoids placing an arbitrarily long customer/title/address value in the 512-character cursor. Permission drift produces the existing stale-permission error rather than a generic parse error.

## 6. Authority and privacy

### 6.1 `search_customers`

Name mode requires:

- OAuth `ops.customers.read`;
- `clients.view:all|assigned`;
- current same-company actor and grant;
- current row-level client/sub-client visibility in the same SQL statement.

Exact email/phone mode additionally requires:

- OAuth `ops.customer_contacts.read`.

The stronger contact scope authorizes use of the exact lookup key, not disclosure of the stored value.

Authoritative rows are current canonical, non-deleted, non-merged `clients`, plus current non-deleted `sub_clients` whose current parent client is canonical and visible. A hidden/deleted/merged parent makes the sub-client absent.

### 6.2 `search_jobs`

Every selected job-kind branch is independently required:

- OAuth `ops.jobs.read`;
- opportunity branch: `pipeline.view:all|assigned`;
- project branch: `projects.view:all|assigned`.

The service-role RPC re-resolves the current actor permission snapshot and row authority. RLS is defense in depth, not the authority source. Hidden and nonexistent rows have indistinguishable empty behavior.

### 6.3 Forbidden sources and fields

Neither tool reads or projects:

- raw email bodies, subjects, notes, descriptions, OCR, filenames, URLs, or attachments;
- `ops_contacts`, public-site `contact_messages`, unscoped address books, or inferred contacts;
- private employee email/phone/home/emergency/HR fields;
- financial, estimate, invoice, expense, payment, inventory, or supplier data;
- suppression reason/source metadata;
- deleted, merged, superseded, or cross-company records.

All returned business strings are explicitly untrusted data. They cannot alter authority, choose tools, or become instructions.

## 7. Database boundary

Create one new transactional migration containing:

- a strict immutable discovery-text normalizer shared by indexes and RPCs;
- strict exact email and NANP phone normalizers;
- partial GIN trigram expression indexes for active client/sub-client names and opportunity/project titles/addresses;
- supporting keyset indexes for the fixed filter-only paths;
- one service-role-only `SECURITY DEFINER` JSONB RPC per capability;
- fixed search path, explicit prerequisite checks, explicit `REVOKE`/`GRANT`, database-clock reads, and hard candidate sentinels;
- same-statement actor/permission/entity/source-fence capture;
- mandatory child and collection projection proofs.

The migration must not edit an applied migration. Advancing the manifest requires a v7 compatibility bridge for every existing v6 read. The bridge must re-prove the complete JSON projection under v7 in the same statement; a TypeScript-only relabel or acceptance of v6 proofs under v7 is forbidden.

`pg_trgm` is already installed in production. The migration must not pin an extension version because Supabase ignores explicit extension versions as of August 2026.

Before external exposure, run `EXPLAIN (ANALYZE, BUFFERS)` on production-shaped fixtures for exact, prefix, contains, two-character, assigned-scope, address, and filter-only queries. A sequential scan over the whole tenant/source table or an unbounded source expansion blocks rollout.

## 8. Integration boundary

Add strict contracts, closed selectors, nominal authorization proofs, nominal repositories, pure reducers/services, and facade methods. Extend the all-or-nothing trusted repository bundle. Add MCP dispatch only through the server-owned capability-to-domain map.

Mint a new immutable capability-manifest revision. Both discovery entries initially land as:

```text
implementation = unavailable
externalExposure = disabled
```

They move to internal available only after SQL/repository/service integration is green, then to external enabled only after the migration is applied and read back in the target catalog. The existing nine reads must remain functional through the manifest upgrade.

Discovery uses the `evidence_search` rate bucket and must enforce actor + grant + company ceilings. The existing grant/company-only fallback is insufficient for these enumeration-adjacent tools.

## 9. Verification and rollout

### 9.1 Required tests

- strict input parsing with zero repository reads on invalid input;
- exact contact lookup selects the stronger authorization variant;
- partial email/phone queries are rejected;
- cross-company, assigned/all, deleted, merged, hidden-parent, and revoked-grant cases;
- duplicate names and duplicate exact contact keys;
- literal `%`, `_`, `\\`, quotes, Unicode, controls, bidi, and prompt injection;
- opportunity/project filter coupling and reciprocal conversion conflicts;
- deterministic rank/order and cursor continuation;
- cursor actor/company/query/permission/source/ranking/TTL tampering;
- mandatory empty collection proof;
- child/collection hash, source, evidence, locator, order, and count tampering;
- abort before call, transport cancellation, and non-cooperative after-await cancellation;
- 25-item, 26th-sentinel, evidence/source, and 60,000-character bounds;
- absence of every forbidden field;
- MCP listing/dispatch/audit/rate-limit/untrusted-serialization behavior;
- all existing nine reads under the new manifest revision.

### 9.2 Promotion gates

1. Local focused tests, the full agent-control-plane suite, Node 22 TypeScript, formatting, and diff checks are green.
2. Independent P0/P1 review is clean.
3. Migration parses and compiles against a catalog-equivalent disposable database.
4. Migration applies in the authorized environment; signatures, grants, indexes, and manifests read back exactly.
5. Internal canaries prove exact/prefix/token/filter modes, assigned scope, duplicate identities, revocation, cursors, and audit records.
6. External manifest exposure is a separate reviewed commit/deploy.
7. A real Claude session finds a known customer and job, then uses existing detail reads with no unauthorized fields or writes.
8. Rollback restores the prior external nine-tool surface without breaking those reads.

No production apply, push, deploy, or external exposure is implied by local implementation approval.

## 10. Cost

This design uses existing Supabase Postgres, Vercel, OAuth, audit, and MCP infrastructure. It requires no new paid vendor or plan. Incremental cost is limited to indexed database storage, bounded query CPU, function invocations, audit rows, and MCP result traffic. Query-plan verification and strict rate limits are mandatory before exposure so discovery cannot become an unbounded cost surface.

## 11. What follows

After these two tools work in a real Claude workflow, continue read-only coverage in this order:

1. tasks;
2. site visits;
3. job media/document metadata;
4. estimates;
5. invoices and bounded payment ledger;
6. expenses/reimbursements;
7. catalog/inventory;
8. safe company/team context.

Only after the full approved read catalogue passes the production acceptance gate should OPS build the shared prepare → authenticated confirmation → commit mutation kernel. The future order is catalog, draft-only estimate import, project cost allocation, site visits, then communication draft/send. No generic CRUD or raw database executor is ever permitted.
