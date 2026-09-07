# OPS Instagram authoring (Cloud Routine)

Status (2026-09-07): routine created on Jackson's claude.ai account, **disabled**. Enable only after the ops-web release that adds the handoff routes is deployed, the environment API credential exists, and Jackson gives the go.

| Field | Value |
|---|---|
| Routine id | `trig_011aQJD1UqqmG2DVkzHAQTS1` |
| Name | `OPS Instagram authoring` |
| Schedule | `0 15,21 * * *` UTC (08:00 and 14:00 Vancouver, daily) |
| Model | `claude-opus-5` |
| Environment | `env_01SbMVBKxZJvyDPXKYoNkkW5` (Default) with an API credential for host `app.opsapp.co` (Bearer `SOCIAL_AUTHORING_TOKEN`) |
| Repositories / connectors | none / none (cleared; `RemoteTrigger create` attaches every connector by default, so always clear after creating) |
| Tools | `Bash, Read, Write, Edit, Agent` |
| Prompt | canonical copy in `ops-web/docs/social/cloud-authoring-routine.md`, version `routine-prompt-2026-09-07-v1`; edit there first, then `/schedule update` |

What it does per run: claims up to four `social_editorial_assignments` over `POST /api/internal/social/editorial/claim`, writes each draft from the returned brief + complete Sam Parr guide, runs an independent editor subagent, revises once on rejection, and returns the draft to `…/assignments/{id}/draft`. It never renders, publishes, reaches any other host, or prints credentials. Usage draws the subscription and the account's daily routine allowance; a refused run leaves work queued and OPS raises `INSTAGRAM AUTHORING STALLED` after 26 hours of silence.

Manual run: `/schedule run OPS Instagram authoring` or **Run now** at claude.ai/code/routines. Debug: `/schedule why did OPS Instagram authoring do nothing` (lists runs, reads logs).
