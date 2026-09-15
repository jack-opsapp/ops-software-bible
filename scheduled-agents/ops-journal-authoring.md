# OPS Journal authoring (Cloud Routine)

Status (2026-09-15): **created and enabled** — `trig_01NbGDkXXigXTR9K2FYPjZCk`, environment `OPS Journal` (`env_01Rb152WvLvqkQHhHFHmBbQz`), created 2026-09-10 via the RemoteTrigger API, connectors cleared, enabled by Jackson 2026-09-10. First scheduled runs 2026-09-13: 06:05 Vancouver wrote `weekly:2026-09-14` (AUTHORED), 14:05 found nothing (IDLE, 16 s). Prompt updated to v2 on 2026-09-15 (art direction for a generated photograph replaces the plate line).

| Field | Value |
|---|---|
| Name | `OPS Journal authoring` |
| Schedule | `0 13,21 * * 0` UTC (Sunday 06:00 and 14:00 Vancouver) |
| Model | `claude-opus-5` |
| Environment | `OPS Journal` (Trusted network) with an API credential for host `app.opsapp.co` (Bearer `JOURNAL_AUTHORING_TOKEN`), separate from Instagram's `Default` environment so each token reaches only its own routes |
| Repositories / connectors | none / none (cleared after create; `RemoteTrigger create` attaches every connector by default) |
| Tools | `Bash, Read, Write, Edit, Agent, WebSearch` — no WebFetch: pages are read only through OPS |
| Prompt | canonical copy in `ops-web/docs/journal/cloud-authoring-routine.md`, version `journal-routine-prompt-2026-09-15-v2`; edit there first, then `/schedule update` (RemoteTrigger `update` with the full `job_config`) |

What it does per run: claims the week's `journal_editorial_assignments` slot over `POST /api/internal/journal/editorial/claim`, reads the bundled journal brief (governing voice), the Sam Parr blog layer and the OPS product facts, chooses an evergreen topic (backlog first), finds sources with WebSearch and has OPS fetch each one (`…/sources`), writes a 1,000–1,400-word article with FAQs, an email version and the header photograph's art direction (`image_prompt`, judged against the brief's composed-not-posed, residential, warm, wide rules and the eight `recent_images`) in the candidate shape, runs one independent editor subagent that verifies every claim and number against the fetched pages, revises once on rejection, and returns the draft to `…/draft`, fixing any 422 codes. It never publishes, never writes a database, reaches no other host, and never prints credentials. Usage draws the subscription and the account's daily routine allowance; a refused run leaves the slot queued and OPS raises `JOURNAL WRITER STALLED` 12 hours before launch. Usage credits stay off, so nothing is ever billed as overage.

Manual run: `/schedule run OPS Journal authoring` or **Run now** at claude.ai/code/routines. It claims only a slot that is open (72 hours before its Monday).
