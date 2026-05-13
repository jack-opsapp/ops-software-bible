# OPS Software Bible — Development Standards

Self-contained CLAUDE.md for the `ops-software-bible` sub-project. Universal OPS rules (kept in sync across every OPS sub-project) come first; bible-specific rules come after the divider.

If you update a universal section here, also update the mirrors in `ops-ios/CLAUDE.md`, `OPS-Web/CLAUDE.md`, `ops-site/CLAUDE.md`, and `/Users/jacksonsweet/Projects/OPS/CLAUDE.md`.

## Perfection Standard

- **We pursue perfection no matter the cost.** We would rather write 1,000 lines of code for 100% perfection than 300 lines for 80%. There is no acceptable threshold below perfect. No shortcuts, no stubs, no TODOs, no "good enough."
- Complexity is not a reason to simplify. If the correct solution requires more code, more logic, or more effort, that is the solution.
- **Never defer work.** Do not push problems to later iterations, future releases, or follow-up PRs. Solve it now, completely.
- Treat every task as if it ships to customers today.

## Brand & MO

We sell confidence, not software. Our user is a trades business owner drowning in texts, paper, and chaos — barely keeping their head above water. OPS gives them back control. The aesthetic is military tactical minimalist: sharp, refined, clean. Every element earns its place. Nothing decorative, nothing cute, nothing that says "tech startup." The vibe is understated confidence — "hell. yeah." not "Hell yeah!" We design for gloves, sunlight, poor connectivity, and distraction. Not for desk-bound power users. The test: does this make a stressed-out business owner feel like they just found the thing that gives them their life back? If it feels like a tech demo, it's wrong. If it feels like a lifeline, it's right.

## Skill Usage — Mandatory

**Default to using a skill rather than not.** If there is even a 1% chance a skill applies, invoke it. This is not optional. Check ALL available skills before every task.

| Skill | When to Use |
|-------|-------------|
| `ops-copywriter` | ANY user-facing text: labels, tooltips, empty states, error messages, button text, headlines, onboarding copy. No writing copy without this skill. |
| `animation-studio:animation-architect` | ANY animation, transition, or motion work. The gateway skill — always load first. |
| `animation-studio:web-animations` / `ios-animations` | Platform-specific animation implementation after loading the architect. |
| `animation-studio:data-visualization` | ANY metrics, charts, or numeric data that could be visualized. Visuals over numbers, always. |
| `animation-studio:interactive-scenes` | Product demos, interactive tutorials, gamified interactions, explainer sequences. |
| `animation-studio:marketing-hero` | Hero sections, scroll narratives, constellation fields, 3D scenes, landing page animations. |
| `ops-design` | ALL visual/UI work across every surface. The Claude Design system skill — read `ops-design-system/project/SKILL.md`. Every styling choice must trace to the design system tokens. |
| `frontend-design` | Any web component, page, or UI build. |
| `mobile-ux-design` | Any mobile screen design or UX decision. |
| `wireframe` | When planning layouts or exploring design options. |
| `brainstorming` | Before any creative or feature work. Explore intent, constraints, and alternatives before building. |

## OPS Software Bible

**The OPS Software Bible (`ops-software-bible/`) is the encyclopedia of OPS.** It is the single source of truth for architecture, data models, API contracts, feature specifications, and the current state of every system. It is used by agents to describe the app, reference endpoints, understand data structures, and pull feature context.

- **Always consult the bible** before making assumptions about data types, table schemas, API behavior, or feature requirements.
- **Always fetch from Supabase** (via MCP tools) to verify table schemas, column types, and RLS policies before writing queries or migrations. Never guess column names or types.
- **Keep the bible updated.** When you implement a feature, add a migration, change a data model, or build a new system — update the relevant bible section in the same session. The bible must stay current. An outdated bible is a broken bible.

## Design System — `ops-design-system/`

All styling decisions live in the centralized design system — not in CLAUDE.md, not improvised. No colors, fonts, spacing, or radii should be hardcoded.

**The OPS visual system lives at `ops-design-system/project/`.** Exported from Claude Design, this is the single source of truth for every styling decision across all surfaces — military tactical minimalist, monochrome canvas, glass + hairlines, steel-blue accent, three-font system (Mohave / JetBrains Mono / Cake Mono), earth-tone semantics.

