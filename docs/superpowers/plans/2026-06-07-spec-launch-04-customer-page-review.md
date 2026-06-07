# SPEC Launch 04 Customer Page Review Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Browser-audit and correct every customer-facing SPEC page needed before paid traffic.

**Architecture:** Start with production-like local verification, capture desktop and mobile evidence, log exact UX defects, then apply focused copy/layout/analytics fixes to `ops-site`. No marketing redesign unless the page fails a launch criterion.

**Tech Stack:** Next.js, Playwright or Browser plugin, OPS design system, Vercel Analytics, Stripe test mode, Supabase test rows.

---

## File Structure

- Create: `/Users/jacksonsweet/Projects/OPS/ops-software-bible/docs/spec-launch/customer-page-review-evidence.md`
- Review and modify for recorded P1/P2 launch blockers: `/Users/jacksonsweet/Projects/OPS/ops-site/src/app/spec/page.tsx`
- Review and modify for recorded P1/P2 launch blockers: `/Users/jacksonsweet/Projects/OPS/ops-site/src/components/spec/SpecHero.tsx`
- Review and modify for recorded P1/P2 launch blockers: `/Users/jacksonsweet/Projects/OPS/ops-site/src/components/spec/SpecPricing.tsx`
- Review and modify for recorded P1/P2 launch blockers: `/Users/jacksonsweet/Projects/OPS/ops-site/src/components/spec/PackageCard.tsx`
- Review and modify for recorded P1/P2 launch blockers: `/Users/jacksonsweet/Projects/OPS/ops-site/src/components/spec/SpecOpsBoard.tsx`
- Review and modify for recorded P1/P2 launch blockers: `/Users/jacksonsweet/Projects/OPS/ops-site/src/components/spec/BillingAddressForm.tsx`
- Review and modify for recorded P1/P2 launch blockers: `/Users/jacksonsweet/Projects/OPS/ops-site/src/components/spec/OwnerApprovalForm.tsx`
- Review and modify for recorded P1/P2 launch blockers: `/Users/jacksonsweet/Projects/OPS/ops-site/src/components/spec/SpecConfirmation.tsx`
- Review and modify for recorded P1/P2 launch blockers: `/Users/jacksonsweet/Projects/OPS/ops-site/src/components/spec/intake/IntakeForm.tsx`

## Task 1: Prepare Review Evidence File

**Files:**
- Create: `/Users/jacksonsweet/Projects/OPS/ops-software-bible/docs/spec-launch/customer-page-review-evidence.md`

- [ ] **Step 1: Create evidence file**

Create:

```markdown
# SPEC Customer Page Review Evidence

## Environment

- Date:
- ops-site branch:
- ops-site HEAD:
- Dev server URL:
- Env flags:

## Pages Reviewed

| Surface | Desktop | Mobile | Analytics | Finding IDs |
|---|---|---|---|---|
| `/spec` |  |  |  |  |
| package expansion |  |  |  |  |
| billing address |  |  |  |  |
| Quebec rejection |  |  |  |  |
| owner approval request |  |  |  |  |
| owner approval decision |  |  |  |  |
| checkout token |  |  |  |  |
| confirmation |  |  |  |  |
| intake |  |  |  |  |
| legal tabs |  |  |  |  |

## Findings

Audit pending.
```

- [ ] **Step 2: Commit evidence shell**

Run:

```bash
cd /Users/jacksonsweet/Projects/OPS/ops-software-bible
git add docs/spec-launch/customer-page-review-evidence.md
git commit -m "docs: add SPEC customer page review evidence"
```

Expected: commit includes only the evidence file.

## Task 2: Run Production-Like Local Site

**Files:**
- Read: `/Users/jacksonsweet/Projects/OPS/ops-site/.env.local`
- Modify: `/Users/jacksonsweet/Projects/OPS/ops-software-bible/docs/spec-launch/customer-page-review-evidence.md`

- [ ] **Step 1: Verify env names**

Run:

```bash
cd /Users/jacksonsweet/Projects/OPS/ops-site
test -f .env.local
rg -n "SPEC_LIVE_DEPOSITS_ENABLED|NEXT_PUBLIC_SUPABASE_URL|STRIPE_SECRET_KEY|SUPABASE_SERVICE_ROLE_KEY" .env.local
```

Expected: env names present without copying secret values.

- [ ] **Step 2: Start dev server**

Run:

```bash
cd /Users/jacksonsweet/Projects/OPS/ops-site
npm run dev -- --port 3010
```

Expected: server starts at `http://localhost:3010`.

- [ ] **Step 3: Record environment evidence**

Update evidence file with:

```markdown
## Environment

- Date: 2026-06-07
- ops-site branch: recorded from `git branch --show-current`
- ops-site HEAD: recorded from `git rev-parse --short HEAD`
- Dev server URL: `http://localhost:3010`
- Env flags: `SPEC_LIVE_DEPOSITS_ENABLED` present; secret values not recorded
```

## Task 3: Browser-Audit Landing And Pricing

**Files:**
- Modify evidence file
- Modify SPEC components named in recorded P1/P2 findings

- [ ] **Step 1: Desktop screenshot review**

Open:

```text
http://localhost:3010/spec?utm_source=google&utm_medium=cpc&utm_campaign=spec_validation_test&gclid=test-gclid
```

Viewport: `1440x1000`.

Check:

- first viewport says custom OPS work clearly
- default OPS path is visible
- capacity board is understandable
- tier totals and deposits match 3,000 / 8,500 / 18,000 CAD and 750 / 2,125 / 4,500 CAD
- no overlapping text
- no broken phone scene
- no console errors

- [ ] **Step 2: Mobile screenshot review**

Viewport: `390x844`.

Check:

- primary value proposition fits without overlap
- package cards are tappable
- CTA text fits
- board does not leak exact sensitive occupancy beyond approved public snapshot
- default OPS crossover path is available

- [ ] **Step 3: Record findings**

For each defect, add:

```markdown
### Finding SPEC-PAGE-N

