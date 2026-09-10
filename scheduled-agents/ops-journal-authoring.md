# OPS Journal authoring (Cloud Routine)

Status (2026-09-10): **not created.** It is created disabled at release step 5 of `ops-web/docs/journal/cloud-editorial-operations.md`, after the ops-web release is deployed, the `OPS Journal` environment carries its API credential, and Jackson gives the go.

| Field | Value |
|---|---|
| Name | `OPS Journal authoring` |
| Schedule | `0 13,21 * * 0` UTC (Sunday 06:00 and 14:00 Vancouver) |
| Model | `claude-opus-5` |
| Environment | `OPS Journal` (Trusted network) with an API credential for host `app.opsapp.co` (Bearer `JOURNAL_AUTHORING_TOKEN`), separate from Instagram's `Default` environment so each token reaches only its own routes |
| Repositories / connectors | none / none (cleared after create; `RemoteTrigger create` attaches every connector by default) |
| Tools | `Bash, Read, Write, Edit, Agent, WebSearch` — no WebFetch: pages are read only through OPS |
| Prompt | canonical copy in `ops-web/docs/journal/cloud-authoring-routine.md`, version `journal-routine-prompt-2026-09-10-v1`; edit there first, then `/schedule update` |

What it does per run: claims the week's `journal_editorial_assignments` slot over `POST /api/internal/journal/editorial/claim`, reads the bundled journal brief (governing voice), the Sam Parr blog layer and the OPS product facts, chooses an evergreen topic (backlog first), finds sources with WebSearch and has OPS fetch each one (`…/sources`), writes a 1,000–1,400-word article with FAQs and an email version in the candidate shape, runs one independent editor subagent that verifies every claim and number against the fetched pages, revises once on rejection, and returns the draft to `…/draft`, fixing any 422 codes. It never publishes, never writes a database, reaches no other host, and never prints credentials. Usage draws the subscription and the account's daily routine allowance; a refused run leaves the slot queued and OPS raises `JOURNAL WRITER STALLED` 12 hours before launch. Usage credits stay off, so nothing is ever billed as overage.

Manual run: `/schedule run OPS Journal authoring` or **Run now** at claude.ai/code/routines. It claims only a slot that is open (72 hours before its Monday).