| Surface | Source of Truth |
|---------|----------------|
| Cross-platform brand | `ops-design-system/project/README.md` (agent brief) + `ops-design-system/project/uploads/system.md` (canonical spec with WCAG ratios) |
| Web tokens (CSS) | `ops-design-system/project/colors_and_type.css` — **import first** in any web work |
| Brand assets | `ops-design-system/project/assets/` (`ops-mark.svg`, `ops-lockup.svg`) |
| Brand fonts | `ops-design-system/project/fonts/` (Cake Mono Light/Regular/Bold) — Mohave + JetBrains Mono via Google Fonts |
| OPS-Web UI kit | `ops-design-system/project/ui_kits/ops-web/` — dashboard components, sidebar, topbar, widgets, FAB |
| Marketing site kit | `ops-design-system/project/ui_kits/ops-site/` — diverges intentionally (heavier Mohave display type) |
| iOS app kit | `ops-design-system/project/ui_kits/opsapp/` — 390×844 phone frames, field-crew screens |
| Per-token previews | `ops-design-system/project/preview/*.html` — buttons, tags, inputs, sidebar, dataviz, colors, type, spacing |
| iOS implementation tokens | `OPS/OPS/Styles/OPSStyle.swift` (+ `Styles/Components/`) — iOS keeps its own tokenized Swift source |
| Broader brand context | `ops-software-bible/05_DESIGN_SYSTEM.md` — for any OPS-Web styling, defer to `ops-design-system/` |

**Rules:**

- **Import `ops-design-system/project/colors_and_type.css` first** in every web component, page, or prototype. Never hardcode color/spacing/radius/font values — every value traces to a token.
- **Read `ops-design-system/project/README.md` before any UI work.** The README is the agent-facing brief; `uploads/system.md` is the canonical spec.
- **Voice:** OPS copy is terse and tactical. `// OPERATOR :: JACKSON`, not "Welcome back!". No emoji, no exclamation points, sentence case for content / UPPERCASE for authority. See `ops-design-system/project/README.md` § CONTENT FUNDAMENTALS.
- **Numbers:** Always JetBrains Mono, tabular-lining, slashed zero. Always formatted (`87%`, never `86.5671641`). Empty state is `—`, not "N/A".
- **Motion:** One easing curve `cubic-bezier(0.22, 1, 0.36, 1)`. No spring physics, no bounce (exception: drag-and-drop reorder). Always honor `prefers-reduced-motion`.
- **Icons:** Lucide, 1.5px stroke, `currentColor`. No emoji, no decorative icons.

### Claude Design Handoff Protocol

When implementing designs exported from Claude Design (handoff bundles), agents must follow this protocol exactly:

1. **Read the skill first.** Load `ops-design-system/project/SKILL.md`, then `ops-design-system/project/README.md`. Become an expert in the OPS brand before touching any code.
2. **Read the handoff bundle top-to-bottom.** Open the primary design file and every file it imports — CSS, components, scripts. Understand how the pieces connect before implementing.
3. **Import tokens first.** In production code: use the project's Tailwind tokens. In prototypes: import `colors_and_type.css`. Every value must trace to a token — zero improvisation.
4. **Match the visual output, not the prototype code.** Handoff HTML/CSS/JS are prototypes, not production code. Recreate the visual result pixel-perfectly in the target tech stack (React, Swift, etc.). Don't copy prototype internals unless they happen to fit.
5. **Verify against reference screenshots.** If the handoff bundle includes `screenshots/`, compare your implementation against them. Flag any deviation in color, spacing, typography, or layout.
6. **When anything is ambiguous, ask.** It is cheaper to clarify scope than to build the wrong thing. Never guess a token value, component pattern, or layout decision.
7. **Plan before coding.** For non-trivial handoffs, write a plan listing every component, token reference, and layout decision — get confirmation, then implement.

## Notification System

- **The web app has a notification rail in the header.** When building any feature that produces a user-facing event (task completed, expense approved, scan finished, import done, etc.), create a notification so it appears in the rail.
- See `ops-software-bible/07_SPECIALIZED_FEATURES.md` Section 14 for the full notification architecture (iOS + Web).
- Notification types: **standard** (dismissible) and **persistent** (stays until resolved). Use `persistent: true` for long-running operations the user is waiting on.
- Action buttons: set `actionUrl` and `actionLabel` to give users a click-through to the relevant page.

## Precision

- **Never guess.** If unsure about a data type, API response shape, table schema, or business rule — look it up or ask the user.
- Do not make inferences. Read the actual code, query the actual database, check the actual documentation.
- When asked about specific code behavior, read the file line by line. Do not speculate.

## Cost Transparency

