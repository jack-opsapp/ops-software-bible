# Scheduled Agents

Autonomous Claude Code runs triggered on cron. Each run drains the platform's bug backlog without blocking on the operator.

## Files in this directory

| File | Purpose |
|---|---|
| `_shared-triage-logic.md` | **Read first.** Single source of truth for batching, claiming, sub-agent delegation, complex-bug classification, and escalation rules. |
| `_batch-fix-prompt.md` | Template prompt for the fresh sub-agent that fixes one 10-bug batch. |
| `_review-pass-prompt.md` | Template prompt for the second-opinion wargame agent invoked on complex bugs after a batch PR lands. |
| `nightly-bug-triage-ios.md` | iOS cron entry point. Working dir, build command, owned paths, iOS patterns. |
| `nightly-bug-triage-web.md` | Web cron entry point. Working dir, build command, owned paths, web patterns. |
| `runs/{platform}/{yyyy-mm-dd}.md` | Per-run log, append-only. Created automatically by each run. |

## Flow

```
[Cron fires 0 10 UTC]
        │
        ▼
[Orchestrator agent] ───────► reads _shared-triage-logic.md
        │                     reads platform-specific prompt
        │
        ├── query backlog (bug_reports ∪ qa_bugs, platform-scoped, unclaimed)
        ├── split into batches of 10
        │
        ▼
   ┌─────────────────────────────────────────────────┐
   │ For each batch (sequential, not parallel):      │
   │   ┌─────────────────────────────────────────┐   │
   │   │ Batch Fix Sub-Agent (fresh context)     │   │
   │   │ • branches from main                    │   │
   │   │ • commits once per bug                  │   │
   │   │ • runs platform build                   │   │
   │   │ • opens one PR per batch                │   │
   │   │ • returns JSON to orchestrator          │   │
   │   └─────────────────────────────────────────┘   │
   │                      │                           │
   │                      ▼                           │
   │          complex bugs in batch?                  │
   │              │yes         │no                    │
   │              ▼             ▼                     │
   │   ┌─────────────────┐  (next batch)              │
   │   │ Review Pass     │                            │
   │   │ Sub-Agent       │                            │
   │   │ (one per bug)   │                            │
   │   │ • wargames edge │                            │
   │   │ • posts line    │                            │
   │   │   comments      │                            │
   │   │ • top summary   │                            │
   │   └─────────────────┘                            │
   └─────────────────────────────────────────────────┘
        │
        ▼
   [Orchestrator writes run log, exits]
```

## What the operator does in the morning

1. Check `runs/{platform}/{today}.md` for the summary.
2. Review the PRs opened overnight. Look for `REVIEW PASS :: BLOCK MERGE` comments first.
3. Merge what's safe. Comment on PRs that need iteration.
4. Check the `bug_reports` and `qa_bugs` tables for rows with `requires_human_review = true` — those are the ones the agent couldn't handle and need the operator's input.

## Adding a new platform

1. Create `nightly-bug-triage-{platform}.md` modeled on the iOS or Web version.
2. Register a new cron via `/schedule` pointing at that prompt.
3. Ensure the platform's value exists in the `bug_reports.platform` / `qa_bugs.platform` check constraints (currently `'ios'` and `'web'` only — add via migration).

## Changing the rules

Edit `_shared-triage-logic.md`. Both platform crons inherit from it, so a single edit updates both.

## Never

- Never remove the `requires_human_review` gate. It's the only escape hatch.
- Never let an agent merge its own PR.
- Never run these agents against a branch that is not `main` without explicit operator opt-in.
- Never skip build verification wholesale. Skipping one failing bug is fine; skipping the build step for the whole batch is not.
