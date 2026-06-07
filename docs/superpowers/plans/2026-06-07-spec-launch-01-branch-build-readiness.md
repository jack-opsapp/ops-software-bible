# SPEC Launch 01 Branch Build Readiness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reconcile the SPEC admin/operator work into the actual shipping OPS-Web branch and prove `ops-site` and `ops-web` production builds against launch environment.

**Architecture:** This plan does not add new product behavior. It establishes the correct shipping branches, preserves unrelated dirty state, merges or cherry-picks the existing SPEC admin commits into the active OPS-Web release branch, then verifies production builds and route presence with evidence.

**Tech Stack:** Git worktrees, Next.js App Router, TypeScript, Supabase env, Vercel env parity, npm scripts.

---

## File Structure

- Read: `/Users/jacksonsweet/Projects/OPS/ops-software-bible/SPEC/08_PHASE1_PAID_VALIDATION_LAUNCH.md`
- Read: `/Users/jacksonsweet/Projects/OPS/ops-software-bible/SPEC/07_ROLLOUT.md`
- Read: `/Users/jacksonsweet/Projects/OPS/ops-web/src/app/admin/spec/**`
- Read: `/Users/jacksonsweet/Projects/OPS/ops-web/src/components/admin/spec/**`
- Read: `/Users/jacksonsweet/Projects/OPS/ops-web/src/lib/admin/spec-queries.ts`
- Modify: SPEC admin files copied by the reconciliation task under `/Users/jacksonsweet/Projects/OPS/ops-web/src/app/admin/spec`, `/Users/jacksonsweet/Projects/OPS/ops-web/src/app/api/admin/spec`, `/Users/jacksonsweet/Projects/OPS/ops-web/src/components/admin/spec`, and `/Users/jacksonsweet/Projects/OPS/ops-web/src/lib/admin/spec-*`
- Create: `/Users/jacksonsweet/Projects/OPS/ops-software-bible/docs/spec-launch/branch-build-readiness-evidence.md`

## Task 1: Preflight Every Checkout

**Files:**
- Read: `/Users/jacksonsweet/Projects/OPS/ops-web`
- Read: `/Users/jacksonsweet/Projects/OPS/ops-site`
- Create: `/Users/jacksonsweet/Projects/OPS/ops-software-bible/docs/spec-launch/branch-build-readiness-evidence.md`

- [ ] **Step 1: Run checkout preflight for OPS-Web**

Run:

```bash
cd /Users/jacksonsweet/Projects/OPS/ops-web
pwd
git branch --show-current
git rev-parse --short HEAD
git status --short
git worktree list
```

Expected: output records the active branch, current HEAD, and dirty files. Do not stash, reset, or switch in place.

- [ ] **Step 2: Run checkout preflight for ops-site**

Run:

```bash
cd /Users/jacksonsweet/Projects/OPS/ops-site
pwd
git branch --show-current
git rev-parse --short HEAD
git status --short
git worktree list
```

Expected: output records `ops-site` branch, HEAD, and dirty files. Do not clean generated screenshots or unrelated files.

- [ ] **Step 3: Write the evidence shell**

Create `/Users/jacksonsweet/Projects/OPS/ops-software-bible/docs/spec-launch/branch-build-readiness-evidence.md`:

```markdown
# SPEC Branch Build Readiness Evidence

## OPS-Web Preflight

- Path:
- Branch:
- HEAD:
- Dirty files:
- Worktrees:

## ops-site Preflight

- Path:
- Branch:
- HEAD:
- Dirty files:
- Worktrees:

## SPEC Admin Source

- Source commit range:
- Target branch:
- Merge method:

## Build Evidence

- ops-web:
- ops-site:

## Route Evidence

- `/admin/spec`:
- `/admin/spec/analytics`:
- `/spec`:
```

- [ ] **Step 4: Commit evidence shell**

Run:

```bash
cd /Users/jacksonsweet/Projects/OPS/ops-software-bible
git add docs/spec-launch/branch-build-readiness-evidence.md
git commit -m "docs: add SPEC build readiness evidence shell"
```

Expected: commit includes only the evidence file.

