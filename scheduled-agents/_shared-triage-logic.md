# Shared Triage Logic — Nightly Bug Agents

This file is the **single source of truth** for how the nightly bug-triage agents behave. The platform-specific prompts (`nightly-bug-triage-ios.md`, `nightly-bug-triage-web.md`) inherit from this doc. When logic changes, change it here and the platform prompts only hold environment (repo path, build command, code ownership).

---

## Data model

Two tables feed the backlog. Both share the same processing contract.

| Table | Source | Shape of the bug |
|---|---|---|
| `public.bug_reports` | User-submitted via the OPS-Web bug button and the iOS Feedback screen | Free-text description + auto-captured context (console, breadcrumbs, screen, URL) |
| `public.qa_bugs` | OpenClaw QA agent | Structured — `title`, `steps`, `expected_behavior`, `actual_behavior`, `suspected_file`, `suspected_component` |

Both tables have these triage fields (migration `bug_reports_triage_fields` brought `bug_reports` to parity with `qa_bugs`):

- `status` — `new` / `triaged` / `in_progress` / `resolved` / `closed` / `duplicate`
- `requires_human_review` (bool) — reporter or agent flag meaning "autonomous fix impossible"
- `human_review_reason` (text) — short explanation
- `fix_branch`, `fix_pr_url`, `fix_commit`, `fix_notes` — populated by this agent
- `claimed_at` — stops double-claims across concurrent runs
- `fixed_at` — set on commit

Agents **do not** talk to Postgres directly. All access goes through the HTTP API below — it's auth-scoped, field-whitelisted, and keeps the service-role key off agent surfaces.

---

## HTTP API (single source of DB access for agents)

Base URL: `https://app.opsapp.co`

All endpoints require header `Authorization: Bearer $BUG_TRIAGE_AGENT_TOKEN`. The token is supplied in the cron prompt at registration time. Do NOT log it, echo it in PR descriptions, commit messages, or any file the agent writes.

### `GET /api/cron/bug-triage/backlog?platform={ios|web}&limit={1..500}`

Returns the unified, unclaimed backlog for one platform. Applies these filters:

- `status in ('new', 'triaged')`
- `requires_human_review = false`
- `false_positive = false` (qa_bugs only)
- `claimed_at is null OR claimed_at < now() - 6h`

Response:
```json
{
  "platform": "ios",
  "fetched_at": "2026-04-24T10:00:00Z",
  "count": 17,
  "bugs": [
    {
      "id": "uuid",
      "source": "bug_reports" | "qa_bugs",
      "summary": "truncated to 800 chars",
      "category": "bug" | "ui_issue" | "crash" | "feature_request" | "other",
      "severity_signal": "urgent|high|medium|low|none" | "critical|high|medium|low",
      "screen_or_url": "/dashboard",
      "suspected_file": "path/to/file.ts" | null,
      "suspected_component": "ComponentName" | null,
      "sort_ts": "2026-04-24T02:00:00Z"
    }
  ]
}
```

The 6-hour claim expiry handles stuck runs — a bug claimed by a crashed prior run becomes eligible again.

### `GET /api/cron/bug-triage/bug?id={uuid}&source={bug_reports|qa_bugs}`

Returns the full row. Agents call this after picking a bug from the backlog so they have console_logs, breadcrumbs, state_snapshot, reproduction steps, etc.

### `POST /api/cron/bug-triage/update`

Batch writes. Whitelisted columns only (`status`, `claimed_at`, `fixed_at`, `fix_branch`, `fix_commit`, `fix_notes`, `fix_pr_url`, `requires_human_review`, `human_review_reason`). Any other key in `updates` is silently dropped — immutable columns (`description`, `category`, `platform`, reporter fields) cannot be touched.

Body:
```json
{
  "items": [
    {
      "id": "uuid",
      "source": "bug_reports",
      "updates": {
        "status": "in_progress",
        "claimed_at": "now",                    // "now" is a sentinel for server-time
        "fix_branch": "nightly/bugs-web-...",
        "fix_commit": "abc123",
        "fix_notes": "Root cause: ...",         // REPLACES existing notes
        "fix_notes_append": "REVIEW PASS: ...", // APPENDS to existing notes
        "fix_pr_url": "https://github.com/...",
        "fixed_at": "now",
        "requires_human_review": true,
        "human_review_reason": "Ambiguous repro steps"
      }
    }
  ]
}
```

Response: `{ "updated": N, "errors": [{ "id", "source", "error" }] }`.

Constraints:
- Max 50 items per request.
- `status` cannot be set to `resolved` or `closed` by an agent — only humans merge PRs, and a separate process flips status on merge.
- Use `fix_notes_append` when adding review-pass notes or incremental context — prevents clobbering prior agent state.

---

## Orchestrator loop (you, the cron agent)

You are the orchestrator. **You do NOT fix bugs yourself.** You delegate fixes to fresh sub-agents so your context stays lean across a long backlog drain.

### Per-run flow

1. **Fetch backlog** via `GET /api/cron/bug-triage/backlog`. Cap at 200 rows (safety); typical nights will be far smaller.
2. **Split into batches of 10.** Oldest first. A batch should ideally be cohesive — prefer grouping by `suspected_component` or `screen_or_url` when the fetch returns clustered hits, but don't spend orchestrator cycles optimizing this.
3. **For each batch, sequentially:**
   1. Claim the batch via `POST /api/cron/bug-triage/update` with each item's `updates: { status: "in_progress", claimed_at: "now" }`.
   2. Spawn a fresh **Batch Fix Agent** via the `Agent` tool (`subagent_type: general-purpose`) with the prompt in `_batch-fix-prompt.md` populated with this batch's bugs.
   3. Wait for the sub-agent to return. It will produce: PR URL, list of fixed bug IDs, list of `requires_human_review` promotions, list of bugs classified as "complex" needing review-pass.
   4. If complex bugs exist, spawn a fresh **Review Pass Agent** via `_review-pass-prompt.md` targeting that PR.
   5. Continue to the next batch.
