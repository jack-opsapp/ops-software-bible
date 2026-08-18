# LEAD ↔ PROJECT IDENTITY — Design (Fable, 2026-08-18)

Authoritative design for bugs d80c5c70, 967bd985, 3799225e, 9a89b951, d1eaebe1 and hazards H1-H10 from the P1-35 investigation. Every file:line below came from that investigation and must be re-verified in code before editing.

## The four decisions (DECIDED — do not re-litigate, implement)

### D1. A human's choice IS the evidence. Address gates CREATE only, never MATCH.
The server already implements this correctly: `convert_opportunity_to_project` applies `address_required` / `matching_project_requires_review` ONLY in the `v_link_to_project_id IS NULL` branch. Both clients wrongly apply a create-path blocker to the match path.
- **iOS** `ConvertToProjectSheet.swift:940-995`: branches 4 (`.addressRequired`) and 5 (`.projectReviewRequired`) must yield to an explicit link target. If `submissionTarget.linkToProjectId != nil`, render MATCH PROJECT and allow commit. Blockers stay authoritative for the nil-target CREATE path only.
- **iOS** `ConvertToProjectSheet.swift:1538-1545` + `reducePreflight` (`:1840-1913`): collapse the three candidate lists into ONE question — "which project is this?" — sourced from `get_manual_project_link_candidates` (address/client become ORDERING only, which is what the RPC already returns). Keep `already_linked` as the only disqualifier. Remove the `candidateLinkCheckFailed` → `.reviewOnly` downgrade; if the manual RPC fails, surface a retry, never a silently unselectable list.
- **Web** `stage-transition-dialog.tsx:113-130, 205, 366-401, 416-417`: `other_client_projects` are rendered informational-and-collapsed and can never be selected; web has never called `get_manual_project_link_candidates`. Wire it in and make the list selectable. Web reaches feature parity with iOS here.
- Junk addresses ("Gordon Head", "500 is close") already normalize to `''` in `normalize_property_address` — correct. Treat empty as UNKNOWN (offer everything, ranked), never as CONFLICTING.

### D2. Name is a PROPOSAL signal, never an auto-link. Sub-contacts join identity resolution.
Elaine Beattie was invisible to every tier because "Bruce And Elaine" has null email/phone/address. `facts.contactName` is carried and never read (`opportunity-relationship-matching.ts`); `email-matching-service-v2.ts:191-196` Tier 3 queries `clients` only, uses only the last name token, and can never link (`:200-208` returns `action:"review"`).
- Add `sub_clients` to Tier 3 name matching alongside `clients`; match on full name and on each token, not just the last.
- A name-only or fuzzy hit NEVER auto-links and NEVER auto-creates a competing top-level client. It produces a PROPOSAL: "This looks like it belongs to <existing client/lead> — same address / sub-contact of / similar name." Auto-link remains restricted to the existing exact tiers (thread, exact email, exact phone, exact normalized address).
- **The `action:"review"` orphan must stop being invisible.** Today it parks an activity with `opportunityId: null` and increments `needsReview` with no surface. Route proposals into the existing review surface the operator actually looks at. If no such surface exists on the destination, that is the design work — do not invent a second inbox.
- Client-level merge does not exist (`execute_opportunity_merge_guarded` covers leads only). Duplicate households are currently permanent. A client-merge path is REQUIRED to close H4 — scope it in this wave; if it cannot be completed, it ships as its own follow-up chip with the Elaine/Beattie case named.
- Also reconcile the two client matchers: web `EmailMatchingServiceV2` (5 tiers, sub-clients on email/domain) vs iOS `LeadClientMatcher.swift:60-82` (3 tiers, NO sub-clients). Divergent answers for the same customer is a defect.

