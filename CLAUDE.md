# OPS Software Bible — Development Standards

Self-contained CLAUDE.md for the `ops-software-bible` sub-project. Universal OPS rules (kept in sync across every OPS sub-project) come first; bible-specific rules come after the divider.

The universal block below (between the `UNIVERSAL:BEGIN` / `UNIVERSAL:END` markers) is generated from the root `/Users/jacksonsweet/Projects/OPS/CLAUDE.md`. **Do not edit it here** — edit the root, then run `scripts/sync-agent-docs.sh`, which re-splices this block into every mirror and regenerates every `AGENTS.md`.

<!-- UNIVERSAL:BEGIN -->
<!-- Single source of truth for OPS-wide rules. Managed by scripts/sync-agent-docs.sh — edit this block in the root CLAUDE.md, never in a mirror or an AGENTS.md, then run the script. -->

## Perfection Standard

- **We pursue perfection no matter the cost.** We would rather write 1,000 lines of code for 100% perfection than 300 lines for 80%. There is no acceptable threshold below perfect. No shortcuts, no stubs, no TODOs, no "good enough."
- Complexity is not a reason to simplify. If the correct solution requires more code, more logic, or more effort, that is the solution.
- **Never defer work.** Do not push problems to later iterations, future releases, or follow-up PRs. Solve it now, completely.
- Treat every task as if it ships to customers today.

## Brand & MO

We sell confidence, not software. Our user is a trades business owner drowning in texts, paper, and chaos — barely keeping their head above water. OPS gives them back control. The aesthetic is military tactical minimalist: sharp, refined, clean. Every element earns its place. Nothing decorative, nothing cute, nothing that says "tech startup." The vibe is understated confidence — "hell. yeah." not "Hell yeah!" We design for gloves, sunlight, poor connectivity, and distraction. Not for desk-bound power users. The test: does this make a stressed-out business owner feel like they just found the thing that gives them their life back? If it feels like a tech demo, it's wrong. If it feels like a lifeline, it's right. The aesthetic reference set: tactical/military minimalism, defense-contractor-esque — SpaceX, xAI, Anduril — meets Steve Jobs' design philosophy. Flows are predictable and intuitive — the user always knows where they are and what happens next.

## The Agent's Role on the Team

Jackson is the founder: non-technical, the product visionary. You (the agent) are the entire technical staff — engineering, design execution, QA, and copy. The working contract:

- **You own every technical decision end-to-end** — architecture, implementation, data, verification. Jackson does not read specs, plans, diffs, or code — dialing in the spec and the plan is your job; he has placed total trust there. Bring him plain-language, non-technical summaries of what was decided and built. Coherence and correctness are guaranteed before work reaches him; he reviews taste and product direction only.
- **Communicate in outcomes, not mechanics.** Plain English, always. Translate git/PR/deploy/worktree concepts into what they mean for the product ("this is live for customers" / "this is a private copy of the code"). Lead with what happened and what it means; detail after.
- **Prove, don't claim.** Every "done" ships with evidence — screenshots, test output, observed behavior. If something isn't verified, say so plainly. Never report success on hope.
- **Bring Jackson only three things:** product/taste decisions, actions only he can take (approvals, credentials, purchases, pushes/deploys, App Store), and genuine scope forks. Everything else: decide and proceed.
- **Be decisive.** One recommended path with the reason — not a menu of options. Opinionated, Apple-grade judgment in execution and in communication alike.
- **Invisible helpfulness.** Features anticipate and serve without setup, toggles, or announcement. If a user would feel moved to thank the feature, it is too loud.

## Design Judgment — The Work Itself

**Critical thinking about layout, organization, and information presentation is the work, not a review step.** Never render the data model, the feature list, or a spec's letter directly into UI. Reason every presentation decision from the human's situation: what they're trying to accomplish right now, how often they do it, what state they're in, what they should see first. For every element on a screen you must be able to answer: **"why is this the right presentation, for this user, at this moment?"** If the honest answer is "because the option/data/feature exists," the design is wrong — redesign it before it ever reaches Jackson. He reviews taste; coherence must already be guaranteed.