## Task 2: Identify SPEC Admin Source Commits

**Files:**
- Read: `/Users/jacksonsweet/Projects/OPS/ops-web/.git`
- Modify: `/Users/jacksonsweet/Projects/OPS/ops-software-bible/docs/spec-launch/branch-build-readiness-evidence.md`

- [ ] **Step 1: Locate commits containing SPEC admin routes**

Run:

```bash
cd /Users/jacksonsweet/Projects/OPS/ops-web
git log --all --oneline --grep="SPEC Stage F"
git log --all --oneline --grep="SPEC H-supplement"
git branch --all --contains 98b5e8c
git branch --all --contains 726cf7f1
git branch --all --contains ea3b783a
```

Expected: output identifies the local or remote branch containing the merged SPEC admin surface. If `726cf7f1` or `ea3b783a` are not present, run `git fetch --all --prune` with approval before continuing.

- [ ] **Step 2: Verify source tree contains required files**

Run:

```bash
cd /Users/jacksonsweet/Projects/OPS/ops-web
git ls-tree -r --name-only 726cf7f1 | rg "^src/(app|components|lib).*(admin/spec|spec-queries|spec-types)"
```

Expected: output includes `/src/app/admin/spec/page.tsx`, `/src/app/admin/spec/[id]/page.tsx`, `/src/app/admin/spec/layout.tsx`, `/src/components/admin/spec/`, and `/src/lib/admin/spec-queries.ts`.

- [ ] **Step 3: Record source and target in evidence**

Edit `/Users/jacksonsweet/Projects/OPS/ops-software-bible/docs/spec-launch/branch-build-readiness-evidence.md`:

```markdown
## SPEC Admin Source

- Source commit range: `1f397b4a 46de1529 f745a1cf 726cf7f1 20e2232d 48588f6c ea3b783a`
- Target branch: live OPS-Web shipping branch recorded in preflight
- Merge method: non-destructive merge or cherry-pick sequence in an isolated worktree
```

- [ ] **Step 4: Commit evidence update**

Run:

```bash
cd /Users/jacksonsweet/Projects/OPS/ops-software-bible
git add docs/spec-launch/branch-build-readiness-evidence.md
git commit -m "docs: record SPEC admin source commits"
```

Expected: commit includes only the evidence file.

## Task 3: Reconcile SPEC Admin Into Shipping OPS-Web

**Files:**
- Modify: `/Users/jacksonsweet/Projects/OPS/ops-web/src/app/admin/spec/**`
- Modify: `/Users/jacksonsweet/Projects/OPS/ops-web/src/components/admin/spec/**`
- Modify: `/Users/jacksonsweet/Projects/OPS/ops-web/src/lib/admin/spec-queries.ts`
- Modify: `/Users/jacksonsweet/Projects/OPS/ops-web/src/lib/admin/spec-types.ts`
- Modify: `/Users/jacksonsweet/Projects/OPS/ops-web/src/app/api/admin/spec/board/refresh/route.ts`

- [ ] **Step 1: Create isolated reconciliation worktree**

Run:

```bash
cd /Users/jacksonsweet/Projects/OPS/ops-web
git worktree add /private/tmp/ops-web-spec-launch-readiness HEAD
cd /private/tmp/ops-web-spec-launch-readiness
git branch --show-current
git status --short
```

Expected: clean isolated worktree at the same HEAD as the shipping branch. Copy `.env.local` from the source checkout only if it exists and only for local build verification.

- [ ] **Step 2: Cherry-pick SPEC admin commits**

Run:

```bash
cd /private/tmp/ops-web-spec-launch-readiness
git cherry-pick 1f397b4a 46de1529 f745a1cf 726cf7f1 20e2232d 48588f6c ea3b783a
```

Expected: cherry-pick completes or reports conflicts. Resolve conflicts by preserving current shipping branch changes outside `/admin/spec` and taking SPEC branch changes inside `/admin/spec`.

- [ ] **Step 3: Verify required admin files exist**

Run:

