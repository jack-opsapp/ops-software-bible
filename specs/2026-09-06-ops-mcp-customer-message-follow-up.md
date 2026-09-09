# OPS MCP customer-message follow-up

**Status:** released to production on 2026-09-06 and independently read back. The capability remains dormant.

## Product contract

Phase 13 prepares one reply to one existing customer email. It is not a general email composer, outreach tool, campaign tool, or autonomous sending surface. The operator supplies a subject and body for an existing job conversation. OPS resolves the only permitted sender, recipient, source message, and thread from current stored provider evidence.

The review in OPS shows the exact personal mailbox, one customer recipient, subject, body, source excerpt, source timestamp, job, thread, expiry, and effects. Approval is named, single use, expires after 30 minutes, and binds the entire preview by SHA-256. Any edit requires a new prepare call and a new preview. No approval payload can replace the sender, recipient, subject, body, thread, source, CC, BCC, or attachments.

The first release installs dormant software only. Active production remains capability manifest v20, MCP exposure v14, and consent catalogue v9. Candidate manifest v21 and exposure v15 are not selectable. Consent v10 is referenced by the database authority fence but is deliberately not installed. No client or grant can therefore authorize Phase 13 until a separate activation is explicitly approved.

## Source and authority

`prepare_customer_message` accepts only:

- `opportunity_id`
- the exact opportunity `updated_at`
- `source_activity_id`
- the exact immutable provider `source_sha256`
- subject
- body
- idempotency key

The caller cannot provide a recipient, sender, thread, CC, BCC, attachment, or new-outreach target. The database requires an active named actor, exact v21/v15 capability identity, exact future v10 grant identity, and all-scope `agent.review`, `clients.view`, `inbox.send`, `inbox.view`, and `pipeline.view`. Required OAuth scopes are `ops.communications.prepare`, `ops.correspondence.read`, `ops.customers.read`, and `ops.jobs.read`.

The source must be an inbound, normalized, attachment-free provider delivery linked to the same company, job, customer, personal mailbox, and canonical email thread. Its sender becomes the only recipient. The mailbox must belong to the named actor, remain active, and pass the existing job-inbox send boundary. Any newer provider message in the thread invalidates preparation and approval. The complete current source is hashed and rechecked before approval and again under the provider claim.

Correspondence and draft text remain untrusted business data. They never confer authority or alter the exact approval requirement.

## Persistence and approval

`private.agent_customer_messages` is the force-RLS proposal ledger. Application roles, including service role, have no direct table privileges. It stores the actor, company, OAuth client and grant, permission revision, exact request, request hash, current-source hash, policy revision, preview, preview hash, expiry, approval or rejection, and the latest truthful receipt.

`private.agent_customer_message_policy` seals the installed send and authorization helpers. Preparation fails closed if those effects drift.

`prepare_agent_customer_message_as_system` is service-role only. It serializes idempotency, refuses a changed request under the same key, permits exact replay only while the source and approval remain current, and creates one private proposal, one actor-owned pending `send_customer_follow_up` action, and one persistent review notification. A second unresolved proposal cannot target the same inbound provider source.

`approve_agent_customer_message_as_actor` is service-role only and requires the named actor, company, action, change set, exact preview digest, and deterministic approval key. It reauthorizes the actor and grant, locks and rechecks the source, then marks the exact action approved. It does not call an email provider.

`reject_agent_customer_message_as_actor` records `cancelled_before_send` only while the action is pending and no durable email intent exists. Cancellation after provider preparation is refused.

The approval desk excludes this action from bulk and autonomous execution. It submits only `change_set_id` and `preview_sha256`. It then calls the established manual approved-email transport. A retry resumes the same action and durable intent. If an exception occurs after the provider boundary becomes owned or cannot be classified, the UI reports reconciliation in progress and never creates another send.

## Existing transport reuse

The migration extends the closed action allowlist in the existing approved-action email transport through a source-drift-checked function rewrite. It wraps every accumulated transport authorization guard and adds `agent_customer_message_intent_is_current` at intent preparation and provider claim.

The new guard requires exact equality for:

- manual execution and named approver
- action-data snapshot and preview seal
- personal connection
- opportunity and customer
- source activity
- internal and provider thread
- `In-Reply-To`
- one `To` address
- empty CC
- subject and authored body
- current provider source with no later correspondence

Signature resolution, mailbox serialization, provider idempotency, provider acceptance, unknown-outcome quarantine, reconciliation, immutable outbound activity capture, and thread linking remain owned by the existing transport.

## Truthful receipts

The action and proposal receive a refreshed receipt whenever the durable intent or action changes. States are:

- `approved_queued`: approved or awaiting a usable signature; no provider attempt claimed
- `attempted`: the durable provider claim is owned
- `provider_accepted`: provider message and thread identity exist; delivery is not claimed
- `reconciled_sent`: OPS persisted the outbound activity and reconciliation timestamp
- `provider_rejected`: the provider definitively rejected the send
- `failed`: a definitive local failure before a provider-owned outcome
- `cancelled_before_send`: rejected while still cancellable
- `unknown`: provider outcome cannot safely be classified and must reconcile

`delivered_at` is always null because the existing provider path reports acceptance, not delivery. A future provider delivery event may add a distinct state only with direct provider evidence.

## Verification

The disposable PostgreSQL 17 contract parses and applies the migration, proves the transport source rewrite, checks service-only grants, executes prepare and exact replay, rejects a substituted preview digest, approves the exact message, advances a durable intent through provider acceptance and reconciled sent, and confirms every receipt keeps `delivered_at = null`.

TypeScript contracts reject caller-supplied recipients, CC, BCC, attachments, and unknown keys. Service tests prove v21/v15 authority binding and reauthorization. Approval tests prove exact seal submission, one manual transport call, no autonomous call, cancellation through the domain RPC, and no blind resend after an uncertain provider boundary. Registry tests prove candidate v21/v15 composition while active v14 remains unchanged. The focused queue and UI tests prove exact addressing, source evidence, expiry, and approval payload.

The earlier delivery-source re-projection replay failure is fixed by `20260906040000_delivery_source_reprojection_replay.sql`. Identical recapture now succeeds after normalization while changed provider bytes still conflict and the original immutable source digest remains unchanged.

Production release evidence:

- Supabase recorded `delivery_source_reprojection_replay` as migration `20260906230408` and `agent_customer_message_follow_up` as migration `20260906230457`.
- The production policy seal matches the installed transport and authority helpers, both private ledgers force RLS, and both receipt triggers are installed.
- Production contains zero Phase 13 message proposals, zero `send_customer_follow_up` actions, zero v15 OAuth clients, and zero live v15 grants.
- The existing Phase 12 authority is unchanged: production contains one v14 client and one live v14 grant.
- OPS Web commit `4907dc649c28009079a600c78e7bbdcdb26b502e` deployed successfully through Vercel and is served by `app.opsapp.co`.
- The live protected-resource metadata and unauthenticated MCP challenge advertise the v14 scope set and omit `ops.communications.prepare`. The MCP endpoint continues to reject unauthenticated requests.
- The merged production build passed, and the focused compatibility suite passed all 234 tests across 32 files. The final Phase 13 vertical check passed all 27 tests across six files.

## Release boundary

The dormant database and web software are now in production. This release did not install consent v10, activate exposure v15, create or remint any client or grant, accept a host, prepare a customer message, create an approval action, or call an email provider. Phase 13 therefore remains unavailable to every production caller. Activation and the first real customer send remain separate exact approvals.
