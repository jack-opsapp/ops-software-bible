# Nightly Bug Triage — Web

**Schedule:** `0 10 * * *` UTC = 3:00 AM PDT (2:00 AM PST after DST ends).

**Platform scope:** `platform = 'web'` rows only in both `bug_reports` and `qa_bugs`.

This prompt is the OPS-Web cron's entry point. It inherits the full contract in `_shared-triage-logic.md` — read that first.

---

## Environment

| Key | Value |
|---|---|
| Working directory | `/Users/jacksonsweet/Projects/OPS/OPS-Web` |
| Main branch | `main` |
| Build command | `npm run typecheck && npm run build` (typecheck runs `tsc --noEmit`; `build` runs Next.js) |
| Style source of truth | `.interface-design/system.md` + tokens in `src/styles/tokens.css` |
| Data layer | Supabase + TanStack Query. RLS enabled on all app tables. |
| Auth | Firebase Auth JWT → Supabase (via Firebase↔Supabase bridge) |
| Commit author attribution | Claude co-author tag permitted per OPS-Web conventions (unlike iOS). |

## Owned code paths (safe to edit)

All of `OPS-Web/src/` except:
- `src/lib/api/services/` — services are load-bearing; edit with caution and check all callers.
- `src/lib/firebase/` — auth wiring is sensitive.
- `src/lib/supabase/helpers.ts` — changes ripple everywhere.

**Skip entirely (not owned by this agent):**
- `OPS-Web/supabase/migrations/` — migrations must be intentional, never driven by nightly sweeps.
- `OPS-Web/tests/` — the agent writes fixes, not tests, unless a bug explicitly calls for a regression test.

## Common web bug patterns the agent should recognize fast

| Pattern | Likely fix |
|---|---|
| Hardcoded color / font / spacing | Swap to design token per `.interface-design/system.md` |
| Header page-level action button (removed) | Migrate to FAB action — see `fab-actions.ts` |
| Unhandled empty-state | Add the empty-state component matching the widget's tier |
| Bug report category hardcoded to "bug" | Already fixed (this session, 2026-04-24) |
| Missing notification rail entry on event | Insert into `notifications` table per OPS-Web CLAUDE.md notification rail section |
| Map widget interactive mode | Map is non-interactive; zoom via toolbar only |
| Z-index collision | Consult OPS-Web CLAUDE.md Z-Index Scale table |

## Per-platform build-failure policy

`npm run typecheck && npm run build` must succeed before committing. If it fails:

1. First, try to fix the error if clearly caused by the current change.
2. If the failure appears pre-existing (fails on `main`), revert the current bug's changes, escalate with `requires_human_review = true` and reason `"Nightly web agent: build fails on main — pre-existing break. Cannot verify fix in isolation."`
3. Continue with the rest of the batch.

**Note on type failures:** if `tsc --noEmit` fails on an `any` or unsafe cast unrelated to the current diff, do NOT add type assertions to silence it — escalate. Silencing prod type errors is out of scope for nightly sweeps.

## Cost transparency

Each nightly run on a ~10-bug backlog is expected to use:
- ~5-10 minutes orchestrator wall-time
- ~10-30 minutes per batch sub-agent (Sonnet class)
- Supabase API + GitHub API (both free within quota)
- Claude API usage: variable, depends on bug complexity

The orchestrator **must** fail-fast on 2 consecutive batch failures to avoid burning spend on a broken pipeline.

## Starting instruction for the orchestrator

```
You are the Nightly Bug Triage — Web orchestrator.

Read ops-software-bible/scheduled-agents/_shared-triage-logic.md in full.
It defines your batching, claiming, sub-agent delegation, and escalation rules.

Then execute the orchestrator loop for platform = 'web'.

Environment is defined in this file (nightly-bug-triage-web.md) — obey it.

Start by running the backlog query (with platform='web'). Report the backlog
size in your first message. Then begin batch 01.
```
