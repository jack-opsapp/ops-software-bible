# 14_FEATURE_POSITIONING.md

**OPS Software Bible — Feature Positioning: Canonical Marketing & Onboarding Copy Reference**

**Purpose**: Single source of truth for how OPS talks about each of its features in marketing, onboarding, and product surfaces. Every other chapter in this bible describes what features *do* (engineering-shaped). This chapter describes how features are *positioned* (marketing-shaped). When a content agent writes an email, an ad, a landing page section, an app store description, or an in-app empty state that mentions a feature by name, the approved positioning lines below are the canonical phrasing to pull from or build on.

**Last Updated**: 2026-05-27
**Source Reference**: `01_PRODUCT_REQUIREMENTS.md`, `04_API_AND_INTEGRATION.md`, `07_SPECIALIZED_FEATURES.md`, `09_FINANCIAL_SYSTEM.md`, `10_JOB_LIFECYCLE_AND_DATA_RELATIONSHIPS.md`, `11_CLIENT_PORTAL.md`, `ops-software-bible/app-store-listing.txt`, `ops-site/src/i18n/dictionaries/en/home.json`, `ops-site/src/i18n/dictionaries/en/platform.json`, `OPS-Web/src/lib/email/react/templates/`

**Out of scope**: Whole-product positioning (the "what is OPS" elevator pitch lives in `00_EXECUTIVE_SUMMARY.md`). Infrastructure systems that aren't user-facing differentiators (notification rail, email transport, sync engine, permissions plumbing). Pricing positioning (lives in `12_SUBSCRIPTION_MANAGEMENT.md` and `ops-site/src/app/plans/`).

---

## Table of Contents

