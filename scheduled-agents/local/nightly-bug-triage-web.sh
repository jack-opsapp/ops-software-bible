#!/bin/bash
# Nightly Bug Triage — Web (local launchd version).
# Uses isolated clones under ~/.cache/ops-nightly/ so it never touches your
# working copies. The orchestrator pulls main, drains the bug-triage backlog,
# and pushes branches + opens PRs to jack-opsapp/ops-web.
#
# Logs: ~/Library/Logs/ops-nightly/web-YYYY-MM-DD.log
# Env file: ~/.config/ops-nightly/env (chmod 600). Must export
#   BUG_TRIAGE_AGENT_TOKEN. Optionally ANTHROPIC_API_KEY (otherwise CLI uses
#   your existing claude login).

set -euo pipefail

# ----- Paths -----
NIGHTLY_HOME="$HOME/.cache/ops-nightly"
PLATFORM_DIR="$NIGHTLY_HOME/ops-web"
BIBLE_DIR="$NIGHTLY_HOME/ops-software-bible"
LOG_DIR="$HOME/Library/Logs/ops-nightly"
ENV_FILE="$HOME/.config/ops-nightly/env"

# ----- Setup -----
mkdir -p "$NIGHTLY_HOME" "$LOG_DIR" "$(dirname "$ENV_FILE")"
LOG_FILE="$LOG_DIR/web-$(date +%Y-%m-%d).log"

# All output (script + claude) tees into the daily log.
exec > >(tee -a "$LOG_FILE") 2>&1

echo ""
echo "===== Nightly Bug Triage — Web — $(date -u +%Y-%m-%dT%H:%M:%SZ) ====="

# ----- Env -----
if [[ ! -f "$ENV_FILE" ]]; then
  echo "FATAL: missing $ENV_FILE (must export BUG_TRIAGE_AGENT_TOKEN). See README.md."
  exit 1
fi
chmod 600 "$ENV_FILE" 2>/dev/null || true
# shellcheck source=/dev/null
source "$ENV_FILE"

if [[ -z "${BUG_TRIAGE_AGENT_TOKEN:-}" ]]; then
  echo "FATAL: BUG_TRIAGE_AGENT_TOKEN not set in $ENV_FILE"
  exit 1
fi
export BUG_TRIAGE_AGENT_TOKEN
[[ -n "${ANTHROPIC_API_KEY:-}" ]] && export ANTHROPIC_API_KEY

# ----- Sync isolated clones -----
sync_clone() {
  local url="$1"
  local dir="$2"
  if [[ -d "$dir/.git" ]]; then
    echo "[sync] $dir → fetching + hard-reset to origin/main"
    git -C "$dir" fetch origin --quiet
    git -C "$dir" reset --hard origin/main --quiet
    git -C "$dir" clean -fdq
  else
    echo "[sync] $dir → fresh clone"
    rm -rf "$dir"
    git clone --quiet "$url" "$dir"
  fi
}

sync_clone "https://github.com/jack-opsapp/ops-web.git" "$PLATFORM_DIR"
sync_clone "https://github.com/jack-opsapp/ops-software-bible.git" "$BIBLE_DIR"

# ----- npm install (so the orchestrator's sub-agents can run type-check + build) -----
echo "[deps] npm ci in $PLATFORM_DIR"
(cd "$PLATFORM_DIR" && npm ci --silent --no-audit --no-fund) || {
  echo "WARN: npm ci failed; sub-agents may not be able to build."
}

# ----- Run the orchestrator -----
PROMPT_FILE=$(mktemp)
trap 'rm -f "$PROMPT_FILE"' EXIT

cat > "$PROMPT_FILE" <<'PROMPT_EOF'
You are the Nightly Bug Triage orchestrator for OPS-Web.

## Working directory layout
- Platform repo (you operate inside this): the directory passed via `--add-dir` (will be `~/.cache/ops-nightly/ops-web`)
- Spec / contract files (read-only): `~/.cache/ops-nightly/ops-software-bible/scheduled-agents/`
- Both repos are already on origin/main, hard-reset, deps installed.

## Step 1 — Read the contract in full
- `~/.cache/ops-nightly/ops-software-bible/scheduled-agents/_shared-triage-logic.md`
- `~/.cache/ops-nightly/ops-software-bible/scheduled-agents/nightly-bug-triage-web.md`
- `~/.cache/ops-nightly/ops-software-bible/scheduled-agents/_batch-fix-prompt.md`
- `~/.cache/ops-nightly/ops-software-bible/scheduled-agents/_review-pass-prompt.md`

The platform spec lists local Mac paths (e.g. `/Users/jacksonsweet/Projects/OPS/OPS-Web`) — substitute `~/.cache/ops-nightly/ops-web` instead.

## Step 2 — Execute the orchestrator loop for platform = 'web'

Per `_shared-triage-logic.md`:
  1. `GET https://app.opsapp.co/api/cron/bug-triage/backlog?platform=web&limit=200` with `Authorization: Bearer $BUG_TRIAGE_AGENT_TOKEN` (the token is in your env, never echo it).
  2. Report backlog size in your first message.
  3. Split into batches of 10 (oldest first).
  4. For each batch sequentially:
     a. Claim items via `POST /api/cron/bug-triage/update` with `updates: { status: 'in_progress', claimed_at: 'now' }`.
     b. Spawn a fresh **Batch Fix** sub-agent (`Agent` tool, `subagent_type: general-purpose`) using the prompt template in `_batch-fix-prompt.md`.
     c. After return, for each bug classified `complex: true`, spawn a fresh **Review Pass** sub-agent using `_review-pass-prompt.md` targeting the PR.
     d. Continue.
  5. Stop on: empty backlog, 20 batches processed, OR 2 consecutive sub-agent failures.

## Hard rules
- You DO NOT fix bugs yourself. Delegate to fresh sub-agents.
- Sub-agents run `npm run type-check && npm run build` before each commit. Soft-fail on pre-existing breaks per the web spec.
- Never amend, force-push, or `git add -A` / `git add .` — explicit file paths only.
- Never set status to `resolved` / `closed` (API rejects).
- Never touch tests or migrations.
- Never silence type errors with `as any` — escalate via `requires_human_review`.
- Claude co-author tag is permitted on web commits.

Begin now.
PROMPT_EOF

echo "[claude] starting orchestrator (max-turns=200)"

# --add-dir lets claude see both repos. --print runs headless and exits.
# --dangerously-skip-permissions is required for unattended runs (no TTY for prompts).
claude \
  --print \
  --dangerously-skip-permissions \
  --add-dir "$PLATFORM_DIR" \
  --add-dir "$BIBLE_DIR" \
  --max-turns 200 \
  < "$PROMPT_FILE"

echo "===== Done — $(date -u +%Y-%m-%dT%H:%M:%SZ) ====="
