# MCP Mount — Claude First (2026-08-18)

**Status:** **PRODUCTION-LIVE AND OPERATIONAL — expanded 2026-08-22 UTC.** The MCP mount is merged into ops-web `main`, deployed at `https://app.opsapp.co/api/mcp`, and backed by the production OAuth, control-plane, discovery, and indexed-writer ACL ledgers. The cursor key is provisioned. Claude remains dynamically registered with one active OPS OAuth grant, and the immutable audit records real production use. Exactly eleven read tools are exposed, including `search_customers` and `search_jobs`; every write and site-visit capability remains disabled. The discovery rollout used OPS-Web release commit `5eb4b561c14cf8dace2b906d50ebcd34a0ba13db` and READY deployment `dpl_6ZMAhdXuweX9jSuVG8T58Z5gzWko`, then revoked and deleted its disposable canary credentials without touching Claude's grant. Plan: `specs/plans/2026-08-18-mcp-mount-claude-first-P1-plan.md`. Full record: `04_API_AND_INTEGRATION.md` § "OPS Remote MCP Server — P1 Mount, Claude First".

**Local P2 update (2026-08-29):** A separate isolated branch now implements the complete thirty-four-read business catalogue, including the site-visit and deck-geometry flow. It does not alter this production-live P1 status: the P2 migrations are unapplied, code is unpushed/undeployed, exposure v1 still lists eleven reads, and no ChatGPT host has been proven. See `specs/2026-08-29-mcp-read-catalogue-p2.md`.

The build also found and repaired four production defects in the Task 13 job-catalog read RPCs — its E2E was their first-ever production execution, and plpgsql's lazy validation had hidden them behind the wave's parse verification. See the API chapter section above for the four defect classes and ledgers `20260818174706` / `20260818175549`.

**Original scoping (2026-08-18):** Jackson ruled that Claude is the first external host to connect to the OPS agent control plane. This document scopes the mounting initiative; the build session produces the implementation plan.

**Parent design:** `specs/2026-08-07-ops-agent-control-plane-mcp-foundation.md` (+ its status updates). The control plane's database and code halves are live in production as of 2026-08-18 — see `04_API_AND_INTEGRATION.md` § "Agent Control Plane Cutover — Applied and Deployed (2026-08-18)".

## Historical starting state (verified before implementation on 2026-08-18)

The bullets in this section are retained as the build baseline. They are not current production status; the status block above records the completed rollout.

- The MCP surface is deliberately dark: `/api/mcp` returns 404; no route under `src/app/` imports `agent-control-plane`. The only MCP artifact is `src/lib/agent-control-plane/mcp/sdk.ts`, unmounted.
- Capability manifest `2026-08-14.capability-manifest.v6`: nine reads are `implementation=available` for internal composition only; every `externalExposure` is `disabled`.
- Remote MCP transport and OAuth are unbuilt (per the foundation spec, unchanged by the cutover).
- `OPS_AGENT_OPERATIONAL_READ_CURSOR_KEY` is blank in production — the operational-read cursor codec requires a provisioned 32-byte key (64 lowercase hex chars) before any external read can page.
- Actor authority, tenant roots, provider-delivery provenance, conversation memory, schedule confirmation, and the readiness reads are all live at the database layer (12 wave migrations + corrective `20260818052612`).
- Auto-send remains OFF (`INBOX_AUTO_SEND_ENABLED` unset). Nothing in this initiative changes outbound posture.

## P1 scope — Claude connects, read-only

Deliver an OPS remote MCP server that a claude.ai / Claude Desktop user can add as a custom connector and use against their own company's data:

1. **Transport:** mount the MCP server over the current-spec remote transport (streamable HTTP) at a dedicated route. The build session verifies the current MCP transport requirements for claude.ai custom connectors at build time rather than trusting this document.
2. **AuthN/AuthZ:** OAuth flow suitable for claude.ai custom connectors, binding each connection to a single OPS user account. The mapped user flows through the existing actor-authority layer (`resolve_agent_actor_authority` lineage) — the MCP layer never invents authority, mirroring how Phase C's internal adapter resolves actors. Company scoping derives from the authenticated user, never from tool arguments.
3. **Capability set:** the nine v6 reads only, flipped to externally exposed one by one behind the server-owned manifest. Read-only; no mutation capability of any kind mounts in P1.
4. **Cursor key:** provision `OPS_AGENT_OPERATIONAL_READ_CURSOR_KEY` in Vercel production (Jackson-gated env change) and prove readback without exposure.
5. **Safety rails:** per-connection rate limiting, request logging with actor identity, and the existing prompt-safety serialization on every read result.

## P1 non-goals

- ChatGPT or any other host (follows Claude once the pattern is proven).
- Any write/mutation capability — no schedule confirmation, no catalog authoring, no estimate/invoice allocation, no email drafting through MCP.
- Phase C behavior changes (the reply shadow, memory context switch, and release gates are a separate, already-specified track).
- Auto-send posture changes.

## Verification bar for P1

- Live connector handshake from a real claude.ai account (Jackson's), tool listing visible in the Claude UI.
- Scoped reads exercised against MAVERICK PROJECTS LTD (`ddee107c-33cd-483e-8278-0f8d8a180181`), the designated test company.
- Tenant-isolation probes: an actor bound to one company must receive sentinel errors, not data, for any other company's identifiers.
- The dark-until-now guarantee holds for unauthenticated traffic: unauthenticated `/api/mcp` requests are rejected without capability disclosure.

## Jackson-gated steps — completed 2026-08-20

- Production cursor-key environment variable provisioned and accepted by the live runtime.
- Connector added to Claude and OAuth consent completed.
- MCP mount merged to `main` and deployed to `app.opsapp.co`.