- Surface:
- Severity: P1/P2/P3
- Evidence:
- Required fix:
- File:
```

- [ ] **Step 4: Apply focused fixes**

For copy fixes, edit only the affected component. Example CTA copy:

```tsx
defaultOpsCtaLabel="USE DEFAULT OPS"
```

For layout fixes, use existing design tokens/classes. Do not add one-off colors, rounded pills, or decorative gradients.

- [ ] **Step 5: Re-run screenshots**

Repeat desktop and mobile review. Update each finding with:

```markdown
- Retest result: PASS
```

- [ ] **Step 6: Commit fixes and evidence**

Run:

```bash
cd /Users/jacksonsweet/Projects/OPS/ops-site
git add src/app/spec src/components/spec
git commit -m "fix(spec): tighten paid launch customer page"

cd /Users/jacksonsweet/Projects/OPS/ops-software-bible
git add docs/spec-launch/customer-page-review-evidence.md
git commit -m "docs: record SPEC landing page review"
```

Expected: product commit contains only page fixes; Bible commit contains only evidence.

## Task 4: Browser-Audit Payment And Eligibility Flow

**Files:**
- Modify: `/Users/jacksonsweet/Projects/OPS/ops-site/src/components/spec/BillingAddressForm.tsx`
- Modify: `/Users/jacksonsweet/Projects/OPS/ops-site/src/app/api/spec/create-checkout-session/route.ts`
- Modify evidence file

- [ ] **Step 1: Test non-Quebec billing path**

Open the billing address page through the package CTA. Submit:

```text
line1: 123 Main St
city: Vancouver
province: BC
postal code: V5K 0A1
country: CA
attestations: all checked
```

Expected: checkout session is created or owner approval path appears depending on signed-in account role.

- [ ] **Step 2: Test Quebec rejection path**

Submit:

```text
line1: 123 Rue Principale
city: Montreal
province: QC
postal code: H2X 1Y4
country: CA
attestations: checked
```

Expected: no Stripe session, no `spec_projects` row for eligible purchase, clear rejection copy, contact path present.

- [ ] **Step 3: Record and fix findings**

Use the same finding format. If the rejection copy is vague, replace it with:

```tsx
"SPEC is not available in Quebec at launch. No charge was made."
```

- [ ] **Step 4: Run focused tests**

Run:

```bash
cd /Users/jacksonsweet/Projects/OPS/ops-site
npm test -- src/components/spec/__tests__/billing-redirect.test.ts src/lib/spec/__tests__/resolve-company-redirect.test.ts
```

Expected: exit 0.

- [ ] **Step 5: Commit**

Run product and evidence commits as in Task 3.

## Task 5: Browser-Audit Confirmation, Intake, Legal

**Files:**
- Review and modify for recorded P1/P2 launch blockers: `/Users/jacksonsweet/Projects/OPS/ops-site/src/components/spec/SpecConfirmation.tsx`
- Review and modify for recorded P1/P2 launch blockers: `/Users/jacksonsweet/Projects/OPS/ops-site/src/components/spec/intake/IntakeForm.tsx`
- Review and modify for recorded P1/P2 launch blockers: `/Users/jacksonsweet/Projects/OPS/ops-site/src/lib/legal-content.ts`
- Modify evidence file

- [ ] **Step 1: Confirmation page review**

Open a test session confirmation URL after Stripe test checkout.

Check:

- deposit paid amount matches tier
- next action is intake
- guarantee language is clear
- scheduling path is clear
- no raw Stripe IDs shown to customer

- [ ] **Step 2: Intake page review**

Open `/spec/intake/[token]` with a test token.

Check:

- field labels are direct
- prohibited workflow attestations are clear
- file upload constraints are visible
- autosave status is clear
- mobile inputs do not overflow

- [ ] **Step 3: Legal tab review**

Open:

```text
http://localhost:3010/legal?page=spec-terms
http://localhost:3010/legal?page=privacy
http://localhost:3010/legal?page=dpa
```

Check:

- SPEC terms render in initial HTML
- Privacy includes SPEC data and processor additions
- DPA includes SPEC-specific processing notes
- Cal.com is the scheduling subprocessor
- Stripe ToS URL target is `https://opsapp.co/legal?page=spec-terms`

- [ ] **Step 4: Commit fixes and evidence**

Run product and evidence commits as in Task 3.

## Task 6: Final Customer-Page Verification

**Files:**
- Modify evidence file

- [ ] **Step 1: Run build**

Run:

```bash
cd /Users/jacksonsweet/Projects/OPS/ops-site
npm run build
```

Expected: exit 0.

- [ ] **Step 2: Run SPEC cron tests**

Run:

```bash
cd /Users/jacksonsweet/Projects/OPS/ops-site
npm run test:spec-cron
```

Expected: exit 0.

- [ ] **Step 3: Record final verdict**

Append:

```markdown
## Final Verdict

- Desktop review: PASS
- Mobile review: PASS
- Payment eligibility review: PASS
- Confirmation/intake/legal review: PASS
- Build: PASS
- SPEC cron tests: PASS
```

- [ ] **Step 4: Commit evidence**

Run:

```bash
cd /Users/jacksonsweet/Projects/OPS/ops-software-bible
git add docs/spec-launch/customer-page-review-evidence.md
git commit -m "docs: record SPEC customer page final review"
```

Expected: evidence commit only.