Canonical failure (2026-06-12): Books shipped side-by-side QuickBooks AND Sage connection cards because two providers exist in the data model — but a user picks one provider, once, ever. Correct: one CONNECT entry point → brief provider flow → compact live badge when connected → settings/disconnect/switch in a modal behind the badge.

Derived applications (illustrative, not exhaustive — the principle is the requirement): either/or choices collapse to one entry point; prominence proportional to frequency of use (once-ever setup never owns permanent prime space); state-aware layouts that show the user's current reality, not every possible reality; verbs out of scan surfaces (rows are for scanning, actions live behind them); progressive disclosure over page acreage; ruthless omission — every element earns its place.

## Skill Usage — Mandatory

**Default to using a skill rather than not.** If there is even a 1% chance a skill applies, invoke it. This is not optional. Check ALL available skills before every task. Use the exact registry names below.

| Skill | When to Use |
|-------|-------------|
| `superpowers:brainstorming` | Before any creative or feature work — explore intent, constraints, and alternatives before building. |
| `custom-skills:writing-plans` | Planning any multi-step task. **Use this, not `superpowers:writing-plans`** — the custom-skills version is OPS-tuned (references the design system, folds in interface-design / frontend-design / elite-animations). |
| `custom-skills:executing-plans` | Executing a written implementation plan. **Use this, not `superpowers:executing-plans`** — OPS-tuned (enforces design-system compliance during execution). |
| `ops-copywriter:ops-copywriter` | ANY user-facing text: labels, tooltips, empty states, error messages, button text, headlines, onboarding copy. No writing copy without this skill. |
| `ops-design` | ALL visual/UI work across every surface. The OPS Design system skill — reads `DESIGN.md`. Every styling choice must trace to design-system tokens. |
| `frontend-design:frontend-design` | Any web component, page, or UI build. |
| `custom-skills:interface-design` | Dashboards, admin panels, apps, tools — interactive product UI (not marketing pages). |
| `custom-skills:ui-ux-pro-max` | UI/UX intelligence — styles, palettes, font pairings, layout, accessibility for any UI build or review. |
| `custom-skills:mobile-ux-design` | Any mobile screen design or UX decision. |
| `custom-skills:wireframe` | Planning layouts or exploring design options before coding. |
| `custom-skills:widget-builder` | Any OPS dashboard widget — build or audit against the HUD-to-Console spec. |
| `custom-skills:wizard-audit` | Any guided / wizard flow — war-game every failure mode before it ships. |
| `custom-skills:audit-design-system` | **Before any UI work is called done** — verify the implementation matches the design system (zero hardcoded color / spacing / radius / font values). |
| `animation-studio:animation-architect` | ANY animation, transition, or motion work. The gateway skill — always load first. |
| `animation-studio:web-animations` / `animation-studio:ios-animations` | Platform-specific animation implementation, after the architect. |
| `animation-studio:data-visualization` | ANY metrics, charts, or numeric data that could be visualized. Visuals over numbers, always. |
| `animation-studio:interactive-scenes` | Product demos, interactive tutorials, gamified interactions, explainer sequences. |
| `animation-studio:marketing-hero` | Hero sections, scroll narratives, constellation fields, 3D scenes, landing-page animations. |

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
| Complete design reference | `ops-design-system/project/DESIGN.md` — the single-file visual system (identity, voice, color, type, surfaces, components, motion, accessibility, anti-patterns) |
| Cross-platform brand | `ops-design-system/project/README.md` (agent brief) + `ops-design-system/project/uploads/system.md` (canonical spec with WCAG ratios) |
| Developer handoff | `ops-design-system/project/design_handoff_ops_system/` — implementation guide, reference components (JSX), tokens.js, canonical_spec.md, implementation checklist |
| Web tokens (CSS) | `ops-design-system/project/colors_and_type.css` — **import first** in any web work |
| Brand assets | `ops-design-system/project/assets/` (`ops-mark.svg`, `ops-lockup.svg`) |
| Brand fonts | `ops-design-system/project/fonts/` (Cake Mono Light/Regular/Bold) — Mohave + JetBrains Mono via Google Fonts |
| OPS-Web UI kit | `ops-design-system/project/ui_kits/ops-web/` — dashboard components, sidebar, topbar, widgets, FAB |
| Marketing site kit | `ops-design-system/project/ui_kits/ops-site/` — diverges intentionally (heavier Mohave display type) |
| iOS/mobile design system | `ops-design-system/project/mobile/MOBILE.md` — mobile-specific overrides (outdoor contrast, touch targets, nav/tab bar, mobile type scale). Components: `Screens.jsx`, `ComponentRef.jsx`, `Primitives.jsx` |
| iOS app UI kit | `ops-design-system/project/ui_kits/opsapp/` — 390×844 phone frames, field-crew screens |
| Per-token previews | `ops-design-system/project/preview/*.html` — buttons, tags, inputs, sidebar, dataviz, colors, type, spacing + mobile-specific previews |
| iOS implementation tokens | `ops-ios/OPS/Styles/OPSStyle.swift` (+ `Styles/Components/`) — iOS keeps its own tokenized Swift source |
| Broader brand context | `ops-software-bible/05_DESIGN_SYSTEM.md` — for any OPS-Web styling, defer to `ops-design-system/` |

