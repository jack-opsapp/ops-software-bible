# Nightly Bug Triage — iOS

**Schedule:** `0 10 * * *` UTC = 3:00 AM PDT (2:00 AM PST after DST ends).

**Platform scope:** `platform = 'ios'` rows only in both `bug_reports` and `qa_bugs`.

This prompt is the iOS cron's entry point. It inherits the full contract in `_shared-triage-logic.md` — read that first. This file holds only iOS-specific environment.

---

## Environment

| Key | Value |
|---|---|
| Working directory | `/Users/jacksonsweet/Projects/OPS/OPS` (iOS app repo root) |
| Main branch | `main` |
| Build command | `xcodebuild -scheme OPS -destination 'generic/platform=iOS' -quiet` |
| **Never use** | `-destination 'platform=iOS Simulator,…'` (per OPS iOS CLAUDE.md) |
| Style source of truth | `OPS/OPS/Styles/OPSStyle.swift` + files in `OPS/OPS/Styles/Components/` |
| Data layer | SwiftData via `DataController`, ModelActor refactor in progress (see `project_model_actor_refactor.md` memory) |
| Commit author attribution | **Never add Claude as co-author.** Per OPS iOS CLAUDE.md. |

## Owned code paths (safe to edit)

All of `OPS/OPS/` except:
- `OPS/OPS/Network/Sync/` — touch only if the bug root-causes there; wizard_states sync is sensitive (see ios-bug-sweep plan).
- `OPS/OPS.xcodeproj/project.pbxproj` — the Batch Fix sub-agent should avoid adding new files if at all possible (Xcode project edits are merge-conflict magnets). Prefer touching existing files.

## Common iOS bug patterns the agent should recognize fast

| Pattern | Likely fix |
|---|---|
| SwiftUI "publishing changes from within view update" warning | Move mutation out of `body` into `task`/`onAppear`/`onChange` closure |
| Mapbox annotation size warning | Check annotation view frame is set before `didAdd` |
| Duplicate task rows | Check echo-race path in `InboundProcessor`; dedup key is `id` |
| Past-date crash in TaskFormSheet | Guard date picker bounds |
| Onboarding "Join Crew fails silently" | Migrate to `public.join_user_to_company` Supabase RPC (not Bubble) |
| Lockout screen "check access" no feedback | Add success/failure haptics + toast |

These are not a substitute for reading each bug — but when a new bug matches a known pattern, cite the prior fix commit in `fix_notes`.

## Per-platform build-failure policy

Per the user's ask: full `xcodebuild` must succeed before committing a fix. If the build fails:

1. First, try to fix the build error if clearly caused by the current change.
2. If the failure appears pre-existing (fails on `main` too, or touches files not in this diff), revert the current bug's changes only, escalate the bug with `requires_human_review = true` and reason `"Nightly iOS agent: xcodebuild fails on main — pre-existing build break. Cannot verify fix in isolation."`
3. Continue with the rest of the batch.

## Starting instruction for the orchestrator

```
You are the Nightly Bug Triage — iOS orchestrator.

Read ops-software-bible/scheduled-agents/_shared-triage-logic.md in full.
It defines your batching, claiming, sub-agent delegation, and escalation rules.

Then execute the orchestrator loop for platform = 'ios'.

Environment is defined in this file (nightly-bug-triage-ios.md) — obey it.

Start by running the backlog query (with platform='ios'). Report the backlog
size in your first message. Then begin batch 01.
```