- **Always inform the user of associated costs** when making decisions that involve money — Vercel subscriptions, function invocation costs, third-party API pricing, database tier changes, etc.
- If you don't know the cost, tell the user you need to research it before proceeding. Never assume something is free or cheap.

## Development Velocity Context

- This project moves at extreme speed. Major features (entire pipeline system, full web app foundation, notification systems) are built in single sessions.
- The developer runs 8-9 Claude terminal windows in parallel.
- **When estimating timelines or scoping work:** assume AI-assisted development at this pace. A "week-long" feature by traditional estimates is a single-day build here. Do not pad estimates or suggest breaking work across multiple days/sprints unless the scope genuinely requires it.
- **Never suggest deferring scope** because "it would take too long." Build it now, build it complete.

## Git Commit Guidelines

- **You may commit without asking first.** The default "ask before committing" behavior is overridden — make atomic commits as work lands. **Pushes still require explicit permission** (`git push`, force-push, rebase against shared history, branch deletion, tag-write).
- **Don't step on parallel agent work.** This repo regularly has multiple Claude sessions / worktrees running in parallel (`git worktree list` shows current ones). Before acting on shared state:
  - Do **not** stash, reset, restore, or `git add` files that have pre-existing uncommitted WIP you did not create.
  - Do **not** rebase or rewrite history on a branch a sibling worktree is using.
  - Do **not** delete, rename, or move files another session is mid-edit on.
  - Do **not** modify shared build artifacts (DerivedData, lockfiles, migrations, generated types) that a parallel session may be writing to. Check `lsof` or running processes if uncertain.
  - When uncertain whether parallelism applies, ask before acting.
- **Atomic commits.** One logical change per commit. Do not mix unrelated scopes (e.g. a feature + a docs update) in a single commit; split them, even within the same branch.
- **Branch scope discipline.** A feature branch (e.g. `nightly/...`, `feat/...`) is for that feature only. Drop unrelated commits (docs, policy, tooling) onto `main` directly or on their own short-lived branch — not onto someone else's feature branch.
- **Never include Claude as co-author.** No `Co-Authored-By: Claude`, no `noreply@anthropic.com`, no AI attribution of any kind in commit messages or trailers.
- **Stage by name, not bulk.** Never `git add -A` or `git add .` — name the specific files. Bulk-staging risks pulling in unrelated WIP, secrets (`Secrets.xcconfig`, `.env*`), or another session's files.
- **Conventional-commit style.** `feat(scope): …`, `fix(scope): …`, `docs(scope): …`, `refactor(scope): …`. Describe what changed and why, not how.

## Spawned Task Naming Convention

When spawning a follow-up chat, fresh worktree, or background task (e.g. via `mcp__ccd_session__spawn_task`, `Agent` with isolation, or any "open this in a new chat" affordance), the **title** must follow this hierarchical convention so spawned tasks can be traced back to the parent initiative + phase + ordinal at a glance.

**Format:**

```
<PROJECT> - P<phase>-<task#>[-<subtask#>...]
```

- `<PROJECT>` — uppercase, hyphenated. The initiative the spawn relates to (e.g. `INBOX REDESIGN`, `PIPELINE V2`, `ESTIMATES OVERHAUL`). Pulled from the session brief, the PR title, the active ticket, or — failing all of those — the most-edited directory name in the current worktree.
- `P<phase>` — the phase number of the parent initiative (`P1`, `P6`, etc.). Phases come from the brief, the implementation plan, or the PR description. If the parent initiative is single-phase or unphased, use `P1`.
- `<task#>` — the spawn ordinal **within the current phase, in the current session**. First spawn of the session within P6 → `1`. Second spawn → `2`. Restart at `1` for a new phase.
- `<subtask#>` — present only when spawning from inside an already-spawned task (a "spawn within a spawn"). Increments per nesting level.

**Examples:**

- Working on phase 1 of inbox redesign, spawning the first follow-up: `INBOX REDESIGN - P1-1`
- Second follow-up from the same phase: `INBOX REDESIGN - P1-2`
- A follow-up discovered while inside that second follow-up's chat: `INBOX REDESIGN - P1-2-1`
- Working on phase 6 of inbox redesign, first follow-up: `INBOX REDESIGN - P6-1`

**Rules:**

- The convention is **mandatory** — every spawned task title must conform. Do not deviate even when "the task is small" or "it's just a one-off."
- Project name + phase number persist across sessions. When a session ends and a new one resumes the same initiative, the new session's first spawn continues the ordinal sequence (P6-3 follows P6-2, not P6-1).
- The `tldr` and `prompt` fields are unrelated to this convention — they describe what the spawned chat will do; the title encodes lineage.
- If you cannot confidently determine the project + phase from context, ask the user before spawning rather than guessing.

