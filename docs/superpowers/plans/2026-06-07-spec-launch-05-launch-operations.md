# SPEC Launch 05 Launch Operations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Configure and verify the non-code launch controls for the 1,500 CAD two-week SPEC paid validation run.

**Architecture:** Treat launch operations as a release gate with evidence. Each external system gets a concrete verification artifact: Google Ads, GA4, Stripe, Cal.com, Vercel env, Supabase security, SendGrid, legal links, budget controls, and daily review cadence.

**Tech Stack:** Google Ads, GA4, Stripe Dashboard, Cal.com, Vercel, Supabase, SendGrid, OPS-Web admin, ops-site.

---

## File Structure

- Create: `/Users/jacksonsweet/Projects/OPS/ops-software-bible/docs/spec-launch/phase1-launch-operations-runbook.md`
- Create: `/Users/jacksonsweet/Projects/OPS/ops-software-bible/docs/spec-launch/phase1-launch-go-no-go.md`
- Modify only after verification: `/Users/jacksonsweet/Projects/OPS/ops-software-bible/SPEC/08_PHASE1_PAID_VALIDATION_LAUNCH.md`

## Task 1: Create Launch Operations Runbook

**Files:**
- Create: `/Users/jacksonsweet/Projects/OPS/ops-software-bible/docs/spec-launch/phase1-launch-operations-runbook.md`

- [ ] **Step 1: Write runbook shell**

Create:

```markdown
# SPEC Phase 1 Launch Operations Runbook

## Campaign

- Budget cap: 1,500 CAD
- Window: 14 days
- Channel: Google Search
- Geography: Canada excluding Quebec
- Capacity cap: 5 visible slots

## Daily Review

Run every day before increasing spend.

| Metric | Source | Current | Action |
|---|---|---:|---|
| Spend used | `/admin/spec/analytics` |  |  |
| CTR | Google Ads |  |  |
| CPC | Google Ads |  |  |
| Search terms | `/admin/spec/analytics` |  |  |
| Package expansion | `/admin/spec/analytics` |  |  |
| Checkout opened | `/admin/spec/analytics` |  |  |
| Deposit paid | `/admin/spec/analytics` |  |  |
| Default OPS signup | `/admin/spec/analytics` |  |  |

## Pause Rules

- Pause keyword after 100 CAD spend with no qualified signal.
- Pause campaign after 60 percent budget spend with zero qualified signals.
- Add negative keyword for consumer, job seeker, template, student, employment, or non-trade traffic.

## Price Rules

- Hold pricing for 2-5 deposits.
- Raise Build/Enterprise 15-25 percent if more than 5 deposits or waitlist pressure occurs.
- Do not lower price unless traffic quality, page engagement, and checkout trust are proven.
```

- [ ] **Step 2: Commit runbook shell**

Run:

```bash
cd /Users/jacksonsweet/Projects/OPS/ops-software-bible
git add docs/spec-launch/phase1-launch-operations-runbook.md
git commit -m "docs: add SPEC phase one launch runbook"
```

Expected: commit includes only runbook.

## Task 2: Verify Google Ads Configuration

**Files:**
- Modify: `/Users/jacksonsweet/Projects/OPS/ops-software-bible/docs/spec-launch/phase1-launch-operations-runbook.md`

- [ ] **Step 1: Confirm campaign settings**

In Google Ads UI, configure:

```text
Campaign type: Search
Networks: Search Network only
Locations: Canada
Excluded locations: Quebec
Budget: 107 CAD/day average
End condition: manual review at 1,500 CAD total spend
Match types: exact and phrase only
Broad match: disabled
```

- [ ] **Step 2: Confirm conversion action roles**

Configure:

```text
stripe_checkout_completed: Primary, included in bidding
pay_deposit_click: Secondary, not included in bidding
billing_address_submitted: Secondary, not included in bidding
stripe_checkout_opened: Secondary, not included in bidding
intake_submitted: Secondary, not included in bidding
discovery_booked: Secondary, not included in bidding
spec_default_ops_signup_completed: Secondary, not included in bidding
spec_default_ops_trial_activated: Secondary, not included in bidding
quebec_rejected: not imported
refund_invoked: not imported
```

- [ ] **Step 3: Record evidence**

Append:

```markdown
## Google Ads Evidence

- Search-only campaign:
- Canada excluding Quebec:
- Daily budget:
- Conversion roles:
- Primary conversion:
- Secondary conversions:
- Screenshots stored:
```

- [ ] **Step 4: Commit evidence**

Run:

```bash
cd /Users/jacksonsweet/Projects/OPS/ops-software-bible
git add docs/spec-launch/phase1-launch-operations-runbook.md
git commit -m "docs: record SPEC Google Ads launch settings"
```

Expected: runbook evidence commit.

## Task 3: Verify GA4 And Vercel Analytics

**Files:**
- Modify runbook

- [ ] **Step 1: Confirm GA4 property**

Verify:

```text
Property: opsapp.co production
Enhanced measurement: page views enabled
Realtime path: /spec visible during test visit
Events: page_view visible
```

- [ ] **Step 2: Confirm Vercel Analytics**

Visit:

```text
https://opsapp.co/spec?utm_source=google&utm_medium=cpc&utm_campaign=spec_validation_test&gclid=test-gclid
```

Expected: Vercel Analytics shows `/spec` traffic after its normal latency.

- [ ] **Step 3: Record evidence and commit**

Append GA4/Vercel evidence to runbook and commit:

```bash
cd /Users/jacksonsweet/Projects/OPS/ops-software-bible
git add docs/spec-launch/phase1-launch-operations-runbook.md
git commit -m "docs: record SPEC analytics platform checks"
```

## Task 4: Verify Stripe Live/Test Readiness

**Files:**
- Modify runbook

- [ ] **Step 1: Confirm Stripe ToS link**

In Stripe Dashboard, confirm Terms of Service URL:

```text
https://opsapp.co/legal?page=spec-terms
```

- [ ] **Step 2: Confirm Stripe Tax and CAD**

Verify:

```text
Currency: CAD
Stripe Tax: enabled
Billing address collection: required
Phone collection: enabled
Terms consent: required
GST/HST custom field: present
```

- [ ] **Step 3: Run 1 CAD test-mode deposit**

Run a test purchase through the Phase 1 flow with a reduced test price or Stripe test coupon. Verify:

```text
Checkout opens
Terms checkbox appears
Payment succeeds
Webhook writes spec_projects row
spec_acceptance_events includes tos_accepted
conversion_event_outbox includes stripe_checkout_completed
confirmation page renders
```

- [ ] **Step 4: Record and commit evidence**

Append Stripe evidence to runbook and commit:

```bash
cd /Users/jacksonsweet/Projects/OPS/ops-software-bible
git add docs/spec-launch/phase1-launch-operations-runbook.md
git commit -m "docs: record SPEC Stripe readiness"
```

## Task 5: Verify Cal.com Scheduling

**Files:**
- Modify runbook

- [ ] **Step 1: Confirm Cal.com event type**

Configure:

```text
Provider: Cal.com
Event: SPEC discovery
Duration: 30 or 60 minutes
Required fields: name, email, company, phone
Webhook: production OPS endpoint
```

- [ ] **Step 2: Book test discovery**

Book a test discovery call from a SPEC confirmation/intake path.

Expected:

```text
Cal.com booking succeeds
Webhook reaches OPS
spec_projects.discovery_scheduled_at is set
conversion_event_outbox includes discovery_booked
```

- [ ] **Step 3: Record and commit evidence**

Append Cal.com evidence to runbook and commit:

```bash
cd /Users/jacksonsweet/Projects/OPS/ops-software-bible
git add docs/spec-launch/phase1-launch-operations-runbook.md
git commit -m "docs: record SPEC Cal.com readiness"
```

## Task 6: Verify Supabase Security And Live Toggles

**Files:**
- Create: `/Users/jacksonsweet/Projects/OPS/ops-software-bible/docs/spec-launch/phase1-launch-go-no-go.md`

- [ ] **Step 1: Run Supabase advisor**

Use Supabase MCP:

```text
Project: ijeekuhbatykdomumfjx
Action: security advisor
```

Expected: no SPEC launch runs while public-data exposure overlaps Stripe events, contact messages, admin/operator data, email logs, SPEC tables, conversion outbox, or analytics exports.

- [ ] **Step 2: Verify SPEC live toggle remains off**

Confirm Vercel env:

```text
SPEC_LIVE_DEPOSITS_ENABLED=false
```

Expected: remains false until go/no-go checklist passes.

- [ ] **Step 3: Create go/no-go file**

Create:

```markdown
# SPEC Phase 1 Go / No-Go

## Required Evidence

- [ ] OPS-Web build with SPEC admin and analytics
- [ ] ops-site build with launch env
- [ ] Supabase SPEC schema/RLS/cron/storage proof
- [ ] Google Ads Search-only setup
- [ ] Google Ads primary/secondary conversion roles
- [ ] GA4 `/spec` proof
- [ ] Stripe test deposit proof
- [ ] Owner approval proof
- [ ] Quebec rejection proof
- [ ] Refund proof
- [ ] Cal.com booking proof
- [ ] SendGrid SPEC template proof
- [ ] Legal pages live
- [ ] Customer page desktop/mobile review
- [ ] `SPEC_LIVE_DEPOSITS_ENABLED` ready to flip

## Decision

- Status: NO-GO
- Reason: Evidence not complete
```

- [ ] **Step 4: Commit go/no-go file**

Run:

```bash
cd /Users/jacksonsweet/Projects/OPS/ops-software-bible
git add docs/spec-launch/phase1-launch-go-no-go.md
git commit -m "docs: add SPEC launch go-no-go checklist"
```

Expected: commit includes go/no-go checklist.

## Task 7: Final Launch Toggle

**Files:**
- Modify: `/Users/jacksonsweet/Projects/OPS/ops-software-bible/docs/spec-launch/phase1-launch-go-no-go.md`

- [ ] **Step 1: Confirm all checklist boxes are checked**

Open the go/no-go file and verify every required evidence checkbox is checked with links to evidence.

- [ ] **Step 2: Flip Vercel env**

In Vercel production env:

```text
SPEC_LIVE_DEPOSITS_ENABLED=true
```

Redeploy `ops-site`.

- [ ] **Step 3: Run live smoke**

Visit:

```text
https://opsapp.co/spec
```

Expected:

```text
Pay deposit CTAs are live
Billing address gate opens
No console errors
Analytics page receives page_view within expected latency
```

- [ ] **Step 4: Update go/no-go decision**

Change:

```markdown
## Decision

- Status: GO
- Reason: All required evidence complete; live smoke passed
- Live deposits enabled at:
```

- [ ] **Step 5: Commit decision**

Run:

```bash
cd /Users/jacksonsweet/Projects/OPS/ops-software-bible
git add docs/spec-launch/phase1-launch-go-no-go.md
git commit -m "docs: record SPEC phase one launch go decision"
```

Expected: final launch decision evidence committed.