1. [How to use this chapter](#how-to-use-this-chapter)
2. [Voice & format rules](#voice--format-rules)
3. [Feature: Inbox → Lead Extraction](#feature-inbox--lead-extraction)
4. [Feature: Pipeline / CRM](#feature-pipeline--crm)
5. [Feature: Project Workspace](#feature-project-workspace)
6. [Feature: Estimates + Client Portal](#feature-estimates--client-portal)
7. [Feature: Invoices + Payments](#feature-invoices--payments)
8. [Feature: Schedule View](#feature-schedule-view)
9. [Feature: Crew Dispatch & Team Visibility](#feature-crew-dispatch--team-visibility)
10. [Feature: Field-First iOS App / Offline-First](#feature-field-first-ios-app--offline-first)
11. [Feature: Photo Capture + Markup](#feature-photo-capture--markup)
12. [Feature: Site Visits](#feature-site-visits)
13. [Features intentionally not covered](#features-intentionally-not-covered)
14. [Known positioning contradictions](#known-positioning-contradictions)
15. [Maintenance](#maintenance)

---

## How to use this chapter

This chapter is a reference, not a marketing surface. Read it the way you'd read a parts catalogue: find the feature you're writing about, lift the approved lines verbatim where they fit, build on them where the format requires more space.

**When to pull from this chapter:**

- Writing an onboarding email that highlights a single feature (e.g. the trial-drip emails in `OPS-Web/src/lib/email/react/templates/`)
- Adding a feature section to `ops-site/` or `try-ops/` or a new industry landing page
- Updating the iOS App Store listing (`ops-software-bible/app-store-listing.txt`)
- Writing a Google or Meta ad headline that names a feature
- Adding feature copy to an in-app empty state, paywall, or onboarding step
- Reviewing existing copy for voice drift

**When NOT to pull from this chapter:**

- Writing technical documentation, API references, or developer onboarding (those are engineering-shaped — read the bible chapter listed under each feature's "Source of truth for behavior")
- Describing a feature that isn't documented here yet — first verify the feature ships and is stable, then add it to this chapter before writing the email or ad
- Whole-product elevator-pitch copy ("what is OPS") — that's in `00_EXECUTIVE_SUMMARY.md`

**Discipline:** The bible exists so every agent shares the same picture of OPS. If two surfaces describe the same feature differently, the surface that contradicts this chapter loses. If this chapter contradicts current product behavior, this chapter loses — and gets updated in the same session.

---

## Voice & format rules

The approved positioning lines below sit in OPS marketing voice — terse, tactical, pain-driven, no marketing-jargon, no emoji, no exclamation points. The framing prose around them (this paragraph, every section header, every "Why this is here" line) sits in bible voice — engineering-shaped, factual, structural. Don't blur the two.

**OPS marketing voice in one paragraph:** Jocko Willink discipline (every word earns its place; no filler), Bruce Springsteen working-class poetry (the dignity of labor; concrete moments on a job site), Elon Musk first-principles clarity (cut to the obvious truth). The feeling the reader gets is a quiet under-the-breath "fuck yeah" — not a fist-pumping "YEAH." Authority without shouting. Confidence without preening. See `ops-design-system/project/DESIGN.md` § VOICE & COPY and the `ops-copywriter` skill (`/Users/jacksonsweet/.claude/plugins/cache/custom-skills-plugin/ops-copywriter/`) for the full voice reference.

**Format rules for positioning lines:**

| Element | Constraint |
|---|---|
| Headline | 5–7 words. ALL CAPS. No period. No exclamation point. No emoji. Reads like a foreman, not a brochure. |
| Subhead | One sentence. Sentence case. Period at the end. Concrete specifics over abstractions. |
| Expanded | Two or three sentences. Sentence case. Leads with a concrete moment of pain or relief (not with the feature name). |

**Universal don't-say list** (applies to every feature; the per-feature "Don't say" lists add to this, never override it):

- "AI-powered" — generic. Say what it actually does (e.g. "classifies emails as leads").
- "Intelligent" / "smart [anything]" — filler. Cut it.
- "Powerful" — vacuous. Show power with a specific.
- "Seamless" / "frictionless" — corporate. Describe the actual friction it removes.
- "Cutting-edge" / "revolutionary" / "disruptive" / "next-generation" — startup-speak.
- "Solution" — corporate. Say "OPS" or name the feature.
- "Leverage" / "synergy" / "ecosystem" / "paradigm" — banned.
- "Streamlined" / "robust" / "scalable" — vacuous adjectives.
- Exclamation points. Anywhere. Confidence doesn't shout.
- Emoji in primary copy.

---

## Feature: Inbox → Lead Extraction

**Source of truth for behavior**: `04_API_AND_INTEGRATION.md` § Email Pipeline Integration Routes; `10_JOB_LIFECYCLE_AND_DATA_RELATIONSHIPS.md` § Gmail Integration (company inbox + per-user, AI email classification with GPT-4o-mini, 3-tier client matching, inbox leads queue).

**Persona / who feels it**: Admin or office operator running pipeline. The moment they open their laptop Monday morning to triage the weekend's emails and find the work already triaged.

**Pain before OPS** (one concrete moment): Friday night, sitting on the couch re-reading 200 emails trying to figure out which ones are leads, which already got quoted, and which got lost. Half the week is spent moving information out of email and into spreadsheets, notepads, or whatever CRM keeps timing out.

**Relief after OPS** (one concrete moment): Monday morning, OPS already pulled three new lead emails out of the inbox over the weekend, matched two of them to existing clients, and parked all three in the pipeline's new-lead column. The operator's first action is reading them, not finding them.

**Differentiator vs competitors**: Pipeline starts at the lead, not the booking. Most trades software (Jobber, Housecall Pro, ServiceTitan) picks up after the client is already on the hook — at the quote or the booking. OPS reads the inbox, classifies what's a lead with an LLM, matches it against the existing client roster, and inserts it into pipeline with the email thread attached. The pipeline also auto-advances on the first logged activity (`tr_activities_first_log_auto_advance` trigger, 2026-05-20) so the column you're staring at always tells the truth.

**Approved positioning lines** (verbatim, OPS voice):
- **Headline (5–7 words)**: `PIPELINE STARTS AT THE LEAD`
- **Subhead (1 sentence)**: Connect Gmail or Microsoft 365 and OPS pulls every quote request out of your inbox, sorts it, and drops it in pipeline.
- **Expanded (2–3 sentences)**: Leads come in through email. They don't come in through your CRM. So OPS scans your inbox, classifies what's a lead, matches it to a client you already know — and queues it before you finish your coffee. No copy-paste. Nothing slips.

**Don't say**:
- "AI-powered inbox" (generic; the differentiator is *pipeline auto-advance from email activity*, not the AI)
- "Smart email" (filler)
- "Email integration" (engineering-shaped; doesn't convey the value)
- "Convert emails to leads" (too transactional; the framing is "your inbox already has the leads — OPS just routes them")
- Anything implying OPS *replies* on the operator's behalf (the AI-drafts feature is separate and not yet positioned — see [Features intentionally not covered](#features-intentionally-not-covered))

**Where this feature is referenced today**:
- `ops-software-bible/app-store-listing.txt` — "AI EMAIL LEAD IMPORT" + "PIPELINE STARTS AT THE LEAD, NOT THE BOOKING" sections
- `ops-site/src/i18n/dictionaries/en/platform.json` — `feature.pipeline.heading` "EVERY LEAD. EVERY STAGE. NOTHING LOST." and `feature.pipeline.body`
- `OPS-Web/src/lib/email/react/templates/InboxConnectionDown.tsx` — implicit positioning: "leads coming into your inbox aren't being captured"
- iOS: not yet a top-level entry point (Gmail OAuth lives in setup wizard; see `OPS/OPS/Views/Setup/` for the 6-step flow)

---

## Feature: Pipeline / CRM

**Source of truth for behavior**: `09_FINANCIAL_SYSTEM.md` § Pipeline / CRM System; `10_JOB_LIFECYCLE_AND_DATA_RELATIONSHIPS.md` § Pipeline: The Job Spine. Eight stages — `new_lead`, `qualifying`, `quoting`, `quoted`, `follow_up`, `negotiation`, `won`, `lost`. Auto-advance triggers off first activity log, estimate send, and approval. Drag-to-stage on web records a `StageTransition` row. Follow-ups auto-create on stage rules.

**Persona / who feels it**: Owner-operator or office operator. The moment they look at the pipeline board on Monday morning and see exactly where every opportunity stands.

**Pain before OPS**: A lead comes in through a text or email. The operator scribbles the name and address on a notepad on the dashboard of the truck. Two weeks later they find the notepad and can't remember if they quoted it.

**Relief after OPS**: Every opportunity is on the board. Hot stuff is in `quoting` or `negotiation`. Stale stuff is in `follow_up` with a timestamp. When the operator logs a call, the lead auto-moves from `new_lead` to `qualifying` — they don't have to remember to drag it.

**Differentiator vs competitors**: Auto-advance + immutable stage transitions. Most pipeline CRMs (HubSpot, Pipedrive, Jobber) ask the operator to manually drag cards between columns; the column quickly stops reflecting reality. OPS moves cards as activity happens (log call → `qualifying`, send estimate → `quoted`, approve estimate → `won`) and records every stage move with a timestamp + actor in the `StageTransition` table, so you can audit how a deal moved. Manual drag is supported when needed.

**Approved positioning lines** (verbatim, OPS voice):
- **Headline (5–7 words)**: `EVERY LEAD. EVERY STAGE. NOTHING LOST`
- **Subhead (1 sentence)**: Eight stages from first contact to signed contract, and OPS moves leads forward as the work happens.
- **Expanded (2–3 sentences)**: A lead comes in. Two weeks later you can't remember if you quoted it. OPS tracks the whole pipeline — new lead through won — and auto-advances stages off your activity, so the column you're staring at always tells the truth. Drag manually when you need to.

**Don't say**:
- "Sales funnel" (B2B SaaS jargon; trades say "pipeline")
- "Deal flow" (corporate)
- "Manage your opportunities" (vacuous; what *happens* to them is the value)
- "Visual pipeline" (every Kanban tool says this)
- "Drag-and-drop" as the lead value — it's *manual override of auto-advance*, not the headline

**Where this feature is referenced today**:
- `ops-site/src/i18n/dictionaries/en/platform.json` — `feature.pipeline.label` "PIPELINE" through `feature.pipeline.body`
- `ops-software-bible/app-store-listing.txt` — "[ WHAT'S IN THE APP TODAY ] > SALES & CRM > 8-stage pipeline Kanban with drag-and-drop"
- `OPS-Web/src/app/(authenticated)/pipeline/` — the in-product surface (referenced by name in onboarding)
- iOS: pipeline tab is gated on Books Phase 2 (per memory; not yet shipped on iOS as a standalone tab)

---

## Feature: Project Workspace

**Source of truth for behavior**: `10_JOB_LIFECYCLE_AND_DATA_RELATIONSHIPS.md` § Design Philosophy (Project = Folder); `03_DATA_ARCHITECTURE.md` § Project model. The project is the spine: estimates, tasks, photos, invoices, site visits, activity comments, notes — all link by `projectId` or `opportunityId`. Computed dates derive from child tasks. Soft-delete with 30-day recovery.

**Persona / who feels it**: Everyone — admin, office, operator, crew. The moment any one of them opens a project and the full state of the job is visible without flipping screens.

**Pain before OPS**: Job details scattered across a group chat for the crew, a spreadsheet for materials, a folder of photos on a personal phone, a printed contract in the truck. Client calls to ask a question and the operator's scrolling through three apps trying to remember what was promised.

**Relief after OPS**: Open the project. The quote is there. The tasks the crew is doing today are there. The before-photos from the site visit are there. The invoice with what's been paid is there. The client's last three messages are there. Nothing is somewhere else.

**Differentiator vs competitors**: One container, not five tools wired together. Jobber, Housecall, and ServiceTitan keep work, scheduling, financials, and communication on separate screens with their own filters and search bars. OPS folds them into the project so the picture you see is the picture that exists.

**Approved positioning lines** (verbatim, OPS voice):
- **Headline (5–7 words)**: `EVERY JOB IN ONE PLACE`
- **Subhead (1 sentence)**: Photos, notes, tasks, estimates, invoices, site visits — all on one project, not three apps and five group chats.
- **Expanded (2–3 sentences)**: A project is the spine. Quote, schedule, photos, invoice, client messages — they all hang off it. You open the project and the whole picture is in front of you. The crew sees the same thing on their phones.

**Don't say**:
- "Centralized hub" (corporate)
- "All-in-one platform" (every SaaS says this; meaningless)
- "360-degree view" (jargon)
- "Project management" (too generic — every PM tool says this; OPS is not a PM tool)
- Any framing that suggests the project is a *dashboard* — it's a workspace where the work happens

**Where this feature is referenced today**:
- `ops-site/src/i18n/dictionaries/en/platform.json` — `feature.projectManagement.heading` "STOP HUNTING THROUGH TEXTS FOR JOB DETAILS" + `feature.projectManagement.body`
- `ops-site/src/i18n/dictionaries/en/home.json` — `showcase.feature2` (photo doc) and `whatIsOps.definition` (project tracking)
- `OPS-Web/src/app/(authenticated)/projects/[id]/` — the in-product surface
- `OPS/OPS/Views/Projects/` — iOS project detail screens
- `ops-software-bible/app-store-listing.txt` — surfaces under SCHEDULING / iOS FIELD APP sections

---

## Feature: Estimates + Client Portal

**Source of truth for behavior**: `09_FINANCIAL_SYSTEM.md` § Estimates System; `11_CLIENT_PORTAL.md` (whole chapter — magic-link auth, portal_branding with 3 templates + accent color + logo, line-item questions with 5 answer types: text, select, multiselect, color, number).

**Persona / who feels it**: Operator sending the quote; client approving it. The moment a client opens the portal on their phone and the quote looks like it came from a real business — not a Word doc with the logo stretched sideways.

**Pain before OPS**: Operator builds a quote in a Google Doc or PDF tool. Emails it. Client texts back: "what color is the stain?" "does the corner cap come with it?" "can we move the gate?" Six text-message threads later, the quote's been verbally amended four times and nobody knows what's been agreed.

**Relief after OPS**: Operator attaches questions directly to the line items that need decisions ("pick a stain color," "pick a gate hardware finish," "do you want corner caps"). Sends the branded portal link. Client opens it, picks the options, answers the questions, signs. The answers come back attached to the line items they belong to, ready to convert to invoice and to a project the crew can execute.

**Differentiator vs competitors**: Line-item questions. No competitor in trades software attaches structured questions to specific line items with typed answers (color, select, number) the way OPS does. Combine that with company-customizable portal branding (logo, template, accent color) and the client experience looks bespoke without the operator doing custom design work.

**Approved positioning lines** (verbatim, OPS voice):
- **Headline (5–7 words)**: `ESTIMATES YOUR CLIENTS ACTUALLY UNDERSTAND`
- **Subhead (1 sentence)**: Send a branded estimate; the client opens it on their phone, picks the options, answers the questions you set, signs.
- **Expanded (2–3 sentences)**: Line items, optional add-ons, deposit schedules — built into the quote. Attach questions to specific line items: pick a stain color, pick a gate hardware finish, decide on corner caps. Your client answers in the portal. You don't get a six-text-message thread on a Wednesday night.

**Don't say**:
- "Professional quotes" (every quoting tool says this; vacuous)
- "Beautiful estimates" (decorative framing; OPS is functional)
- "Customer portal" (B2B SaaS jargon; trades say "client portal" or just "the link you send")
- "E-signature" (engineering-shaped; the framing is "they sign," not "they e-sign")
- "Interactive proposal" (corporate)
- Anything implying the client downloads a PDF and prints it — the portal *is* the deliverable

**Where this feature is referenced today**:
- `ops-site/src/i18n/dictionaries/en/platform.json` — `feature.invoicing.heading` (currently bundles estimates + invoices together; consider splitting in next ops-site rewrite)
- `OPS-Web/src/lib/email/react/templates/PortalEstimateReady.tsx` — "Your estimate's ready. Tap below to review the work and pricing"
- `OPS-Web/src/lib/email/react/templates/PortalQuestionsReminder.tsx` — reminds client to answer unanswered line-item questions
- `OPS-Web/src/lib/email/react/templates/PortalMagicLink.tsx` — portal access magic link
- `OPS-Web/src/app/(authenticated)/estimates/` — operator-side estimate builder
- `OPS-Web/src/app/portal/` — the client-facing portal
- `ops-software-bible/app-store-listing.txt` — "ESTIMATES BUILT FOR REAL JOBS" + "[ WHAT'S IN THE APP TODAY ] > QUOTING & INVOICING"

---

## Feature: Invoices + Payments

**Source of truth for behavior**: `09_FINANCIAL_SYSTEM.md` § Invoices System + § Payments. Atomic `convert_estimate_to_invoice` RPC, DB-trigger-maintained `amount_paid`/`balance_due`, insert-only `payments` table (with void via reversing row, not deletion), multi-payment with deposit + milestone structure inherited from the estimate's line items.

**Persona / who feels it**: Owner-operator. The moment they finish a job on Friday and the invoice is ready to send on the same drive home — not two weeks later.

**Pain before OPS**: The job's done. The invoice is still in the operator's head. Every day it sits there, the client's project is being financed for free. By the time the operator gets around to it, three other jobs have closed and the details are blurry.

**Relief after OPS**: One click on the approved estimate converts it to an invoice. Deposit, milestones, balance — already structured from the line items. Send it from the portal. Track what's paid and what's outstanding without a spreadsheet.

**Differentiator vs competitors**: Deposit + milestone structure tied to estimate line items. Most trades software treats the deposit as a single flat field on the invoice. OPS lets the operator structure payment milestones against specific deliverables in the original quote, so progress billing is the default not the exception. Combined with one-click estimate-to-invoice conversion (an atomic RPC, no copy-paste, no field-by-field re-entry), the friction from "job done" to "invoice sent" collapses to seconds.

**Approved positioning lines** (verbatim, OPS voice):
- **Headline (5–7 words)**: `THE JOB'S DONE. INVOICE SHOULD BE TOO`
- **Subhead (1 sentence)**: One click converts the approved estimate to an invoice — deposit, milestones, and balance all already structured.
- **Expanded (2–3 sentences)**: Every day the invoice sits in your head is another day you're financing the client's project for free. OPS converts the approved estimate to an invoice in one click — deposit, milestones, and balance pre-structured from the line items. Track what's paid and what's outstanding without a spreadsheet.

**Don't say**:
- "Get paid faster" (every invoicing tool says this; vacuous unless backed by a specific)
- "Online payments" (table stakes; not a differentiator)
- "Send professional invoices" (vacuous)
- "Cash flow management" (corporate; trades say "what's paid and what's outstanding")
- "Streamline billing" (corporate)
- Any claim involving specific time-to-paid metrics unless backed by current production data

**Where this feature is referenced today**:
- `ops-site/src/i18n/dictionaries/en/platform.json` — `feature.invoicing.heading` "THE JOB'S DONE. WHY HAVEN'T YOU INVOICED" + `feature.invoicing.body`
- `OPS-Web/src/lib/email/react/templates/PortalInvoiceReady.tsx` — "Job's done. Tap below to review and pay"
- `OPS-Web/src/app/(authenticated)/invoices/` — operator-side invoice surface
- `ops-software-bible/app-store-listing.txt` — "QUOTING & INVOICING > Partial payments, balance tracking, PDF storage, version control"

---

## Feature: Schedule View

**Source of truth for behavior**: `01_PRODUCT_REQUIREMENTS.md` § Calendar & Scheduling; `10_JOB_LIFECYCLE_AND_DATA_RELATIONSHIPS.md` § Recurring Task Lifecycle (Phase 3). Five view types — month, week, day, team timeline, agenda. Drag-and-drop with 15-minute snap grid (`@dnd-kit`). Task-only scheduling — `ProjectTask` carries `startDate`/`endDate`/`duration`/`allDay`/`startTime`/`endTime`. Recurring via RFC 5545 RRULE templates expanded by `/api/cron/recurrence-generate`. Conflict detection via `detectConflicts()`.

**Persona / who feels it**: Field crew opening the app at 6am. Office operator dragging next week's work into shape on Friday afternoon.

**Pain before OPS**: Monday morning, five texts before 7am: "what's the address," "who am I riding with," "did the scope change," "what time is the appointment," "did the client confirm." Every morning starts with phone calls instead of work.

**Relief after OPS**: The crew opens the app. They see their day. Address, scope, who else is on the job, what time. They get in the truck. The office operator's phone doesn't ring.

**Differentiator vs competitors**: Task-native scheduling. Most field-service software keeps a separate `CalendarEvent` table next to the work — meaning the schedule and the work can drift. OPS removed the separate event model in the lifecycle redesign (2026-05-x); the calendar shows the actual tasks, scheduled in place. Recurring routes (weekly cleaning, monthly maintenance) generate themselves from RRULE templates. Conflict detection runs on drag, so you don't double-book a crew member.

**Approved positioning lines** (verbatim, OPS voice):
- **Headline (5–7 words)**: `EVERYONE KNOWS WHERE THEY'RE GOING`
- **Subhead (1 sentence)**: Day, week, month, team, agenda — drag tasks where they need to be, and the crew sees their day before they leave the driveway.
- **Expanded (2–3 sentences)**: Monday morning, five texts before 7am — what's the address, who am I riding with, did the scope change. OPS puts the daily schedule, site address, and job details in front of every crew member before they get in the truck. Drag tasks to reschedule. Recurring routes generate themselves.

**Don't say**:
- "Calendar integration" (engineering-shaped; the calendar *is* the work, it doesn't integrate with one)
- "Smart scheduling" (filler)
- "Resource allocation" (corporate; trades don't have "resources," they have crew)
- "Optimize your day" (vague; tell the operator what's optimized)
- "Time tracking" (separate feature; not part of schedule positioning)

**Where this feature is referenced today**:
- `ops-site/src/i18n/dictionaries/en/platform.json` — `feature.scheduling.heading` "NO MORE 'WHERE AM I GOING TODAY?'" + `feature.scheduling.body`
- `ops-site/src/i18n/dictionaries/en/home.json` — `showcase.feature3` "A SCHEDULE YOUR CREW ACTUALLY READS"
- `OPS-Web/src/app/(authenticated)/schedule/` — operator-side schedule surface
- `OPS/OPS/Views/Calendar/` — iOS calendar views
- `ops-software-bible/app-store-listing.txt` — "SCHEDULING > 5-view calendar — month, week, day, team timeline, agenda"

---

## Feature: Crew Dispatch & Team Visibility

**Source of truth for behavior**: `01_PRODUCT_REQUIREMENTS.md` § Team Management; `10_JOB_LIFECYCLE_AND_DATA_RELATIONSHIPS.md` § ProjectTask assignment. `team_member_ids` array on tasks; project team computed from task assignments (no separate project-level team editor). `TaskType.defaultTeamMemberIds` populates auto-generated tasks. Reassignment writes to `team_member_ids` and triggers iOS push via OneSignal.

**Persona / who feels it**: Owner-operator at the office, mid-day, with a job that needs a second person. The moment they reassign one crew member without calling three.

**Pain before OPS**: The job needs another hand. The operator calls the first crew member's cell — no answer. Calls the second — they're on another job. Calls the third — they're already at the right address but didn't know they were supposed to be there. Twenty minutes of phone calls to surface what should take fifteen seconds.

**Relief after OPS**: Open the team view. See who's on which job, who's free, who's already en route. Tap one name to reassign. The new person opens the app and the job's there. No phone call.

**Differentiator vs competitors**: Team derives from task assignments — there's no separate "project team" the operator has to keep in sync with task assignments. Combined with the schedule view, the operator can see the whole crew's day on one screen and reassign by drag.

**Approved positioning lines** (verbatim, OPS voice):
- **Headline (5–7 words)**: `SEE YOUR WHOLE CREW AT A GLANCE`
- **Subhead (1 sentence)**: Reassign in one tap, not five phone calls.
- **Expanded (2–3 sentences)**: A job site needs another hand. You'd usually call three guys to find one available. OPS shows the whole crew — who's on which job, who's free, who's en route — and lets you reassign in a single tap. The new person opens the app and the job's already there.

**Don't say**:
- "Team collaboration" (corporate jargon; trades say "crew")
- "Workforce management" (enterprise jargon)
- "Real-time crew tracking" (creepy framing; the value is *visibility*, not surveillance)
- "Optimize crew utilization" (corporate)
- Anything implying GPS-tracking the crew without their knowledge — OPS doesn't track location on the operator's behalf; the *crew* sees their own assigned work

**Where this feature is referenced today**:
- `ops-site/src/i18n/dictionaries/en/platform.json` — `feature.teamManagement.heading` "STOP CALLING AROUND TO FIND YOUR CREW" + `feature.teamManagement.body`
- `ops-site/src/i18n/dictionaries/en/home.json` — `painPoints.card3` mentions "Whiteboard for crew assignments" as a solved pain
- `OPS-Web/src/app/(authenticated)/team/` — operator-side team surface
- `OPS/OPS/Views/Team/` — iOS team views
- `OPS-Web/src/lib/email/react/templates/TeamInvite.tsx` — onboarding new crew members

---

## Feature: Field-First iOS App / Offline-First

**Source of truth for behavior**: `01_PRODUCT_REQUIREMENTS.md` § Field-Specific Requirements; `04_API_AND_INTEGRATION.md` § SyncEngine (Offline-First Orchestrator). SwiftData local persistence with Supabase mirror. Triple-layer sync: immediate, event-driven, periodic. `OutboundProcessor` push queue + `InboundProcessor` field-level merge. Kalman GPS filter for turn-by-turn navigation in low-signal areas. 56pt touch targets for gloved use. Dark theme for sunlight + battery.

**Persona / who feels it**: Field crew — the operator standing in a basement, in a parking garage, on a rural property with no service. The moment they open the app and the job loads.

**Pain before OPS**: Crew member arrives at a basement install. No signal. The job-management app shows a loading spinner. They can't see the scope, can't see the materials list, can't update task status. They guess from memory and hope they were briefed correctly.

**Relief after OPS**: Crew member arrives at the basement install. No signal. OPS opens. The job is there — scope, materials, the operator's notes, the photos from the site visit. They do the work. They mark the task complete. When they drive back into signal, the status sync happens in the background.

**Differentiator vs competitors**: Offline-first from the ground up, not retrofitted. Jobber, Housecall, and ServiceTitan are server-first apps with offline cache layers bolted on — they degrade ungracefully when signal drops. OPS was built the other way around: the iOS app reads from local SwiftData first, queues mutations, and syncs to Supabase when connectivity returns. Combined with field-design constraints (56pt touch targets for gloves, dark theme for sunlight + battery, swipe gestures for status), it's the only field app trades crews actually keep open.

**Approved positioning lines** (verbatim, OPS voice):
- **Headline (5–7 words)**: `BUILT FOR THE TRUCK, NOT THE DESK`
- **Subhead (1 sentence)**: Offline-first iOS app — dark for sunlight, big buttons for gloves, works in basements and dead zones because the jobs were already on the device.
- **Expanded (2–3 sentences)**: Most field apps were built for desks and bolted on offline support later. OPS was built the other way around. Jobs load in basements and dead zones because they were already cached. Changes queue when signal drops and sync the moment it returns. The crew never gets stuck.

**Don't say**:
- "Works without WiFi" (sounds 2010; reads as a feature, not a foundation)
- "Mobile-friendly" (table stakes; meaningless)
- "Native iOS app" (engineering-shaped; the value is what it lets the crew do, not the tech stack)
- "Responsive design" (web jargon; OPS is a native app)
- "Cloud-based" (anti-positioning — OPS's value is that it doesn't *require* the cloud at point-of-use)
- Anything implying it works on Android *today* — Android is in development, not shipping

**Where this feature is referenced today**:
- `ops-site/src/i18n/dictionaries/en/home.json` — `whatIsOps.detail1` (offline-first) + `whatIsOps.detail2` (field-optimized)
- `ops-site/src/i18n/dictionaries/en/home.json` — `painPoints` cards and `showcase.feature1` "NO TRAINING REQUIRED"
- `ops-site/src/i18n/dictionaries/en/platform.json` — `comparison.row.offlineMode`
- `ops-software-bible/app-store-listing.txt` — "REAL OFFLINE" section + "iOS FIELD APP" section
- `OPS/OPS/` — the entire iOS codebase is this feature

---

## Feature: Photo Capture + Markup

**Source of truth for behavior**: `01_PRODUCT_REQUIREMENTS.md` § Image Management; `09_FINANCIAL_SYSTEM.md` § Project Photos (`is_client_visible` toggle for portal). PencilKit drawing on iOS; SVG annotation on web. `PhotoAnnotation` entity stores markup overlay. Offline queue via `LocalPhoto` + `PhotoProcessor`. Upload via presigned S3 URLs (`/api/uploads/presign`). Photos group by source — site visit, in-progress, completion — and site-visit photos auto-attach to projects when leads convert (2026-05-20).

**Persona / who feels it**: Field crew documenting damage, scope, deliverables. Office operator showing the client what's been done.

**Pain before OPS**: Crew takes a photo on site to flag a problem. It saves to the personal phone's camera roll. They text it to the operator with a confusing caption. The operator forwards it to the client. Months later someone needs the photo and it's lost in 4,000 vacation photos.

**Relief after OPS**: Crew takes the photo *in* the app. Draws on it — circle the crack, arrow the leak, add a note. It lives with the job. The crew sees it. The operator sees it. The client sees it in the portal if `is_client_visible` is on. Years later, the photo is still attached to the project.

**Differentiator vs competitors**: PencilKit-grade markup attached to the project, not the device. Other field apps (CompanyCam, Jobber's photo feature) capture and upload but don't offer in-app drawing with the fidelity OPS does — and don't materialize site-visit photos automatically into the project that comes out of the lead. The continuity from site visit → project means the crew sees the same photos the operator took during scoping, without anyone re-uploading.

**Approved positioning lines** (verbatim, OPS voice):
- **Headline (5–7 words)**: `POINT AT THE PROBLEM. LITERALLY`
- **Subhead (1 sentence)**: Take a photo on site, draw on it, attach a note — it lives with the job, not in your camera roll.
- **Expanded (2–3 sentences)**: Before-and-after shots. Damage documentation. Scope changes. Take the photo, draw on it with your finger or an Apple Pencil, add a note. The photo lives with the job — the crew sees it without a phone call, the client sees it in the portal, and you find it again next year without scrolling through four thousand vacation photos.

**Don't say**:
- "Photo gallery" (every app has one; not a differentiator)
- "Cloud photo storage" (engineering-shaped; the value is *attached to the job*, not stored in the cloud)
- "Image management" (corporate)
- "Visual documentation" (vague)
- "AI photo recognition" (OPS doesn't do this; don't imply features that don't ship)

**Where this feature is referenced today**:
- `ops-site/src/i18n/dictionaries/en/platform.json` — `feature.photoMarkup.heading` "POINT AT THE PROBLEM. LITERALLY" + `feature.photoMarkup.body`
- `ops-site/src/i18n/dictionaries/en/home.json` — `showcase.feature2` "PHOTO DOCUMENTATION THAT WORKS"
- `ops-software-bible/app-store-listing.txt` — "PHOTO MARKUP ON THE JOB" section
- `OPS/OPS/Views/Photos/` — iOS photo capture and markup screens
- `OPS-Web/src/app/(authenticated)/projects/[id]/photos/` — web photo gallery

---

## Feature: Site Visits

**Source of truth for behavior**: `10_JOB_LIFECYCLE_AND_DATA_RELATIONSHIPS.md` § New Entities → SiteVisit. `SiteVisit` entity carries `scheduledAt`, `status`, `notes`, `photos[]`, `completedAt`. Auto-creates an Activity row on completion. Site-visit photos auto-attach to the project when the originating lead converts to a project — `project_photos` row inserted with `source='site_visit'` and `siteVisitId` back-link (implemented 2026-05-20).

**Persona / who feels it**: Owner-operator who does their own quoting walks. The moment they win the job and realize they don't have to re-photograph the site for the crew.

**Pain before OPS**: Operator walks the site to scope a quote. Takes photos and notes on their personal phone. Two weeks later the client signs. The operator now has to re-share photos with the crew, re-explain what they saw, and remember measurements that were scribbled in a notebook somewhere.

**Relief after OPS**: Operator books the site visit in OPS. Walks the site, takes photos and notes in the app. Lead is in `qualifying`. Client signs. Pipeline auto-advances to `won`. The site-visit photos materialize on the new project automatically — the crew sees them on day one.

**Differentiator vs competitors**: Site visit photos carry through to the project on win — zero re-entry. Most trades software treats site visits (when it has them at all) as a stand-alone appointment type with photos that live on the appointment, not the project. OPS makes the site visit the *beginning* of the project: the same data, photos, and notes flow forward without manual copy.

**Approved positioning lines** (verbatim, OPS voice):
- **Headline (5–7 words)**: `WALK THE SITE. NOTHING GETS LOST`
- **Subhead (1 sentence)**: Schedule a site visit, take photos and notes on-site, win the job — and every photo carries through to the project automatically.
- **Expanded (2–3 sentences)**: Most software treats the site visit as a separate thing. OPS treats it as the start of the project. Book it, walk it, document it on your phone. When the client says yes, the photos you took during scoping show up on the project the crew sees on day one. You don't take them again.

**Don't say**:
- "Site survey" (formal; trades say "walk the site")
- "Discovery visit" (B2B SaaS jargon)
- "Estimate appointment" (collapses two different things; site visit is its own object)
- "Pre-sales visit" (corporate)
- "Inspection" (overlapping with regulatory inspections — confusing for trades whose work *is* inspections)

**Where this feature is referenced today**:
- Not yet a top-level entry on `ops-site/` (the marketing site is the first place to lead with this story — flag for the next ops-site update)
- `OPS-Web/src/app/(authenticated)/site-visits/` — operator-side surface
- `OPS/OPS/Views/SiteVisits/` — iOS site-visit screens
- `ops-software-bible/app-store-listing.txt` — not currently called out; consider adding in next listing refresh

---

## Features intentionally not covered

The following features either ship today and aren't well-suited to top-of-funnel marketing copy, or are in flight and don't have stable enough behavior to position. Add them to this chapter when those conditions change.

| Feature | Why excluded (for now) |
|---|---|
| AI email drafts / AI memory | Feature spec exists (`04_API_AND_INTEGRATION.md` § Email Pipeline Integration Routes references the email-drafting routes) but full behavior is not finalized in the bible — drafting model, voice training, operator approval flow, edit-before-send semantics are all in flight. Don't position until the spec is stable. |
| Financial dashboard / cashflow forecast | Referenced in `09_FINANCIAL_SYSTEM.md` (accounting integrations) but the dashboard surface, formulas, and forecast horizon aren't yet documented. Don't position numbers we can't back. |
| Catalog & products (configurable products, recipes, materials) | Real engineering differentiator (see `03_DATA_ARCHITECTURE.md` § Phase 13) — but it's internal product-authoring infrastructure. It surfaces *through* estimates and invoices; positioning it as its own feature confuses prospects. Pull it into estimate positioning when the line-item question story needs reinforcement. |
| Notifications system (in-app rail + push) | Infrastructure, not a value prop. Every product has notifications; OPS's are well-built but a trade-business owner doesn't buy software because of the notification design. Documented in `07_SPECIALIZED_FEATURES.md` § 14 — reference it from inside other feature positioning where relevant ("you'll get a notification when…"). |
| Permissions / RBAC (5 roles, 55+ granular permissions) | Real differentiator for larger crews but lives in plumbing-shaped territory. Surface in pricing-plan comparisons and enterprise-track sales copy (`ops-site/src/app/plans/`), not in mass-market drip. |
| Turn-by-turn navigation (Kalman-filtered GPS) | Technically impressive but not a lead value prop — every phone has Maps. Reference inside the field-first positioning where it strengthens the offline story. |
| 4-digit PIN security | Micro-feature; mentions on App Store listing are sufficient. Don't make it a separate positioning entry. |
| Inventory tracking | Live but the positioning currently leans on a single line in `ops-site/platform.json` (`feature.inventory`). Pull it in for trade verticals where stock is the bottleneck (electrical, plumbing) rather than as universal positioning. |
| Activity timeline / Project notes / @mentions | Strong product features but supporting cast — they reinforce the project-workspace positioning above rather than standing alone. |

---

## Known positioning contradictions

These are inconsistencies discovered while writing this chapter. Each one is a candidate for the next marketing rewrite. None block any current copy.

1. **Pricing-multiple claim drift.** `ops-software-bible/app-store-listing.txt` says "A THIRD THE PRICE OF JOBBER." `00_EXECUTIVE_SUMMARY.md` says "Competes with Jobber ($300+/month) at 1/3 the cost." But `ops-site/src/i18n/dictionaries/en/platform.json` `comparison.row.price.jobber` lists Jobber at **$169/mo** for 5 users vs OPS at $140/mo — a ~17% gap, not a 67% gap. Pick a canonical comparison and update the other surfaces. The platform-page number is the most recently maintained; the "1/3 the price" framing reads as legacy positioning from an earlier Jobber price point. **Canonical for now: the platform-page comparison number ($169 Jobber / $140 OPS at 5 users).** Drop the "1/3 the price" line from app-store and executive-summary copy on next revision.
2. **Audience-naming drift.** `00_EXECUTIVE_SUMMARY.md` is explicit: OPS is for *subtrades* (the people doing the work), not general contractors. But marketing copy across `ops-site/` and the app store listing uses "trades," "trade crews," "service-based businesses," and "owner-operators" somewhat interchangeably. None of those are wrong — but "contractor" appears in some SEO-shaped places (`ops-site/src/app/page.tsx` JSON-LD description). Audit for the word "contractor" and replace with "trade" / "service-based business" / "owner-operator" where the meaning is "the people doing the work." Founder rule: *never* refer to a trade-business owner as a "tradesperson" (sounds forced) or a "contractor" (means something different).
3. **Inbox feature naming.** Within OPS the feature is called variously "Inbox," "email lead capture," "AI email lead import," and "Gmail integration." The app store listing uses "AI EMAIL LEAD IMPORT" prominently; ops-site doesn't yet have a dedicated entry; emails reference it indirectly. **Canonical for marketing: "Inbox → pipeline"** (it's the *destination* that matters, not the source) — but accept "AI email lead import" as a longer-form fallback when SEO keywords matter.

---

## Maintenance

Update this chapter when any of the following happens:

| Trigger | Update |
|---|---|
| A new feature ships that warrants its own positioning entry | Add the entry following the per-feature template. Verify it's documented in another bible chapter first; if it isn't, document the behavior there before positioning it here. |
| An existing feature's behavior changes materially | Update the "Source of truth for behavior" line, then re-check that the approved positioning lines still accurately describe what the feature does. Update the lines if not. |
| The OPS voice rules in `ops-design-system/project/DESIGN.md` § VOICE & COPY change | Re-read every feature's positioning lines and update any that drift from the new voice. |
| A marketing surface is rewritten (`ops-site/`, `try-ops/`, app store listing, an email template) | Add or update the entries in each feature's "Where this feature is referenced today" list. Where the new surface invents better positioning than what's in this chapter, lift it back into the approved lines. |
| The positioning contradictions section above gets resolved | Remove the resolved contradiction. Add a `// RESOLVED 2026-mm-dd` note in commit message but not in this file (the chapter stays current; resolved contradictions don't earn space). |
| A new feature is identified for the "Features intentionally not covered" list | Add it with a precise reason. Re-check that list periodically — features that mature out of "not covered" status should graduate to a full entry. |

**Versioning discipline.** The lines in this chapter are quoted into emails, ads, and landing pages. Treat changes the way you'd treat a database migration: the old line might still be live somewhere when the new line ships. Where a change matters, grep the surfaces in "Where this feature is referenced today" and update them in the same session.

**Skill alignment.** When writing or revising any positioning line in this chapter, invoke the `ops-copywriter` skill first — it's the canonical voice reference and includes DO/DON'T patterns this chapter's framing cannot fit. The "Don't say" lists per feature are a fast filter, not a complete voice guide.