---

# Bible-specific rules

## What this repo is

The OPS Software Bible is the **canonical written record** of the entire OPS application — its architecture, data models, API contracts, feature specifications, financial logic, design system, deployment topology, and operational state. It does NOT contain code. It exists so any agent (or human) with zero prior context can come up to speed on any part of OPS by reading the bible.

If something is true about OPS and it isn't written in the bible, the bible is wrong — write it down. If something is written in the bible and it isn't true about OPS anymore, the bible is wrong — update it.

## File structure

| Pattern | Purpose |
|---------|---------|
| `NN_TOPIC_NAME.md` (numbered, top-level) | The canonical chapters. `00_EXECUTIVE_SUMMARY.md` is the orientation doc; the others are deep dives by topic. See `README.md` for the full navigation. |
| `migrations/` | Supabase migration archive — every SQL file applied to prod, in chronological order. Mirror of the migration list returned by `mcp__plugin_supabase_supabase__list_migrations`. |
| `research/` | Background research, vendor evaluations, competitive analyses. Not the source of truth for product behavior — chapters are. |
| `scheduled-agents/` | Prompt definitions for cron-triggered Claude routines (review passes, batch fixes, triage logic). Read before editing any scheduled agent. |
| `specs/` | One-off design specs that haven't (yet) been merged into the numbered chapters. Treat as drafts. |
| `app-store-listing.txt` | iOS App Store metadata. |
| `README.md` | Navigation + chapter ordering. Update when adding a new top-level chapter. |

## Documentation conventions

- **Always use the numbered chapter that matches the topic.** Schema goes in `03_DATA_ARCHITECTURE.md`. API contracts in `04_API_AND_INTEGRATION.md`. Notifications in `07_SPECIALIZED_FEATURES.md` § 14. Money in `09_FINANCIAL_SYSTEM.md`. If unsure, check `README.md`.
- **Section anchors are load-bearing.** Other CLAUDE.md files reference bible sections by anchor (e.g. "see `07_SPECIALIZED_FEATURES.md` § 14.3.2"). Don't rename section headings without grepping across `OPS/`, `OPS-Web/`, `ops-site/` for references first.
- **Date your changes inline.** When adding a new feature section, prefix with the date of the design: `## Cashflow Forecast (2026-05-11)`. Future readers need to know vintage.
- **Cite primary sources.** When documenting a schema column, reference the exact migration filename that introduced it. When documenting an API contract, reference the route file. When documenting iOS behavior, reference the Swift file path.
- **No marketing voice in the bible.** This is an engineering reference. Terse, factual, unambiguous. Save the OPS tactical voice for product copy.

## When to update the bible

Any of these in the same session, no exceptions:

- Adding a Supabase migration → mirror the file into `migrations/` and update `03_DATA_ARCHITECTURE.md` schema descriptions
- Adding or modifying a notification type → update `07_SPECIALIZED_FEATURES.md` § 14
- Adding a new revenue / billing path → update `09_FINANCIAL_SYSTEM.md`
- Adding a new job lifecycle stage or transition → update `10_JOB_LIFECYCLE_AND_DATA_RELATIONSHIPS.md`
- Adding a new API endpoint or RPC → update `04_API_AND_INTEGRATION.md`
- Adding a new top-level feature or specialized system → either add a new numbered chapter or extend `07_SPECIALIZED_FEATURES.md`
- Adding a new analytics event or funnel definition → update `21_ANALYTICS_SYSTEM.md`

If the change affects multiple chapters, update all of them in the same commit.

## Cross-repo dependencies

Bible updates often must land in lockstep with code in another repo. The discipline:

- iOS or Web code commit → land first (with a clear commit message)
- Bible commit → land second (referencing the code commit)
- Both should land within the same session if possible. If the bible commit is deferred, the code commit message must explicitly call out the bible debt as a follow-up task.

## Scheduled agents

`scheduled-agents/*.md` contains prompt definitions consumed by cron-triggered Claude routines. Treat them like production code:

- Each prompt is paired with a routine on the Claude scheduler side (see ops dashboard or `mcp__scheduled-tasks__list_scheduled_tasks`)
- Edits to a prompt take effect on the next cron firing
- Do not rename a prompt file without updating its scheduler registration in lockstep
- The `_shared-triage-logic.md` and `_batch-fix-prompt.md` and `_review-pass-prompt.md` files are referenced by multiple routines — changes propagate broadly