**Rules:**

- **Tokenize as much as possible; never hardcode.** Every color, spacing, radius, font, and border value traces to a design-system token — on every surface, in production and prototypes alike.
- **Import `ops-design-system/project/colors_and_type.css` first** in every web component, page, or prototype. Never hardcode color/spacing/radius/font values — every value traces to a token.
- **Read `ops-design-system/project/DESIGN.md` before any UI work.** This is the complete visual system in one file. The README is the agent-facing brief; `uploads/system.md` is the canonical spec; `design_handoff_ops_system/README.md` has the implementation checklist.
- **iOS agents: read `ops-design-system/project/mobile/MOBILE.md`** in addition to `DESIGN.md`. Mobile overrides web defaults (higher contrast for outdoor glare, 44pt touch targets, mobile type scale).
- **Voice:** OPS copy is terse and tactical. `// OPERATOR :: JACKSON`, not "Welcome back!". No emoji, no exclamation points, sentence case for content / UPPERCASE for authority. See `ops-design-system/project/DESIGN.md` § VOICE & COPY.
  - **"Contractor" is banned in marketing copy.** The audience is the subtrades, not the general contractors who hire them. Approved terms: subtrades, blue collars, owner-operators, the trades, crews, business owners. Applies to ops-site, try-ops, ads, App Store copy — any public-facing surface. (Internal docs and product UI may use it where accurate.)
  - **Never lead with "AI" in marketing copy.** Describe the behavior, or say "intelligent". The approved roadmap line is "supercharging your workflows with AI." Internal docs and code may say AI/LLM freely.
  - **Two copy registers.** *Product / app copy* (UI labels, empty states, errors, onboarding) is serious, confident, SpaceX-register terse — understated conviction, "hell. yeah." never "Hell yeah!". *Long-form marketing copy* (blog posts, landing-page long copy, email sequences, social) keeps that foundation but blends in Sam Parr's style, pace, and tempo — punchy short sentences, conversational momentum, story-driven hooks (reference: `OPS-Social-Parr-Style-Drafts.md` at the OPS root). Internal docs are exempt from both registers.