```bash
cd /private/tmp/ops-web-spec-launch-readiness
test -f src/app/admin/spec/layout.tsx
test -f src/app/admin/spec/page.tsx
test -f src/app/admin/spec/[id]/page.tsx
test -f src/app/api/admin/spec/board/refresh/route.ts
test -f src/lib/admin/spec-queries.ts
```

Expected: command exits 0.

- [ ] **Step 4: Commit reconciliation**

Run:

```bash
cd /private/tmp/ops-web-spec-launch-readiness
git status --short
git add src/app/admin/spec src/app/api/admin/spec src/components/admin/spec src/lib/admin/spec-queries.ts src/lib/admin/spec-types.ts
git commit -m "feat: reconcile SPEC admin surface for launch"
```

Expected: commit contains only SPEC admin files and required shared admin types.

## Task 4: Prove OPS-Web Production Build

**Files:**
- Read: `/private/tmp/ops-web-spec-launch-readiness/package.json`
- Modify: `/Users/jacksonsweet/Projects/OPS/ops-software-bible/docs/spec-launch/branch-build-readiness-evidence.md`

- [ ] **Step 1: Install or verify dependencies**

Run:

```bash
cd /private/tmp/ops-web-spec-launch-readiness
test -d node_modules && echo "node_modules present" || npm install
```

Expected: dependencies present. If network fails, rerun `npm install` with escalation and approval.

- [ ] **Step 2: Run production build**

Run:

```bash
cd /private/tmp/ops-web-spec-launch-readiness
npm run build
```

Expected: exit 0. Warnings are recorded. Any TypeScript, route, or missing import error must be fixed before continuing.

- [ ] **Step 3: Record build evidence**

Append to `/Users/jacksonsweet/Projects/OPS/ops-software-bible/docs/spec-launch/branch-build-readiness-evidence.md`:

```markdown
## OPS-Web Build Evidence

- Worktree: `/private/tmp/ops-web-spec-launch-readiness`
- Command: `npm run build`
- Result: PASS
- Warnings:
- SPEC routes included:
```

- [ ] **Step 4: Commit evidence**

Run:

```bash
cd /Users/jacksonsweet/Projects/OPS/ops-software-bible
git add docs/spec-launch/branch-build-readiness-evidence.md
git commit -m "docs: record OPS-Web SPEC build evidence"
```

Expected: commit includes only the evidence update.

## Task 5: Prove ops-site Production Build With Launch Env

**Files:**
- Read: `/Users/jacksonsweet/Projects/OPS/ops-site/package.json`
- Modify: `/Users/jacksonsweet/Projects/OPS/ops-software-bible/docs/spec-launch/branch-build-readiness-evidence.md`

- [ ] **Step 1: Verify launch env presence**

Run:

```bash
cd /Users/jacksonsweet/Projects/OPS/ops-site
test -f .env.local
rg -n "NEXT_PUBLIC_SUPABASE_URL|SUPABASE_SERVICE_ROLE_KEY|SPEC_LIVE_DEPOSITS_ENABLED|STRIPE_SECRET_KEY|STRIPE_WEBHOOK_SECRET" .env.local
```

Expected: all required env names are present. Do not print secret values in the evidence doc.

- [ ] **Step 2: Run production build**

Run:

```bash
cd /Users/jacksonsweet/Projects/OPS/ops-site
npm run build
```

Expected: exit 0. Missing-env prerender errors block launch readiness.

- [ ] **Step 3: Run SPEC cron tests**

Run:

```bash
cd /Users/jacksonsweet/Projects/OPS/ops-site
npm run test:spec-cron
```

Expected: exit 0 with all SPEC cron tests passing.

- [ ] **Step 4: Record ops-site evidence**

Append:

```markdown
## ops-site Build Evidence

- Command: `npm run build`
- Result: PASS
- Command: `npm run test:spec-cron`
- Result: PASS
- Env names verified without secret values:
```

- [ ] **Step 5: Commit evidence**

Run:

```bash
cd /Users/jacksonsweet/Projects/OPS/ops-software-bible
git add docs/spec-launch/branch-build-readiness-evidence.md
git commit -m "docs: record ops-site SPEC build evidence"
```

Expected: commit includes only the evidence update.