### D3. ONE authority for "won", it always asks, and it is reversible.
Three actors can win a lead today (human sheet, actorless email engine, and a Postgres trigger). Only one asks. Jackson's bug 9a89b951 explicitly requests the prompt.
- `enforce_project_opportunity_link()` (`ops-software-bible/migrations/20260713200000_project_opportunity_link_invariant.sql`) must STOP writing `stage='won'` + `stage_manually_set=true` + a null-actor `stage_transitions` row as a side effect of project status. It keeps enforcing the link invariant (the four link columns) — that is its legitimate job.
- The intent moves to the existing seam: `projects_enqueue_status_lifecycle` → `project_status_lifecycle_outbox`. Project reaching accepted/in_progress/completed/closed PROPOSES winning its linked lead.
- The app asks, in Jackson's own words' spirit (terse OPS voice, `ops-copywriter` for the exact string): confirm marking the linked lead won. Confirm → win, with the ACTOR recorded in `stage_transitions` (never null). Decline → nothing, and do not re-ask on every subsequent status write (record the declination).
- **A machine must never write `stage_manually_set = true`.** That forged flag currently locks leads out of the actorless engine permanently (`guard_reason: 'manual_stage_override'`).
- Reversibility: moving a project back to rfq/estimated currently does nothing (short-circuit). At minimum the win must be undoable through a product affordance — see D4's unlink.
- **H2 IS URGENT AND SHIPS FIRST.** The same trigger requires `pipeline.manage @ all` for ANY status write on a lead-linked project when `auth.role() <> 'service_role'`. Every crew member and both non-owner operators fail that check — a crew member marking a converted job in-progress gets a raw permission error. Field work is blocked today. Fix: a crew member's ordinary project-status write must not require pipeline-management permission. Gate the LINK-MUTATING path, not the status path.

### D4. "Won with no project" is a first-class repairable state, and links are reversible.
19 of 49 won leads (39%) have no project; 3 touched in August; most are permanently stuck behind `address_required`. Today the only affordance is a chip that `LeadConversionVisibilityStore` (`LeadConversionVisibilityStore.swift:24-40`) can dismiss to `UserDefaults` FOREVER, per-device, with no server mirror (H8).
- Orphan wins get a real, server-backed, surfaced queue with the full unlinked-project picker attached (D1's single list). Device-local dismissal must not be able to hide a server-side data problem — either mirror dismissal server-side with a reason, or drop dismissal entirely in favour of resolution.
- **An unlink/undo path must exist.** `convert_opportunity_to_project` writes four link columns, re-parents estimates, materializes tasks, copies site-visit photos, and writes audit rows; there is NO unlink RPC in `pg_proc` (H3). A wrong link is currently unrecoverable in product. Build a guarded unlink that reverses the link contract and records the reversal; do NOT attempt to un-materialize tasks/photos silently — decide and document what a reversal keeps.

## Sequencing (ship order)

1. **H2 crew unblock** (urgent, standalone, smallest).
2. **D1 manual-link unblock** — iOS footer + single candidate list; web parity. Unblocks the 19 orphans by hand immediately.
3. **D4 orphan queue + unlink**.
4. **D3 won-authority + prompt + trigger surgery** (DB migration; additive, iOS-compatible).
5. **D2 identity/name/sub-contacts + client merge** (web email engine; largest, least urgent).

## Constraints

- Supabase changes are ADDITIVE-ONLY between iOS releases (nullable columns / new tables only). A shipped 3.0.5 build still reads the old shape.
- Prod is low-tenant; direct prod migrations are acceptable, but archive every migration in `ops-software-bible/migrations/` per its README, and verify the ledger BY OBJECT (version keys lie).
- `auth.uid()` is unusable under the Firebase bridge — match by email / firebase_uid.
- Kill `public.convert_lead_to_project` (H10) — dead since 2026-07-16, zero callers, and the only door into the convert transaction that skips `p_expected_stage` / `p_expected_assignment_version`. Removing it is not additive for any client that still calls it: verify zero callers across ops-ios AND ops-web AND edge functions before dropping; otherwise revoke EXECUTE.
- Never gate on role names — granular permission only.
- The primary ops-web checkout is parked on a stale May branch; current web code is `ops-web-agent-control-plane` / origin/main.