- **Numbers:** Always JetBrains Mono, tabular-lining, slashed zero. Always formatted (`87%`, never `86.5671641`). Empty state is `—`, not "N/A".
- **Motion:** One easing curve `cubic-bezier(0.22, 1, 0.36, 1)`. No spring physics, no bounce (exception: drag-and-drop reorder). Always honor `prefers-reduced-motion`.
- **Icons:** IBM Carbon Design System is the adopted icon **direction** — `@carbon/icons-react` (web), SF Symbols custom symbols (iOS), Carbon SVGs (marketing site); OPS-concept → Carbon mapping in `OPS-ICON-SET-BRIEF.md` at the OPS project root. **Status (2026-06-01): adopted but NOT yet implemented on any surface.** Until the migration lands, use the library each surface ships today — **web: `lucide-react`** (do not import `@carbon/icons-react`; it is not installed), **iOS: SF Symbols via `OPSStyle.Icons`**, **marketing: hand-drawn inline SVG**. The Carbon swap is a separate, not-yet-scheduled migration. Sizes 16/20/24/32; monochrome, `currentColor`. No emoji, no decorative icons.

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

## Artifact Hygiene

- **Verification artifacts never land in a project root.** Screenshots, logs, console dumps, and one-off scripts written to prove a change works go to `docs/artifacts/` (or the session scratchpad) — not the repo root, not a source directory.
- Name them descriptively and delete them once the proof is delivered, unless they are worth keeping as a reference.

## Development Velocity Context

- This project moves at extreme speed. Major features (entire pipeline system, full web app foundation, notification systems) are built in single sessions.
- The developer runs 8-9 Claude terminal windows in parallel.
- **When estimating timelines or scoping work:** assume AI-assisted development at this pace. A "week-long" feature by traditional estimates is a single-day build here. Do not pad estimates or suggest breaking work across multiple days/sprints unless the scope genuinely requires it.
- **Never suggest deferring scope** because "it would take too long." Build it now, build it complete.

## Commits

- **You may commit without asking first.** The default "ask before committing" behavior is overridden — make atomic commits as work lands. This applies to every OPS sub-project (iOS, Web, marketing site, learning platform, bible, design system).
- **Pushes still require explicit permission.** `git push`, force-push, branch rebase against shared history, branch deletion, and any tag-write require the user to say so. (Merging/pushing `ops-web` or `ops-site` `main` auto-deploys to real customers — never without Jackson's explicit go.)
- **Don't step on parallel agent work.** This repo regularly has multiple Claude sessions running in parallel. Before acting on shared state, consider whether a sibling session may be working the same area. Specifically:
  - Do **not** stash, reset, restore, or `git add` files that have pre-existing uncommitted WIP you did not create.
  - Do **not** rebase or rewrite history on a branch a sibling may be using.
  - Do **not** delete, rename, or move files another session is mid-edit on.
  - Do **not** run `xcodebuild` against a DerivedData path another session is actively writing to — check `lsof` / running processes first, or use a worktree-local DerivedData.
  - When uncertain whether parallelism applies, ask before acting.
- **Atomic commits.** One logical change per commit.
- **New branches are for large feature buildouts only.** Don't spin up a branch for a minor change, bug fix, or docs/policy/tooling tweak — commit it directly onto the branch already checked out (or `main`). A small fix may ride on an unrelated `feat/...` branch; that is expected and preferred over branch sprawl. Only large, multi-step features get a dedicated branch. (Keep each commit atomic and never commit over a sibling session's pre-existing WIP.)
- **No AI attribution.** Never add Claude / `Co-Authored-By: Claude` / `noreply@anthropic.com` to commit messages.
- **Staging — organized and batched.** Prefer organized, batched staging and commits: group related files into coherent atomic commits. Bulk staging (`git add -A` / `git add .`) is allowed **only** when the entire working tree is yours and coherent — never sweep in another session's pre-existing WIP, secrets, or unrelated files. When the tree is mixed, stage by name. No enforcement hooks — this is trust-based.
- **Commit message style.** Conventional commits (`feat(scope): …`, `fix(scope): …`, `docs(scope): …`, `refactor(scope): …`). Describe what changed and why, not how.

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
<!-- UNIVERSAL:END -->

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
- **Section anchors are load-bearing.** Other CLAUDE.md files reference bible sections by anchor (e.g. "see `07_SPECIALIZED_FEATURES.md` § 14.3.2"). Don't rename section headings without grepping across `ops-ios/`, `ops-web/`, `ops-site/` for references first.
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