4. **Stop conditions:**
   - Backlog empty.
   - 20 batches processed (hard cap of 200 bugs / run).
   - 2 consecutive batches had sub-agent failures — pause, surface the error, do not burn more API spend.

### Complex-bug classifier

A bug is "complex" (and triggers a review pass) if ANY of:

- `category = 'crash'`
- `source = 'qa_bugs'` AND `severity in ('high', 'critical')`
- `summary` matches (case-insensitive) any of: `auth`, `login`, `password`, `sign in`, `sign-in`, `onboarding`, `sync`, `offline`, `data loss`, `payment`, `billing`, `subscription`, `lockout`, `permission`, `access`, `crash`, `freeze`, `hang`
- `suspected_file` (qa_bugs) is within any of: `DataController`, `SyncManager`, `ModelActor`, `Auth`, `SubscriptionStore`, `PermissionStore`, `Onboarding`, `Stripe`, `webhook`

Simple bugs (copy changes, spacing, typos, one-line SwiftUI modifier tweaks) skip the review pass.

---

## Batch Fix Agent contract

This sub-agent does the actual coding. Its prompt (`_batch-fix-prompt.md`) is self-contained — it receives only the 10-bug batch, not the full backlog. Its deliverables:

1. **One branch per batch:** `nightly/bugs-{platform}-{yyyy-mm-dd}-batch-{NN}` cut from `main`.
2. **One commit per bug** on that branch. Commit message: `fix(bug-{short-id}): {summary}` — so each bug can be cleanly reverted or cherry-picked.
3. **One PR per batch** titled `Nightly Bug Sweep — {platform} — {date} — Batch {NN}` with a body listing each bug with its DB ID, short description, and a one-paragraph explanation of the fix.
4. **Build verification** (see platform prompts for the exact command). On build success: commit + push. On build failure: try to fix the build error if clearly related to the current change, otherwise skip this specific bug (leave it in `triaged` with `requires_human_review = true` and `human_review_reason = 'Nightly agent: build failed — pre-existing issue or complex dependency. Needs human diagnosis.'`), continue with the rest of the batch.
5. **Per-bug row updates** after each commit — via `POST /api/cron/bug-triage/update`:
   ```json
   {
     "items": [{
       "id": "{bug_id}",
       "source": "{table}",
       "updates": {
         "fix_branch": "{branch}",
         "fix_commit": "{sha}",
         "fix_notes": "Root cause: ... Fix: ... Edge cases considered: ...",
         "fix_pr_url": "{pr_url}",
         "fixed_at": "now"
       }
     }]
   }
   ```
   `status` stays `in_progress` — it flips to `resolved` only after a human merges the PR (the API rejects agent attempts to set resolved/closed).
6. **Escalation:** If the agent reads the bug and determines a fix needs reporter clarification (ambiguous steps, can't reproduce, user describes desired behavior unclearly), set `requires_human_review: true` with a reason via the update endpoint — do NOT guess.
7. **Return value to orchestrator:**
   ```
   {
     batch_id: "nightly/bugs-web-2026-04-24-batch-01",
     pr_url: "https://github.com/...",
     fixed: [ { id, table, commit, complex: true|false } ],
     escalated: [ { id, table, reason } ],
     failed: [ { id, table, error } ]
   }
   ```

---

## Review Pass Agent contract

After a batch PR lands, for each bug in that PR marked `complex: true`, spawn a fresh review agent. It has no memory of the fix — that's the point.

Its prompt (`_review-pass-prompt.md`) gets: the PR URL, the bug ID + description, and the diff hunks touching that fix.

Its job:

1. Read the bug report / qa_bug row in full (not just the summary).
2. Read the relevant diff hunks.
3. Wargame edge cases:
   - Race conditions, concurrency
   - Offline / poor-network paths
   - Auth state (signed-out, expired token, cross-tenant)
   - Permission boundaries (role, company scope)
   - Empty / null / extreme values
   - Pre-existing callers of the changed code
4. For each concern found, post a PR comment on the relevant line via `gh api` (not a top-level review comment — line-anchored).
5. Append a summary comment at the top of the PR: `REVIEW PASS :: {n} concerns :: block=yes|no`. If any concern is blocking, ping the human.
6. Update the bug row via `POST /api/cron/bug-triage/update` using `fix_notes_append` so prior fix notes aren't clobbered:
   ```json
   { "items": [{ "id": "{bug_id}", "source": "{table}", "updates": { "fix_notes_append": "REVIEW PASS ({date}): {review_summary}" } }] }
   ```

---

## What NOT to do

- **Do not** edit any bug with `requires_human_review = true`. Skip silently.
- **Do not** batch-merge PRs. Humans merge. The agent only opens PRs.
- **Do not** force-push. Never.
- **Do not** amend commits from prior batches. If a regression is found in a prior batch's PR, open a new bug report referencing it.
- **Do not** touch `closed` / `resolved` / `duplicate` rows.
- **Do not** attempt to close the loop by marking a bug `resolved`. Only humans merge PRs; a post-merge webhook or a separate agent flips `status = 'resolved'`. (This bible entry is the only place that boundary is stated — respect it.)

---

## Logging

Every orchestrator and sub-agent run writes to `ops-software-bible/scheduled-agents/runs/{platform}/{yyyy-mm-dd}.md` (append-only) with:

- Start time, end time
- Backlog size at fetch
- Batches processed + PR URLs
- Complex bugs surfaced + review outcomes
- Escalations
- Failures

These run logs are the breadcrumb trail for the human operator's morning review.
