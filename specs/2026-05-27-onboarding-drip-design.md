# Onboarding Drip — Design Spec

**Date**: 2026-05-27
**Status**: Approved by founder (Jackson) — ready for implementation plan.
**Scope**: Outbound onboarding email drip for new trial signups. Day 0 through Day 14, then handoff to the existing trial-expiry cron at Day 23. Closes the gap documented in `13_EMAIL_SYSTEM.md` § Known Gaps #1 ("No welcome email on signup") and #8 ("No automatic mid-trial engagement drip").

**Source Reference**:
- `13_EMAIL_SYSTEM.md` — outbound email infrastructure (transport, chokepoint, suppressions, killswitches, cron pipeline)
- `14_FEATURE_POSITIONING.md` — canonical positioning for the two feature emails (Day 3 inbox, Day 8 estimates)
- `OPS-Web/src/lib/email/sendgrid.tsx` — `gatedSend` chokepoint
- `OPS-Web/supabase/migrations/053_trial_expiry_notifications.sql` — analogous dedup pattern this spec mirrors
- `OPS-Web/supabase/migrations/065_company_trial_init_trigger.sql` / `066_refine_company_trial_trigger.sql` — the existing `companies` INSERT trigger this spec extends
- `OPS-Web/src/lib/api/services/trial-expiry-service.ts` — service shape this spec mirrors
- Brand voice: `/Users/jacksonsweet/Projects/OPS/CLAUDE.md` § Brand & MO, `ops-software-bible/14_FEATURE_POSITIONING.md` § "Don't say" lists, founder memory files (`feedback_contractor_banned_in_marketing.md`, `feedback_ai_framing_in_marketing.md`)

---

## Table of Contents

