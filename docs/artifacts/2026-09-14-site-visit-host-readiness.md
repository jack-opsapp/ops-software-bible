# Site-visit native-host readiness — 2026-09-14

**Superseding implementation update:** the restricted connection path is now implemented and its database lifecycle is production-installed. See [the trial release record](2026-09-14-site-visit-trial-release.md) for application rollout and remaining phone/host prerequisites. The observations below remain the pre-implementation evidence; “unimplemented” below is historical, not the current source status.

Status: database rollout and phone installation are complete as recorded in the [release receipt](2026-09-14-site-visit-choice-release.md). Native site-visit prepare/review/save acceptance remains blocked by the unimplemented restricted OAuth activation path and inactive company authority. No business write or permission change was performed during this check.

## Fresh observations

- A real native Codex `get_company_context({})` call succeeded at `2026-09-14T16:27:30.687Z`. It returned **Canpro Deck and Rail**, not MAVERICK. This proves authenticated company reading only.
- Native tool discovery exposes 35 OPS tools. It includes the existing `list_site_visits` and `get_site_visit_context` reads, but none of the new site-visit preparation or template operations. No native site-visit write tool was called.
- The in-app OPS browser settled on the financial-policy page signed in as **MAVERICK PROJECTS LTD / Pete Mitchell**. This is a separate web session, not evidence of a MAVERICK-bound native MCP grant. No form, consent, or policy control was submitted. The financial-policy page is not a site-visit activation surface.
- Narrow production metadata readback confirmed both private activation tables exist with RLS enabled. At `2026-09-14T16:30:37.903535Z`, `private.site_visit_concurrency_companies` and `private.agent_site_visit_workflow_effect_policy` each had **zero rows**. No full function source, grant credentials, or authority records were exported.

## Activation is an implementation boundary, not only a reconnect

Reviewed OPS-Web source: owned phase branch `babe8ec1da3a15b417399eb872f979057278d755`; the two files below are byte-identical on local main `244a11ed5` at this check.

- `src/lib/agent-control-plane/registry/mcp-exposure-catalog.ts` defines the frozen site-visit V22 candidate but keeps public registration on V23.
- `src/lib/agent-control-plane/mcp/oauth/canary.ts` does not resolve V22 for an OAuth subject. Its restricted trial selection covers existing catalog, financial, and V3 candidates, not site visits.
- `src/app/api/mcp/oauth/register/route.ts` uses the active public exposure. Reconnecting an ordinary public client alone therefore does not establish the reserved site-visit trial. Editing an existing Canpro grant or broadly changing the public default is not an acceptable substitute.

The next bounded implementation is an exact actor/company/client-bound site-visit trial path, preserving frozen V22 tools/scopes and V17 consent. Production compatibility/effect enrollment and host access require separate exact approval and fresh host consent; installed-phone pending-work recovery must be verified before shared-write activation. Every save remains subject to its exact OPS review. No Canpro activation, financial/catalog resealing, provider messaging, or general public exposure expansion is included.

After activation, proof still requires a real MAVERICK-bound native prepare → OPS review → exact save → independent readback/revocation, followed by physical-device offline/reconnect/conflict/media checks. Local tests and installation receipts do not substitute for those results.

No application source, migrations, business records, credentials, subscriptions, or paid API settings changed during this check. The shared iOS build baton was released by the expense task; this task started no new build. A minimal status-only reply was sent to that task in response to its coordination request; sensitive production/device details were not forwarded.
