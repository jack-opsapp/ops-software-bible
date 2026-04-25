# Local launchd setup for nightly bug triage

The remote claude.ai routine path is blocked by Anthropic's egress proxy
(it can't reach `app.opsapp.co`). This directory holds the equivalent setup
that runs on your Mac via `launchd`, with `pmset` waking the Mac if it's
asleep.

## What it does

Two daily jobs:

| Label | Local time | Script | Logs |
|---|---|---|---|
| `co.opsapp.nightly-bug-triage-web` | 03:00 | `nightly-bug-triage-web.sh` | `~/Library/Logs/ops-nightly/web-YYYY-MM-DD.log` |
| `co.opsapp.nightly-bug-triage-ios` | 03:15 | `nightly-bug-triage-ios.sh` | `~/Library/Logs/ops-nightly/ios-YYYY-MM-DD.log` |

Each script:
1. Hard-syncs `~/.cache/ops-nightly/{platform-repo,bible}` to `origin/main` (your working copies are untouched).
2. Sources `~/.config/ops-nightly/env` for `BUG_TRIAGE_AGENT_TOKEN`.
3. Invokes `claude --print --dangerously-skip-permissions --add-dir ...` with the orchestrator prompt.
4. Streams everything to today's log file.

The orchestrator follows `_shared-triage-logic.md`: drains the bug backlog
in batches of 10, delegates each batch to a fresh sub-agent, runs review-pass
for complex bugs, opens one PR per batch.

## Install

```bash
# 1) Make scripts executable.
chmod +x ~/Projects/OPS/ops-software-bible/scheduled-agents/local/nightly-bug-triage-{web,ios}.sh

# 2) Create the env file.
mkdir -p ~/.config/ops-nightly
cp ~/Projects/OPS/ops-software-bible/scheduled-agents/local/env.example ~/.config/ops-nightly/env
chmod 600 ~/.config/ops-nightly/env
$EDITOR ~/.config/ops-nightly/env   # paste BUG_TRIAGE_AGENT_TOKEN

# 3) Copy the launchd plists into the user LaunchAgents dir.
mkdir -p ~/Library/LaunchAgents
cp ~/Projects/OPS/ops-software-bible/scheduled-agents/local/co.opsapp.nightly-bug-triage-{web,ios}.plist ~/Library/LaunchAgents/

# 4) Load them.
launchctl load -w ~/Library/LaunchAgents/co.opsapp.nightly-bug-triage-web.plist
launchctl load -w ~/Library/LaunchAgents/co.opsapp.nightly-bug-triage-ios.plist

# 5) Schedule the Mac to wake at 02:55 every day so 03:00 fires.
sudo pmset repeat wakeorpoweron MTWRFSU 02:55:00
# Verify with: pmset -g sched

# 6) Verify GitHub auth — the scripts push branches and call `gh pr create`.
#    Make sure the `gh` CLI is logged into both jack-opsapp and jackson-sweet:
gh auth status
```

## Test runs (manual)

Fire either job immediately to verify before tomorrow night:

```bash
launchctl start co.opsapp.nightly-bug-triage-web
# or:
~/Projects/OPS/ops-software-bible/scheduled-agents/local/nightly-bug-triage-web.sh
```

Watch the log:

```bash
tail -f ~/Library/Logs/ops-nightly/web-$(date +%Y-%m-%d).log
```

## Inspect / control

```bash
# Show the loaded jobs.
launchctl list | grep opsapp

# Disable temporarily (clears wake schedule too).
launchctl unload ~/Library/LaunchAgents/co.opsapp.nightly-bug-triage-web.plist
sudo pmset repeat cancel

# Cancel the scheduled wake without unloading the job.
sudo pmset repeat cancel
```

## Caveats

- **Mac must be plugged in** for `pmset repeat wakeorpoweron` to wake from sleep on AC. If it's on battery and lid is closed, the wake won't fire.
- **PATH in launchd plists is hardcoded** to `/Users/jacksonsweet/.local/bin:/opt/homebrew/bin:...`. If you reinstall `claude` to a different prefix, update both plists.
- **Cost**: each nightly run consumes Claude API tokens against whatever auth your local `claude` CLI is using (OAuth login by default). Expect roughly $3-15 per run depending on backlog size and bug complexity. Worst case (full 200-bug nights, 20 batches × 2 platforms) ~$150-300 in a single night.
- **The disabled remote routines on https://claude.ai/code/routines** are dead — don't re-enable them. Delete from the UI when convenient.
