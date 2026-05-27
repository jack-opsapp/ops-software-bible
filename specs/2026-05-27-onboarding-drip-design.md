# Onboarding Drip — Design Spec (v2)

**Date**: 2026-05-27 (revised after outside review + discovery of dormant existing system)
**Status**: Approved by founder (Jackson) — ready for implementation plan.
**Supersedes**: commit `6549513` (v1). See [Revision History](#revision-history) for what changed.
**Scope**: Replace the dormant `lifecycle-emails` / `lifecycle-cron` / `lifecycle-onboarding-complete` / `lifecycle-first-action` Supabase Edge Functions with an in-repo onboarding drip integrated into the OPS-Web `gatedSend` chokepoint. Day 0 through Day 14, then handoff to the existing trial-expiry cron at Day 23. Closes `13_EMAIL_SYSTEM.md` Known Gaps #1, #2, #8.

**Source Reference**:
- `13_EMAIL_SYSTEM.md` — outbound email infrastructure
- `14_FEATURE_POSITIONING.md` — canonical positioning for Day 3 (inbox) and Day 8 (estimates + portal)
- `12_SUBSCRIPTION_MANAGEMENT.md` — trial lifecycle, hand-off at day 23
- `OPS-Web/src/lib/email/sendgrid.tsx` — the `gatedSend` chokepoint (line 122)
- `OPS-Web/src/app/api/setup/progress/route.ts:122` — the verified `companies` INSERT site (Day 0 hook point)
- `OPS-Web/supabase/migrations/053_trial_expiry_notifications.sql` — analogous dedup pattern this spec mirrors
- `OPS-Web/supabase/migrations/065_company_trial_init_trigger.sql` / `066_refine_company_trial_trigger.sql` — the existing trial-window trigger (unchanged by this spec)
- `OPS-Web/src/lib/api/services/trial-expiry-service.ts` — service shape this spec mirrors
- `OPS-Web/src/lib/api/services/notification-dispatch.ts:187-201` — the real `task_completed` notification format that the Day 4A mock must match
- Supabase Edge Functions: `lifecycle-emails` (v11), `lifecycle-cron` (v5), `lifecycle-onboarding-complete` (v5), `lifecycle-first-action` (v5) — the dormant systems being decommissioned
- Brand voice: `/Users/jacksonsweet/Projects/OPS/CLAUDE.md` § Brand & MO; founder memory files (`feedback_contractor_banned_in_marketing.md`, `feedback_ai_framing_in_marketing.md`)

---

## Table of Contents

1. [Background — including what's being replaced](#1-background--including-whats-being-replaced)
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
14. [Migration & cutover plan](#14-migration--cutover-plan)
15. [Open questions and known gaps](#15-open-questions-and-known-gaps)
16. [Decision log](#16-decision-log)
17. [Revision history](#revision-history)

---

## 1. Background — including what's being replaced

A new trades business signs up at `/register`. Firebase Auth creates the credential; the user/company rows are written into Supabase via `POST /api/setup/progress`; the `initialize_company_trial` Postgres trigger stamps a 30-day trial window. The operator lands on the onboarding screen.

From that moment until day 23 (when the trial-expiry cron fires `warning_7d`), **the operator currently receives zero production emails from OPS**. This spec closes that gap.

### What already exists (and why it can't be used as-is)

Four Supabase Edge Functions ship a lifecycle-email scaffolding that was built and deployed but never put into production:

| Function | Status | What it does |
|---|---|---|
| `lifecycle-emails` (v11) | ACTIVE in Supabase, **all 11 email types disabled** in `lifecycle_email_config` since 2026-03-05, **zero rows in `email_log`** for any of its email_type values | Direct SendGrid Mail API send (bypasses `gatedSend`). 11 hardcoded plain-text templates in Jack's voice. Reads enable/disable + day windows from `lifecycle_email_config` |
| `lifecycle-cron` (v5) | ACTIVE | Cron-style sweep that adds contacts to SendGrid Marketing Lists (e.g. `SENDGRID_LIST_INACTIVE_14D`) when companies hit specific day-offsets |
| `lifecycle-onboarding-complete` (v5) | ACTIVE | Webhook on `users.has_completed_onboarding` flipping true. Removes from `NO_ONBOARDING` list, adds to `NO_FIRST_PROJECT` list if no projects/clients exist |
| `lifecycle-first-action` (v5) | ACTIVE | Webhook on first project/client insert. Removes from `NO_FIRST_PROJECT` list |

**As confirmed with the founder on 2026-05-27, there are no live SendGrid Automations attached to any of those lists.** The entire existing system is dormant. No emails have ever sent in production.

This spec therefore:
- Treats the existing edge functions as **reference material**, not running infrastructure
- Adopts the **precise trigger conditions** the existing system already worked out (`has_completed_onboarding=false`, `!hasProjects && !hasClients`) — these are sharper than the v1 spec's "has at least one project" check
- Inherits a few **good copy patterns** from the existing templates where they're sharper than ours (specific lines noted in §6)
- Plans a **clean cutover** that disables the 4 edge functions and deletes the `lifecycle_email_config` rows — see §14

### Why a new in-repo system instead of fixing the edge functions

The existing edge functions have structural problems that aren't worth patching:

| Existing edge function problem | In-repo solution |
|---|---|
| Bypasses `gatedSend` — no suppression, no pause killswitch, no RFC 8058 unsubscribe header | All sends route through `gatedSend` |
| Templates are inline HTML strings, no React Email, no design system, no admin preview | React Email TSX templates in `OPS-Web/src/lib/email/react/templates/onboarding/` with `template-registry.ts` entries |
| Lives in separate Deno repo, not version-controlled with OPS-Web | All code in `OPS-Web/` |
| Hardcoded `FROM_EMAIL = 'jack@opsapp.co'`; not a documented sender identity | `JACK` added to `OPS-Web/src/lib/email/senders.ts` and `13_EMAIL_SYSTEM.md` § Sender Identities |
| No timezone awareness | Hourly cron + `detectCompanyTimezone()` |
| No compliance footer | Visible footer on every email (see §12) |
| Not in the bible | Documented in `13_EMAIL_SYSTEM.md` § Onboarding Drip after launch |

### Activation research that motivates the shape

Sources documented in the brainstorming session transcript. Specific numbers omitted from this spec body to keep it source-bound; qualitative points only:

- Activated trial users convert at a meaningfully higher rate than unactivated ones
- Email-engaged trial users convert at a meaningfully higher rate than non-engaged ones
- Branched / personalized onboarding outperforms static
- Proactive founder outreach correlates with better activation and retention
- Industry sweet spot for B2B SaaS trial onboarding is 5–8 emails over 14–30 days

This spec ships 6 calendar-scheduled emails + 1 behavior-triggered re-engagement send, plus a real-time Day 0 founder welcome.

---

## 2. Drip shape

| Day | From | Voice | Job |
|---|---|---|---|
| **0** | Jack | Personal, plain text | Founder welcome. Asks what brought them in. "I read every reply." |
| **1** | Dispatch | Tactical, HTML | First project nudge. Branched on whether they have a project AND a client. |
| **3** | **Jack** | Personal, plain text | Inbox → lead. Triage + measurement value-prop. |
| **4** | Dispatch | Tactical, HTML | Crew + completion notification. Branched on whether they've felt the aha. Includes mocked iOS push card matching the real `dispatchTaskCompleted` format. |
| **8** | **Jack** | Personal, plain text | Estimates + branded portal. Deck-builder Word-doc-disaster story. |
| **14** | **Jack** | Personal, plain text | Honest pulse check. Branched on activity. From Jack (changed from v1 — see decision log #16). |
| **+** | **Jack** | Personal, plain text | "Lost you?" re-engagement. Fires on 6+ days of zero activity between Day 1 and Day 14. |

Sender rhythm: Jack on Days 0/3/8/14 + Re-engagement (5 personal beats); Dispatch on Days 1/4 (2 tactical beats). The personal-heavy mix is intentional because (a) every email's reply-to is Jack so the From should match, and (b) the activation lift research correlates with founder presence, not branded sends.

After Day 14 the drip ends. Trial-expiry cron handles Day 23 onward.

---

## 3. Trigger architecture

### Day 0 — real-time on company creation

**Hook point: `POST /api/setup/progress/route.ts:122`** (verified — this is the actual `companies` INSERT site, NOT `sync-user`).

After the company INSERT succeeds, the route:
1. Inserts a row into `onboarding_email_log` with `kind='day_0_welcome'`, `status='pending'`, `attempts=0`
2. Dispatches the send asynchronously via `Promise.resolve().then(() => sendOnboardingDay0Welcome(...))` (non-awaited, non-blocking on the API response)
3. On send success → update `onboarding_email_log` row to `status='sent'`, write `sent_at`, link `email_log_id`
4. On send failure → update to `status='failed'`, increment `attempts`, record `last_error`

**Durable retry**: the daily cron (§3 next subsection) sweeps `onboarding_email_log WHERE kind='day_0_welcome' AND status IN ('pending','failed') AND attempts < 3 AND created_at > now() - interval '24 hours'` and retries. If a Day 0 send is lost (Vercel function killed mid-dispatch, SendGrid 503, etc.), the cron picks it up on the next tick.

**Skip conditions for Day 0**:
- `user_type` is not `"company"` (i.e. invited team member, not new operator)
- Company `deleted_at` is set
- Email domain matches an internal allowlist (`@opsapp.co`, `@anthropic.com`, test domains)
- Email is on `email_suppressions.list='global'` (handled automatically by `gatedSend`)

The existing `lifecycle-onboarding-complete` edge function's filter `userType === "company"` is preserved as the canonical "is this an operator?" check.

### Days 1, 3, 4, 8, 14 — hourly cron with operator-local-time gating

**Schedule: `0 * * * *` (every hour at minute 0).** Replaces the daily `0 14 * * *` from v1 which the reviewer correctly flagged as broken — a single 14:00 UTC daily fire can't deliver to all timezones in their morning window.

The cron route `/api/cron/onboarding-drip`:
1. Queries `companies` where `created_at` was 1, 3, 4, 8, or 14 days ago (within a generous 25-hour bracket per offset to never miss anyone)
2. For each candidate company, resolves operator timezone via `detectCompanyTimezone(lat, lon)` (existing helper used by trial-expiry)
3. Fires only if **operator-local hour is 9** (single target hour — not a 2-hour window — because the hourly cron only fires once per hour per operator; the single-hour gate prevents drift across DST boundaries and edge cases)
4. Resolves Day N state (see §5), picks the matching email kind
5. Calls `sendForKind(kind, company, user)` which uses claim-before-send dedup

**Claim-before-send dedup** (fixes v1's race condition where Day 1A and Day 1B could both fire if state flipped between cron ticks):

```
INSERT INTO onboarding_email_log (user_id, company_id, day_slot, branch, status, attempts)
VALUES ($1, $2, $3, $4, 'pending', 0)
ON CONFLICT (user_id, day_slot) DO NOTHING
RETURNING id;
```

- `day_slot` is the day number alone (`0`, `1`, `3`, `4`, `8`, `14`, `lost_you`) — **same regardless of branch**
- `branch` records which variant was chosen (`'no_project'`, `'has_project'`, `'no_aha'`, `'has_aha'`, `'quiet'`, `'active'`, or `null` for unbranched)
- Unique constraint on `(user_id, day_slot)` — only one row per user per slot, no matter which branch
- Only the winner of the INSERT gets a row id back; only the winner sends; the loser silently skips

This is a strict improvement over v1's branch-specific dedup keys which would allow both branches to fire under a state flip.

### Behavior-triggered re-engagement

Same hourly cron sweeps for the "Lost you?" send. Conditions in §7.

---

## 4. Sender, format, and voice rules

| Email | From | Reply-To | Format | Voice |
|---|---|---|---|---|
| Day 0 | `Jack Sweet <jack@opsapp.co>` | `jack@opsapp.co` | Plain text. No glass card. No logo. No bracketed CTAs. | Jack the human — warm, specific, ends with a question |
| Day 1 | `OPS Dispatch <dispatch@opsapp.co>` | `jack@opsapp.co` | Standard OPS HTML template, glass card, JetBrains Mono numbers | Tactical OPS — `// OPERATOR ::` register, terse, action-oriented |
| Day 3 | `Jack Sweet <jack@opsapp.co>` | `jack@opsapp.co` | Plain text | Jack the human |
| Day 4 | `OPS Dispatch <dispatch@opsapp.co>` | `jack@opsapp.co` | OPS HTML template + custom mocked iOS push notification card matching `dispatchTaskCompleted` format | Tactical OPS |
| Day 8 | `Jack Sweet <jack@opsapp.co>` | `jack@opsapp.co` | Plain text | Jack the human |
| Day 14 | **`Jack Sweet <jack@opsapp.co>`** (changed from v1) | `jack@opsapp.co` | Plain text | Jack the human |
| Re-engagement | `Jack Sweet <jack@opsapp.co>` | `jack@opsapp.co` | Plain text | Jack the human |

**Jack added as a documented sender identity.** New constant in `OPS-Web/src/lib/email/senders.ts`:

```ts
export const JACK: Sender = {
  email: "jack@opsapp.co",
  name: "Jack Sweet",
};
```

`13_EMAIL_SYSTEM.md` § Sender Identities updated to include the JACK bucket (used for founder-direct sends).

**Visible compliance footer on every email** (changed from v1 — the v1 argument that founder emails could skip the visible footer under transactional/relationship exemption was optimistic; outside review correctly flagged CAN-SPAM / CASL / PECR / Google Sender Guidelines all push toward visible footers for any message that promotes product usage, which Days 3, 8, 14, and Re-engagement all do).

Footer format (rendered as a single small grey line, both for plain-text emails and HTML emails):

```
OPS LTD. · 1515 Douglas St, Victoria, BC V8W 2G4 · Unsubscribe
```

The "Unsubscribe" link uses the existing RFC 8058 HMAC-signed unsubscribe URL (`buildUnsubscribeUrl` in `OPS-Web/src/lib/email/unsubscribe-token.ts`).

`gatedSend` continues to attach the `List-Unsubscribe` SMTP header automatically for one-click Gmail/Outlook unsubscribe — the visible footer adds the legally-required visible opt-out path on top.

---

## 5. State branches and skip rules

### Branches — adopting the precise conditions from the dormant edge function

The dormant `lifecycle-emails` worked out more-precise branch conditions than v1 of this spec used. Adopting them:

| Email | State question | A | B |
|---|---|---|---|
| Day 1 | `users.has_completed_onboarding = true` AND (any non-deleted project OR any non-deleted client)? | **No** → "the move that gets OPS working" | **Yes** → "you're moving" |
| Day 4 | Any `notifications` row for this user where `type='task_completed'`? | **No** → "the notification you're working toward" (with mocked push card) | **Yes** → "you've heard the ping" |
| Day 14 | Any `projects.updated_at`, `project_tasks.updated_at`, `clients.updated_at`, `opportunities.updated_at`, `estimates.updated_at`, or `invoices.updated_at` for this company within the last 7 days? | **Quiet** → "is OPS slotting in or in the way?" | **Active** → "you're 14 days in" (with live stats, gated by threshold — see below) |

**Why these specific signals**:
- Day 1's "real project with client/address or tasks" v1 check is replaced by "completed onboarding AND has projects-or-clients" — directly matches `!hasProjects && !hasClients` from `lifecycle-emails` line ~340 and `lifecycle-onboarding-complete` lines 42-49
- Day 4's `notifications` table check is the real signal that a task_completed event actually surfaced to the admin (the v1 check "ever received a task_completed notification" was already correct; this just nails down the exact query)
- Day 14's expanded activity signal addresses the reviewer's flag that v1 missed meaningful activation events. Uses `updated_at` across six tables, mirroring how `lifecycle-cron` aggregates project + task `updated_at` for inactivity detection.

**Day 14 Active stats threshold** (fixes the "tiny stats feel surveillance-y" concern):
- If `projectCount + taskCount + notificationCount >= 5` → render the Active branch with live stats
- If sum < 5 → downgrade to Active-without-stats variant: "Day 14. You're moving in OPS. Jack wants to know what's working and what's broken..." — same body, no numbers

### Kill switches (skip drip entirely for this recipient on this day)

Evaluated by the cron before computing state:

1. **Company `deleted_at` is set** → skip silently
2. **Company `subscription_status` ∈ {`cancelled`, `expired`, `paused`}** → skip silently. Resubscribers do not retroactively receive missed drip emails.
3. **Company `subscription_status` = `active` (paid early)** → still fire all drip emails. The check-in and feature beats are still useful post-paid. v2 may add a "welcome to paid" variant.
4. **Admin user list empty or all admin emails NULL/deleted** → skip silently, log warning
5. **All admin emails on `email_suppressions.list='global'`** → handled automatically by `gatedSend`

---

## 6. Email copy (canonical)

All copy below is canonical and was vetted line-by-line against:
- The OPS copywriter brand voice (60% Jocko / 20% Springsteen / 20% Musk)
- The banned-word list (`contractor` as label, `AI` as bare claim, plus AI-tell vocabulary: `delve`, `tapestry`, `landscape` metaphor, `seamless`, `robust`, `streamline`, `leverage`, `elevate`, `embark`, `navigate` metaphor, `cutting-edge`, `revolutionary`, `game-changer`, `multifaceted`, `testament`, `treasure trove`, `realm of`, `unlocks`, `comes alive`)
- The AI-generated-tell phrase list ("In today's...", "It's important to note", "In summary / In essence", "It's not about X, it's about Y")

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

OPS LTD. · 1515 Douglas St, Victoria, BC V8W 2G4 · {{unsubscribeUrl}}
```

If `{{firstName}}` is null/empty, opener degrades to `Hey there,`.

### Day 1 Branch A — Onboarding incomplete OR no project/client

**From**: `OPS Dispatch <dispatch@opsapp.co>` · **Reply-To**: `jack@opsapp.co`
**Subject**: `the move that gets OPS working`
**Body** (OPS tactical HTML template):

```
Day 1. You signed up yesterday.

The move that puts the rest of the system to work: drop your
first project in. Real client, real address, real tasks.

Without a project, OPS has nothing to work from. Once a
project's in, the schedule, the crew, the photos, the
estimates, the invoices all hang off it.

Use a job you're actually running this week. Takes two minutes.

[ DROP YOUR FIRST PROJECT ]

OPS LTD. · 1515 Douglas St, Victoria, BC V8W 2G4 · {{unsubscribeUrl}}
```

CTA URL: `${NEXT_PUBLIC_APP_URL}/projects/new`

**Copy edits from v1** (per reviewer):
- "unlocks the rest" → "puts the rest of the system to work" (drops the startup verb)
- "the system starts coming alive" → "OPS has nothing to work from / Once a project's in..." (concrete, no metaphor)

### Day 1 Branch B — Onboarded with project or client

**From**: `OPS Dispatch <dispatch@opsapp.co>` · **Reply-To**: `jack@opsapp.co`
**Subject**: `you're moving`
**Body**:

```
Day 1. {{projectCountLine}}

That's the spine. The next move puts OPS to work for you:
tasks on those projects, and at least one crew member with
the mobile app installed.

When a team member taps DONE in the field, a notification
lands on your phone. From a job you weren't on. On a task
you didn't have to chase.

[ ASSIGN A TASK + INVITE A CREW MEMBER ]

OPS LTD. · 1515 Douglas St, Victoria, BC V8W 2G4 · {{unsubscribeUrl}}
```

`{{projectCountLine}}` renders as:
- `count === 1` → `You've already got your first project in.`
- `count > 1` → `You've got {{count}} projects in.`

CTA URL: `${NEXT_PUBLIC_APP_URL}/dashboard`

**Copy edit from v1** (per reviewer): removed the duplicate "from a job you weren't on, on a task you didn't have to chase" — preserved on Day 4A where it's the load-bearing emotional beat. Day 1B now uses a shorter foreshadowing version.

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

One inbox. Lead emails, supplier emails, sub-trade emails,
accounting questions, customer photos — all of it landing
in the same spot at the same time. No office. Nobody
triaging anything. Nobody nudging me when I'd missed
replying to a lead from three days back.

And I had no idea if my ads were working. I'd spend money
on Google and Facebook and Yelp, and at the end of the
month I couldn't tell you which inquiries had turned into
jobs, or what those jobs were actually worth.

Data is power.

That's the part of OPS I'm most proud of.

You connect your work inbox. OPS reads your inbox and
separates the leads from the noise — the customer asking
for a quote on a new install lands in your pipeline, tagged,
with the address pulled out and the scope extracted. The
supplier confirming an order goes somewhere else.

Then OPS tracks every lead from "first email" to "job won"
to "invoice paid." You see what your cost per won job is,
by source. You see which ads are paying back. You make
decisions on numbers instead of gut.

Connecting your inbox takes about two minutes. Hit reply
if you want to tell me what your inbox chaos looks like
right now — I read every reply.

— Jack

OPS LTD. · 1515 Douglas St, Victoria, BC V8W 2G4 · {{unsubscribeUrl}}
```

**Copy edits from v1** (per reviewer):
- "I was flying blind" → cut (reduces sentence-length uniformity, lets "Data is power." stand alone)
- "I didn't have any." → cut (slogan-y in reviewer's read; "Data is power." stands on its own)
- "sub emails" → "sub-trade emails" (clarifies — subcontractor, not "sub" anything)
- "OPS reads everything" → "OPS reads your inbox" (bounded, less surveillance-feeling)
- "scope guessed at" → "scope extracted" (precise verb, doesn't undermine trust)
- The "intelligent classification" paragraph → cut entirely. The behavior is described in plain language; naming the mechanism was a forced compliance maneuver. The forward-looking AI line moved to a separate spot or cut. (Per the founder's brand rule, "AI is positioned as forward-looking only" — and Day 3 isn't a roadmap email. Save the approved line for surfaces where it earns its place.)

### Day 4 Branch A — No completion notification yet

**From**: `OPS Dispatch <dispatch@opsapp.co>` · **Reply-To**: `jack@opsapp.co`
**Subject**: `the notification you're working toward`
**Body** (OPS HTML template with custom iOS push notification card matching real `dispatchTaskCompleted` format):

```
Day 4.

Here's the moment you're working toward:

[ Mocked iOS push card, styled in TSX: ]
┌─────────────────────────────────────────────┐
│ OPS                              now        │
│                                             │
│ Task Completed                              │
│ Jake completed "Rail Install" on 5611       │
│ Batu Rd                                     │
└─────────────────────────────────────────────┘

That notification lands on your phone the first time someone
on your crew taps DONE in the field. From a job you weren't
on. On a task you didn't have to chase.

To get there:
  1. Invite at least one crew member
  2. Get them logged into the OPS mobile app
  3. Assign them a task

[ INVITE YOUR CREW ]

The first time you hear that ping while you're somewhere
else, you'll know why we built this.

OPS LTD. · 1515 Douglas St, Victoria, BC V8W 2G4 · {{unsubscribeUrl}}
```

**Push notification format**: matches `notification-dispatch.ts:200-201` exactly. Title is `Task Completed`. Body is `${completedByName} completed "${taskTitle}" on ${projectTitle}`. The TSX mock uses these strings verbatim with placeholder values that look credible (`Jake` / `Rail Install` / `5611 Batu Rd`).

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
  → Adding more crew, so the same setup covers more work
  → Templates so you don't rebuild the same tasks every time

[ SET UP RECURRING JOBS ]

You're past the first hill. The next 26 days is about
putting the rest of your business in.

OPS LTD. · 1515 Douglas St, Victoria, BC V8W 2G4 · {{unsubscribeUrl}}
```

**Copy edit from v1** (per reviewer): "the leverage scales" → "adding more crew, so the same setup covers more work" (concrete, no banned word).

CTA URL: `${NEXT_PUBLIC_APP_URL}/projects?filter=recurring`

### Day 8 — Estimates + portal (Jack)

**From**: `Jack Sweet <jack@opsapp.co>` · **Reply-To**: `jack@opsapp.co`
**Subject**: `how your customers see your estimates`
**Body** (plain text):

```
Hey there {{firstName}},

Jack again, last one of these you'll get from me for a while.

A deck builder I know ran his estimates out of a Word doc
template. Every new customer, he'd open the last one he sent,
save-as, update the fields. Or try to.

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
anything. You can't forget to update a field that doesn't
exist.

If you want to see what your customers see, send a test
estimate to your own email. Takes about three minutes from
inside OPS.

— Jack

OPS LTD. · 1515 Douglas St, Victoria, BC V8W 2G4 · {{unsubscribeUrl}}
```

**Copy edits from v1** (per reviewer):
- "I want to tell you a story about a deck builder I know" → cut. Just start with the story.
- "You can imagine how that went over." — kept verbatim. Reviewer called this filler; in fact this is the founder's actual voice (he wrote this line himself). Push back accepted in spec.

### Day 14 Branch A — Quiet (from Jack)

**From**: `Jack Sweet <jack@opsapp.co>` · **Reply-To**: `jack@opsapp.co`
**Subject**: `is OPS slotting in or in the way?`
**Body** (plain text):

```
Hey there {{firstName}},

Jack here.

Day 14. You're halfway through your trial and it's been
quiet on your account.

Could be a lot of things — you've been busy on actual work,
something tripped you up during setup, OPS didn't fit how
you run things, the timing's wrong, you forgot about it.
No judgment either way.

But I want to know which one it is. Hit reply on this email
— goes to my inbox. One sentence is enough.

If something specifically didn't work, tell me. If you
forgot about it, tell me that too. The product gets better
when operators tell me what's grinding their gears.

— Jack

OPS LTD. · 1515 Douglas St, Victoria, BC V8W 2G4 · {{unsubscribeUrl}}
```

**Changes from v1**:
- Sender: Dispatch → Jack (per reviewer's logic: if the reply lands at Jack, the From should be Jack)
- "Jack wants to know" → "I want to know" (first person, no longer awkward third-person framing)
- No CTA button — the action is the reply

### Day 14 Branch B — Active (from Jack)

**From**: `Jack Sweet <jack@opsapp.co>` · **Reply-To**: `jack@opsapp.co`
**Subject**: `you're 14 days in`
**Body — when `projectCount + taskCount + notificationCount >= 5`** (plain text):

```
Hey there {{firstName}},

Jack here.

Day 14. You're running OPS — {{projectCount}} projects,
{{taskCount}} tasks assigned, {{notificationCount}}
completion notifications that have landed on your phone.

I want to know two things:

  1. What's working that you didn't expect?
  2. What's broken, missing, or in the way?

Hit reply — goes to my inbox. One sentence per question
is enough.

The product gets better when operators tell me what's
grinding their gears.

— Jack

OPS LTD. · 1515 Douglas St, Victoria, BC V8W 2G4 · {{unsubscribeUrl}}
```

**Body — when `projectCount + taskCount + notificationCount < 5`** (suppresses tiny stats):

```
Hey there {{firstName}},

Jack here.

Day 14. You're moving in OPS.

I want to know two things:

  1. What's working that you didn't expect?
  2. What's broken, missing, or in the way?

Hit reply — goes to my inbox. One sentence per question
is enough.

The product gets better when operators tell me what's
grinding their gears.

— Jack

OPS LTD. · 1515 Douglas St, Victoria, BC V8W 2G4 · {{unsubscribeUrl}}
```

**Changes from v1**: same sender + framing changes as 14A. Stats threshold added so tiny numbers don't read as surveillance.

---

## 7. Behavior-triggered re-engagement send

Fires from the same hourly cron, evaluated per company after the calendar-driven checks.

### Conditions to fire

ALL of the following must hold:

1. Company `created_at` is between 1 and 14 days ago (the drip window)
2. **Zero activity in the last 6+ consecutive calendar days** — no `updated_at` newer than `now() - interval '6 days'` across `projects`, `project_tasks`, `clients`, `opportunities`, `estimates`, `invoices` for this company
3. The "Lost you?" email has NOT already been sent (`onboarding_email_log` has no row with `day_slot='lost_you'` for any admin of this company)
4. Day 14 has not yet fired
5. Standard kill switches from §5 do not apply

**Threshold raised from v1's 4 days to 6 days** (per reviewer): trades operators take weekends + weather days + job pushes. 4 calendar days false-triggers across a long weekend with rain. 6 days covers a long weekend plus a few work days quiet.

### Email copy

**From**: `Jack Sweet <jack@opsapp.co>` · **Reply-To**: `jack@opsapp.co`
**Subject**: `lost you?`
**Send time**: 10am operator local (later than morning sends, lower-urgency)
**Body** (plain text):

```
Hey {{firstName}},

Jack here.

You signed up for OPS {{daysSinceSignup}} days ago and
haven't been back in {{daysSinceLastActivity}}.

That's a long enough gap that I want to ask straight: is
something stopping you, or is the timing just wrong?

If setup tripped you up, I can usually point you at the
move that gets you unstuck. If OPS isn't the right fit, no
hard feelings — I'd just want to know what you were looking
for.

Hit reply with one sentence. Goes to my inbox.

— Jack

OPS LTD. · 1515 Douglas St, Victoria, BC V8W 2G4 · {{unsubscribeUrl}}
```

**Copy rewrite from v1** (per reviewer): dropped "Noticed..." and "That's a real signal" CRM-flavored phrases. Opens with specific days, lays out the binary (stopped vs timing), offers help, asks for the reply.

`{{daysSinceLastActivity}}` formatting:
- `1` → `"a day"`
- `n > 1` → `"${n} days"`

---

## 8. Data model changes

### New table — `onboarding_email_log`

Migration filename: `108_onboarding_email_log.sql` (next sequential slot — verify before applying).

```sql
DO $$ BEGIN
  CREATE TYPE onboarding_email_status AS ENUM (
    'pending', 'sent', 'failed', 'skipped'
  );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE TABLE IF NOT EXISTS public.onboarding_email_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  day_slot text NOT NULL CHECK (day_slot IN (
    'day_0', 'day_1', 'day_3', 'day_4', 'day_8', 'day_14', 'lost_you'
  )),
  branch text NULL,
  status onboarding_email_status NOT NULL DEFAULT 'pending',
  attempts int NOT NULL DEFAULT 0,
  last_error text NULL,
  sent_at timestamptz NULL,
  email_log_id uuid REFERENCES public.email_log(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT onboarding_email_log_unique UNIQUE (user_id, day_slot)
);

CREATE INDEX IF NOT EXISTS idx_onboarding_email_log_company
  ON public.onboarding_email_log (company_id);
CREATE INDEX IF NOT EXISTS idx_onboarding_email_log_sent_at
  ON public.onboarding_email_log (sent_at DESC);
CREATE INDEX IF NOT EXISTS idx_onboarding_email_log_pending_retry
  ON public.onboarding_email_log (status, attempts, created_at)
  WHERE status IN ('pending', 'failed');

DROP TRIGGER IF EXISTS trg_onboarding_email_log_updated_at ON public.onboarding_email_log;
CREATE TRIGGER trg_onboarding_email_log_updated_at
  BEFORE UPDATE ON public.onboarding_email_log
  FOR EACH ROW EXECUTE FUNCTION public.fn_email_campaigns_set_updated_at();

COMMENT ON TABLE public.onboarding_email_log IS
  'Dedup + state table for the onboarding drip cron. UNIQUE (user_id, day_slot) enforces one email per user per day-slot regardless of branch. Claim-before-send pattern: INSERT pending ON CONFLICT DO NOTHING RETURNING id — only the winner sends.';

COMMENT ON COLUMN public.onboarding_email_log.branch IS
  'Which branch variant was sent. NULL for unbranched (day_0, day_3, day_8, lost_you). For branched days: no_project / has_project / no_aha / has_aha / quiet / active.';

COMMENT ON COLUMN public.onboarding_email_log.status IS
  'pending: claim succeeded, send not yet attempted. sent: gatedSend returned status=sent. failed: send attempted and errored; retried if attempts < 3. skipped: send returned suppression_skipped or paused_skipped (terminal).';
```

**Changes from v1**:
- `kind` column replaced with `day_slot` (without branch suffix) + separate `branch` column. The UNIQUE on `(user_id, day_slot)` is what makes the claim-before-send dedup correct.
- Added `status` ENUM (was: text status implied via presence of row)
- Added `attempts` for retry tracking
- Added `last_error` for debugging
- Added the `updated_at` trigger
- Added partial index on `(status, attempts, created_at) WHERE status IN ('pending', 'failed')` to make the retry sweep cheap

### Additions to existing tables / config

| File | Change |
|---|---|
| `OPS-Web/src/lib/email/constants.ts` | Add 10 new entries to `KIND_TO_LIST` — one per typed sender (branch-specific so analytics can distinguish e.g. Day 1A from Day 1B open rates), all mapped to `'global'` list. Keys: `onboarding_day_0_welcome`, `onboarding_day_1_no_project`, `onboarding_day_1_has_project`, `onboarding_day_3_inbox`, `onboarding_day_4_no_notification`, `onboarding_day_4_has_notification`, `onboarding_day_8_estimates`, `onboarding_day_14_quiet`, `onboarding_day_14_active`, `onboarding_lost_you` |
| `OPS-Web/src/lib/email/template-registry.ts` | Add 10 new entries (one per distinct template: Day 0 + Day 1A + Day 1B + Day 3 + Day 4A + Day 4B + Day 8 + Day 14A + Day 14B + LostYou) |
| `OPS-Web/src/lib/email/pause.ts` `resolveEmailBucket()` | Add 10 case statements mapping the new kinds — all to `'dispatch'` (Jack rides the same bucket-level pause as Dispatch since `jack@opsapp.co` is operationally part of the dispatch sender bucket) |
| `OPS-Web/src/lib/email/senders.ts` | Add `JACK` sender identity constant (see §4) |
| `OPS-Web/vercel.json` | Add cron entry `{"path": "/api/cron/onboarding-drip", "schedule": "0 * * * *"}` (hourly, replacing the v1 daily 14:00 UTC) |

### No schema changes to existing tables

- `companies` — unchanged
- `users` — unchanged
- `notifications` — unchanged (query only)
- `email_log` — unchanged (writes happen via `gatedSend`)

---

## 9. Cron schedule additions

One new entry in `OPS-Web/vercel.json` `crons` array:

```json
{
  "path": "/api/cron/onboarding-drip",
  "schedule": "0 * * * *"
}
```

`0 * * * *` = every hour at minute 0, UTC. The cron handler gates each candidate company on `localHour === 9` so the actual send window is one hour per day per operator (their local 9am).

Hourly fire vs daily-with-timezone-math (v1): hourly is simpler, handles DST transitions naturally, and survives a single missed cron run with at most 1-hour delay vs 24-hour delay.

**Vercel Hobby plan cron limit**: hourly crons count as 24 invocations/day. Existing email-related crons already total >40/day. Verify Vercel plan tier supports the additional load before implementing — if on Hobby with strict limits, consider every-2-hours `0 */2 * * *` instead (worst case = operator gets the email 9 or 10am local).

---

## 10. Implementation plumbing

### New files

| Path | Purpose |
|---|---|
| `OPS-Web/src/lib/email/react/templates/onboarding/Day0Welcome.tsx` | Plain-text template, no glass card |
| `OPS-Web/src/lib/email/react/templates/onboarding/Day1NoProject.tsx` | OPS HTML, glass card |
| `OPS-Web/src/lib/email/react/templates/onboarding/Day1HasProject.tsx` | OPS HTML |
| `OPS-Web/src/lib/email/react/templates/onboarding/Day3Inbox.tsx` | Plain-text |
| `OPS-Web/src/lib/email/react/templates/onboarding/Day4NoNotification.tsx` | OPS HTML + custom iOS push notification mockup |
| `OPS-Web/src/lib/email/react/templates/onboarding/Day4HasNotification.tsx` | OPS HTML |
| `OPS-Web/src/lib/email/react/templates/onboarding/Day8Estimates.tsx` | Plain-text |
| `OPS-Web/src/lib/email/react/templates/onboarding/Day14Quiet.tsx` | Plain-text |
| `OPS-Web/src/lib/email/react/templates/onboarding/Day14Active.tsx` | Plain-text with conditional stats block |
| `OPS-Web/src/lib/email/react/templates/onboarding/LostYou.tsx` | Plain-text |
| `OPS-Web/src/lib/email/react/primitives/MockPushNotification.tsx` | Reusable iOS-push-notification visual component for Day 4A. Renders an iOS-style notification card with title + body lines, matching the visual shape of a real push notification on lock screen. **Design note**: deliberately stylized (not pixel-perfect iOS chrome) so we never look like we're impersonating Apple's UI. The shape should be recognizably "a push notification" without copying Apple specifics. |
| `OPS-Web/src/lib/email/react/primitives/PlainTextLayout.tsx` | Layout primitive for founder emails (Days 0, 3, 8, 14A, 14B, LostYou). Renders body + signature + the single-line compliance footer. No glass card, no logo, no `// OPERATOR ::` chrome. |
| `OPS-Web/src/lib/email/react/primitives/FounderFooter.tsx` | The single-line compliance footer used by founder emails. Renders `OPS LTD. · 1515 Douglas St, Victoria, BC V8W 2G4 · Unsubscribe` in small grey text. Distinct from the existing `ComplianceFooter` which is taller and richer for Dispatch emails. |
| `OPS-Web/src/lib/api/services/onboarding-drip-service.ts` | Service mirroring `TrialExpiryService` shape. Methods: `processAll(supabase, now)`, `processCompany(supabase, company, now, result)`, `computeState(supabase, company, daySlot)`, `claimAndSend(supabase, user, company, daySlot, branch)` |
| `OPS-Web/src/app/api/cron/onboarding-drip/route.ts` | Cron route, auth via `Bearer ${CRON_SECRET}`, calls `OnboardingDripService.processAll()` |
| `OPS-Web/supabase/migrations/108_onboarding_email_log.sql` | Dedup + state table (see §8) |

### Modified files

| Path | Change |
|---|---|
| `OPS-Web/src/lib/email/sendgrid.tsx` | Add 10 typed senders: `sendOnboardingDay0Welcome`, `sendOnboardingDay1NoProject`, `sendOnboardingDay1HasProject`, `sendOnboardingDay3Inbox`, `sendOnboardingDay4NoNotification`, `sendOnboardingDay4HasNotification`, `sendOnboardingDay8Estimates`, `sendOnboardingDay14Quiet`, `sendOnboardingDay14Active`, `sendOnboardingLostYou`. All Jack-from-address sends pass `from: JACK` and `replyTo: 'jack@opsapp.co'`. All Dispatch sends pass `from: DISPATCH`, `replyTo: 'jack@opsapp.co'`. |
| `OPS-Web/src/lib/email/senders.ts` | Add `JACK` constant per §4 |
| `OPS-Web/src/lib/email/constants.ts` | Add 10 entries to `KIND_TO_LIST` per §8 (one per typed sender) |
| `OPS-Web/src/lib/email/template-registry.ts` | Add 10 entries |
| `OPS-Web/src/lib/email/pause.ts` | `resolveEmailBucket()` switch: all 10 onboarding kinds → `'dispatch'` |
| `OPS-Web/src/app/api/setup/progress/route.ts` | After the verified `companies` INSERT at line 122, insert pending row in `onboarding_email_log` and dispatch Day 0 async (non-awaited Promise). Failure of the Day 0 send logs but does not roll back the signup. |
| `OPS-Web/vercel.json` | Add hourly cron entry |
| `OPS-Web/supabase/migrations/065_company_trial_init_trigger.sql` | **NOT modified** — trial trigger continues to handle trial-window stamping only. Day 0 enqueue is application code, not Postgres trigger. |

---

## 11. Testing approach

### Unit tests

- `OPS-Web/tests/unit/api/services/onboarding-drip-service.test.ts`
  - `computeState()` returns the correct branch for each day_slot given fixture company state
  - `processCompany()` skips on each kill condition (deleted, cancelled, expired, no admins, all-suppressed, internal-domain)
  - `claimAndSend()` writes the correct `onboarding_email_log` row on success
  - Claim-before-send race: two concurrent invocations for the same `(user_id, day_slot)` — only one INSERT succeeds, only one send fires
  - Retry: a 'failed' row with attempts < 3 is picked up on the next sweep; with attempts = 3, it's not
  - Day 14 stats threshold: under 5, returns the no-stats variant
  - Lost You: only fires when all 5 conditions hold; doesn't fire if Day 14 already sent

- `OPS-Web/tests/unit/email/templates/onboarding/*.test.tsx`
  - Each template renders with `previewProps` without error
  - Plural handling on Day 1B and Day 14B (0, 1, many)
  - `{{firstName}}` null fallback on Day 0 / Day 3 / Day 8 / Day 14 / LostYou
  - `FounderFooter` always renders (no path lets it be omitted)
  - `MockPushNotification` renders the `Task Completed` title + body shape

### Integration tests

- `OPS-Web/tests/integration/onboarding-drip-cron.test.ts`
  - End-to-end cron run: seed N companies at various ages + timezones, invoke the route handler, assert correct sends + dedup rows
  - Verify timezone gating: operator at `localHour=9` gets sent, operator at `localHour=10` does not (this cron tick)
  - Verify activity-detection logic for Day 14 branching + `lost_you` trigger using real updated_at timestamps
  - Verify Day 0 retry: simulate SendGrid failure on first attempt, verify the cron picks it up on next tick

- `OPS-Web/tests/integration/onboarding-drip-day0-realtime.test.ts`
  - POST to `/api/setup/progress` triggers Day 0 enqueue + async dispatch
  - Failure of Day 0 send does not roll back the signup response

### Manual / staging

- Each typed sender has an admin send-test invocation point — operator sends each template to themselves before launch
- Day 0 real-time trigger: create a test signup in staging, verify email lands within 30 seconds
- Cron: invoke `/api/cron/onboarding-drip` manually with `Authorization: Bearer ${CRON_SECRET}` against staging
- Cutover dry-run: confirm `lifecycle_email_config` rows still all `enabled=false` immediately before launch

---

## 12. Compliance + brand discipline

### Compliance

- Every send routes through `gatedSend` → automatic RFC 8058 `List-Unsubscribe` SMTP header
- **Visible single-line footer on every email** including founder plain-text emails (changed from v1; reviewer correctly flagged that the transactional/relationship exemption defense was optimistic for emails that promote product usage — Days 3, 8, 14, Re-engagement all do)
- Footer format: `OPS LTD. · 1515 Douglas St, Victoria, BC V8W 2G4 · Unsubscribe` (link uses RFC 8058 HMAC token)
- All 10 send kinds on `'global'` suppression list — opt-out of one means opt-out of all OPS email (consistent with the policy on auth, billing, portal, trial-expiry kinds)
- Reply-to is always `jack@opsapp.co` — operators replying to any drip email reach Jack directly

### Brand discipline (per founder memory files and chapter 14)

All copy in this spec was vetted line-by-line against the banned lists:

- **"Contractor" as audience label** — banned. Approved alternatives used: deck and rail crew, deck builder, crew, operators, businesses, owner-operators, sub-trades, trades. Verified zero "contractor" instances across all 10 emails.
- **"AI" as bare claim** — banned. The v1 spec used the approved forward-looking line ("We're working on supercharging your workflows with AI.") in Day 3, but the reviewer flagged that placing it after "intelligent classification" muddied current vs. roadmap. Resolution: Day 3 no longer names a mechanism at all — describes the behavior in plain language. The forward-looking line is reserved for surfaces where it earns its placement (e.g. a roadmap email, an in-product banner, an ad).
- **AI-tell vocabulary** — banned across all copy: `delve`, `tapestry`, `landscape` (metaphor), `seamless`, `robust`, `streamline`, `leverage`, `elevate`, `embark`, `navigate` (metaphor), `cutting-edge`, `revolutionary`, `game-changer`, `multifaceted`, `testament`, `treasure trove`, `realm of`, `unlocks`, `comes alive`. **All v1 violations resolved** (specifically: "the leverage scales" on Day 4B, "unlocks the rest" on Day 1A, "the system starts coming alive" on Day 1A).
- **AI-tell phrases** — banned: "In today's...", "It's important to note", "In summary / In essence", "It's not about X, it's about Y".

Any future copy edit to this spec or the implementing templates MUST pass the same vetting. The `ops-copywriter` skill enforces this on net-new copy.

---

## 13. Bible updates required

After implementation lands, the following bible updates ship in the same session:

1. **`13_EMAIL_SYSTEM.md`** — Add new section "Onboarding Drip" between § Trial-Expiry Lifecycle and § Deliverability Anomaly Detector:
   - 10 send kinds + the day_slot/branch model
   - Trigger architecture (real-time Day 0 + hourly cron)
   - Dedup model (claim-before-send)
   - Branch logic and kill switches
   - Alternating Jack/Dispatch sender pattern
   - `onboarding_email_log` table
   - Update § Cron Schedule table to include the new cron
   - Update § Email Kinds Catalog table to include the new kinds
   - Update § Sender Identities to add JACK
   - Update § Known Gaps:
     - Remove gap #1 ("No welcome email on signup") — resolved
     - Remove gap #8 ("No mid-trial engagement drip") — resolved
     - Gap #2 ("No internal new-signup alert") — partially addressed by Day 0 reply-to-Jack creating organic inbound visibility, but NOT closed; leave the gap open until a dedicated Slack/email alert ships

2. **`03_DATA_ARCHITECTURE.md`** — Add `onboarding_email_log` to the outbound email tables cross-reference

3. **`14_FEATURE_POSITIONING.md`** — No changes required

4. **README.md** — No new chapter; existing chapter 13 update covers it

---

## 14. Migration & cutover plan

### What's being replaced

| Component | Disposition |
|---|---|
| `lifecycle-emails` edge function (v11) | Disable in Supabase Dashboard. Keep code in Supabase Functions for 30 days for rollback, then delete. |
| `lifecycle-cron` edge function (v5) | Disable. Keep for 30 days, then delete. |
| `lifecycle-onboarding-complete` edge function (v5) | Disable. Keep for 30 days, then delete. |
| `lifecycle-first-action` edge function (v5) | Disable. Keep for 30 days, then delete. |
| `lifecycle_email_config` table | All 11 rows currently `enabled=false`. Leave the table in place for 30 days post-cutover for rollback. Drop the table in a follow-up migration after the 30-day window. |
| SendGrid Marketing Lists (`SENDGRID_LIST_*`) | **Confirmed dormant by founder on 2026-05-27** — no live Automations attached. Operator should delete the lists from the SendGrid dashboard during cutover. |
| `lifecycle-emails` allowlist entry in `/api/admin/email/trigger/route.ts` | Remove from `ALLOWED_SLUGS` post-cutover so the admin UI can no longer manually invoke the dormant function |

### Cutover sequence

Single-session cutover on launch day:

1. **Pre-launch verification** (T-1 hour):
   - Re-run the dormancy verification SQL: `SELECT email_type_key, enabled FROM lifecycle_email_config` — confirm all 11 still disabled
   - Confirm no rows added to `email_log` for any of the 11 `email_type` values in the last 24 hours
   - Confirm founder hasn't re-attached SendGrid Automations
2. **Deploy the new system** (T+0):
   - Apply migration `108_onboarding_email_log.sql`
   - Deploy OPS-Web with the new templates, service, cron route, and the `setup/progress` hook
   - Verify `vercel.json` cron is registered post-deploy
3. **Disable the old system** (T+30 min, after smoke test passes):
   - Supabase Dashboard → Edge Functions → set status `INACTIVE` on all 4 lifecycle functions
   - Operator deletes the SendGrid Marketing Lists from the SendGrid dashboard
4. **First-hour observation** (T+1 hour):
   - Tail `email_log` for any onboarding_* sends — confirm shape matches expectations
   - Tail `onboarding_email_log` for new rows
   - Confirm no errors in `/api/cron/onboarding-drip` route
5. **24-hour observation**:
   - Confirm Day 0 send rate matches new signup rate
   - Confirm Day 1 cron tick fires and produces correct branch decisions
   - Spot-check the rendered HTML in inbox previews (Gmail web + iOS Mail)
6. **30-day cleanup** (separate session):
   - Drop `lifecycle_email_config` table via migration
   - Delete the 4 edge function definitions
   - Remove the 5 lifecycle-related slugs from `/api/admin/email/trigger/route.ts` ALLOWED_SLUGS

### Rollback plan

If the new system misbehaves in the first 24 hours:
1. Disable the new cron in `vercel.json` (one-line revert + redeploy)
2. Re-enable the 4 edge functions in Supabase (single click each)
3. Operator could re-enable selected `lifecycle_email_config` rows if needed — but since the existing system was never live, "rollback" really means "back to nothing sent," which matches the pre-launch baseline

The new system can be disabled without data loss — `onboarding_email_log` rows remain for forensics.

---

## 15. Open questions and known gaps

### Resolved during the v2 revision (no longer open)

- ✅ Day 0 retry semantics — durable pending row + cron retry up to 3 attempts
- ✅ Activity definition — multi-table `updated_at` max across projects, project_tasks, clients, opportunities, estimates, invoices
- ✅ Push notification mockup — matches real `dispatchTaskCompleted` format; deliberately stylized to avoid Apple impersonation
- ✅ Day 14 sender — Jack (changed from Dispatch)
- ✅ Branch conditions — adopted precise conditions from dormant edge function

### Still open

1. **Vercel cron plan limit** — confirm Vercel plan tier supports the additional hourly cron. If on Hobby with strict limits, fall back to `0 */2 * * *` (every 2 hours).
2. **`MockPushNotification` exact visual** — stylized vs. iOS-faithful is a real design decision. Default: stylized. Confirm during template implementation.
3. **30-day cleanup of `lifecycle_email_config` table** — scheduled as a separate follow-up migration. Should not block initial launch.

### Known gaps (deferred to v2 of the drip itself)

1. **"Welcome to paid" variant** when operator pays before Day 14 — out of scope for this v1
2. **Subject A/B test infrastructure** — no infrastructure built. Fixed subjects per §6. If open rates underperform, A/B requires a new column + RNG split.
3. **Instant aha congrats** — Day 4B currently fires on calendar (Day 4), not in real time on the actual first `task_completed` notification. Real-time send is a follow-up.
4. **Localized copy** — English-only at launch. Spanish translation is a follow-up.
5. **Internal "new signup" alert** — Day 0 reply-to-Jack provides organic signal but doesn't catch silent signups. Separate feature, not in this spec. Bible gap #2 stays open.

---

## 16. Decision log

Decisions captured during brainstorming + v2 revision (with the founder), in chronological order:

| # | Decision | Why |
|---|---|---|
| 1 | Reply commitment: "I read every reply" verbatim | Founder confirmed personal reply commitment at any expected volume |
| 2 | Drip length: 6 calendar emails (revised from initial 4) | Founder wanted feature beats interleaved; settled on 6 scheduled + 1 behavior-triggered |
| 3 | Aha moment: completion notification from the field | Founder identified — "Jake completed 5611 Batu Rd Rail Install" is the leverage moment |
| 4 | Branched content (not skip-based) | Founder suggested branching on user state; more impactful than skipping |
| 5 | Trigger on company creation (not Firebase signup) | Distinguishes new operators from invited team members |
| 6 | Day 0 plain text from `jack@opsapp.co` | Must look like real personal email; styled template breaks the spell |
| 7 | All 10 kinds on `'global'` suppression list | Founder-drip unsubscribe = full opt-out signal |
| 8 | Three research-driven tunings: instant Day 0, local-time sends, behavior-triggered re-engagement | Research showed clear lift |
| 9 | Feature emails (Day 3, Day 8) shifted from Dispatch to Jack personal voice | Personal beats Dispatch for feature explanations |
| 10 | Day 3 reframed from "missed an email at work" to "drowning in single inbox + no measurement" | Founder corrected — owner-operator pain is wearing too many hats, not being busy |
| 11 | Day 8 story: deck builder + 20%-mid-job disaster | Founder provided real story; earns the length |
| 12 | "Contractor" as audience label banned; "AI" as bare claim banned | Founder corrections to chapter 14; applied across all drip copy |
| 13 | No first-name attribution for the deck builder on Day 8 | Privacy + the anonymous version reads stronger |
| 14 | Hardcode copy in templates (not features catalog table) for v1 | Refactor path noted if scope grows |
| 15 | Onboarding drip uses transactional sends, NOT the campaign engine | Better matches per-recipient calendar pattern; mirrors `TrialExpiryService` |
| **16** | **Day 14 sender changed from Dispatch to Jack** (v2) | Reviewer flagged: if reply lands at Jack, From should be Jack. Reframed copy from "Jack wants to know" to "I want to know." |
| **17** | **Replace dormant edge functions instead of building parallel** (v2) | Discovery: `lifecycle-emails` + 3 others exist but never sent in production. Migration framing avoids double-send risk that would have existed if both ran. |
| **18** | **Hourly cron with localHour=9 gate** (v2) | Reviewer flagged: daily 14:00 UTC can't deliver 8-10am local for all timezones. Hourly fires once per operator per day at their local 9am. |
| **19** | **Claim-before-send dedup with `day_slot` (not `kind`) unique key** (v2) | Reviewer flagged race condition where Day 1A and Day 1B could both fire if state flipped between cron ticks. Single unique key per day prevents this. |
| **20** | **Visible compliance footer on every email** (v2) | Reviewer flagged: transactional/relationship exemption doesn't cover product-promoting emails. Single-line grey footer satisfies CAN-SPAM, CASL, PECR, Google Sender Guidelines. |
| **21** | **Mock push notification format matches real `dispatchTaskCompleted`** (v2) | Reviewer flagged: mock invented a format the product can't deliver. Now uses `Task Completed / Jake completed "Rail Install" on 5611 Batu Rd` exactly. |
| **22** | **Lost You threshold raised from 4 to 6 days** (v2) | Reviewer flagged: trades operators take weekends, weather days, job pushes. 4 days false-triggers across a long weekend. |
| **23** | **Day 14 Active stats threshold (>=5)** (v2) | Reviewer flagged: tiny stats (1 project, 2 tasks) feel surveillance-y. Threshold downgrades to no-stats variant when activity is low. |
| **24** | **Jack as documented sender identity** (v2) | Reviewer flagged: founder emails were using `jack@opsapp.co` ad hoc, not as a documented bucket. Added `JACK` to `senders.ts` + bible. |

---

## Revision History

**v2 — 2026-05-27** (this version)

Triggered by outside agent review of v1 (commit `6549513`) which surfaced 23 findings across copy quality, architecture, compliance, and brand discipline. Subsequent discovery via Supabase MCP that four lifecycle-related edge functions already exist in production but are entirely dormant (`lifecycle-emails` disabled in config since 2026-03-05, zero rows in `email_log` for any of its kinds, no live SendGrid Automations confirmed by founder).

Material changes from v1:

| Area | v1 | v2 |
|---|---|---|
| Framing | Greenfield build | Migration/replacement of dormant edge functions |
| Day 0 hook point | `/api/auth/sync-user` (incorrect) | `/api/setup/progress/route.ts:122` (verified) |
| Day 0 retry | `setTimeout(0)`, accept lost sends | Pending row + cron-driven retry up to 3 attempts |
| Cron schedule | Daily `0 14 * * *` UTC | Hourly `0 * * * *` with localHour=9 gate |
| Dedup key | `(user_id, kind)` with branch-specific kinds | `(user_id, day_slot)` with separate branch column |
| Activity signal | `last_login_at` (does not exist on `users`) | Multi-table `updated_at` max |
| Branch precision | Generic ("has at least one project") | Precise (adopted from dormant edge function) |
| Day 14 sender | Dispatch ("Jack wants to know") | Jack ("I want to know") |
| Day 14 stats | Always shown | Threshold (>=5) — qualitative copy below |
| Lost You threshold | 4 days | 6 days |
| Footer | No visible footer on founder emails | Single-line grey footer on every email |
| Push notification mock | Invented format | Matches real `dispatchTaskCompleted` |
| Banned-word violations | "leverage scales" (Day 4B), "unlocks" (Day 1A), "comes alive" (Day 1A) | All resolved |
| Jack as sender identity | Implicit | Documented `JACK` constant + bible entry |
| `onboarding_email_log` schema | Minimal (kind + sent_at) | Full state (status enum + attempts + last_error + email_log_id) |
| Section 14 (Migration) | Did not exist | New section covering dormant systems + cutover sequence |
| Open questions | 4 open | 3 open (rest resolved in revision) |

**v1 — 2026-05-27** (commit `6549513`)

Initial spec from brainstorming session with founder. Approved before outside review surfaced architectural and copy issues.

---

**End of spec.**