1. [Background](#1-background)
2. [Drip shape](#2-drip-shape)
3. [Trigger architecture](#3-trigger-architecture)
4. [Sender, format, and voice rules](#4-sender-format-and-voice-rules)
5. [State branches and skip rules](#5-state-branches-and-skip-rules)
6. [Email copy (canonical)](#6-email-copy-canonical)
7. [Behavior-triggered re-engagement send](#7-behavior-triggered-re-engagement-send)
8. [Data model changes](#8-data-model-changes)
9. [Cron schedule additions](#9-cron-schedule-additions)
10. [Implementation plumbing](#10-implementation-plumbing)
11. [Testing approach](#11-testing-approach)
12. [Compliance + brand discipline](#12-compliance--brand-discipline)
13. [Bible updates required](#13-bible-updates-required)
14. [Open questions and known gaps](#14-open-questions-and-known-gaps)
15. [Decision log](#15-decision-log)

---

## 1. Background

A new trades business signs up for OPS at `/register`. Firebase Auth creates the credential; the user/company rows are synced into Supabase; the `initialize_company_trial` Postgres trigger stamps a 30-day trial window. The operator lands on the onboarding screen.

From that moment until day 23 (when the trial-expiry cron fires `warning_7d`), **the operator receives zero emails from OPS in code today**. No welcome, no verification, no internal alert, no activation nudge, no mid-trial check-in. This spec closes that gap.

Activation research (cited in conversation, sources in the brainstorming transcript):
- Activated trial users convert at **5–10×** the rate of unactivated users
- Email-engaged trial users convert at **15%** vs **3%** for non-engaged
- Personalized/branched onboarding outperforms static by **30–45%** in activation
- Proactive founder outreach correlates with **+40%** activation and **+50%** 90-day retention
- 5–8 emails over 14–30 days is the consensus B2B SaaS sweet spot

This spec ships 6 calendar-scheduled emails + 1 behavior-triggered re-engagement send, plus a real-time Day 0 founder welcome that fires immediately on signup.

---

## 2. Drip shape

| Day | From | Voice | Job |
|---|---|---|---|
| **0** | Jack | Personal | Founder welcome. Asks what brought them in. "I read every reply." |
| **1** | Dispatch | Tactical | First project nudge. Branched on whether they have a project. |
| **3** | **Jack** | Personal | Inbox → lead. The triage + measurement value-prop. |
| **4** | Dispatch | Tactical | Crew + completion notification. Branched on whether they've felt the aha. Includes mocked notification preview. |
| **8** | **Jack** | Personal | Estimates + branded portal. Deck-builder Word-doc-disaster story. |
| **14** | Dispatch | Tactical | Honest pulse check. Branched on activity. Reply-to-Jack. |
| **+** | Jack | Personal | "Lost you?" re-engagement. Fires only on 4+ consecutive days of zero activity between Day 1 and Day 14. |

Alternating rhythm: Jack hits them on the three personal beats (0/3/8); Dispatch hits them on the three tactical beats (1/4/14). The behavior-triggered send is from Jack and fires at most once per trial.

After Day 14 the drip goes quiet until the existing trial-expiry cron picks up at Day 23 (warning_7d).

---

## 3. Trigger architecture

### Day 0 — real-time on company creation

Fires from the OPS-Web signup application code immediately after the `companies` INSERT succeeds — NOT from the Postgres trigger. The existing `initialize_company_trial` Postgres trigger (migrations 065/066) is left untouched; it continues to handle trial-window stamping only. Day 0 send is appended to the API route that performs the company insert (likely `POST /api/auth/sync-user` or wherever the company row is created), post-success but pre-response, dispatched asynchronously (`setTimeout(0)` or a non-awaited Promise) so the signup response is not blocked. Send failure logs but does not roll back the signup.

**Why real-time, not cron**: research is unambiguous that the welcome email should fire instantly. Waiting until the next 7am cron loses the "they just signed up and are still in their browser" moment.

**Recipient**: the first admin of the newly created company (`companies.admin_ids[0]` joined to `users`). If multiple admin_ids are pre-populated at insert time (rare on signup), only the first gets Day 0 — others get nothing from this drip.

**Skip conditions for Day 0**:
- User invited as a team member (joined an existing company instead of creating one) — handled by the existing team-invite path, not this drip
- Company is internal/test (env-flagged email domains: `@opsapp.co`, `@anthropic.com`, etc. — full allowlist in implementation)
- Email is on `email_suppressions` with `list='global'` (handled by `gatedSend` automatically)

### Days 1, 3, 4, 8, 14 — daily cron at 8am operator local time

New cron route: `/api/cron/onboarding-drip`. Schedule: `0 14 * * *` UTC (7am PT — same slot as `/api/cron/trial-expiry`, the two services share the operator's daily email send window).

The cron queries `companies` where `created_at` was N days ago (N ∈ {1, 3, 4, 8, 14}), computes operator-local time per `(latitude, longitude)` via existing `detectCompanyTimezone()` helper, and only sends if the current UTC moment falls within the 8–10am local window for that operator. Operators outside the window get the email at the next cron tick that catches them in-window.

**Why local time**: research showed morning sends (8–10am local) produce meaningfully better open rates for B2B. We already have the timezone helper. Reusing it is free.

**Dedup**: each send writes to a new `onboarding_email_log` table (see §8) with unique `(user_id, kind)` where `kind` encodes the day AND the branch (`day_1_no_project`, `day_1_has_project`, etc.). Reruns are safe — already-sent rows are skipped silently.

### Behavior-triggered re-engagement

Same cron sweeps for the "Lost you?" send. Conditions in §7.

---

## 4. Sender, format, and voice rules

| Email | From | Reply-To | Format | Voice |
|---|---|---|---|---|
| Day 0 | `Jack Sweet <jack@opsapp.co>` | `jack@opsapp.co` | Plain text. No glass card. No logo. No `[ CTA ]` brackets. | Jack the human — warm, specific, ends with a question |
| Day 1 | `OPS Dispatch <dispatch@opsapp.co>` | `jack@opsapp.co` | Standard OPS HTML template, glass card, JetBrains Mono numbers | Tactical OPS — `// OPERATOR ::` register, terse, action-oriented |
| Day 3 | `Jack Sweet <jack@opsapp.co>` | `jack@opsapp.co` | Plain text (same as Day 0) | Jack the human |
| Day 4 | `OPS Dispatch <dispatch@opsapp.co>` | `jack@opsapp.co` | OPS HTML template + custom mocked iOS push notification card | Tactical OPS |
| Day 8 | `Jack Sweet <jack@opsapp.co>` | `jack@opsapp.co` | Plain text | Jack the human |
| Day 14 | `OPS Dispatch <dispatch@opsapp.co>` | `jack@opsapp.co` | OPS HTML template, branched on activity stats | Tactical OPS, with "Jack wants to know" reply path |
| Re-engagement | `Jack Sweet <jack@opsapp.co>` | `jack@opsapp.co` | Plain text | Jack the human |

**Reply-to is always `jack@opsapp.co`** so any reply to any email in the drip lands in his inbox — DISPATCH is not a monitored sender.

**Plain-text emails (Days 0, 3, 8, re-engagement) intentionally bypass the standard `ComplianceFooter`** rendered by other OPS email templates. The reasoning:
- These are arguably transactional/relationship messages under CAN-SPAM (welcome from founder, behavioral check-in) — exempt from the physical-address requirement
- The `gatedSend` chokepoint still attaches the RFC 8058 `List-Unsubscribe` SMTP header, so Gmail/Outlook show an "Unsubscribe" link by the sender name automatically — invisible to the reader but provides the legal opt-out path
- Result: reader experiences a clean personal email; compliance is intact

If legal review later determines visible attribution is required, a single grey line at the bottom (`OPS LTD. · Victoria, BC`) is a 5-minute template change.

---

## 5. State branches and skip rules

### Branches

| Email | State question | A (default) | B (state-aware) |
|---|---|---|---|
| Day 1 | Has at least one non-deleted project? | **No** → "the move that gets OPS working" | **Yes** → "you're moving" |
| Day 4 | Has the operator ever received a `task_completed` notification? | **No** → "the notification you're working toward" (with mocked push card) | **Yes** → "you've heard the ping" |
| Day 14 | Any project create, task assign, or task complete in the last 7 days? | **Quiet** → "is OPS slotting in or in the way?" | **Active** → "you're 14 days in" (with live stats) |

### Kill switches (skip drip entirely for this recipient on this day)

Evaluated in the cron before computing state:

1. **Company `deleted_at` is set** → skip silently
2. **Company `subscription_status` ∈ {`cancelled`, `expired`, `paused`}** → skip silently. Resubscribers will not retroactively receive missed drip emails — this is acceptable.
3. **Company `subscription_status` = `active` (paid early)** → still fire all drip emails as scheduled. The check-in and feature beats are still useful post-paid. v2 may add a "welcome to paid" variant; out of scope here.
4. **Admin user list is empty or all admin emails are NULL/deleted** → skip silently and log a warning
5. **All admin emails are on `email_suppressions.list='global'`** → `gatedSend` handles this automatically — the row is written to `email_log` with `status='suppression_skipped'`

### Skip-individual-email rules (continue the drip but don't send this one)

- **Day 14 Active branch**: if all three stat counts (`projectCount`, `taskCount`, `notificationCount`) are zero, downgrade to the Quiet branch instead. The "you're moving" framing only fires when there's real activity to point at.

---

## 6. Email copy (canonical)

The copy below is the authoritative source. The TSX templates implement these strings verbatim; future copy edits land here first, then in the templates.

### Day 0 — Founder welcome

**From**: `Jack Sweet <jack@opsapp.co>` · **Reply-To**: `jack@opsapp.co`
**Subject**: `quick question`
**Body** (plain text):

```
Hey there {{firstName}},

My name is Jack, I built OPS.

I'm glad you signed up, and I'm looking forward to hearing
what you think of it as you grow.

What led you to join? Are you just kicking tires? Are you
considering moving from another platform? Just getting into
digital tools for your business? Whatever the case, I'm
happy to help you get rolling. I built this tool because
there was nothing on the market that worked for my crew.
I got the impression those were all tech companies built
by guys who have never actually worked on a jobsite. So
here we are.

Again, if there's anything you need help with, you can reply
to this email, it's my personal inbox.

— Jack
```

If `{{firstName}}` is null/empty, opener degrades to `Hey there,`.

### Day 1 Branch A — No project yet

**From**: `OPS Dispatch <dispatch@opsapp.co>` · **Reply-To**: `jack@opsapp.co`
**Subject**: `the move that gets OPS working`
**Body** (OPS tactical HTML template):

```
Day 1. You signed up yesterday.

The move that unlocks the rest: drop your first project in.
Real client, real address, real tasks.

Without a project, the rest of OPS has nothing to attach to.
With one, the system starts coming alive — schedule, crew,
photos, estimates, invoices all hang off it.

Use a job you're actually running this week. Takes two minutes.

[ DROP YOUR FIRST PROJECT ]
```

CTA URL: `${NEXT_PUBLIC_APP_URL}/projects/new`

### Day 1 Branch B — Has at least one project

**From**: `OPS Dispatch <dispatch@opsapp.co>` · **Reply-To**: `jack@opsapp.co`
**Subject**: `you're moving`
**Body**:

```
Day 1. {{projectCountLine}}

That's the spine. Next move that gets you to the moment OPS
actually earns its keep: tasks on those projects + a crew
member with the mobile app installed.

When a team member taps DONE in the field, the notification
lands on your phone — from a job you weren't on, on a task
you didn't have to chase.

[ ASSIGN A TASK + INVITE A CREW MEMBER ]
```

`{{projectCountLine}}` renders as:
- `count === 1` → `You've already got your first project in.`
- `count > 1` → `You've got {{count}} projects in.`

CTA URL: `${NEXT_PUBLIC_APP_URL}/dashboard` (operator picks where to go from there)

### Day 3 — Inbox → lead (Jack)

**From**: `Jack Sweet <jack@opsapp.co>` · **Reply-To**: `jack@opsapp.co`
**Subject**: `the part of OPS I'm most proud of`
**Body** (plain text):

```
Hey there {{firstName}},

Jack again.

When I was running my deck and rail crew, the thing that
killed me wasn't a single big problem. It was wearing every
hat at once.

One inbox. Lead emails, vendor emails, sub emails, accounting
questions, customer photos, supplier confirmations — all of
it landing in the same spot at the same time. No office.
Nobody triaging anything. Nobody nudging me when I'd missed
replying to a lead from three days back.

And I had no idea if my ads were working. I'd spend money
on Google and Facebook and Yelp, and at the end of the
month I couldn't tell you which inquiries had turned into
jobs, or what those jobs were actually worth. I was flying
blind.

Data is power. I didn't have any.

That's the part of OPS I'm most proud of.

You connect your work inbox. OPS reads everything that comes
in and separates the leads from the noise. The customer
asking for a quote on a new install lands in your pipeline,
tagged, with their address pulled out and the scope guessed
at. The vendor confirming an order goes elsewhere. The
supplier asking for a PO doesn't get treated like a lead.

Then OPS tracks every lead from "first email" to "job won"
to "invoice paid." You see what your cost per won job is,
by source. You see which ads are actually paying back. You
make decisions on numbers instead of gut.

The intelligent classification doing the work is the kind
of thing I'd never explain on a job site, so I won't here.
It works. We're working on supercharging your workflows with AI.

Connecting your inbox takes about two minutes. Hit reply if
you want to tell me what your inbox chaos looks like right
now — I read every reply.

— Jack
```

### Day 4 Branch A — No completion notification yet

**From**: `OPS Dispatch <dispatch@opsapp.co>` · **Reply-To**: `jack@opsapp.co`
**Subject**: `the notification you're working toward`
**Body** (OPS HTML template with custom iOS push notification card):

```
Day 4.

Here's the moment you're working toward:

[ ╔══════════════════════════════════╗ ]
[ ║ OPS                       now    ║ ]   <- styled as iOS push card
[ ║                                  ║ ]      in the TSX template
[ ║ // JAKE COMPLETED                ║ ]
[ ║    5611 BATU RD — RAIL INSTALL   ║ ]
[ ║                                  ║ ]
[ ║ TAP TO VIEW                      ║ ]
[ ╚══════════════════════════════════╝ ]

That notification lands on your phone the first time someone
on your crew taps DONE in the field. From a job you weren't
on. On a task you didn't have to chase.

To get there:
  1. Invite at least one crew member
  2. Get them logged into the OPS mobile app
  3. Assign them a task

[ INVITE YOUR CREW ]

The first time you hear that ping while you're somewhere else,
you'll know why we built this.
```

The notification mockup is a custom React Email component styled to look like an iOS push notification — black background, JetBrains Mono, slight border-radius. NOT ASCII art in production.

CTA URL: `${NEXT_PUBLIC_APP_URL}/settings/team`

### Day 4 Branch B — Already received completion notification

**From**: `OPS Dispatch <dispatch@opsapp.co>` · **Reply-To**: `jack@opsapp.co`
**Subject**: `you've heard the ping`
**Body**:

```
Day 4. At least one crew member has tapped DONE in the field
and you've seen the notification land.

Most operators are surprised by how good that feels — the
quiet of not having to chase.

The moves that compound it:

  → Recurring jobs for the work you do every week
  → More crew, so the leverage scales
  → Templates so you don't rebuild the same tasks every time

[ SET UP RECURRING JOBS ]

You're past the first hill. The next 26 days is about putting
the rest of your business in.
```

CTA URL: `${NEXT_PUBLIC_APP_URL}/projects?filter=recurring`

### Day 8 — Estimates + portal (Jack)

**From**: `Jack Sweet <jack@opsapp.co>` · **Reply-To**: `jack@opsapp.co`
**Subject**: `how your customers see your estimates`
**Body** (plain text):

```
Hey there {{firstName}},

Jack again, last one of these you'll get from me for a while.

I want to tell you a story about a deck builder I know.

He ran his estimates out of a Word doc template. Every new
customer, he'd open the last one he sent, save-as, update
the fields. Or try to.

I was constantly on his back about it. He'd send estimates
with the wrong customer name at the top. With the previous
customer's address still in there. With totals that didn't
match the line items because he'd updated the materials but
forgot the bottom number.

If he caught it, he'd send a follow-up: "sorry, mixed up
the name." "Sorry, clerical error on the address." "Apologies
for the confusion."

The one I'll never forget: he started a job on a Monday,
realized halfway through the week that the estimate he'd
sent was for the previous customer's project, and the price
was 20% below what the new job actually cost him. He had to
beg the customer mid-job to accept the higher number because
he'd forgotten to update one field in a template.

You can imagine how that went over.

That's the kind of thing that kills small businesses. Not
because the work is bad. Because the back-office is held
together with copy-paste and good intentions.

When you send an estimate from OPS, your customer gets a
link to a branded portal — your logo, your business name,
the line items pulled from your real pricing. They read it,
ask questions on individual items, approve or decline, and
pay through the portal directly. You don't copy-paste
anything. You can't forget to update a field that doesn't exist.

If you want to see what your customers see, send a test
estimate to your own email. Takes about three minutes from
inside OPS.

— Jack
```

### Day 14 Branch A — Quiet

**From**: `OPS Dispatch <dispatch@opsapp.co>` · **Reply-To**: `jack@opsapp.co`
**Subject**: `is OPS slotting in or in the way?`
**Body**:

```
Day 14. Halfway through your trial.

It's been quiet on your account.

Could be a lot of things — you've been busy on actual work,
you tried it and it didn't fit, something tripped you up
during setup, the timing isn't right.

No judgment either way. But Jack wants to know which one it is.

Hit reply on this email — goes to his inbox. One sentence
is enough.

If something specifically didn't work, tell him. If you forgot
about it, tell him that too. The product gets better when
operators tell us what's grinding their gears.

[ OR PICK UP WHERE YOU LEFT OFF ]
```

CTA URL: `${NEXT_PUBLIC_APP_URL}/dashboard`

### Day 14 Branch B — Active

**From**: `OPS Dispatch <dispatch@opsapp.co>` · **Reply-To**: `jack@opsapp.co`
**Subject**: `you're 14 days in`
**Body** (template logic drops any stat line whose count is zero):

```
Day 14. You're running OPS.

You've got {{projectCount}} project{{s}} going,
{{taskCount}} task{{s}} assigned, and your crew has fired off
{{notificationCount}} completion notification{{s}}.

Jack wants to know two things:

  1. What's working that you didn't expect?
  2. What's broken, missing, or in the way?

Hit reply — goes to his inbox. One sentence per question
is enough.

The product gets better when operators tell us what's
grinding their gears.
```

No CTA URL — the action IS the reply.

---

## 7. Behavior-triggered re-engagement send

Fires from the same daily cron, evaluated per company after the calendar-driven checks.

### Conditions to fire

ALL of the following must hold:

1. Company `created_at` is between 1 and 14 days ago (the drip window)
2. **Zero activity in the last 4+ consecutive days** — no project create, no task assign, no task complete, no completion notification, no login (use `last_login_at` from `users` if available; otherwise fall back to last `notifications` row for this user)
3. The "Lost you?" email has NOT already been sent to this company (`onboarding_email_log` has no row with `kind='lost_you'` for any admin of this company)
4. The Day 14 email has not yet fired (after Day 14 the calendar drip ends and behavior-trigger stops)
5. Standard kill switches from §5 do not apply

### Email copy

**From**: `Jack Sweet <jack@opsapp.co>` · **Reply-To**: `jack@opsapp.co`
**Subject**: `lost you?`
**Send time**: 10am operator local (later than morning sends, lower-urgency)
**Body** (plain text):

```
Hey {{firstName}},

Jack here.

Noticed you signed up for OPS {{daysSinceSignup}} days ago
and haven't been back in {{daysSinceLastActivity}} days.

That's a real signal. Could be:

  - You got busy on actual work (most common)
  - Something tripped you up during setup
  - You tried it and it didn't fit
  - The timing's wrong

Whichever one it is, I want to know. Hit reply and tell me
in one sentence — goes to my personal inbox.

If it's the setup one, I'll usually be able to point you at
the move that gets you unstuck.

— Jack
```

### Why this fires from Jack, not Dispatch

Behavior triggers like this only land if the recipient believes a human noticed. Sending it from Dispatch would feel automated and undermine the whole point.

---

## 8. Data model changes

### New table — `onboarding_email_log`

Migration filename: `108_onboarding_email_log.sql` (next sequential slot; verify before applying).

```sql
CREATE TABLE IF NOT EXISTS public.onboarding_email_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  kind text NOT NULL CHECK (kind IN (
    'day_0_welcome',
    'day_1_no_project',
    'day_1_has_project',
    'day_3_inbox',
    'day_4_no_notification',
    'day_4_has_notification',
    'day_8_estimates',
    'day_14_quiet',
    'day_14_active',
    'lost_you'
  )),
  sent_at timestamptz NOT NULL DEFAULT now(),
  email_log_id uuid REFERENCES public.email_log(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT onboarding_email_log_unique UNIQUE (user_id, kind)
);

CREATE INDEX IF NOT EXISTS idx_onboarding_email_log_company
  ON public.onboarding_email_log (company_id);
CREATE INDEX IF NOT EXISTS idx_onboarding_email_log_sent_at
  ON public.onboarding_email_log (sent_at DESC);

COMMENT ON TABLE public.onboarding_email_log IS
  'Dedup table for the onboarding drip cron. UNIQUE (user_id, kind) prevents duplicate sends; ON CONFLICT DO NOTHING on insert makes the cron idempotent. Mirrors the trial_expiry_notifications pattern from migration 053.';
```

### Additions to existing tables / config

| File | Change |
|---|---|
| `OPS-Web/src/lib/email/constants.ts` | Add 10 new entries to `KIND_TO_LIST` — all 10 `kind` values above mapped to `'global'` list |
| `OPS-Web/src/lib/email/template-registry.ts` | Add 10 new entries (one per distinct template) so admin preview works for each |
| `OPS-Web/src/lib/email/pause.ts` `resolveEmailBucket()` | Add 10 case statements mapping the new kinds — Jack's go to `dispatch` (same bucket, just a different sender identity); Dispatch's also go to `dispatch` |
| `OPS-Web/vercel.json` | Add cron entry `{"path": "/api/cron/onboarding-drip", "schedule": "0 14 * * *"}` |

### No schema changes to existing tables

- `companies` — unchanged
- `users` — unchanged
- `notifications` — unchanged
- `email_log` / `email_campaigns` / `email_jobs` — unchanged. Onboarding drip uses transactional sends (typed `sendXxx` directly), NOT the campaign engine. Rationale: campaign engine is built for "blast N recipients on a schedule"; the drip is "1 recipient, deterministic schedule, per-recipient state branch" — better matches the trial-expiry pattern than the campaign pattern.

---

## 9. Cron schedule additions

One new entry in `OPS-Web/vercel.json` `crons` array:

```json
{
  "path": "/api/cron/onboarding-drip",
  "schedule": "0 14 * * *"
}
```

`0 14 * * *` UTC = 7am PT daily. Same slot as `/api/cron/trial-expiry`. Both crons read the operator's local timezone via `detectCompanyTimezone(lat, lon)` and only fire for operators whose local time is currently in the 8–10am window.

**Why not stagger the trial-expiry and onboarding-drip crons?** They operate on disjoint company sets (`subscription_status='trial' AND created_at < N days ago` vs `created_at BETWEEN N-14 and N days ago`) and write to disjoint dedup tables. No collision risk. Running both at the same UTC moment is simpler.

---

## 10. Implementation plumbing

### New files

| Path | Purpose |
|---|---|
| `OPS-Web/src/lib/email/react/templates/onboarding/Day0Welcome.tsx` | Plain-text template, no glass card |
| `OPS-Web/src/lib/email/react/templates/onboarding/Day1NoProject.tsx` | OPS HTML, glass card |
| `OPS-Web/src/lib/email/react/templates/onboarding/Day1HasProject.tsx` | OPS HTML |
| `OPS-Web/src/lib/email/react/templates/onboarding/Day3Inbox.tsx` | Plain-text |
| `OPS-Web/src/lib/email/react/templates/onboarding/Day4NoNotification.tsx` | OPS HTML + custom iOS push notification mockup component |
| `OPS-Web/src/lib/email/react/templates/onboarding/Day4HasNotification.tsx` | OPS HTML |
| `OPS-Web/src/lib/email/react/templates/onboarding/Day8Estimates.tsx` | Plain-text |
| `OPS-Web/src/lib/email/react/templates/onboarding/Day14Quiet.tsx` | OPS HTML |
| `OPS-Web/src/lib/email/react/templates/onboarding/Day14Active.tsx` | OPS HTML with conditional stat rendering |
| `OPS-Web/src/lib/email/react/templates/onboarding/LostYou.tsx` | Plain-text |
| `OPS-Web/src/lib/email/react/primitives/MockPushNotification.tsx` | Reusable iOS-push-notification visual component for Day 4A |
| `OPS-Web/src/lib/email/react/primitives/PlainTextLayout.tsx` | New layout primitive for Jack's emails — no glass card, no logo, minimal styling, just text + signature |
| `OPS-Web/src/lib/api/services/onboarding-drip-service.ts` | Service mirroring `TrialExpiryService` structure. Methods: `processAll(supabase, now)`, `processCompany(supabase, company, now, result)`, `computeState(supabase, company)`, `sendForKind(...)` |
| `OPS-Web/src/app/api/cron/onboarding-drip/route.ts` | Cron route, auth via `Bearer ${CRON_SECRET}`, calls `OnboardingDripService.processAll()` |
| `OPS-Web/supabase/migrations/108_onboarding_email_log.sql` | Dedup table (see §8) |

### Modified files

| Path | Change |
|---|---|
| `OPS-Web/src/lib/email/sendgrid.tsx` | Add 10 typed senders: `sendOnboardingDay0Welcome`, `sendOnboardingDay1NoProject`, `...Day1HasProject`, `...Day3Inbox`, `...Day4NoNotification`, `...Day4HasNotification`, `...Day8Estimates`, `...Day14Quiet`, `...Day14Active`, `sendOnboardingLostYou`. All Jack-from-address sends pass `from: { email: 'jack@opsapp.co', name: 'Jack Sweet' }` and `replyTo: 'jack@opsapp.co'`. All Dispatch sends pass `from: DISPATCH`, `replyTo: 'jack@opsapp.co'`. |
| `OPS-Web/src/lib/email/constants.ts` | Add 10 entries to `KIND_TO_LIST` (all → `'global'`) |
| `OPS-Web/src/lib/email/template-registry.ts` | Add 10 entries — one per distinct template (Day 0 + Day 1A + Day 1B + Day 3 + Day 4A + Day 4B + Day 8 + Day 14A + Day 14B + LostYou = 10) |
| `OPS-Web/src/lib/email/pause.ts` | `resolveEmailBucket()` switch: all 10 kinds → `'dispatch'` (default bucket; Jack's emails ride the same bucket-level pause as Dispatch's) |
| `OPS-Web/vercel.json` | Add cron entry |
| `OPS-Web/supabase/migrations/065_company_trial_init_trigger.sql` is NOT modified | Day 0 enqueue happens in application code (Supabase route handler), not in the Postgres trigger. The trigger continues to handle trial state only. |

### Real-time Day 0 trigger

The signup flow currently goes:
1. Frontend calls `signUpWithEmail()` (Firebase)
2. Frontend calls `POST /api/auth/sync-user` (creates `users` row + finds-or-creates `companies` row in Supabase)
3. The `initialize_company_trial` Postgres trigger fires on `companies` insert

Day 0 send is added to step 2 — after the `companies` insert succeeds, the API route calls `sendOnboardingDay0Welcome(...)` asynchronously (`setTimeout(0)` or `Promise.race` with a 3s budget) so the signup response is not blocked. Failure of the Day 0 send logs but does not roll back the signup.

`onboarding_email_log` gets the Day 0 row written immediately on successful send so the daily cron's idempotency check works correctly.

---

## 11. Testing approach

### Unit tests

- `OPS-Web/tests/unit/api/services/onboarding-drip-service.test.ts`
  - `computeState()` returns the correct branch for each Day given fixture company state
  - `processCompany()` skips on each kill condition (deleted, cancelled, expired, no admins, suppressed)
  - `processCompany()` writes the correct `onboarding_email_log` row on success
  - Dedup: second invocation for the same (company, kind) is a no-op
  - Behavior trigger: `lost_you` only fires when all 5 conditions in §7 hold

- `OPS-Web/tests/unit/email/templates/onboarding/*.test.tsx`
  - Each template renders with `previewProps` without error
  - Plural handling on Day 1B and Day 14B (0, 1, many)
  - `{{firstName}}` null fallback on Day 0 / Day 3 / Day 8

### Integration tests

- `OPS-Web/tests/integration/onboarding-drip-cron.test.ts`
  - End-to-end cron run: seed N companies at various ages, invoke the route handler, assert correct sends + dedup rows
  - Verify timezone gating (operator outside 8–10am local does not get sent)
  - Verify activity-detection logic for Day 14 branching + `lost_you` trigger

### Manual / staging

- Each typed sender has a `POST /api/admin/email/templates/[templateId]/send-test` invocation point — operator sends each template to themselves before launch
- Day 0 real-time trigger: create a test signup in staging, verify email lands within 5 seconds
- Cron: invoke `/api/cron/onboarding-drip` manually with `Authorization: Bearer ${CRON_SECRET}` against staging

---

## 12. Compliance + brand discipline

### Compliance

- Every send routes through `gatedSend` → automatic RFC 8058 `List-Unsubscribe` SMTP header
- All 10 kinds on `'global'` suppression list — opt-out of one means opt-out of all OPS email
- Plain-text founder emails (Days 0, 3, 8, re-engagement) intentionally have no visible footer; relying on transactional/relationship CAN-SPAM exemption + the SMTP header for compliance
- OPS HTML emails (Days 1, 4, 14) use the standard `ComplianceFooter` already implemented in OPS templates

### Brand discipline (per the founder memory files and chapter 14)

All copy in this spec was vetted against these bans:

- **"Contractor" as audience label** — banned. Approved alternatives used: deck and rail crew, deck builder, crew, operators, businesses, owner-operators. Verified zero "contractor" instances in any email body or subject.
- **"AI" as bare claim** — banned. Only used:
  - In the forward-looking approved line: "We're working on supercharging your workflows with AI." (Day 3 only)
  - As "intelligent classification" framing for current behavior (Day 3 only)
- **Generic AI-tell vocabulary** — banned across all copy: `delve`, `tapestry`, `landscape` (metaphor), `seamless`, `robust`, `streamline`, `leverage`, `elevate`, `embark`, `navigate` (metaphor), `cutting-edge`, `revolutionary`, `game-changer`, `multifaceted`, `testament`, `treasure trove`, `realm of`
- **Generic AI-tell phrases** — banned: "In today's...", "It's important to note", "In summary / In essence", "It's not about X, it's about Y"

Any future copy edit to this spec or the implementing templates MUST run through the same vetting. The `ops-copywriter` skill enforces this on net-new copy.

---

## 13. Bible updates required

After implementation lands, the following bible updates ship in the same session:

1. **`13_EMAIL_SYSTEM.md`** — Add new section between § Trial-Expiry Lifecycle and § Deliverability Anomaly Detector:
   - `## Onboarding Drip` — covering the 10 kinds, the trigger architecture (real-time + cron), the dedup table, the branch logic, the kill switches, and the alternating Jack/Dispatch sender pattern
   - Add the cron to § Cron Schedule table
   - Add the 10 kinds to § Email Kinds Catalog table
   - Add `onboarding_email_log` to § Data Model
   - Update § Known Gaps to remove gap #1 ("No welcome email on signup") and gap #8 ("No mid-trial engagement drip") and gap #2 ("No internal new-signup alert" — partially resolved by Day 0 reply-to-Jack creating organic inbound visibility)

2. **`03_DATA_ARCHITECTURE.md`** — Add `onboarding_email_log` to the outbound email tables cross-reference section (added by spawned task `BIBLE EMAIL CHAPTER - P1-1`)

3. **`14_FEATURE_POSITIONING.md`** — No changes required. The Inbox and Estimates+Portal positioning lines were drawn from this chapter; the emails are downstream consumers.

---

## 14. Open questions and known gaps

### Open

1. **Plural handling rendering** — TSX components for Day 1B and Day 14B need conditional logic. Confirmed approach: use a small helper `pluralize(count, singular, plural)` that the templates import. Out of scope for this spec; trivial implementation.
2. **iOS push notification mockup styling** — the `MockPushNotification.tsx` primitive needs to look credibly like an iOS push card without copying Apple's design verbatim. Design pass needed; defer to implementation.
3. **What counts as "activity" for the `lost_you` trigger** — current proposal: any of {project create, task assign, task complete, login}. Open question: should opening a project window also count? Probably yes — implementation pulls from existing analytics if available, else falls back to the listed events.
4. **Real-time Day 0 send retry semantics** — if SendGrid is down at signup, the Day 0 email is lost (the daily cron's `kind='day_0_welcome'` check will see no row and try to send it the next day, but at Day 1 it's no longer real-time and the moment is gone). Acceptable for v1. Future improvement: a small retry queue.

### Known gaps (deferred to v2)

1. **"Welcome to paid" variant when operator pays early** — out of scope. v1 continues firing the calendar drip even after they convert.
2. **Subjects A/B test infrastructure** — no infrastructure built. v1 ships fixed subjects per the canonical copy in §6. If open rates underperform, building A/B requires a new column on `onboarding_email_log` and a tiny RNG split — small follow-up.
3. **"You've hit the aha" instant congrats** — earlier discussion considered firing Day 4B in real time the moment the first completion notification lands instead of waiting for Day 4. Deferred; the calendar trigger is good enough for v1.
4. **Localized copy (Spanish)** — all copy in this spec is English. OPS-Web has `useDictionary` i18n infrastructure but the onboarding drip is launching English-only. Spanish translation is a follow-up.
5. **Internal "new signup" Slack/email alert to the operator team** — separate feature, not in this spec. Day 0's reply-to-Jack creates organic signal but doesn't catch silent signups.

---

## 15. Decision log

Decisions captured during brainstorming (with the founder), in chronological order:

| # | Decision | Why |
|---|---|---|
| 1 | Reply commitment: "I read every reply" verbatim | Founder confirmed personal reply commitment at any expected volume |
| 2 | Drip length: 6 calendar emails (revised from initial "4 emails" answer) | Founder wanted feature beats interleaved; ended at 6 scheduled + 1 behavior-triggered |
| 3 | Aha moment: completion notification from the field | Founder identified — "Jake completed 5611 Batu Rd Rail Install" is the leverage moment |
| 4 | Branched content (not skip-based) | Founder suggested branching on user state; more impactful than skipping |
| 5 | Trigger on company creation (not Firebase signup) | Distinguishes new operators from invited team members |
| 6 | Day 0 plain text from `jack@opsapp.co` | Must look like real personal email; styled marketing template breaks the spell |
| 7 | All 10 kinds on `'global'` suppression list | Founder drip unsubscribe = full opt-out signal |
| 8 | Three research-driven tunings adopted: instant Day 0, local-time sends, behavior-triggered re-engagement | Research data on activation lift was unambiguous |
| 9 | Feature emails (Day 3, Day 8) shifted from Dispatch to Jack personal voice | Founder direction post-feature-positioning-chapter review; personal beats Dispatch for feature explanations |
| 10 | Day 3 reframed from "missed an email at work" to "drowning in single inbox + no measurement" | Founder corrected — the real owner-operator pain is wearing too many hats, not being busy |
| 11 | Day 8 story switched from painter to deck builder; specific 20%-mid-job-disaster anecdote added | Founder provided real story; on-brand and earns the length |
| 12 | "Contractor" as audience label banned; "AI" as bare claim banned | Founder corrections to chapter 14; applied across all drip copy |
| 13 | No first-name attribution for the deck builder friend on Day 8 | Founder direction — privacy + the anonymous version reads stronger |
| 14 | Hardcode copy in templates (not features catalog table) | Chosen for v1; refactor path noted if scope grows |
| 15 | Onboarding drip uses transactional sends, NOT the campaign engine | Better matches the per-recipient calendar pattern; mirrors `TrialExpiryService` |

---

**End of spec.**
