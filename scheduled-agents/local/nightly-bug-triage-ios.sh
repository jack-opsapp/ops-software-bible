#!/bin/bash
# Nightly Bug Triage — iOS (local launchd version).
# Uses isolated clones under ~/.cache/ops-nightly/ so it never touches your
# working copies. The orchestrator pulls main, drains the iOS bug-triage
# backlog, and pushes branches + opens PRs to jackson-sweet/opsapp.
#
# Logs: ~/Library/Logs/ops-nightly/ios-YYYY-MM-DD.log
# Env file: ~/.config/ops-nightly/env (chmod 600). Must export
#   BUG_TRIAGE_AGENT_TOKEN. Optionally ANTHROPIC_API_KEY.

set -euo pipefail

# ----- Paths -----
NIGHTLY_HOME="$HOME/.cache/ops-nightly"
PLATFORM_DIR="$NIGHTLY_HOME/opsapp"
BIBLE_DIR="$NIGHTLY_HOME/ops-software-bible"
LOG_DIR="$HOME/Library/Logs/ops-nightly"
ENV_FILE="$HOME/.config/ops-nightly/env"

mkdir -p "$NIGHTLY_HOME" "$LOG_DIR" "$(dirname "$ENV_FILE")"
LOG_FILE="$LOG_DIR/ios-$(date +%Y-%m-%d).log"

exec > >(tee -a "$LOG_FILE") 2>&1

echo ""
echo "===== Nightly Bug Triage — iOS — $(date -u +%Y-%m-%dT%H:%M:%SZ) ====="

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

sync_clone "https://github.com/jackson-sweet/opsapp.git" "$PLATFORM_DIR"
sync_clone "https://github.com/jack-opsapp/ops-software-bible.git" "$BIBLE_DIR"

# ----- Verify Xcode is selected (sub-agents will run xcodebuild) -----
if ! xcode-select -p >/dev/null 2>&1; then
  echo "FATAL: no Xcode selected. Run: sudo xcode-select -s /Applications/Xcode.app"
  exit 1
fi
echo "[xcode] using $(xcode-select -p)"

# ----- Run the orchestrator -----
PROMPT_FILE=$(mktemp)
trap 'rm -f "$PROMPT_FILE"' EXIT

cat > "$PROMPT_FILE" <<'PROMPT_EOF'
You are the Nightly Bug Triage orchestrator for the OPS iOS app.

## Working directory layout
- Platform repo: `~/.cache/ops-nightly/opsapp`
- Spec / contract files: `~/.cache/ops-nightly/ops-software-bible/scheduled-agents/`
- Both repos are already on origin/main, hard-reset.

## Step 1 — Read the contract in full
- `~/.cache/ops-nightly/ops-software-bible/scheduled-agents/_shared-triage-logic.md`
- `~/.cache/ops-nightly/ops-software-bible/scheduled-agents/nightly-bug-triage-ios.md`
- `~/.cache/ops-nightly/ops-software-bible/scheduled-agents/_batch-fix-prompt.md`
- `~/.cache/ops-nightly/ops-software-bible/scheduled-agents/_review-pass-prompt.md`

Substitute `~/.cache/ops-nightly/opsapp` for any `/Users/jacksonsweet/Projects/OPS/OPS` paths in the spec.

## Step 2 — Execute the orchestrator loop for platform = 'ios'

Per `_shared-triage-logic.md`:
  1. `GET https://app.opsapp.co/api/cron/bug-triage/backlog?platform=ios&limit=200` with `Authorization: Bearer $BUG_TRIAGE_AGENT_TOKEN`.
  2. Report backlog size in your first message.
  3. Split into batches of 10 (oldest first).
  4. For each batch sequentially:
     a. Claim items via `POST /api/cron/bug-triage/update` with `updates: { status: 'in_progress', claimed_at: 'now' }`.
     b. Spawn a fresh **Batch Fix** sub-agent (`Agent` tool, `subagent_type: general-purpose`) using `_batch-fix-prompt.md`.
     c. After return, for each `complex: true` bug, spawn a fresh **Review Pass** sub-agent using `_review-pass-prompt.md`.
     d. Continue.
  5. Stop on: empty backlog, 20 batches processed, OR 2 consecutive sub-agent failures.

## Hard rules
- You DO NOT fix bugs yourself. Delegate to fresh sub-agents.
- Sub-agents run `xcodebuild -scheme OPS -destination 'generic/platform=iOS' -quiet` before each commit. Never use `iOS Simulator` destinations.
- **Never add Claude as git co-author on iOS commits** (per OPS iOS CLAUDE.md).
- Never amend, force-push, or `git add -A` / `git add .`.
- Never set status to `resolved` / `closed`.
- Never touch tests, migrations, or `OPS.xcodeproj/project.pbxproj` (unless absolutely required).

Begin now.
PROMPT_EOF

echo "[claude] starting orchestrator (max-turns=200)"

claude \
  --print \
  --dangerously-skip-permissions \
  --add-dir "$PLATFORM_DIR" \
  --add-dir "$BIBLE_DIR" \
  --max-turns 200 \
  < "$PROMPT_FILE"

echo "===== Done — $(date -u +%Y-%m-%dT%H:%M:%SZ) ====="
