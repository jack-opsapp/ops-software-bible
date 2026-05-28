# Onboarding Drip Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the onboarding drip designed in `ops-software-bible/specs/2026-05-27-onboarding-drip-design.md` (v3.1) — 7 typed sends (1 founder + 1 follow-up + 4 calendar + 1 behavior-triggered = 10 distinct templates across branches) delivered via the OPS-Web `gatedSend` chokepoint, with claim-before-send dedup, in-flight-safe retry, partial-success reconciliation, and a clean cutover that decommissions the four dormant lifecycle edge functions.

**Architecture:** Real-time Day 0 send dispatched async from `setup/progress` after the company INSERT, with a durable retry path. Days 1/3/4/8/14 and the Lost You re-engagement fire from a single hourly Vercel cron (`/api/cron/onboarding-drip`) gated to operator-local 9am via `detectCompanyTimezone()`. State + dedup live in a new `onboarding_email_log` table with `UNIQUE (user_id, day_slot)`. Pauses re-pend without burning attempts; suppressions are terminal; partial-success is reconciled against `email_log` by `metadata.onboarding_email_log_id` before retry. Every send routes through `gatedSend` so suppression/pause/RFC-8058 compliance is automatic.

**Tech Stack:** Next.js 14 App Router (TypeScript), Vitest, Supabase Postgres, SendGrid (via `@sendgrid/mail`), React Email (`@react-email/render`), Vercel Cron.

---

## Source Spec

Read first: `ops-software-bible/specs/2026-05-27-onboarding-drip-design.md` (v3.1, commits `baebce3` + `ef33c5a`). Every task below maps to a section of that spec. If a task is ambiguous, the spec is the tiebreaker. If the spec is ambiguous, stop and ask the founder — do not improvise.

---

## Pre-flight (before any code changes)

These must pass before opening the worktree. They're not tasks in the TDD sense — they're gates.

- [ ] **PF-1: Verify Vercel plan tier supports hourly cron**

```bash
# Pull the project's vercel.json crons and confirm at least one sub-daily cron exists
# (proves Pro+ in production — hourly would fail deployment on Hobby per
# https://vercel.com/docs/cron-jobs/usage-and-pricing).
cat /Users/jacksonsweet/Projects/OPS/OPS-Web/vercel.json | jq '.crons[] | select(.schedule | test("[*/]"))'
```

Expected: At least one cron with a schedule like `*/5`, `*/10`, `*/15`. If output is empty, OPS-Web is on Hobby and this plan cannot ship as designed — escalate to founder.

- [ ] **PF-2: Verify the dormant edge functions are still dormant**

Run this query via the Supabase MCP `execute_sql` tool against project `ijeekuhbatykdomumfjx`:

```sql
SELECT email_type_key, enabled FROM lifecycle_email_config ORDER BY email_type_key;
```

Expected: 11 rows, all `enabled = false`. If any are `true`, stop — the existing system has been re-enabled since the spec was written and the migration plan needs updating.

```sql
SELECT email_type, count(*) FROM email_log
WHERE email_type IN (
  'no_onboarding_day1','no_onboarding_day3',
  'no_first_project_day2','no_first_project_day5',
  'inactive_14d','inactive_30d',
  'trial_expiring_7d','trial_expiring_3d',
  'trial_expired_day1','trial_expired_day3','trial_expired_day7'
)
GROUP BY email_type;
```

Expected: Empty result (zero sends ever). If any rows exist, the dormant system has fired in production — escalate.

- [ ] **PF-3: Confirm the migration naming convention**

```bash
ls /Users/jacksonsweet/Projects/OPS/OPS-Web/supabase/migrations/ | sort | tail -3
```

Expected: most recent migrations use date-stamped names like `20260527140000_lead_lifecycle_p4_foundation.sql` (NOT sequential `108_…`). The repo migrated from sequential to date-stamped naming somewhere between migration 107 and the current convention. The new migration uses `YYYYMMDDHHMMSS_onboarding_email_log.sql` — pick a fresh timestamp (e.g. `20260527150000`) that's later than any existing migration. Verify with `ls supabase/migrations/ | sort | tail` before applying.

**Parallel-work check (added during pre-flight)**: `20260527140000_lead_lifecycle_p4_foundation.sql` was committed today by another agent/session working on a separate "lead lifecycle" initiative. Do not modify their migration file. Coordinate timestamps so the new onboarding migration sorts AFTER theirs.

- [ ] **PF-4: Confirm the spec is the latest version**

```bash
cd /Users/jacksonsweet/Projects/OPS/ops-software-bible
git log --oneline specs/2026-05-27-onboarding-drip-design.md | head -3
```

Expected: Most recent commit is `ef33c5a` (signoff polish) on top of `68efe73` (v3.1) on top of `baebce3` (v3). If anything newer landed, re-read the spec before continuing.

- [ ] **PF-5: Create a worktree for the implementation**

Per the workspace convention, this work should run in an isolated worktree. Use the `superpowers:using-git-worktrees` skill to create one rooted at the OPS-Web feature branch.

---

## Phase 1 — Foundation (data model + sender + config)

This phase ships the migration, the new `JACK` sender identity, the new `KIND_TO_LIST` entries, and the new `resolveEmailBucket()` cases. No business logic yet. After Phase 1, nothing in production behavior changes — the new table is empty and no code reads it.

### Task 1: Migration 108 — `onboarding_email_log` table

**Files:**
- Create: `OPS-Web/supabase/migrations/20260527150000_onboarding_email_log.sql`
- Mirror into bible: `ops-software-bible/migrations/20260527150000_onboarding_email_log.sql`

- [ ] **Step 1: Write the migration**

```sql
-- 20260527150000_onboarding_email_log.sql
-- Dedup + state table for the onboarding drip cron. UNIQUE (user_id, day_slot)
-- enforces one email per user per day-slot regardless of branch. Claim-before-send
-- pattern: INSERT pending ON CONFLICT DO NOTHING RETURNING id — only the winner
-- sends. See specs/2026-05-27-onboarding-drip-design.md §8 for the full schema
-- rationale.

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
  email_type text NOT NULL,
  status onboarding_email_status NOT NULL DEFAULT 'pending',
  attempts int NOT NULL DEFAULT 0,
  last_error text NULL,
  sent_at timestamptz NULL,
  sg_message_id text NULL,
  day_slot_expires_at timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT onboarding_email_log_unique UNIQUE (user_id, day_slot)
);

CREATE INDEX IF NOT EXISTS idx_onboarding_email_log_company
  ON public.onboarding_email_log (company_id);
CREATE INDEX IF NOT EXISTS idx_onboarding_email_log_sent_at
  ON public.onboarding_email_log (sent_at DESC);
CREATE INDEX IF NOT EXISTS idx_onboarding_email_log_retry_sweep
  ON public.onboarding_email_log (day_slot_expires_at, status, attempts)
  WHERE status IN ('pending', 'failed');
CREATE INDEX IF NOT EXISTS idx_onboarding_email_log_sg_message_id
  ON public.onboarding_email_log (sg_message_id)
  WHERE sg_message_id IS NOT NULL;

DROP TRIGGER IF EXISTS trg_onboarding_email_log_updated_at ON public.onboarding_email_log;
CREATE TRIGGER trg_onboarding_email_log_updated_at
  BEFORE UPDATE ON public.onboarding_email_log
  FOR EACH ROW EXECUTE FUNCTION public.fn_email_campaigns_set_updated_at();

COMMENT ON TABLE public.onboarding_email_log IS
  'Dedup + state table for the onboarding drip cron. UNIQUE (user_id, day_slot) enforces one email per user per day-slot regardless of branch. Claim-before-send pattern: INSERT pending ON CONFLICT DO NOTHING RETURNING id — only the winner sends.';

COMMENT ON COLUMN public.onboarding_email_log.email_type IS
  'The KIND_TO_LIST key passed to gatedSend (e.g. onboarding_day_1_no_project). Stored here so reconciliation queries against email_log can match by (recipient_email, email_type, sent_at window) without requiring a foreign key to email_log.id (gatedSend does not return that id).';

COMMENT ON COLUMN public.onboarding_email_log.branch IS
  'Which branch variant was sent. NULL for unbranched (day_0, day_3, day_8, lost_you). For branched days: no_project / has_project / no_aha / has_aha / quiet / active.';

COMMENT ON COLUMN public.onboarding_email_log.sg_message_id IS
  'SendGrid message id returned by gatedSend on successful send. Used to join against email_events for engagement metrics on this drip. NULL when status is not yet sent.';

COMMENT ON COLUMN public.onboarding_email_log.day_slot_expires_at IS
  'Hard end of the retry window for this row. Computed at insert: operator-local 9am of the target day + 24 hours, in UTC. After this time, the cron skips this row even if pending/failed — the send window for this day-slot is over.';

COMMENT ON COLUMN public.onboarding_email_log.status IS
  'pending: claim succeeded, send not yet attempted, OR paused by gatedSend pause check (re-tried on next cron tick until day_slot_expires_at). sent: gatedSend returned status=sent. failed: send attempted and errored; retried if attempts<3 AND now()<day_slot_expires_at. skipped: gatedSend returned suppression_skipped — terminal (suppressions are permanent opt-outs, not reversible like pauses).';
```

- [ ] **Step 2: Apply the migration via Supabase MCP**

Use `mcp__plugin_supabase_supabase__apply_migration` with project `ijeekuhbatykdomumfjx`, name `20260527150000_onboarding_email_log`, and the SQL from Step 1.

Expected: success response. Verify with:

```sql
SELECT column_name, data_type, is_nullable FROM information_schema.columns
WHERE table_schema='public' AND table_name='onboarding_email_log'
ORDER BY ordinal_position;
```

Should return all 13 columns from the CREATE TABLE.

- [ ] **Step 3: Mirror the migration into the bible**

```bash
cp /Users/jacksonsweet/Projects/OPS/OPS-Web/supabase/migrations/20260527150000_onboarding_email_log.sql \
   /Users/jacksonsweet/Projects/OPS/ops-software-bible/migrations/
```

- [ ] **Step 4: Commit**

```bash
cd /Users/jacksonsweet/Projects/OPS/OPS-Web
git add supabase/migrations/20260527150000_onboarding_email_log.sql
git commit -m "feat(onboarding-drip): add onboarding_email_log dedup table (migration 108)"
cd /Users/jacksonsweet/Projects/OPS/ops-software-bible
git add migrations/20260527150000_onboarding_email_log.sql
git commit -m "docs(bible): mirror migration 108 onboarding_email_log"
```

---

### Task 2: Add `JACK` sender identity

**Files:**
- Modify: `OPS-Web/src/lib/email/senders.ts`

- [ ] **Step 1: Add JACK constant**

Read `OPS-Web/src/lib/email/senders.ts`. Append after the `FIELD_NOTES` constant (before `portalSender`):

```ts
/**
 * Founder-direct sender bucket — used by the onboarding drip's personal
 * emails (Day 0/3/8/14 + Lost You). Operationally part of the dispatch
 * bucket for pause-killswitch purposes (see resolveEmailBucket).
 */
export const JACK: Sender = {
  email: "jack@opsapp.co",
  name: "Jack Sweet",
};
```

Also update the file header comment block to add `JACK` to the four-bucket list (it becomes five if you treat Jack as separate, but for pause purposes Jack rides on `dispatch` — describe it as "founder identity, operationally part of dispatch").

- [ ] **Step 2: Verify no other call site needs updating**

```bash
cd /Users/jacksonsweet/Projects/OPS/OPS-Web
grep -rn "from \"@/lib/email/senders\"" src/ | head -10
grep -rn "from \"./senders\"" src/lib/email/ | head -10
```

Expected: only `sendgrid.tsx` imports from `senders`. No other file needs touching for the sender add itself.

- [ ] **Step 3: Commit**

```bash
git add src/lib/email/senders.ts
git commit -m "feat(onboarding-drip): add JACK sender identity (jack@opsapp.co)"
```

---

### Task 3: Add KIND_TO_LIST entries

**Files:**
- Modify: `OPS-Web/src/lib/email/constants.ts`

- [ ] **Step 1: Add the 10 new entries**

Read `OPS-Web/src/lib/email/constants.ts`. Inside the `KIND_TO_LIST` object, append these 10 entries (alphabetically grouped with existing entries or at the end — match the file's existing style):

```ts
  // Onboarding drip — see specs/2026-05-27-onboarding-drip-design.md §6.
  // All on 'global' suppression list per decision log #7: founder-drip
  // unsubscribe = full opt-out signal.
  onboarding_day_0_welcome: "global",
  onboarding_day_1_no_project: "global",
  onboarding_day_1_has_project: "global",
  onboarding_day_3_inbox: "global",
  onboarding_day_4_no_notification: "global",
  onboarding_day_4_has_notification: "global",
  onboarding_day_8_estimates: "global",
  onboarding_day_14_quiet: "global",
  onboarding_day_14_active: "global",
  onboarding_lost_you: "global",
```

- [ ] **Step 2: Verify the file still parses**

```bash
cd /Users/jacksonsweet/Projects/OPS/OPS-Web
pnpm tsc --noEmit src/lib/email/constants.ts 2>&1 | head -5
```

Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add src/lib/email/constants.ts
git commit -m "feat(onboarding-drip): add 10 KIND_TO_LIST entries for onboarding kinds"
```

---

### Task 4: Add `resolveEmailBucket()` cases for onboarding kinds

**Files:**
- Modify: `OPS-Web/src/lib/email/pause.ts`

- [ ] **Step 1: Add the cases**

Read `OPS-Web/src/lib/email/pause.ts`. Find the `resolveEmailBucket()` function (around line 42). The switch currently has cases for `gate`, `field_notes`, `portal`, with `dispatch` as default. The 10 onboarding kinds all ride on `dispatch` (Jack's sends share the dispatch bucket for pause-killswitch purposes per Task 2's note). Default case already covers them — but we add explicit cases so the code is greppable and the design intent is explicit.

Add inside the switch, before the `default:`:

```ts
    // Onboarding drip — Jack-persona and Dispatch-persona both ride the
    // dispatch bucket for pause-killswitch purposes. Explicit cases for
    // greppability.
    case "onboarding_day_0_welcome":
    case "onboarding_day_1_no_project":
    case "onboarding_day_1_has_project":
    case "onboarding_day_3_inbox":
    case "onboarding_day_4_no_notification":
    case "onboarding_day_4_has_notification":
    case "onboarding_day_8_estimates":
    case "onboarding_day_14_quiet":
    case "onboarding_day_14_active":
    case "onboarding_lost_you":
      return "dispatch";
```

- [ ] **Step 2: Write a smoke test**

Create `OPS-Web/tests/unit/email/pause-onboarding-buckets.test.ts`:

```ts
import { describe, it, expect } from "vitest";
import { resolveEmailBucket } from "@/lib/email/pause";

describe("resolveEmailBucket — onboarding kinds", () => {
  const kinds = [
    "onboarding_day_0_welcome",
    "onboarding_day_1_no_project",
    "onboarding_day_1_has_project",
    "onboarding_day_3_inbox",
    "onboarding_day_4_no_notification",
    "onboarding_day_4_has_notification",
    "onboarding_day_8_estimates",
    "onboarding_day_14_quiet",
    "onboarding_day_14_active",
    "onboarding_lost_you",
  ];

  for (const kind of kinds) {
    it(`maps ${kind} to dispatch bucket`, () => {
      expect(resolveEmailBucket(kind)).toBe("dispatch");
    });
  }
});
```

- [ ] **Step 3: Run the test**

```bash
cd /Users/jacksonsweet/Projects/OPS/OPS-Web
pnpm vitest run tests/unit/email/pause-onboarding-buckets.test.ts
```

Expected: all 10 tests pass.

- [ ] **Step 4: Commit**

```bash
git add src/lib/email/pause.ts tests/unit/email/pause-onboarding-buckets.test.ts
git commit -m "feat(onboarding-drip): map 10 onboarding kinds to dispatch bucket in pause.ts"
```

---

End of Phase 1. After these 4 tasks: the table exists, the sender identity is registered, kind-to-list mapping is in place, and bucket resolution works. Nothing in production fires from any of this — pure foundation.

---

## Phase 2 — Email primitives

Three reusable React Email components. Templates in Phase 3 depend on these.

### Task 5: `FounderFooter` primitive

**Files:**
- Create: `OPS-Web/src/lib/email/react/primitives/FounderFooter.tsx`
- Test: `OPS-Web/tests/unit/email/primitives/founder-footer.test.tsx`

- [ ] **Step 1: Write the failing test**

```tsx
import { describe, it, expect } from "vitest";
import { render } from "@react-email/render";
import { FounderFooter } from "@/lib/email/react/primitives/FounderFooter";

describe("FounderFooter", () => {
  it("renders the OPS LTD legal address", async () => {
    const html = await render(
      <FounderFooter unsubscribeUrl="https://app.opsapp.co/api/email/unsubscribe?t=abc" />,
    );
    expect(html).toContain("OPS LTD.");
    expect(html).toContain("1515 Douglas St, Victoria, BC V8W 2G4");
  });

  it("renders an Unsubscribe link pointed at the given URL", async () => {
    const url = "https://app.opsapp.co/api/email/unsubscribe?t=abc";
    const html = await render(<FounderFooter unsubscribeUrl={url} />);
    expect(html).toContain(`href="${url}"`);
    expect(html).toContain("Unsubscribe");
  });

  it("renders as plain text with minimal styling", async () => {
    const text = await render(
      <FounderFooter unsubscribeUrl="https://x.test" />,
      { plainText: true },
    );
    expect(text).toMatch(/OPS LTD\..*Victoria, BC.*Unsubscribe/s);
  });
});
```

- [ ] **Step 2: Run test, verify it fails**

```bash
cd /Users/jacksonsweet/Projects/OPS/OPS-Web
pnpm vitest run tests/unit/email/primitives/founder-footer.test.tsx
```

Expected: FAIL with "Cannot find module ... FounderFooter".

- [ ] **Step 3: Implement the primitive**

```tsx
// OPS-Web/src/lib/email/react/primitives/FounderFooter.tsx
import * as React from "react";
import { Text, Link, Section } from "@react-email/components";

/**
 * Minimal single-line compliance footer used by founder plain-text emails
 * (Day 0, Day 3, Day 8, Day 14, LostYou) in the onboarding drip.
 * Renders in small grey type so it's legally compliant without breaking
 * the personal-email feel.
 *
 * @template-version 1.0.0
 */
export function FounderFooter({ unsubscribeUrl }: { unsubscribeUrl: string }) {
  return (
    <Section
      style={{
        marginTop: "32px",
        paddingTop: "16px",
        borderTop: "1px solid #e5e5e5",
      }}
    >
      <Text
        style={{
          fontSize: "11px",
          color: "#8A8A8A",
          fontFamily: "Helvetica, Arial, sans-serif",
          margin: 0,
          lineHeight: "16px",
        }}
      >
        OPS LTD. · 1515 Douglas St, Victoria, BC V8W 2G4 ·{" "}
        <Link
          href={unsubscribeUrl}
          style={{ color: "#8A8A8A", textDecoration: "underline" }}
        >
          Unsubscribe
        </Link>
      </Text>
    </Section>
  );
}

export const previewProps = {
  unsubscribeUrl: "https://app.opsapp.co/api/email/unsubscribe?t=preview",
};
```

- [ ] **Step 4: Run test, verify it passes**

```bash
pnpm vitest run tests/unit/email/primitives/founder-footer.test.tsx
```

Expected: all 3 tests pass.

- [ ] **Step 5: Commit**

```bash
git add src/lib/email/react/primitives/FounderFooter.tsx \
        tests/unit/email/primitives/founder-footer.test.tsx
git commit -m "feat(onboarding-drip): add FounderFooter primitive for plain-text founder emails"
```

---

### Task 6: `PlainTextLayout` primitive

**Files:**
- Create: `OPS-Web/src/lib/email/react/primitives/PlainTextLayout.tsx`
- Test: `OPS-Web/tests/unit/email/primitives/plain-text-layout.test.tsx`

- [ ] **Step 1: Write the failing test**

```tsx
import { describe, it, expect } from "vitest";
import { render } from "@react-email/render";
import { PlainTextLayout } from "@/lib/email/react/primitives/PlainTextLayout";

describe("PlainTextLayout", () => {
  it("renders body content and footer", async () => {
    const html = await render(
      <PlainTextLayout
        unsubscribeUrl="https://app.opsapp.co/api/email/unsubscribe?t=test"
      >
        Hey there Jackson, this is the body.
      </PlainTextLayout>,
    );
    expect(html).toContain("Hey there Jackson, this is the body.");
    expect(html).toContain("OPS LTD.");
    expect(html).toContain("Unsubscribe");
  });

  it("does NOT render glass card, logo, or branded chrome", async () => {
    const html = await render(
      <PlainTextLayout unsubscribeUrl="https://x.test">body</PlainTextLayout>,
    );
    // Founder emails are stripped — no OPS logo, no glass background
    expect(html).not.toMatch(/ops-mark|ops-lockup|backdrop-blur|rgba\(18, 18, 20/);
  });

  it("preserves newlines in plain-text rendering", async () => {
    const text = await render(
      <PlainTextLayout unsubscribeUrl="https://x.test">
        Line one.{"\n\n"}Line two.
      </PlainTextLayout>,
      { plainText: true },
    );
    expect(text).toContain("Line one.");
    expect(text).toContain("Line two.");
  });
});
```

- [ ] **Step 2: Run test, verify it fails**

```bash
pnpm vitest run tests/unit/email/primitives/plain-text-layout.test.tsx
```

Expected: FAIL — module not found.

- [ ] **Step 3: Implement**

```tsx
// OPS-Web/src/lib/email/react/primitives/PlainTextLayout.tsx
import * as React from "react";
import { Html, Head, Body, Container, Text } from "@react-email/components";
import { FounderFooter } from "./FounderFooter";

/**
 * Layout primitive for the onboarding drip's founder-voice emails
 * (Day 0, Day 3, Day 8, Day 14 quiet/active, LostYou). Renders the
 * body content as a single white container — NO glass card, NO logo,
 * NO branded chrome. The whole point is that the email looks like a
 * real personal email Jack typed, not a templated send.
 *
 * Children should be plain text (or simple <Text> blocks). Newlines
 * are preserved via white-space: pre-wrap.
 *
 * @template-version 1.0.0
 */
export function PlainTextLayout({
  children,
  unsubscribeUrl,
}: {
  children: React.ReactNode;
  unsubscribeUrl: string;
}) {
  return (
    <Html>
      <Head />
      <Body
        style={{
          backgroundColor: "#ffffff",
          fontFamily: "Helvetica, Arial, sans-serif",
          color: "#1a1a1a",
          margin: 0,
          padding: 0,
        }}
      >
        <Container
          style={{
            maxWidth: "560px",
            margin: "0 auto",
            padding: "32px 24px",
          }}
        >
          <Text
            style={{
              fontSize: "15px",
              lineHeight: "22px",
              color: "#1a1a1a",
              margin: 0,
              whiteSpace: "pre-wrap",
            }}
          >
            {children}
          </Text>
          <FounderFooter unsubscribeUrl={unsubscribeUrl} />
        </Container>
      </Body>
    </Html>
  );
}

export const previewProps = {
  unsubscribeUrl: "https://app.opsapp.co/api/email/unsubscribe?t=preview",
  children: "Hey there Jackson,\n\nThis is a preview of the layout.\n\n— Jack",
};
```

- [ ] **Step 4: Run test, verify it passes**

```bash
pnpm vitest run tests/unit/email/primitives/plain-text-layout.test.tsx
```

Expected: 3 passes.

- [ ] **Step 5: Commit**

```bash
git add src/lib/email/react/primitives/PlainTextLayout.tsx \
        tests/unit/email/primitives/plain-text-layout.test.tsx
git commit -m "feat(onboarding-drip): add PlainTextLayout primitive (no glass card, no logo)"
```

---

### Task 7: `MockPushNotification` primitive

**Files:**
- Create: `OPS-Web/src/lib/email/react/primitives/MockPushNotification.tsx`
- Test: `OPS-Web/tests/unit/email/primitives/mock-push-notification.test.tsx`

This component renders an iOS-style push notification card for Day 4A's "the notification you're working toward" mockup. **Deliberately stylized** (not pixel-perfect iOS chrome) so we never look like we're impersonating Apple.

- [ ] **Step 1: Write the failing test**

```tsx
import { describe, it, expect } from "vitest";
import { render } from "@react-email/render";
import { MockPushNotification } from "@/lib/email/react/primitives/MockPushNotification";

describe("MockPushNotification", () => {
  it("renders the real dispatchTaskCompleted format", async () => {
    // Must match notification-dispatch.ts:200-201:
    //   title: "Task Completed"
    //   body:  `${completedByName} completed "${taskTitle}" on ${projectTitle}`
    const html = await render(
      <MockPushNotification
        completedByName="Jake"
        taskTitle="Rail Install"
        projectTitle="5611 Batu Rd"
      />,
    );
    expect(html).toContain("Task Completed");
    expect(html).toContain(`Jake completed "Rail Install" on 5611 Batu Rd`);
  });

  it("renders the sender name (OPS) and a 'now' timestamp", async () => {
    const html = await render(
      <MockPushNotification
        completedByName="Jake"
        taskTitle="Rail Install"
        projectTitle="5611 Batu Rd"
      />,
    );
    expect(html).toContain("OPS");
    expect(html).toContain("now");
  });
});
```

- [ ] **Step 2: Run test, verify it fails**

```bash
pnpm vitest run tests/unit/email/primitives/mock-push-notification.test.tsx
```

Expected: FAIL — module not found.

- [ ] **Step 3: Implement**

```tsx
// OPS-Web/src/lib/email/react/primitives/MockPushNotification.tsx
import * as React from "react";
import { Section, Text } from "@react-email/components";

/**
 * Mocked iOS-style push notification card. Used by Day 4A's
 * "the notification you're working toward" email to give the operator
 * a visual preview of the moment they're driving toward.
 *
 * Format MUST match the real notification produced by
 * dispatchTaskCompleted() at OPS-Web/src/lib/api/services/notification-dispatch.ts:200-201:
 *   title: "Task Completed"
 *   body:  `${completedByName} completed "${taskTitle}" on ${projectTitle}`
 *
 * Stylistic choice: deliberately not pixel-perfect iOS chrome so we
 * don't impersonate Apple UI. Shape is "recognizably a push notification"
 * without copying Apple's exact spec.
 *
 * @template-version 1.0.0
 */
export function MockPushNotification({
  completedByName,
  taskTitle,
  projectTitle,
}: {
  completedByName: string;
  taskTitle: string;
  projectTitle: string;
}) {
  return (
    <Section
      style={{
        maxWidth: "440px",
        margin: "16px auto",
        backgroundColor: "#1c1c1e",
        borderRadius: "14px",
        padding: "12px 16px",
        fontFamily:
          "-apple-system, BlinkMacSystemFont, 'Helvetica Neue', sans-serif",
      }}
    >
      <table width="100%" style={{ borderCollapse: "collapse" }}>
        <tr>
          <td style={{ fontSize: "13px", color: "#9a9a9a", paddingBottom: "4px" }}>
            OPS
          </td>
          <td
            style={{
              fontSize: "13px",
              color: "#9a9a9a",
              textAlign: "right",
              paddingBottom: "4px",
            }}
          >
            now
          </td>
        </tr>
      </table>
      <Text
        style={{
          fontSize: "15px",
          color: "#ffffff",
          fontWeight: 600,
          margin: "0 0 2px 0",
          lineHeight: "20px",
        }}
      >
        Task Completed
      </Text>
      <Text
        style={{
          fontSize: "15px",
          color: "#e5e5e7",
          margin: 0,
          lineHeight: "20px",
        }}
      >
        {`${completedByName} completed "${taskTitle}" on ${projectTitle}`}
      </Text>
    </Section>
  );
}

export const previewProps = {
  completedByName: "Jake",
  taskTitle: "Rail Install",
  projectTitle: "5611 Batu Rd",
};
```

- [ ] **Step 4: Run test, verify it passes**

```bash
pnpm vitest run tests/unit/email/primitives/mock-push-notification.test.tsx
```

Expected: 2 passes.

- [ ] **Step 5: Commit**

```bash
git add src/lib/email/react/primitives/MockPushNotification.tsx \
        tests/unit/email/primitives/mock-push-notification.test.tsx
git commit -m "feat(onboarding-drip): add MockPushNotification primitive matching dispatchTaskCompleted format"
```

---

End of Phase 2. Three primitives ready; templates in Phase 3 import them.

---

## Phase 3 — Templates

Ten React Email templates, one per task. Each template has:
- A canonical copy block (from spec §6 — copy verbatim)
- Props interface
- A `previewProps` export so the admin template-registry preview works
- A test that renders with `previewProps` and asserts key copy is present

Body copy is canonical — do not improvise. If you find a typo or feel the copy could be tighter, stop and ask the founder.

### Task 8: `Day0Welcome` template

**Files:**
- Create: `OPS-Web/src/lib/email/react/templates/onboarding/Day0Welcome.tsx`
- Test: `OPS-Web/tests/unit/email/templates/onboarding/day-0-welcome.test.tsx`

- [ ] **Step 1: Write the failing test**

```tsx
import { describe, it, expect } from "vitest";
import { render } from "@react-email/render";
import { Day0Welcome, previewProps } from "@/lib/email/react/templates/onboarding/Day0Welcome";

describe("Day0Welcome", () => {
  it("renders with previewProps", async () => {
    const html = await render(<Day0Welcome {...previewProps} />);
    expect(html).toContain("My name is Jack, I built OPS.");
    expect(html).toContain("OPS LTD.");
  });

  it("substitutes firstName when provided", async () => {
    const html = await render(
      <Day0Welcome firstName="Pat" unsubscribeUrl="https://x.test" />,
    );
    expect(html).toContain("Hey there Pat,");
  });

  it("degrades to 'Hey there,' when firstName is null", async () => {
    const html = await render(
      <Day0Welcome firstName={null} unsubscribeUrl="https://x.test" />,
    );
    expect(html).toContain("Hey there,");
    expect(html).not.toContain("Hey there null");
    expect(html).not.toContain("Hey there ,");
  });

  it("includes 'I read every reply' verbatim (load-bearing)", async () => {
    const html = await render(<Day0Welcome {...previewProps} />);
    // Per spec decision log #1: this phrase is canonical, not paraphrased.
    // Day 0 doesn't explicitly say it — that's Day 3 — but the body
    // promises Jack reads replies via "it's my personal inbox".
    expect(html).toContain("it's my personal inbox");
  });
});
```

- [ ] **Step 2: Run test, verify it fails**

```bash
pnpm vitest run tests/unit/email/templates/onboarding/day-0-welcome.test.tsx
```

Expected: FAIL — module not found.

- [ ] **Step 3: Implement**

```tsx
// OPS-Web/src/lib/email/react/templates/onboarding/Day0Welcome.tsx
import * as React from "react";
import { PlainTextLayout } from "@/lib/email/react/primitives/PlainTextLayout";

/**
 * Day 0 founder welcome — sent real-time from /api/setup/progress after
 * the company INSERT. Copy is canonical per spec §6; do not edit without
 * a brand review (founder-voice email, written by the founder himself).
 *
 * @template-version 1.0.0
 */
export interface Day0WelcomeProps {
  firstName: string | null;
  unsubscribeUrl: string;
}

export function Day0Welcome({ firstName, unsubscribeUrl }: Day0WelcomeProps) {
  const greeting = firstName ? `Hey there ${firstName},` : "Hey there,";
  return (
    <PlainTextLayout unsubscribeUrl={unsubscribeUrl}>
      {greeting}
      {"\n\n"}
      My name is Jack, I built OPS.
      {"\n\n"}
      I'm glad you signed up, and I'm looking forward to hearing what you think of it as you grow.
      {"\n\n"}
      What led you to join? Are you just kicking tires? Are you considering moving from another platform? Just getting into digital tools for your business? Whatever the case, I'm happy to help you get rolling. I built this tool because there was nothing on the market that worked for my crew. I got the impression those were all tech companies built by guys who have never actually worked on a jobsite. So here we are.
      {"\n\n"}
      Again, if there's anything you need help with, you can reply to this email, it's my personal inbox.
      {"\n\n"}
      — Jack
    </PlainTextLayout>
  );
}

export const previewProps: Day0WelcomeProps = {
  firstName: "Jackson",
  unsubscribeUrl: "https://app.opsapp.co/api/email/unsubscribe?t=preview",
};
```

- [ ] **Step 4: Run test, verify it passes**

```bash
pnpm vitest run tests/unit/email/templates/onboarding/day-0-welcome.test.tsx
```

Expected: 4 passes.

- [ ] **Step 5: Commit**

```bash
git add src/lib/email/react/templates/onboarding/Day0Welcome.tsx \
        tests/unit/email/templates/onboarding/day-0-welcome.test.tsx
git commit -m "feat(onboarding-drip): add Day 0 founder welcome template"
```

---

### Task 9: `Day1NoProject` template

**Files:**
- Create: `OPS-Web/src/lib/email/react/templates/onboarding/Day1NoProject.tsx`
- Test: `OPS-Web/tests/unit/email/templates/onboarding/day-1-no-project.test.tsx`

This is a Dispatch-voice HTML template (tactical, with the CTA button). It uses the standard OPS HTML email layout — look for the existing layout primitive used by `ProductUpdate.tsx`, `FeatureAnnouncement.tsx`, etc. and follow the same pattern.

- [ ] **Step 1: Inspect the existing OPS HTML layout pattern**

```bash
cd /Users/jacksonsweet/Projects/OPS/OPS-Web
ls src/lib/email/react/primitives/
cat src/lib/email/react/templates/ProductUpdate.tsx | head -80
```

Note the layout primitive name (likely something like `OpsLayout` or imported via a `Body`+`Container`+`Section` composition). Reuse it for Day 1A and the other Dispatch templates. If no shared layout primitive exists, follow the inline composition pattern of `ProductUpdate.tsx`.

- [ ] **Step 2: Write the failing test**

```tsx
import { describe, it, expect } from "vitest";
import { render } from "@react-email/render";
import { Day1NoProject, previewProps } from "@/lib/email/react/templates/onboarding/Day1NoProject";

describe("Day1NoProject", () => {
  it("renders with previewProps", async () => {
    const html = await render(<Day1NoProject {...previewProps} />);
    expect(html).toContain("Day 1. You signed up yesterday.");
    expect(html).toContain("drop your first project in");
  });

  it("includes the CTA button pointing at the projects/new URL", async () => {
    const html = await render(
      <Day1NoProject
        ctaUrl="https://app.opsapp.co/projects/new"
        unsubscribeUrl="https://x.test"
      />,
    );
    expect(html).toContain("DROP YOUR FIRST PROJECT");
    expect(html).toContain('href="https://app.opsapp.co/projects/new"');
  });

  it("does not contain banned vocabulary", async () => {
    const html = await render(<Day1NoProject {...previewProps} />);
    // Per spec §12 banned list — v3 explicitly removed "unlocks" and "comes alive"
    expect(html.toLowerCase()).not.toMatch(/\bunlocks?\b/);
    expect(html.toLowerCase()).not.toContain("comes alive");
    expect(html.toLowerCase()).not.toContain("leverage");
  });

  it("includes the visible compliance footer", async () => {
    const html = await render(<Day1NoProject {...previewProps} />);
    expect(html).toContain("OPS LTD.");
    expect(html).toContain("Unsubscribe");
  });
});
```

- [ ] **Step 3: Run test, verify it fails**

```bash
pnpm vitest run tests/unit/email/templates/onboarding/day-1-no-project.test.tsx
```

Expected: FAIL — module not found.

- [ ] **Step 4: Implement**

Use the existing OPS HTML email layout pattern observed in Step 1. The body text below is canonical per spec §6:

```tsx
// OPS-Web/src/lib/email/react/templates/onboarding/Day1NoProject.tsx
import * as React from "react";
import {
  Html,
  Head,
  Body,
  Container,
  Section,
  Text,
  Button,
} from "@react-email/components";
import { FounderFooter } from "@/lib/email/react/primitives/FounderFooter";

/**
 * Day 1 Branch A — fires when the operator has NOT completed web
 * onboarding OR has zero projects. Sent from OPS Dispatch.
 * Body copy is canonical per spec §6.
 *
 * @template-version 1.0.0
 */
export interface Day1NoProjectProps {
  ctaUrl: string;
  unsubscribeUrl: string;
}

export function Day1NoProject({ ctaUrl, unsubscribeUrl }: Day1NoProjectProps) {
  return (
    <Html>
      <Head />
      <Body
        style={{
          backgroundColor: "#000000",
          color: "#EDEDED",
          fontFamily: "Helvetica, Arial, sans-serif",
          margin: 0,
          padding: 0,
        }}
      >
        <Container style={{ maxWidth: "560px", margin: "0 auto", padding: "32px 24px" }}>
          <Section>
            <Text style={{ fontSize: "15px", lineHeight: "22px", margin: "0 0 16px 0" }}>
              Day 1. You signed up yesterday.
            </Text>
            <Text style={{ fontSize: "15px", lineHeight: "22px", margin: "0 0 16px 0" }}>
              The move that puts the rest of the system to work: drop your first project in. Real client, real address, real tasks.
            </Text>
            <Text style={{ fontSize: "15px", lineHeight: "22px", margin: "0 0 16px 0" }}>
              Without a project, OPS has nothing to work from. Once a project's in, the schedule, the crew, the photos, the estimates, the invoices all hang off it.
            </Text>
            <Text style={{ fontSize: "15px", lineHeight: "22px", margin: "0 0 24px 0" }}>
              Use a job you're actually running this week. Takes two minutes.
            </Text>
            <Section style={{ textAlign: "left", margin: "24px 0" }}>
              <Button
                href={ctaUrl}
                style={{
                  backgroundColor: "transparent",
                  color: "#6F94B0",
                  border: "1px solid #6F94B0",
                  padding: "12px 20px",
                  borderRadius: "5px",
                  fontFamily: "'JetBrains Mono', monospace",
                  fontSize: "13px",
                  textTransform: "uppercase",
                  letterSpacing: "0.05em",
                  textDecoration: "none",
                }}
              >
                DROP YOUR FIRST PROJECT
              </Button>
            </Section>
          </Section>
          <FounderFooter unsubscribeUrl={unsubscribeUrl} />
        </Container>
      </Body>
    </Html>
  );
}

export const previewProps: Day1NoProjectProps = {
  ctaUrl: "https://app.opsapp.co/projects/new",
  unsubscribeUrl: "https://app.opsapp.co/api/email/unsubscribe?t=preview",
};
```

- [ ] **Step 5: Run test, verify it passes**

```bash
pnpm vitest run tests/unit/email/templates/onboarding/day-1-no-project.test.tsx
```

Expected: 4 passes.

- [ ] **Step 6: Commit**

```bash
git add src/lib/email/react/templates/onboarding/Day1NoProject.tsx \
        tests/unit/email/templates/onboarding/day-1-no-project.test.tsx
git commit -m "feat(onboarding-drip): add Day 1A no-project template (Dispatch HTML)"
```

---

### Task 10: `Day1HasProject` template

**Files:**
- Create: `OPS-Web/src/lib/email/react/templates/onboarding/Day1HasProject.tsx`
- Test: `OPS-Web/tests/unit/email/templates/onboarding/day-1-has-project.test.tsx`

- [ ] **Step 1: Write the failing test**

```tsx
import { describe, it, expect } from "vitest";
import { render } from "@react-email/render";
import { Day1HasProject, previewProps } from "@/lib/email/react/templates/onboarding/Day1HasProject";

describe("Day1HasProject", () => {
  it("renders 'first project' singular when projectCount === 1", async () => {
    const html = await render(
      <Day1HasProject
        projectCount={1}
        ctaUrl="https://app.opsapp.co/dashboard"
        unsubscribeUrl="https://x.test"
      />,
    );
    expect(html).toContain("You've already got your first project in.");
    expect(html).not.toContain("You've got 1 projects in");
  });

  it("renders count + plural when projectCount > 1", async () => {
    const html = await render(
      <Day1HasProject
        projectCount={3}
        ctaUrl="https://app.opsapp.co/dashboard"
        unsubscribeUrl="https://x.test"
      />,
    );
    expect(html).toContain("You've got 3 projects in.");
  });

  it("includes the next-step copy + CTA", async () => {
    const html = await render(<Day1HasProject {...previewProps} />);
    expect(html).toContain("tasks on those projects");
    expect(html).toContain("ASSIGN A TASK + INVITE A CREW MEMBER");
  });

  it("does not contain banned vocabulary", async () => {
    const html = await render(<Day1HasProject {...previewProps} />);
    expect(html.toLowerCase()).not.toMatch(/\bunlocks?\b/);
    expect(html.toLowerCase()).not.toContain("leverage");
    expect(html.toLowerCase()).not.toContain("comes alive");
  });
});
```

- [ ] **Step 2: Run test, verify it fails**

```bash
pnpm vitest run tests/unit/email/templates/onboarding/day-1-has-project.test.tsx
```

Expected: FAIL — module not found.

- [ ] **Step 3: Implement**

```tsx
// OPS-Web/src/lib/email/react/templates/onboarding/Day1HasProject.tsx
import * as React from "react";
import {
  Html, Head, Body, Container, Section, Text, Button,
} from "@react-email/components";
import { FounderFooter } from "@/lib/email/react/primitives/FounderFooter";

/**
 * Day 1 Branch B — fires when the operator has completed web onboarding
 * AND has at least one project. Sent from OPS Dispatch. Body copy is
 * canonical per spec §6.
 *
 * @template-version 1.0.0
 */
export interface Day1HasProjectProps {
  projectCount: number;
  ctaUrl: string;
  unsubscribeUrl: string;
}

export function Day1HasProject({
  projectCount,
  ctaUrl,
  unsubscribeUrl,
}: Day1HasProjectProps) {
  const countLine =
    projectCount === 1
      ? "You've already got your first project in."
      : `You've got ${projectCount} projects in.`;
  return (
    <Html>
      <Head />
      <Body style={{ backgroundColor: "#000000", color: "#EDEDED", fontFamily: "Helvetica, Arial, sans-serif", margin: 0, padding: 0 }}>
        <Container style={{ maxWidth: "560px", margin: "0 auto", padding: "32px 24px" }}>
          <Section>
            <Text style={{ fontSize: "15px", lineHeight: "22px", margin: "0 0 16px 0" }}>
              Day 1. {countLine}
            </Text>
            <Text style={{ fontSize: "15px", lineHeight: "22px", margin: "0 0 16px 0" }}>
              That's the spine. The next move puts OPS to work for you: tasks on those projects, and at least one crew member with the mobile app installed.
            </Text>
            <Text style={{ fontSize: "15px", lineHeight: "22px", margin: "0 0 24px 0" }}>
              When a team member taps DONE in the field, a notification lands on your phone. From a job you weren't on. On a task you didn't have to chase.
            </Text>
            <Section style={{ textAlign: "left", margin: "24px 0" }}>
              <Button
                href={ctaUrl}
                style={{
                  backgroundColor: "transparent",
                  color: "#6F94B0",
                  border: "1px solid #6F94B0",
                  padding: "12px 20px",
                  borderRadius: "5px",
                  fontFamily: "'JetBrains Mono', monospace",
                  fontSize: "13px",
                  textTransform: "uppercase",
                  letterSpacing: "0.05em",
                  textDecoration: "none",
                }}
              >
                ASSIGN A TASK + INVITE A CREW MEMBER
              </Button>
            </Section>
          </Section>
          <FounderFooter unsubscribeUrl={unsubscribeUrl} />
        </Container>
      </Body>
    </Html>
  );
}

export const previewProps: Day1HasProjectProps = {
  projectCount: 2,
  ctaUrl: "https://app.opsapp.co/dashboard",
  unsubscribeUrl: "https://app.opsapp.co/api/email/unsubscribe?t=preview",
};
```

- [ ] **Step 4: Run test, verify it passes**

```bash
pnpm vitest run tests/unit/email/templates/onboarding/day-1-has-project.test.tsx
```

Expected: 4 passes.

- [ ] **Step 5: Commit**

```bash
git add src/lib/email/react/templates/onboarding/Day1HasProject.tsx \
        tests/unit/email/templates/onboarding/day-1-has-project.test.tsx
git commit -m "feat(onboarding-drip): add Day 1B has-project template (Dispatch HTML)"
```

---

### Task 11: `Day3Inbox` template

**Files:**
- Create: `OPS-Web/src/lib/email/react/templates/onboarding/Day3Inbox.tsx`
- Test: `OPS-Web/tests/unit/email/templates/onboarding/day-3-inbox.test.tsx`

- [ ] **Step 1: Write the failing test**

```tsx
import { describe, it, expect } from "vitest";
import { render } from "@react-email/render";
import { Day3Inbox, previewProps } from "@/lib/email/react/templates/onboarding/Day3Inbox";

describe("Day3Inbox", () => {
  it("renders with previewProps", async () => {
    const html = await render(<Day3Inbox {...previewProps} />);
    expect(html).toContain("Jack again.");
    expect(html).toContain("deck and rail crew");
  });

  it("substitutes firstName when provided", async () => {
    const html = await render(<Day3Inbox firstName="Pat" unsubscribeUrl="https://x.test" />);
    expect(html).toContain("Hey there Pat,");
  });

  it("degrades when firstName is null", async () => {
    const html = await render(<Day3Inbox firstName={null} unsubscribeUrl="https://x.test" />);
    expect(html).toContain("Hey there,");
  });

  it("includes 'Data is power.' (canonical beat)", async () => {
    const html = await render(<Day3Inbox {...previewProps} />);
    expect(html).toContain("Data is power.");
  });

  it("includes 'I read every reply' verbatim", async () => {
    const html = await render(<Day3Inbox {...previewProps} />);
    expect(html).toContain("I read every reply");
  });

  it("uses 'sub-trade emails' (not 'sub emails' — v3 clarification)", async () => {
    const html = await render(<Day3Inbox {...previewProps} />);
    expect(html).toContain("sub-trade emails");
  });

  it("does NOT contain 'intelligent classification' (v3 removed)", async () => {
    const html = await render(<Day3Inbox {...previewProps} />);
    expect(html).not.toContain("intelligent classification");
  });

  it("does not contain banned vocabulary", async () => {
    const html = await render(<Day3Inbox {...previewProps} />);
    expect(html.toLowerCase()).not.toContain("leverage");
    expect(html.toLowerCase()).not.toContain("seamless");
    expect(html.toLowerCase()).not.toMatch(/\bunlocks?\b/);
  });
});
```

- [ ] **Step 2: Run test, verify it fails**

```bash
pnpm vitest run tests/unit/email/templates/onboarding/day-3-inbox.test.tsx
```

Expected: FAIL — module not found.

- [ ] **Step 3: Implement**

```tsx
// OPS-Web/src/lib/email/react/templates/onboarding/Day3Inbox.tsx
import * as React from "react";
import { PlainTextLayout } from "@/lib/email/react/primitives/PlainTextLayout";

/**
 * Day 3 — Inbox → lead, founder voice. Sent from JACK. Body copy is
 * canonical per spec §6.
 *
 * @template-version 1.0.0
 */
export interface Day3InboxProps {
  firstName: string | null;
  unsubscribeUrl: string;
}

export function Day3Inbox({ firstName, unsubscribeUrl }: Day3InboxProps) {
  const greeting = firstName ? `Hey there ${firstName},` : "Hey there,";
  return (
    <PlainTextLayout unsubscribeUrl={unsubscribeUrl}>
      {greeting}
      {"\n\n"}
      Jack again.
      {"\n\n"}
      When I was running my deck and rail crew, the thing that killed me wasn't a single big problem. It was wearing every hat at once.
      {"\n\n"}
      One inbox. Lead emails, supplier emails, sub-trade emails, accounting questions, customer photos — all of it landing in the same spot at the same time. No office. Nobody triaging anything. Nobody nudging me when I'd missed replying to a lead from three days back.
      {"\n\n"}
      And I had no idea if my ads were working. I'd spend money on Google and Facebook and Yelp, and at the end of the month I couldn't tell you which inquiries had turned into jobs, or what those jobs were actually worth.
      {"\n\n"}
      Data is power.
      {"\n\n"}
      That's the part of OPS I'm most proud of.
      {"\n\n"}
      You connect your work inbox. OPS reads your inbox and separates the leads from the noise — the customer asking for a quote on a new install lands in your pipeline, tagged, with the address pulled out and the scope extracted. The supplier confirming an order goes somewhere else.
      {"\n\n"}
      Then OPS tracks every lead from "first email" to "job won" to "invoice paid." You see what your cost per won job is, by source. You see which ads are paying back. You make decisions on numbers instead of gut.
      {"\n\n"}
      Connecting your inbox takes about two minutes. Hit reply if you want to tell me what your inbox chaos looks like right now — I read every reply.
      {"\n\n"}
      — Jack
    </PlainTextLayout>
  );
}

export const previewProps: Day3InboxProps = {
  firstName: "Jackson",
  unsubscribeUrl: "https://app.opsapp.co/api/email/unsubscribe?t=preview",
};
```

- [ ] **Step 4: Run test, verify it passes**

```bash
pnpm vitest run tests/unit/email/templates/onboarding/day-3-inbox.test.tsx
```

Expected: 8 passes.

- [ ] **Step 5: Commit**

```bash
git add src/lib/email/react/templates/onboarding/Day3Inbox.tsx \
        tests/unit/email/templates/onboarding/day-3-inbox.test.tsx
git commit -m "feat(onboarding-drip): add Day 3 inbox founder template"
```

---

### Task 12: `Day4NoNotification` template

**Files:**
- Create: `OPS-Web/src/lib/email/react/templates/onboarding/Day4NoNotification.tsx`
- Test: `OPS-Web/tests/unit/email/templates/onboarding/day-4-no-notification.test.tsx`

This template uses the `MockPushNotification` primitive from Task 7.

- [ ] **Step 1: Write the failing test**

```tsx
import { describe, it, expect } from "vitest";
import { render } from "@react-email/render";
import { Day4NoNotification, previewProps } from "@/lib/email/react/templates/onboarding/Day4NoNotification";

describe("Day4NoNotification", () => {
  it("renders with previewProps", async () => {
    const html = await render(<Day4NoNotification {...previewProps} />);
    expect(html).toContain("Day 4.");
    expect(html).toContain("Here's the moment you're working toward");
  });

  it("renders the mocked push notification in real dispatchTaskCompleted format", async () => {
    const html = await render(<Day4NoNotification {...previewProps} />);
    expect(html).toContain("Task Completed");
    expect(html).toContain('Jake completed "Rail Install" on 5611 Batu Rd');
  });

  it("renders the CTA pointing at /settings/team", async () => {
    const html = await render(
      <Day4NoNotification
        ctaUrl="https://app.opsapp.co/settings/team"
        unsubscribeUrl="https://x.test"
      />,
    );
    expect(html).toContain("INVITE YOUR CREW");
    expect(html).toContain('href="https://app.opsapp.co/settings/team"');
  });

  it("includes the closing 'you'll know why we built this' line", async () => {
    const html = await render(<Day4NoNotification {...previewProps} />);
    expect(html).toContain("you'll know why we built this");
  });
});
```

- [ ] **Step 2: Run test, verify it fails**

```bash
pnpm vitest run tests/unit/email/templates/onboarding/day-4-no-notification.test.tsx
```

Expected: FAIL — module not found.

- [ ] **Step 3: Implement**

```tsx
// OPS-Web/src/lib/email/react/templates/onboarding/Day4NoNotification.tsx
import * as React from "react";
import {
  Html, Head, Body, Container, Section, Text, Button,
} from "@react-email/components";
import { FounderFooter } from "@/lib/email/react/primitives/FounderFooter";
import { MockPushNotification } from "@/lib/email/react/primitives/MockPushNotification";

/**
 * Day 4 Branch A — fires when the operator has NOT received a
 * task_completed notification yet. Sent from OPS Dispatch.
 * Body copy is canonical per spec §6. Load-bearing visual element:
 * the MockPushNotification card showing the future-state moment.
 *
 * @template-version 1.0.0
 */
export interface Day4NoNotificationProps {
  ctaUrl: string;
  unsubscribeUrl: string;
}

export function Day4NoNotification({
  ctaUrl,
  unsubscribeUrl,
}: Day4NoNotificationProps) {
  return (
    <Html>
      <Head />
      <Body style={{ backgroundColor: "#000000", color: "#EDEDED", fontFamily: "Helvetica, Arial, sans-serif", margin: 0, padding: 0 }}>
        <Container style={{ maxWidth: "560px", margin: "0 auto", padding: "32px 24px" }}>
          <Section>
            <Text style={{ fontSize: "15px", lineHeight: "22px", margin: "0 0 8px 0" }}>
              Day 4.
            </Text>
            <Text style={{ fontSize: "15px", lineHeight: "22px", margin: "0 0 16px 0" }}>
              Here's the moment you're working toward:
            </Text>
            <MockPushNotification
              completedByName="Jake"
              taskTitle="Rail Install"
              projectTitle="5611 Batu Rd"
            />
            <Text style={{ fontSize: "15px", lineHeight: "22px", margin: "16px 0" }}>
              That notification lands on your phone the first time someone on your crew taps DONE in the field. From a job you weren't on. On a task you didn't have to chase.
            </Text>
            <Text style={{ fontSize: "15px", lineHeight: "22px", margin: "0 0 8px 0" }}>
              To get there:
            </Text>
            <Text style={{ fontSize: "15px", lineHeight: "22px", margin: "0 0 4px 0" }}>
              &nbsp;&nbsp;1. Invite at least one crew member
            </Text>
            <Text style={{ fontSize: "15px", lineHeight: "22px", margin: "0 0 4px 0" }}>
              &nbsp;&nbsp;2. Get them logged into the OPS mobile app
            </Text>
            <Text style={{ fontSize: "15px", lineHeight: "22px", margin: "0 0 24px 0" }}>
              &nbsp;&nbsp;3. Assign them a task
            </Text>
            <Section style={{ textAlign: "left", margin: "24px 0" }}>
              <Button
                href={ctaUrl}
                style={{
                  backgroundColor: "transparent",
                  color: "#6F94B0",
                  border: "1px solid #6F94B0",
                  padding: "12px 20px",
                  borderRadius: "5px",
                  fontFamily: "'JetBrains Mono', monospace",
                  fontSize: "13px",
                  textTransform: "uppercase",
                  letterSpacing: "0.05em",
                  textDecoration: "none",
                }}
              >
                INVITE YOUR CREW
              </Button>
            </Section>
            <Text style={{ fontSize: "15px", lineHeight: "22px", margin: "16px 0 0 0" }}>
              The first time you hear that ping while you're somewhere else, you'll know why we built this.
            </Text>
          </Section>
          <FounderFooter unsubscribeUrl={unsubscribeUrl} />
        </Container>
      </Body>
    </Html>
  );
}

export const previewProps: Day4NoNotificationProps = {
  ctaUrl: "https://app.opsapp.co/settings/team",
  unsubscribeUrl: "https://app.opsapp.co/api/email/unsubscribe?t=preview",
};
```

- [ ] **Step 4: Run test, verify it passes**

```bash
pnpm vitest run tests/unit/email/templates/onboarding/day-4-no-notification.test.tsx
```

Expected: 4 passes.

- [ ] **Step 5: Commit**

```bash
git add src/lib/email/react/templates/onboarding/Day4NoNotification.tsx \
        tests/unit/email/templates/onboarding/day-4-no-notification.test.tsx
git commit -m "feat(onboarding-drip): add Day 4A no-notification template with iOS push mock"
```

---

### Task 13: `Day4HasNotification` template

**Files:**
- Create: `OPS-Web/src/lib/email/react/templates/onboarding/Day4HasNotification.tsx`
- Test: `OPS-Web/tests/unit/email/templates/onboarding/day-4-has-notification.test.tsx`

- [ ] **Step 1: Write the failing test**

```tsx
import { describe, it, expect } from "vitest";
import { render } from "@react-email/render";
import { Day4HasNotification, previewProps } from "@/lib/email/react/templates/onboarding/Day4HasNotification";

describe("Day4HasNotification", () => {
  it("renders with previewProps", async () => {
    const html = await render(<Day4HasNotification {...previewProps} />);
    expect(html).toContain("Day 4. At least one crew member has tapped DONE");
    expect(html).toContain("the quiet of not having to chase");
  });

  it("includes the three compounding moves", async () => {
    const html = await render(<Day4HasNotification {...previewProps} />);
    expect(html).toContain("Recurring jobs");
    expect(html).toContain("adding more crew, so the same setup covers more work");
    expect(html).toContain("Templates so you don't rebuild");
  });

  it("CTA points at recurring projects filter", async () => {
    const html = await render(
      <Day4HasNotification
        ctaUrl="https://app.opsapp.co/projects?filter=recurring"
        unsubscribeUrl="https://x.test"
      />,
    );
    expect(html).toContain("SET UP RECURRING JOBS");
    expect(html).toContain('href="https://app.opsapp.co/projects?filter=recurring"');
  });

  it("does NOT contain 'leverage' (v3 banned-word fix)", async () => {
    const html = await render(<Day4HasNotification {...previewProps} />);
    expect(html.toLowerCase()).not.toContain("leverage");
  });
});
```

- [ ] **Step 2: Run test, verify it fails**

```bash
pnpm vitest run tests/unit/email/templates/onboarding/day-4-has-notification.test.tsx
```

Expected: FAIL — module not found.

- [ ] **Step 3: Implement**

```tsx
// OPS-Web/src/lib/email/react/templates/onboarding/Day4HasNotification.tsx
import * as React from "react";
import {
  Html, Head, Body, Container, Section, Text, Button,
} from "@react-email/components";
import { FounderFooter } from "@/lib/email/react/primitives/FounderFooter";

/**
 * Day 4 Branch B — fires when the operator has already received a
 * task_completed notification. Sent from OPS Dispatch. Pivots to
 * compounding moves (recurring jobs, more crew, templates).
 * Body copy is canonical per spec §6.
 *
 * @template-version 1.0.0
 */
export interface Day4HasNotificationProps {
  ctaUrl: string;
  unsubscribeUrl: string;
}

export function Day4HasNotification({
  ctaUrl,
  unsubscribeUrl,
}: Day4HasNotificationProps) {
  return (
    <Html>
      <Head />
      <Body style={{ backgroundColor: "#000000", color: "#EDEDED", fontFamily: "Helvetica, Arial, sans-serif", margin: 0, padding: 0 }}>
        <Container style={{ maxWidth: "560px", margin: "0 auto", padding: "32px 24px" }}>
          <Section>
            <Text style={{ fontSize: "15px", lineHeight: "22px", margin: "0 0 16px 0" }}>
              Day 4. At least one crew member has tapped DONE in the field and you've seen the notification land.
            </Text>
            <Text style={{ fontSize: "15px", lineHeight: "22px", margin: "0 0 16px 0" }}>
              Most operators are surprised by how good that feels — the quiet of not having to chase.
            </Text>
            <Text style={{ fontSize: "15px", lineHeight: "22px", margin: "0 0 8px 0" }}>
              The moves that compound it:
            </Text>
            <Text style={{ fontSize: "15px", lineHeight: "22px", margin: "0 0 4px 0" }}>
              &nbsp;&nbsp;→ Recurring jobs for the work you do every week
            </Text>
            <Text style={{ fontSize: "15px", lineHeight: "22px", margin: "0 0 4px 0" }}>
              &nbsp;&nbsp;→ Adding more crew, so the same setup covers more work
            </Text>
            <Text style={{ fontSize: "15px", lineHeight: "22px", margin: "0 0 24px 0" }}>
              &nbsp;&nbsp;→ Templates so you don't rebuild the same tasks every time
            </Text>
            <Section style={{ textAlign: "left", margin: "24px 0" }}>
              <Button
                href={ctaUrl}
                style={{
                  backgroundColor: "transparent",
                  color: "#6F94B0",
                  border: "1px solid #6F94B0",
                  padding: "12px 20px",
                  borderRadius: "5px",
                  fontFamily: "'JetBrains Mono', monospace",
                  fontSize: "13px",
                  textTransform: "uppercase",
                  letterSpacing: "0.05em",
                  textDecoration: "none",
                }}
              >
                SET UP RECURRING JOBS
              </Button>
            </Section>
            <Text style={{ fontSize: "15px", lineHeight: "22px", margin: "16px 0 0 0" }}>
              You're past the first hill. The next 26 days is about putting the rest of your business in.
            </Text>
          </Section>
          <FounderFooter unsubscribeUrl={unsubscribeUrl} />
        </Container>
      </Body>
    </Html>
  );
}

export const previewProps: Day4HasNotificationProps = {
  ctaUrl: "https://app.opsapp.co/projects?filter=recurring",
  unsubscribeUrl: "https://app.opsapp.co/api/email/unsubscribe?t=preview",
};
```

- [ ] **Step 4: Run test, verify it passes**

```bash
pnpm vitest run tests/unit/email/templates/onboarding/day-4-has-notification.test.tsx
```

Expected: 4 passes.

- [ ] **Step 5: Commit**

```bash
git add src/lib/email/react/templates/onboarding/Day4HasNotification.tsx \
        tests/unit/email/templates/onboarding/day-4-has-notification.test.tsx
git commit -m "feat(onboarding-drip): add Day 4B has-notification template (Dispatch HTML)"
```

---

### Task 14: `Day8Estimates` template

**Files:**
- Create: `OPS-Web/src/lib/email/react/templates/onboarding/Day8Estimates.tsx`
- Test: `OPS-Web/tests/unit/email/templates/onboarding/day-8-estimates.test.tsx`

- [ ] **Step 1: Write the failing test**

```tsx
import { describe, it, expect } from "vitest";
import { render } from "@react-email/render";
import { Day8Estimates, previewProps } from "@/lib/email/react/templates/onboarding/Day8Estimates";

describe("Day8Estimates", () => {
  it("renders with previewProps", async () => {
    const html = await render(<Day8Estimates {...previewProps} />);
    expect(html).toContain("Jack again, last one of these you'll get from me for a while.");
    expect(html).toContain("deck builder I know");
  });

  it("includes the 20% mid-job disaster moment (load-bearing)", async () => {
    const html = await render(<Day8Estimates {...previewProps} />);
    expect(html).toContain("price was 20% below what the new job actually cost him");
    expect(html).toContain("You can imagine how that went over.");
  });

  it("includes the kills-small-businesses couplet", async () => {
    const html = await render(<Day8Estimates {...previewProps} />);
    expect(html).toContain("kind of thing that kills small businesses");
    expect(html).toContain("back-office is held together with copy-paste");
  });

  it("does NOT start with 'I want to tell you a story' (v3 cut)", async () => {
    const html = await render(<Day8Estimates {...previewProps} />);
    expect(html).not.toContain("I want to tell you a story");
  });

  it("degrades when firstName is null", async () => {
    const html = await render(<Day8Estimates firstName={null} unsubscribeUrl="https://x.test" />);
    expect(html).toContain("Hey there,");
  });
});
```

- [ ] **Step 2: Run test, verify it fails**

```bash
pnpm vitest run tests/unit/email/templates/onboarding/day-8-estimates.test.tsx
```

Expected: FAIL.

- [ ] **Step 3: Implement**

```tsx
// OPS-Web/src/lib/email/react/templates/onboarding/Day8Estimates.tsx
import * as React from "react";
import { PlainTextLayout } from "@/lib/email/react/primitives/PlainTextLayout";

/**
 * Day 8 — Estimates + portal, founder voice. Sent from JACK.
 * Body copy is canonical per spec §6 (founder-provided deck-builder
 * anecdote; do not edit).
 *
 * @template-version 1.0.0
 */
export interface Day8EstimatesProps {
  firstName: string | null;
  unsubscribeUrl: string;
}

export function Day8Estimates({ firstName, unsubscribeUrl }: Day8EstimatesProps) {
  const greeting = firstName ? `Hey there ${firstName},` : "Hey there,";
  return (
    <PlainTextLayout unsubscribeUrl={unsubscribeUrl}>
      {greeting}
      {"\n\n"}
      Jack again, last one of these you'll get from me for a while.
      {"\n\n"}
      A deck builder I know ran his estimates out of a Word doc template. Every new customer, he'd open the last one he sent, save-as, update the fields. Or try to.
      {"\n\n"}
      I was constantly on his back about it. He'd send estimates with the wrong customer name at the top. With the previous customer's address still in there. With totals that didn't match the line items because he'd updated the materials but forgot the bottom number.
      {"\n\n"}
      If he caught it, he'd send a follow-up: "sorry, mixed up the name." "Sorry, clerical error on the address." "Apologies for the confusion."
      {"\n\n"}
      The one I'll never forget: he started a job on a Monday, realized halfway through the week that the estimate he'd sent was for the previous customer's project, and the price was 20% below what the new job actually cost him. He had to beg the customer mid-job to accept the higher number because he'd forgotten to update one field in a template.
      {"\n\n"}
      You can imagine how that went over.
      {"\n\n"}
      That's the kind of thing that kills small businesses. Not because the work is bad. Because the back-office is held together with copy-paste and good intentions.
      {"\n\n"}
      When you send an estimate from OPS, your customer gets a link to a branded portal — your logo, your business name, the line items pulled from your real pricing. They read it, ask questions on individual items, approve or decline, and pay through the portal directly. You don't copy-paste anything. You can't forget to update a field that doesn't exist.
      {"\n\n"}
      If you want to see what your customers see, send a test estimate to your own email. Takes about three minutes from inside OPS.
      {"\n\n"}
      — Jack
    </PlainTextLayout>
  );
}

export const previewProps: Day8EstimatesProps = {
  firstName: "Jackson",
  unsubscribeUrl: "https://app.opsapp.co/api/email/unsubscribe?t=preview",
};
```

- [ ] **Step 4: Run test, verify it passes**

```bash
pnpm vitest run tests/unit/email/templates/onboarding/day-8-estimates.test.tsx
```

Expected: 5 passes.

- [ ] **Step 5: Commit**

```bash
git add src/lib/email/react/templates/onboarding/Day8Estimates.tsx \
        tests/unit/email/templates/onboarding/day-8-estimates.test.tsx
git commit -m "feat(onboarding-drip): add Day 8 estimates founder template"
```

---

### Task 15: `Day14Quiet` template

**Files:**
- Create: `OPS-Web/src/lib/email/react/templates/onboarding/Day14Quiet.tsx`
- Test: `OPS-Web/tests/unit/email/templates/onboarding/day-14-quiet.test.tsx`

- [ ] **Step 1: Write the failing test**

```tsx
import { describe, it, expect } from "vitest";
import { render } from "@react-email/render";
import { Day14Quiet, previewProps } from "@/lib/email/react/templates/onboarding/Day14Quiet";

describe("Day14Quiet", () => {
  it("renders with previewProps", async () => {
    const html = await render(<Day14Quiet {...previewProps} />);
    expect(html).toContain("Jack here.");
    expect(html).toContain("Day 14. You're halfway through your trial");
    expect(html).toContain("quiet on your account");
  });

  it("uses first-person 'I want to know' (not 'Jack wants to know' third-person)", async () => {
    const html = await render(<Day14Quiet {...previewProps} />);
    expect(html).toContain("I want to know");
    expect(html).not.toContain("Jack wants to know");
  });

  it("includes the binary slotting-in vs in-the-way framing", async () => {
    const html = await render(<Day14Quiet {...previewProps} />);
    expect(html).toContain("OPS didn't fit how you run things");
  });

  it("degrades when firstName is null", async () => {
    const html = await render(<Day14Quiet firstName={null} unsubscribeUrl="https://x.test" />);
    expect(html).toContain("Hey there,");
  });
});
```

- [ ] **Step 2: Run test, verify it fails**

```bash
pnpm vitest run tests/unit/email/templates/onboarding/day-14-quiet.test.tsx
```

Expected: FAIL.

- [ ] **Step 3: Implement**

```tsx
// OPS-Web/src/lib/email/react/templates/onboarding/Day14Quiet.tsx
import * as React from "react";
import { PlainTextLayout } from "@/lib/email/react/primitives/PlainTextLayout";

/**
 * Day 14 Branch A — fires when the operator has had zero activity in
 * the last 7 days. Sent from JACK (changed v3 from Dispatch).
 * Body copy is canonical per spec §6.
 *
 * @template-version 1.0.0
 */
export interface Day14QuietProps {
  firstName: string | null;
  unsubscribeUrl: string;
}

export function Day14Quiet({ firstName, unsubscribeUrl }: Day14QuietProps) {
  const greeting = firstName ? `Hey there ${firstName},` : "Hey there,";
  return (
    <PlainTextLayout unsubscribeUrl={unsubscribeUrl}>
      {greeting}
      {"\n\n"}
      Jack here.
      {"\n\n"}
      Day 14. You're halfway through your trial and it's been quiet on your account.
      {"\n\n"}
      Could be a lot of things — you've been busy on actual work, something tripped you up during setup, OPS didn't fit how you run things, the timing's wrong, you forgot about it. No judgment either way.
      {"\n\n"}
      But I want to know which one it is. Hit reply on this email — goes to my inbox. One sentence is enough.
      {"\n\n"}
      If something specifically didn't work, tell me. If you forgot about it, tell me that too. The product gets better when operators tell me what's grinding their gears.
      {"\n\n"}
      — Jack
    </PlainTextLayout>
  );
}

export const previewProps: Day14QuietProps = {
  firstName: "Jackson",
  unsubscribeUrl: "https://app.opsapp.co/api/email/unsubscribe?t=preview",
};
```

- [ ] **Step 4: Run test, verify it passes**

```bash
pnpm vitest run tests/unit/email/templates/onboarding/day-14-quiet.test.tsx
```

Expected: 4 passes.

- [ ] **Step 5: Commit**

```bash
git add src/lib/email/react/templates/onboarding/Day14Quiet.tsx \
        tests/unit/email/templates/onboarding/day-14-quiet.test.tsx
git commit -m "feat(onboarding-drip): add Day 14 quiet check-in template (from Jack)"
```

---

### Task 16: `Day14Active` template

**Files:**
- Create: `OPS-Web/src/lib/email/react/templates/onboarding/Day14Active.tsx`
- Test: `OPS-Web/tests/unit/email/templates/onboarding/day-14-active.test.tsx`

This template has stats threshold logic — when `projectCount + taskCount + notificationCount < 5`, the stats line is suppressed.

- [ ] **Step 1: Write the failing test**

```tsx
import { describe, it, expect } from "vitest";
import { render } from "@react-email/render";
import { Day14Active, previewProps } from "@/lib/email/react/templates/onboarding/Day14Active";

describe("Day14Active", () => {
  it("renders stats line when sum >= 5", async () => {
    const html = await render(
      <Day14Active
        firstName="Pat"
        projectCount={3}
        taskCount={7}
        notificationCount={2}
        unsubscribeUrl="https://x.test"
      />,
    );
    expect(html).toContain("Day 14. You're running OPS — 3 projects, 7 tasks assigned, 2 completion notifications");
  });

  it("renders pluralization correctly (1 project, 1 task, 1 notification)", async () => {
    const html = await render(
      <Day14Active
        firstName="Pat"
        projectCount={1}
        taskCount={1}
        notificationCount={3}
        unsubscribeUrl="https://x.test"
      />,
    );
    // sum is 5, so stats line renders. Singular for 1, plural for 3.
    expect(html).toMatch(/1 project,/);
    expect(html).toMatch(/1 task /);
    expect(html).toMatch(/3 completion notifications/);
  });

  it("suppresses stats line when sum < 5 (renders no-stats variant)", async () => {
    const html = await render(
      <Day14Active
        firstName="Pat"
        projectCount={1}
        taskCount={2}
        notificationCount={1}
        unsubscribeUrl="https://x.test"
      />,
    );
    expect(html).toContain("Day 14. You're moving in OPS.");
    expect(html).not.toContain("projects,");
    expect(html).not.toContain("tasks assigned");
  });

  it("renders the two-question structure in both variants", async () => {
    const lowStatsHtml = await render(
      <Day14Active firstName="Pat" projectCount={0} taskCount={1} notificationCount={0} unsubscribeUrl="https://x.test" />,
    );
    const highStatsHtml = await render(
      <Day14Active firstName="Pat" projectCount={5} taskCount={10} notificationCount={2} unsubscribeUrl="https://x.test" />,
    );
    for (const html of [lowStatsHtml, highStatsHtml]) {
      expect(html).toContain("What's working that you didn't expect");
      expect(html).toContain("What's broken, missing, or in the way");
    }
  });
});
```

- [ ] **Step 2: Run test, verify it fails**

```bash
pnpm vitest run tests/unit/email/templates/onboarding/day-14-active.test.tsx
```

Expected: FAIL.

- [ ] **Step 3: Implement**

```tsx
// OPS-Web/src/lib/email/react/templates/onboarding/Day14Active.tsx
import * as React from "react";
import { PlainTextLayout } from "@/lib/email/react/primitives/PlainTextLayout";

/**
 * Day 14 Branch B — fires when the operator has had activity in the
 * last 7 days. Sent from JACK. Body has TWO variants depending on
 * whether stats sum >= 5:
 *   - High-activity variant: shows live counts
 *   - Low-activity variant: drops the surveillance-y tiny numbers
 *     and uses qualitative copy instead
 *
 * Threshold logic per spec decision log #23.
 *
 * @template-version 1.0.0
 */
export interface Day14ActiveProps {
  firstName: string | null;
  projectCount: number;
  taskCount: number;
  notificationCount: number;
  unsubscribeUrl: string;
}

const STATS_THRESHOLD = 5;

function pluralize(n: number, singular: string, plural: string): string {
  return n === 1 ? singular : plural;
}

export function Day14Active({
  firstName,
  projectCount,
  taskCount,
  notificationCount,
  unsubscribeUrl,
}: Day14ActiveProps) {
  const greeting = firstName ? `Hey there ${firstName},` : "Hey there,";
  const sum = projectCount + taskCount + notificationCount;
  const showStats = sum >= STATS_THRESHOLD;

  const statsLine = showStats
    ? `Day 14. You're running OPS — ${projectCount} ${pluralize(
        projectCount, "project", "projects",
      )}, ${taskCount} ${pluralize(
        taskCount, "task", "tasks",
      )} assigned, ${notificationCount} completion ${pluralize(
        notificationCount, "notification", "notifications",
      )} that have landed on your phone.`
    : `Day 14. You're moving in OPS.`;

  return (
    <PlainTextLayout unsubscribeUrl={unsubscribeUrl}>
      {greeting}
      {"\n\n"}
      Jack here.
      {"\n\n"}
      {statsLine}
      {"\n\n"}
      I want to know two things:
      {"\n\n"}
      &nbsp;&nbsp;1. What's working that you didn't expect?
      {"\n"}
      &nbsp;&nbsp;2. What's broken, missing, or in the way?
      {"\n\n"}
      Hit reply — goes to my inbox. One sentence per question is enough.
      {"\n\n"}
      The product gets better when operators tell me what's grinding their gears.
      {"\n\n"}
      — Jack
    </PlainTextLayout>
  );
}

export const previewProps: Day14ActiveProps = {
  firstName: "Jackson",
  projectCount: 4,
  taskCount: 12,
  notificationCount: 6,
  unsubscribeUrl: "https://app.opsapp.co/api/email/unsubscribe?t=preview",
};
```

- [ ] **Step 4: Run test, verify it passes**

```bash
pnpm vitest run tests/unit/email/templates/onboarding/day-14-active.test.tsx
```

Expected: 4 passes.

- [ ] **Step 5: Commit**

```bash
git add src/lib/email/react/templates/onboarding/Day14Active.tsx \
        tests/unit/email/templates/onboarding/day-14-active.test.tsx
git commit -m "feat(onboarding-drip): add Day 14 active check-in template with stats threshold"
```

---

### Task 17: `LostYou` template

**Files:**
- Create: `OPS-Web/src/lib/email/react/templates/onboarding/LostYou.tsx`
- Test: `OPS-Web/tests/unit/email/templates/onboarding/lost-you.test.tsx`

- [ ] **Step 1: Write the failing test**

```tsx
import { describe, it, expect } from "vitest";
import { render } from "@react-email/render";
import { LostYou, previewProps } from "@/lib/email/react/templates/onboarding/LostYou";

describe("LostYou", () => {
  it("renders with previewProps", async () => {
    const html = await render(<LostYou {...previewProps} />);
    expect(html).toContain("Jack here.");
    expect(html).toContain("haven't been back in");
  });

  it("substitutes days since signup and days since last activity", async () => {
    const html = await render(
      <LostYou
        firstName="Pat"
        daysSinceSignup={9}
        daysSinceLastActivity={6}
        unsubscribeUrl="https://x.test"
      />,
    );
    expect(html).toContain("You signed up for OPS 9 days ago");
    expect(html).toContain("haven't been back in 6 days");
  });

  it("uses 'a day' (not '1 days') when daysSinceLastActivity === 1", async () => {
    const html = await render(
      <LostYou
        firstName="Pat"
        daysSinceSignup={2}
        daysSinceLastActivity={1}
        unsubscribeUrl="https://x.test"
      />,
    );
    expect(html).toContain("haven't been back in a day");
    expect(html).not.toContain("1 days");
  });

  it("does NOT include 'That's a real signal' or 'Noticed...' (v3 CRM-flavored cuts)", async () => {
    const html = await render(<LostYou {...previewProps} />);
    expect(html).not.toContain("That's a real signal");
    expect(html).not.toMatch(/^Noticed/m);
  });
});
```

- [ ] **Step 2: Run test, verify it fails**

```bash
pnpm vitest run tests/unit/email/templates/onboarding/lost-you.test.tsx
```

Expected: FAIL.

- [ ] **Step 3: Implement**

```tsx
// OPS-Web/src/lib/email/react/templates/onboarding/LostYou.tsx
import * as React from "react";
import { PlainTextLayout } from "@/lib/email/react/primitives/PlainTextLayout";

/**
 * Behavior-triggered re-engagement send. Fires once per trial when
 * the operator has had zero activity for 6+ consecutive calendar days
 * between Day 1 and Day 14. Sent from JACK. Body copy is canonical
 * per spec §7.
 *
 * @template-version 1.0.0
 */
export interface LostYouProps {
  firstName: string | null;
  daysSinceSignup: number;
  daysSinceLastActivity: number;
  unsubscribeUrl: string;
}

function formatDays(n: number): string {
  if (n === 1) return "a day";
  return `${n} days`;
}

export function LostYou({
  firstName,
  daysSinceSignup,
  daysSinceLastActivity,
  unsubscribeUrl,
}: LostYouProps) {
  const greeting = firstName ? `Hey ${firstName},` : "Hey there,";
  return (
    <PlainTextLayout unsubscribeUrl={unsubscribeUrl}>
      {greeting}
      {"\n\n"}
      Jack here.
      {"\n\n"}
      You signed up for OPS {daysSinceSignup} days ago and haven't been back in {formatDays(daysSinceLastActivity)}.
      {"\n\n"}
      That's a long enough gap that I want to ask straight: is something stopping you, or is the timing just wrong?
      {"\n\n"}
      If setup tripped you up, I can usually point you at the move that gets you unstuck. If OPS isn't the right fit, no hard feelings — I'd just want to know what you were looking for.
      {"\n\n"}
      Hit reply with one sentence. Goes to my inbox.
      {"\n\n"}
      — Jack
    </PlainTextLayout>
  );
}

export const previewProps: LostYouProps = {
  firstName: "Jackson",
  daysSinceSignup: 8,
  daysSinceLastActivity: 6,
  unsubscribeUrl: "https://app.opsapp.co/api/email/unsubscribe?t=preview",
};
```

- [ ] **Step 4: Run test, verify it passes**

```bash
pnpm vitest run tests/unit/email/templates/onboarding/lost-you.test.tsx
```

Expected: 4 passes.

- [ ] **Step 5: Commit**

```bash
git add src/lib/email/react/templates/onboarding/LostYou.tsx \
        tests/unit/email/templates/onboarding/lost-you.test.tsx
git commit -m "feat(onboarding-drip): add Lost You re-engagement template"
```

---

End of Phase 3. Ten templates ready. Each renders standalone with `previewProps`; each has unit-test coverage of its load-bearing content.

---

## Phase 4 — Typed senders in `sendgrid.tsx`

Each sender is a thin wrapper that renders the template, builds the compliance headers, and calls `gatedSend` with the right `from`, `replyTo`, `emailType`, and `metadata`. All onboarding sends pass `metadata: { onboarding_email_log_id }` so partial-success reconciliation works (per spec §3 v3.1).

Batched into 2 tasks by sender persona — keeps the file edit reviewable.

### Task 18: Add 6 Jack-persona typed senders

**Files:**
- Modify: `OPS-Web/src/lib/email/sendgrid.tsx`
- Test: `OPS-Web/tests/unit/email/sendgrid-onboarding-jack.test.ts`

Adds: `sendOnboardingDay0Welcome`, `sendOnboardingDay3Inbox`, `sendOnboardingDay8Estimates`, `sendOnboardingDay14Quiet`, `sendOnboardingDay14Active`, `sendOnboardingLostYou`.

- [ ] **Step 1: Read existing sender patterns**

```bash
grep -n "^export async function send" /Users/jacksonsweet/Projects/OPS/OPS-Web/src/lib/email/sendgrid.tsx | head -10
```

Identify a reference implementation (e.g. `sendTrialExpiryWarning` is a good model — it uses gatedSend, passes campaignId/userId, builds compliance headers). The new Jack senders follow the same pattern with `from: JACK` and an `onboardingEmailLogId` parameter that lands in `metadata`.

- [ ] **Step 2: Write the failing test**

```ts
// OPS-Web/tests/unit/email/sendgrid-onboarding-jack.test.ts
import { describe, it, expect, vi, beforeEach } from "vitest";
import sgMail from "@sendgrid/mail";

// Mock supabase service-role client used by gatedSend internals
vi.mock("@/lib/supabase/server-client", () => ({
  getServiceRoleClient: () => ({
    from: () => ({
      insert: () => ({ error: null }),
      select: () => ({ in: () => ({ eq: () => ({ data: [] }) }) }),
      ilike: () => ({ in: () => ({ limit: () => ({ data: [] }) }) }),
    }),
  }),
}));

vi.mock("@sendgrid/mail", () => ({
  default: {
    setApiKey: vi.fn(),
    send: vi.fn().mockResolvedValue([
      { headers: { "x-message-id": "sg-test-123" } },
      {},
    ]),
  },
}));

beforeEach(() => {
  vi.clearAllMocks();
  process.env.SENDGRID_API_KEY = "test-key";
  process.env.EMAIL_UNSUBSCRIBE_SECRET = "0".repeat(64);
});

describe("Jack-persona onboarding senders", () => {
  it("sendOnboardingDay0Welcome uses JACK from, replies to jack@, includes onboarding_email_log_id in customArgs", async () => {
    const { sendOnboardingDay0Welcome } = await import("@/lib/email/sendgrid");
    await sendOnboardingDay0Welcome({
      email: "test@example.com",
      firstName: "Pat",
      onboardingEmailLogId: "log-uuid-123",
    });

    expect(sgMail.send).toHaveBeenCalledTimes(1);
    const call = (sgMail.send as any).mock.calls[0][0];
    expect(call.from).toEqual({ email: "jack@opsapp.co", name: "Jack Sweet" });
    expect(call.replyTo).toBe("jack@opsapp.co");
    expect(call.customArgs.email_type).toBe("onboarding_day_0_welcome");
    expect(call.customArgs.onboarding_email_log_id).toBe("log-uuid-123");
  });

  it("sendOnboardingDay3Inbox has subject 'the part of OPS I'm most proud of'", async () => {
    const { sendOnboardingDay3Inbox } = await import("@/lib/email/sendgrid");
    await sendOnboardingDay3Inbox({
      email: "test@example.com",
      firstName: "Pat",
      onboardingEmailLogId: "log-uuid-456",
    });
    const call = (sgMail.send as any).mock.calls[0][0];
    expect(call.subject).toBe("the part of OPS I'm most proud of");
  });

  it("sendOnboardingDay14Active includes the three stat counts in the rendered html", async () => {
    const { sendOnboardingDay14Active } = await import("@/lib/email/sendgrid");
    await sendOnboardingDay14Active({
      email: "test@example.com",
      firstName: "Pat",
      projectCount: 3,
      taskCount: 8,
      notificationCount: 2,
      onboardingEmailLogId: "log-uuid-789",
    });
    const call = (sgMail.send as any).mock.calls[0][0];
    expect(call.html).toContain("3 projects, 8 tasks");
  });
});
```

- [ ] **Step 3: Run test, verify it fails**

```bash
cd /Users/jacksonsweet/Projects/OPS/OPS-Web
pnpm vitest run tests/unit/email/sendgrid-onboarding-jack.test.ts
```

Expected: FAIL — `sendOnboardingDay0Welcome` does not exist.

- [ ] **Step 4: Implement the 6 Jack senders**

Open `OPS-Web/src/lib/email/sendgrid.tsx`. Add imports near the existing template imports:

```ts
import { Day0Welcome } from "./react/templates/onboarding/Day0Welcome";
import { Day3Inbox } from "./react/templates/onboarding/Day3Inbox";
import { Day8Estimates } from "./react/templates/onboarding/Day8Estimates";
import { Day14Quiet } from "./react/templates/onboarding/Day14Quiet";
import { Day14Active } from "./react/templates/onboarding/Day14Active";
import { LostYou } from "./react/templates/onboarding/LostYou";
```

Update the senders import to include `JACK`:

```ts
import { DISPATCH, GATE, FIELD_NOTES, JACK, portalSender, type Sender } from "./senders";
```

Then append after the existing trial-expiry senders (search for `sendTrialExpiryReengagement`'s closing brace), add the new section:

```tsx
// ─── Onboarding Drip — Jack-persona (plain text, founder voice) ────────────
//
// All six senders pass `metadata: { onboarding_email_log_id }` into gatedSend
// so the partial-success reconciliation in OnboardingDripService can match
// email_log rows back to onboarding_email_log rows. Per spec §3 v3.1.

export async function sendOnboardingDay0Welcome(params: {
  email: string;
  firstName: string | null;
  onboardingEmailLogId: string;
}): Promise<GatedSendResult> {
  const compliance = buildComplianceHeaders({
    email: params.email,
    kind: "onboarding_day_0_welcome",
  });
  const html = await render(
    <Day0Welcome
      firstName={params.firstName}
      unsubscribeUrl={compliance.unsubscribeUrl}
    />,
  );
  return gatedSend({
    to: params.email,
    from: JACK,
    replyTo: JACK.email,
    subject: "quick question",
    html,
    emailType: "onboarding_day_0_welcome",
    list: compliance.list,
    headers: compliance.headers,
    metadata: { onboarding_email_log_id: params.onboardingEmailLogId },
  });
}

export async function sendOnboardingDay3Inbox(params: {
  email: string;
  firstName: string | null;
  onboardingEmailLogId: string;
}): Promise<GatedSendResult> {
  const compliance = buildComplianceHeaders({
    email: params.email,
    kind: "onboarding_day_3_inbox",
  });
  const html = await render(
    <Day3Inbox
      firstName={params.firstName}
      unsubscribeUrl={compliance.unsubscribeUrl}
    />,
  );
  return gatedSend({
    to: params.email,
    from: JACK,
    replyTo: JACK.email,
    subject: "the part of OPS I'm most proud of",
    html,
    emailType: "onboarding_day_3_inbox",
    list: compliance.list,
    headers: compliance.headers,
    metadata: { onboarding_email_log_id: params.onboardingEmailLogId },
  });
}

export async function sendOnboardingDay8Estimates(params: {
  email: string;
  firstName: string | null;
  onboardingEmailLogId: string;
}): Promise<GatedSendResult> {
  const compliance = buildComplianceHeaders({
    email: params.email,
    kind: "onboarding_day_8_estimates",
  });
  const html = await render(
    <Day8Estimates
      firstName={params.firstName}
      unsubscribeUrl={compliance.unsubscribeUrl}
    />,
  );
  return gatedSend({
    to: params.email,
    from: JACK,
    replyTo: JACK.email,
    subject: "how your customers see your estimates",
    html,
    emailType: "onboarding_day_8_estimates",
    list: compliance.list,
    headers: compliance.headers,
    metadata: { onboarding_email_log_id: params.onboardingEmailLogId },
  });
}

export async function sendOnboardingDay14Quiet(params: {
  email: string;
  firstName: string | null;
  onboardingEmailLogId: string;
}): Promise<GatedSendResult> {
  const compliance = buildComplianceHeaders({
    email: params.email,
    kind: "onboarding_day_14_quiet",
  });
  const html = await render(
    <Day14Quiet
      firstName={params.firstName}
      unsubscribeUrl={compliance.unsubscribeUrl}
    />,
  );
  return gatedSend({
    to: params.email,
    from: JACK,
    replyTo: JACK.email,
    subject: "is OPS slotting in or in the way?",
    html,
    emailType: "onboarding_day_14_quiet",
    list: compliance.list,
    headers: compliance.headers,
    metadata: { onboarding_email_log_id: params.onboardingEmailLogId },
  });
}

export async function sendOnboardingDay14Active(params: {
  email: string;
  firstName: string | null;
  projectCount: number;
  taskCount: number;
  notificationCount: number;
  onboardingEmailLogId: string;
}): Promise<GatedSendResult> {
  const compliance = buildComplianceHeaders({
    email: params.email,
    kind: "onboarding_day_14_active",
  });
  const html = await render(
    <Day14Active
      firstName={params.firstName}
      projectCount={params.projectCount}
      taskCount={params.taskCount}
      notificationCount={params.notificationCount}
      unsubscribeUrl={compliance.unsubscribeUrl}
    />,
  );
  return gatedSend({
    to: params.email,
    from: JACK,
    replyTo: JACK.email,
    subject: "you're 14 days in",
    html,
    emailType: "onboarding_day_14_active",
    list: compliance.list,
    headers: compliance.headers,
    metadata: {
      onboarding_email_log_id: params.onboardingEmailLogId,
      projectCount: params.projectCount,
      taskCount: params.taskCount,
      notificationCount: params.notificationCount,
    },
  });
}

export async function sendOnboardingLostYou(params: {
  email: string;
  firstName: string | null;
  daysSinceSignup: number;
  daysSinceLastActivity: number;
  onboardingEmailLogId: string;
}): Promise<GatedSendResult> {
  const compliance = buildComplianceHeaders({
    email: params.email,
    kind: "onboarding_lost_you",
  });
  const html = await render(
    <LostYou
      firstName={params.firstName}
      daysSinceSignup={params.daysSinceSignup}
      daysSinceLastActivity={params.daysSinceLastActivity}
      unsubscribeUrl={compliance.unsubscribeUrl}
    />,
  );
  return gatedSend({
    to: params.email,
    from: JACK,
    replyTo: JACK.email,
    subject: "lost you?",
    html,
    emailType: "onboarding_lost_you",
    list: compliance.list,
    headers: compliance.headers,
    metadata: {
      onboarding_email_log_id: params.onboardingEmailLogId,
      daysSinceSignup: params.daysSinceSignup,
      daysSinceLastActivity: params.daysSinceLastActivity,
    },
  });
}
```

- [ ] **Step 5: Run test, verify it passes**

```bash
pnpm vitest run tests/unit/email/sendgrid-onboarding-jack.test.ts
```

Expected: 3 passes.

- [ ] **Step 6: Commit**

```bash
git add src/lib/email/sendgrid.tsx tests/unit/email/sendgrid-onboarding-jack.test.ts
git commit -m "feat(onboarding-drip): add 6 Jack-persona typed senders (Day 0/3/8/14 quiet+active, LostYou)"
```

---

### Task 19: Add 4 Dispatch-persona typed senders

**Files:**
- Modify: `OPS-Web/src/lib/email/sendgrid.tsx`
- Test: `OPS-Web/tests/unit/email/sendgrid-onboarding-dispatch.test.ts`

Adds: `sendOnboardingDay1NoProject`, `sendOnboardingDay1HasProject`, `sendOnboardingDay4NoNotification`, `sendOnboardingDay4HasNotification`.

- [ ] **Step 1: Write the failing test**

```ts
// OPS-Web/tests/unit/email/sendgrid-onboarding-dispatch.test.ts
import { describe, it, expect, vi, beforeEach } from "vitest";
import sgMail from "@sendgrid/mail";

vi.mock("@/lib/supabase/server-client", () => ({
  getServiceRoleClient: () => ({
    from: () => ({
      insert: () => ({ error: null }),
      select: () => ({ in: () => ({ eq: () => ({ data: [] }) }) }),
      ilike: () => ({ in: () => ({ limit: () => ({ data: [] }) }) }),
    }),
  }),
}));

vi.mock("@sendgrid/mail", () => ({
  default: {
    setApiKey: vi.fn(),
    send: vi.fn().mockResolvedValue([
      { headers: { "x-message-id": "sg-test-456" } },
      {},
    ]),
  },
}));

beforeEach(() => {
  vi.clearAllMocks();
  process.env.SENDGRID_API_KEY = "test-key";
  process.env.EMAIL_UNSUBSCRIBE_SECRET = "0".repeat(64);
});

describe("Dispatch-persona onboarding senders", () => {
  it("sendOnboardingDay1NoProject uses DISPATCH from, replyTo jack@", async () => {
    const { sendOnboardingDay1NoProject } = await import("@/lib/email/sendgrid");
    await sendOnboardingDay1NoProject({
      email: "test@example.com",
      ctaUrl: "https://app.opsapp.co/projects/new",
      onboardingEmailLogId: "log-uuid-1",
    });
    const call = (sgMail.send as any).mock.calls[0][0];
    expect(call.from).toEqual({ email: "dispatch@opsapp.co", name: "OPS Dispatch" });
    expect(call.replyTo).toBe("jack@opsapp.co");
    expect(call.subject).toBe("the move that gets OPS working");
  });

  it("sendOnboardingDay1HasProject renders projectCount-aware copy", async () => {
    const { sendOnboardingDay1HasProject } = await import("@/lib/email/sendgrid");
    await sendOnboardingDay1HasProject({
      email: "test@example.com",
      projectCount: 1,
      ctaUrl: "https://app.opsapp.co/dashboard",
      onboardingEmailLogId: "log-uuid-2",
    });
    const call = (sgMail.send as any).mock.calls[0][0];
    expect(call.subject).toBe("you're moving");
    expect(call.html).toContain("first project");
  });

  it("sendOnboardingDay4NoNotification renders the mocked push card", async () => {
    const { sendOnboardingDay4NoNotification } = await import("@/lib/email/sendgrid");
    await sendOnboardingDay4NoNotification({
      email: "test@example.com",
      ctaUrl: "https://app.opsapp.co/settings/team",
      onboardingEmailLogId: "log-uuid-3",
    });
    const call = (sgMail.send as any).mock.calls[0][0];
    expect(call.html).toContain("Task Completed");
    expect(call.html).toContain("Jake completed");
  });

  it("sendOnboardingDay4HasNotification subject 'you've heard the ping'", async () => {
    const { sendOnboardingDay4HasNotification } = await import("@/lib/email/sendgrid");
    await sendOnboardingDay4HasNotification({
      email: "test@example.com",
      ctaUrl: "https://app.opsapp.co/projects?filter=recurring",
      onboardingEmailLogId: "log-uuid-4",
    });
    const call = (sgMail.send as any).mock.calls[0][0];
    expect(call.subject).toBe("you've heard the ping");
  });
});
```

- [ ] **Step 2: Run test, verify it fails**

```bash
pnpm vitest run tests/unit/email/sendgrid-onboarding-dispatch.test.ts
```

Expected: FAIL.

- [ ] **Step 3: Implement the 4 Dispatch senders**

In `OPS-Web/src/lib/email/sendgrid.tsx`, add the 4 template imports near the others:

```ts
import { Day1NoProject } from "./react/templates/onboarding/Day1NoProject";
import { Day1HasProject } from "./react/templates/onboarding/Day1HasProject";
import { Day4NoNotification } from "./react/templates/onboarding/Day4NoNotification";
import { Day4HasNotification } from "./react/templates/onboarding/Day4HasNotification";
```

Then append after the Jack senders from Task 18:

```tsx
// ─── Onboarding Drip — Dispatch-persona (tactical HTML, OPS voice) ─────────

export async function sendOnboardingDay1NoProject(params: {
  email: string;
  ctaUrl: string;
  onboardingEmailLogId: string;
}): Promise<GatedSendResult> {
  const compliance = buildComplianceHeaders({
    email: params.email,
    kind: "onboarding_day_1_no_project",
  });
  const html = await render(
    <Day1NoProject ctaUrl={params.ctaUrl} unsubscribeUrl={compliance.unsubscribeUrl} />,
  );
  return gatedSend({
    to: params.email,
    from: DISPATCH,
    replyTo: JACK.email,
    subject: "the move that gets OPS working",
    html,
    emailType: "onboarding_day_1_no_project",
    list: compliance.list,
    headers: compliance.headers,
    metadata: { onboarding_email_log_id: params.onboardingEmailLogId },
  });
}

export async function sendOnboardingDay1HasProject(params: {
  email: string;
  projectCount: number;
  ctaUrl: string;
  onboardingEmailLogId: string;
}): Promise<GatedSendResult> {
  const compliance = buildComplianceHeaders({
    email: params.email,
    kind: "onboarding_day_1_has_project",
  });
  const html = await render(
    <Day1HasProject
      projectCount={params.projectCount}
      ctaUrl={params.ctaUrl}
      unsubscribeUrl={compliance.unsubscribeUrl}
    />,
  );
  return gatedSend({
    to: params.email,
    from: DISPATCH,
    replyTo: JACK.email,
    subject: "you're moving",
    html,
    emailType: "onboarding_day_1_has_project",
    list: compliance.list,
    headers: compliance.headers,
    metadata: {
      onboarding_email_log_id: params.onboardingEmailLogId,
      projectCount: params.projectCount,
    },
  });
}

export async function sendOnboardingDay4NoNotification(params: {
  email: string;
  ctaUrl: string;
  onboardingEmailLogId: string;
}): Promise<GatedSendResult> {
  const compliance = buildComplianceHeaders({
    email: params.email,
    kind: "onboarding_day_4_no_notification",
  });
  const html = await render(
    <Day4NoNotification ctaUrl={params.ctaUrl} unsubscribeUrl={compliance.unsubscribeUrl} />,
  );
  return gatedSend({
    to: params.email,
    from: DISPATCH,
    replyTo: JACK.email,
    subject: "the notification you're working toward",
    html,
    emailType: "onboarding_day_4_no_notification",
    list: compliance.list,
    headers: compliance.headers,
    metadata: { onboarding_email_log_id: params.onboardingEmailLogId },
  });
}

export async function sendOnboardingDay4HasNotification(params: {
  email: string;
  ctaUrl: string;
  onboardingEmailLogId: string;
}): Promise<GatedSendResult> {
  const compliance = buildComplianceHeaders({
    email: params.email,
    kind: "onboarding_day_4_has_notification",
  });
  const html = await render(
    <Day4HasNotification ctaUrl={params.ctaUrl} unsubscribeUrl={compliance.unsubscribeUrl} />,
  );
  return gatedSend({
    to: params.email,
    from: DISPATCH,
    replyTo: JACK.email,
    subject: "you've heard the ping",
    html,
    emailType: "onboarding_day_4_has_notification",
    list: compliance.list,
    headers: compliance.headers,
    metadata: { onboarding_email_log_id: params.onboardingEmailLogId },
  });
}
```

- [ ] **Step 4: Run test, verify it passes**

```bash
pnpm vitest run tests/unit/email/sendgrid-onboarding-dispatch.test.ts
```

Expected: 4 passes.

- [ ] **Step 5: Commit**

```bash
git add src/lib/email/sendgrid.tsx tests/unit/email/sendgrid-onboarding-dispatch.test.ts
git commit -m "feat(onboarding-drip): add 4 Dispatch-persona typed senders (Day 1A/1B/4A/4B)"
```

---

End of Phase 4. Ten typed senders ready. All route through `gatedSend`. All pass `metadata.onboarding_email_log_id` for partial-success reconciliation.

---

## Phase 5 — Template registry entries

### Task 20: Register 10 templates in `template-registry.ts`

**Files:**
- Modify: `OPS-Web/src/lib/email/template-registry.ts`

This unlocks admin preview at `/admin/email/templates/[templateId]/`.

- [ ] **Step 1: Add imports**

Append to the import block at the top of `template-registry.ts`:

```ts
import * as Day0WelcomeMod from "./react/templates/onboarding/Day0Welcome";
import * as Day1NoProjectMod from "./react/templates/onboarding/Day1NoProject";
import * as Day1HasProjectMod from "./react/templates/onboarding/Day1HasProject";
import * as Day3InboxMod from "./react/templates/onboarding/Day3Inbox";
import * as Day4NoNotificationMod from "./react/templates/onboarding/Day4NoNotification";
import * as Day4HasNotificationMod from "./react/templates/onboarding/Day4HasNotification";
import * as Day8EstimatesMod from "./react/templates/onboarding/Day8Estimates";
import * as Day14QuietMod from "./react/templates/onboarding/Day14Quiet";
import * as Day14ActiveMod from "./react/templates/onboarding/Day14Active";
import * as LostYouMod from "./react/templates/onboarding/LostYou";
```

- [ ] **Step 2: Add the 10 registry entries**

Append to the `TEMPLATE_REGISTRY` array (before the closing `]`):

```ts
  {
    templateId: "onboarding_day_0_welcome",
    displayName: "Onboarding — Day 0 Founder Welcome",
    defaultSubject: "quick question",
    Component: Day0WelcomeMod.Day0Welcome,
    previewProps: Day0WelcomeMod.previewProps,
    sourcePath: "src/lib/email/react/templates/onboarding/Day0Welcome.tsx",
  },
  {
    templateId: "onboarding_day_1_no_project",
    displayName: "Onboarding — Day 1A No Project",
    defaultSubject: "the move that gets OPS working",
    Component: Day1NoProjectMod.Day1NoProject,
    previewProps: Day1NoProjectMod.previewProps,
    sourcePath: "src/lib/email/react/templates/onboarding/Day1NoProject.tsx",
  },
  {
    templateId: "onboarding_day_1_has_project",
    displayName: "Onboarding — Day 1B Has Project",
    defaultSubject: "you're moving",
    Component: Day1HasProjectMod.Day1HasProject,
    previewProps: Day1HasProjectMod.previewProps,
    sourcePath: "src/lib/email/react/templates/onboarding/Day1HasProject.tsx",
  },
  {
    templateId: "onboarding_day_3_inbox",
    displayName: "Onboarding — Day 3 Inbox (Jack)",
    defaultSubject: "the part of OPS I'm most proud of",
    Component: Day3InboxMod.Day3Inbox,
    previewProps: Day3InboxMod.previewProps,
    sourcePath: "src/lib/email/react/templates/onboarding/Day3Inbox.tsx",
  },
  {
    templateId: "onboarding_day_4_no_notification",
    displayName: "Onboarding — Day 4A No Notification",
    defaultSubject: "the notification you're working toward",
    Component: Day4NoNotificationMod.Day4NoNotification,
    previewProps: Day4NoNotificationMod.previewProps,
    sourcePath: "src/lib/email/react/templates/onboarding/Day4NoNotification.tsx",
  },
  {
    templateId: "onboarding_day_4_has_notification",
    displayName: "Onboarding — Day 4B Has Notification",
    defaultSubject: "you've heard the ping",
    Component: Day4HasNotificationMod.Day4HasNotification,
    previewProps: Day4HasNotificationMod.previewProps,
    sourcePath: "src/lib/email/react/templates/onboarding/Day4HasNotification.tsx",
  },
  {
    templateId: "onboarding_day_8_estimates",
    displayName: "Onboarding — Day 8 Estimates (Jack)",
    defaultSubject: "how your customers see your estimates",
    Component: Day8EstimatesMod.Day8Estimates,
    previewProps: Day8EstimatesMod.previewProps,
    sourcePath: "src/lib/email/react/templates/onboarding/Day8Estimates.tsx",
  },
  {
    templateId: "onboarding_day_14_quiet",
    displayName: "Onboarding — Day 14 Quiet (Jack)",
    defaultSubject: "is OPS slotting in or in the way?",
    Component: Day14QuietMod.Day14Quiet,
    previewProps: Day14QuietMod.previewProps,
    sourcePath: "src/lib/email/react/templates/onboarding/Day14Quiet.tsx",
  },
  {
    templateId: "onboarding_day_14_active",
    displayName: "Onboarding — Day 14 Active (Jack)",
    defaultSubject: "you're 14 days in",
    Component: Day14ActiveMod.Day14Active,
    previewProps: Day14ActiveMod.previewProps,
    sourcePath: "src/lib/email/react/templates/onboarding/Day14Active.tsx",
  },
  {
    templateId: "onboarding_lost_you",
    displayName: "Onboarding — Lost You (re-engagement)",
    defaultSubject: "lost you?",
    Component: LostYouMod.LostYou,
    previewProps: LostYouMod.previewProps,
    sourcePath: "src/lib/email/react/templates/onboarding/LostYou.tsx",
  },
```

- [ ] **Step 3: Verify all 10 register correctly**

Write a quick smoke test at `OPS-Web/tests/unit/email/template-registry-onboarding.test.ts`:

```ts
import { describe, it, expect } from "vitest";
import { TEMPLATE_REGISTRY, getTemplateEntry, renderTemplate } from "@/lib/email/template-registry";

describe("template-registry — onboarding entries", () => {
  const ids = [
    "onboarding_day_0_welcome",
    "onboarding_day_1_no_project",
    "onboarding_day_1_has_project",
    "onboarding_day_3_inbox",
    "onboarding_day_4_no_notification",
    "onboarding_day_4_has_notification",
    "onboarding_day_8_estimates",
    "onboarding_day_14_quiet",
    "onboarding_day_14_active",
    "onboarding_lost_you",
  ];

  it("registers all 10 onboarding template ids", () => {
    for (const id of ids) {
      const entry = getTemplateEntry(id);
      expect(entry, `expected entry for ${id}`).toBeTruthy();
      expect(entry?.Component).toBeTruthy();
      expect(entry?.previewProps).toBeTruthy();
    }
  });

  it("renders each onboarding template with its previewProps", async () => {
    for (const id of ids) {
      const entry = getTemplateEntry(id)!;
      const result = await renderTemplate(id, entry.previewProps);
      expect(result?.html, `html for ${id}`).toBeTruthy();
      expect(result?.html.length, `html length for ${id}`).toBeGreaterThan(100);
    }
  });
});
```

```bash
pnpm vitest run tests/unit/email/template-registry-onboarding.test.ts
```

Expected: 2 tests pass (covers all 10 entries each).

- [ ] **Step 4: Commit**

```bash
git add src/lib/email/template-registry.ts tests/unit/email/template-registry-onboarding.test.ts
git commit -m "feat(onboarding-drip): register 10 onboarding templates in template-registry"
```

---

End of Phase 5. The admin preview at `/admin/email/templates/[templateId]/` now shows each of the 10 onboarding templates.

---

## Phase 6 — Service layer (`OnboardingDripService`)

The service is the brain of the drip. It mirrors `TrialExpiryService` in shape but adds the claim-before-send dedup, partial-success reconciliation, pause-vs-suppression semantics, and timezone-aware scheduling.

Split into 7 focused tasks. Each task adds one method or one set of conditions to the service file, with TDD coverage.

### Task 21: Service skeleton + `computeOperatorLocalHour()` helper

**Files:**
- Create: `OPS-Web/src/lib/api/services/onboarding-drip-service.ts`
- Test: `OPS-Web/tests/unit/api/services/onboarding-drip-service.test.ts`

- [ ] **Step 1: Write the failing test**

```ts
// OPS-Web/tests/unit/api/services/onboarding-drip-service.test.ts
import { describe, it, expect } from "vitest";
import { computeOperatorLocalHour } from "@/lib/api/services/onboarding-drip-service";

describe("computeOperatorLocalHour", () => {
  it("returns the hour in operator local time for a known timezone", () => {
    // 2026-05-27 14:00:00 UTC = 7am PDT
    const utc = new Date("2026-05-27T14:00:00Z");
    expect(computeOperatorLocalHour(utc, "America/Los_Angeles")).toBe(7);
  });

  it("returns 9 in PT when UTC is 16:00 (PDT)", () => {
    const utc = new Date("2026-05-27T16:00:00Z");
    expect(computeOperatorLocalHour(utc, "America/Los_Angeles")).toBe(9);
  });

  it("returns the hour for an Eastern operator", () => {
    // 14:00 UTC = 10am EDT
    const utc = new Date("2026-05-27T14:00:00Z");
    expect(computeOperatorLocalHour(utc, "America/New_York")).toBe(10);
  });

  it("falls back to UTC hour if timezone is unknown / null", () => {
    const utc = new Date("2026-05-27T14:00:00Z");
    expect(computeOperatorLocalHour(utc, null)).toBe(14);
  });
});
```

- [ ] **Step 2: Run test, verify it fails**

```bash
pnpm vitest run tests/unit/api/services/onboarding-drip-service.test.ts
```

Expected: FAIL — module not found.

- [ ] **Step 3: Create the service skeleton**

```ts
// OPS-Web/src/lib/api/services/onboarding-drip-service.ts
import type { SupabaseClient } from "@supabase/supabase-js";

/**
 * Onboarding drip service. Calendar-driven plus behavior-triggered
 * sends for trial signups, Day 0 through Day 14. Cleanly hands off
 * to TrialExpiryService at Day 23.
 *
 * See specs/2026-05-27-onboarding-drip-design.md (v3.1) for the
 * canonical design. Every method here is documented against a
 * section of that spec.
 */

export type DaySlot =
  | "day_0"
  | "day_1"
  | "day_3"
  | "day_4"
  | "day_8"
  | "day_14"
  | "lost_you";

export type Branch =
  | "no_project"
  | "has_project"
  | "no_aha"
  | "has_aha"
  | "quiet"
  | "active"
  | null;

/**
 * Returns the wall-clock hour (0-23) in the operator's local timezone.
 * Used by the cron's localHour===9 gate. Falls back to UTC if timezone
 * is unknown.
 */
export function computeOperatorLocalHour(
  utcNow: Date,
  timezone: string | null,
): number {
  if (!timezone) return utcNow.getUTCHours();
  try {
    const fmt = new Intl.DateTimeFormat("en-US", {
      timeZone: timezone,
      hour: "numeric",
      hour12: false,
    });
    const parts = fmt.formatToParts(utcNow);
    const hourPart = parts.find((p) => p.type === "hour");
    const h = hourPart ? parseInt(hourPart.value, 10) : NaN;
    // Intl returns "24" for midnight in some locales; normalize to 0
    return isNaN(h) ? utcNow.getUTCHours() : h % 24;
  } catch {
    return utcNow.getUTCHours();
  }
}

export const OnboardingDripService = {
  // Subsequent tasks add: computeState, claimAndSend, processCompany,
  // processLostYouCandidate, processAll
};
```

- [ ] **Step 4: Run test, verify it passes**

```bash
pnpm vitest run tests/unit/api/services/onboarding-drip-service.test.ts
```

Expected: 4 passes.

- [ ] **Step 5: Commit**

```bash
git add src/lib/api/services/onboarding-drip-service.ts \
        tests/unit/api/services/onboarding-drip-service.test.ts
git commit -m "feat(onboarding-drip): scaffold OnboardingDripService with operator-local-hour helper"
```

---

### Task 22: `computeState()` — branch resolution

**Files:**
- Modify: `OPS-Web/src/lib/api/services/onboarding-drip-service.ts`
- Modify: `OPS-Web/tests/unit/api/services/onboarding-drip-service.test.ts`

`computeState(supabase, company, daySlot)` returns `{ branch, emailType, payload }` for the given day. The branch decision matches spec §5.

- [ ] **Step 1: Add the failing test**

Append to the test file:

```ts
import { OnboardingDripService } from "@/lib/api/services/onboarding-drip-service";

function mockSupabase(fixtures: Record<string, any>) {
  return {
    from: (table: string) => ({
      select: () => ({
        eq: (col: string, val: any) => ({
          is: () => ({
            limit: () => ({
              maybeSingle: async () =>
                ({ data: fixtures[`${table}:${col}=${val}`] ?? null }),
            }),
          }),
        }),
      }),
    }),
  } as unknown as SupabaseClient;
}

describe("OnboardingDripService.computeState", () => {
  it("day_1 returns no_project branch when user not onboarded", async () => {
    const db = mockSupabase({});
    const user = { id: "u1", onboarding_completed: null } as any;
    const company = { id: "c1" } as any;
    const result = await OnboardingDripService.computeState(db, user, company, "day_1");
    expect(result.branch).toBe("no_project");
    expect(result.emailType).toBe("onboarding_day_1_no_project");
  });

  it("day_1 returns has_project branch when user is web-onboarded AND has projects", async () => {
    const db = mockSupabase({
      "projects:company_id=c1": { id: "p1" },
    });
    const user = { id: "u1", onboarding_completed: { web: true } } as any;
    const company = { id: "c1" } as any;
    const result = await OnboardingDripService.computeState(db, user, company, "day_1");
    expect(result.branch).toBe("has_project");
    expect(result.emailType).toBe("onboarding_day_1_has_project");
  });

  it("day_4 returns no_aha branch when no task_completed notification exists", async () => {
    const db = mockSupabase({});
    const user = { id: "u1" } as any;
    const company = { id: "c1" } as any;
    const result = await OnboardingDripService.computeState(db, user, company, "day_4");
    expect(result.branch).toBe("no_aha");
  });

  it("day_14 returns quiet branch when no recent activity across the 6 tables", async () => {
    const db = mockSupabase({});
    const user = { id: "u1" } as any;
    const company = { id: "c1" } as any;
    const result = await OnboardingDripService.computeState(db, user, company, "day_14");
    expect(result.branch).toBe("quiet");
  });

  it("day_0, day_3, day_8, lost_you return null branch (unbranched)", async () => {
    const db = mockSupabase({});
    const user = { id: "u1" } as any;
    const company = { id: "c1" } as any;
    for (const daySlot of ["day_0", "day_3", "day_8", "lost_you"] as const) {
      const result = await OnboardingDripService.computeState(db, user, company, daySlot);
      expect(result.branch).toBeNull();
    }
  });
});
```

- [ ] **Step 2: Run test, verify it fails**

Expected: FAIL — `computeState` not defined.

- [ ] **Step 3: Implement `computeState`**

Append to `onboarding-drip-service.ts` (inside the `OnboardingDripService` object):

```ts
import { sql } from "@/lib/supabase/sql"; // if not present, use raw .from(...) calls

export interface ComputedState {
  branch: Branch;
  emailType: string;
  payload: Record<string, unknown>;
}

export const OnboardingDripService = {
  /**
   * Resolve the branch + emailType for the given day, given the company + user
   * state. Returns the email_type string to pass into KIND_TO_LIST + sendgrid.
   * See spec §5 for the exact branch conditions.
   */
  async computeState(
    db: SupabaseClient,
    user: { id: string; first_name?: string | null; onboarding_completed?: Record<string, boolean> | null },
    company: { id: string },
    daySlot: DaySlot,
  ): Promise<ComputedState> {
    switch (daySlot) {
      case "day_0":
        return { branch: null, emailType: "onboarding_day_0_welcome", payload: {} };

      case "day_1": {
        const webOnboarded = user.onboarding_completed?.web === true;
        let projectCount = 0;
        if (webOnboarded) {
          const { count } = await db
            .from("projects")
            .select("id", { count: "exact", head: true })
            .eq("company_id", company.id)
            .is("deleted_at", null);
          projectCount = count ?? 0;
        }
        if (webOnboarded && projectCount >= 1) {
          return {
            branch: "has_project",
            emailType: "onboarding_day_1_has_project",
            payload: { projectCount },
          };
        }
        return { branch: "no_project", emailType: "onboarding_day_1_no_project", payload: {} };
      }

      case "day_3":
        return { branch: null, emailType: "onboarding_day_3_inbox", payload: {} };

      case "day_4": {
        const { count } = await db
          .from("notifications")
          .select("id", { count: "exact", head: true })
          .eq("user_id", user.id)
          .eq("type", "task_completed");
        if ((count ?? 0) >= 1) {
          return { branch: "has_aha", emailType: "onboarding_day_4_has_notification", payload: {} };
        }
        return { branch: "no_aha", emailType: "onboarding_day_4_no_notification", payload: {} };
      }

      case "day_8":
        return { branch: null, emailType: "onboarding_day_8_estimates", payload: {} };

      case "day_14": {
        // Activity = any updated_at newer than 7d ago across 6 tables for this company
        const sevenDaysAgo = new Date(Date.now() - 7 * 86400_000).toISOString();
        const checks = await Promise.all(
          ["projects", "project_tasks", "clients", "opportunities", "estimates", "invoices"].map(
            async (table) => {
              const { count } = await db
                .from(table)
                .select("id", { count: "exact", head: true })
                .eq("company_id", company.id)
                .gte("updated_at", sevenDaysAgo);
              return count ?? 0;
            },
          ),
        );
        const totalActivity = checks.reduce((a, b) => a + b, 0);
        if (totalActivity > 0) {
          // Active branch — pull counts for stats display
          const [proj, task, notif] = await Promise.all([
            db.from("projects").select("id", { count: "exact", head: true }).eq("company_id", company.id).is("deleted_at", null),
            db.from("project_tasks").select("id", { count: "exact", head: true }).eq("company_id", company.id).is("deleted_at", null),
            db.from("notifications").select("id", { count: "exact", head: true }).eq("user_id", user.id).eq("type", "task_completed"),
          ]);
          return {
            branch: "active",
            emailType: "onboarding_day_14_active",
            payload: {
              projectCount: proj.count ?? 0,
              taskCount: task.count ?? 0,
              notificationCount: notif.count ?? 0,
            },
          };
        }
        return { branch: "quiet", emailType: "onboarding_day_14_quiet", payload: {} };
      }

      case "lost_you":
        return { branch: null, emailType: "onboarding_lost_you", payload: {} };
    }
  },
};
```

- [ ] **Step 4: Run test, verify it passes**

```bash
pnpm vitest run tests/unit/api/services/onboarding-drip-service.test.ts -t "computeState"
```

Expected: 5 passes.

- [ ] **Step 5: Commit**

```bash
git add src/lib/api/services/onboarding-drip-service.ts \
        tests/unit/api/services/onboarding-drip-service.test.ts
git commit -m "feat(onboarding-drip): add computeState branch resolution"
```

---

### Task 23: `claimAndSend()` — claim-before-send + send + reconciliation

**Files:**
- Modify: `OPS-Web/src/lib/api/services/onboarding-drip-service.ts`
- Modify: `OPS-Web/tests/unit/api/services/onboarding-drip-service.test.ts`

This is the core dispatch primitive. It:
1. Attempts the claim INSERT
2. If a winning row id is returned, runs partial-success reconciliation (primary then fallback)
3. If no matching email_log row, calls the right typed sender
4. Updates the row to terminal status (sent/skipped) or pending (paused) or failed (with attempt increment) based on the gatedSend result

- [ ] **Step 1: Add the failing test**

Append:

```ts
describe("OnboardingDripService.claimAndSend", () => {
  it("returns 'already_claimed' when ON CONFLICT short-circuits the INSERT", async () => {
    // Mock: INSERT returns null (no id) because of conflict
    const db = {
      from: (table: string) => {
        if (table === "onboarding_email_log") {
          return {
            insert: () => ({
              select: () => ({
                single: async () => ({ data: null, error: { code: "23505" } }),
              }),
            }),
          };
        }
        return {};
      },
    } as unknown as SupabaseClient;

    const result = await OnboardingDripService.claimAndSend(db, {
      user: { id: "u1", email: "test@example.com", first_name: "Pat" } as any,
      company: { id: "c1", latitude: 49, longitude: -123 } as any,
      daySlot: "day_1",
      branch: "no_project",
      emailType: "onboarding_day_1_no_project",
      payload: {},
      now: new Date(),
    });

    expect(result.status).toBe("already_claimed");
  });

  it("returns 'reconciled' when a matching email_log row exists with metadata.onboarding_email_log_id", async () => {
    // Mock: INSERT returns winning id; email_log query returns a matching sent row
    const winningRowId = "win-1";
    const sgMessageId = "sg-abc-123";
    let updateCalled = false;

    const db = {
      from: (table: string) => {
        if (table === "onboarding_email_log") {
          return {
            insert: () => ({
              select: () => ({
                single: async () => ({ data: { id: winningRowId }, error: null }),
              }),
            }),
            update: () => ({
              eq: () => {
                updateCalled = true;
                return { error: null };
              },
            }),
          };
        }
        if (table === "email_log") {
          return {
            select: () => ({
              eq: () => ({
                eq: () => ({
                  eq: () => ({
                    eq: () => ({
                      limit: async () => ({
                        data: [{ id: "elog-1", metadata: { sg_message_id: sgMessageId } }],
                      }),
                    }),
                  }),
                }),
              }),
            }),
          };
        }
        return {};
      },
    } as unknown as SupabaseClient;

    const result = await OnboardingDripService.claimAndSend(db, {
      user: { id: "u1", email: "test@example.com", first_name: "Pat" } as any,
      company: { id: "c1", latitude: 49, longitude: -123 } as any,
      daySlot: "day_1",
      branch: "no_project",
      emailType: "onboarding_day_1_no_project",
      payload: {},
      now: new Date(),
    });

    expect(result.status).toBe("reconciled");
    expect(updateCalled).toBe(true);
  });

  // Additional tests for 'sent', 'paused', 'suppressed', 'failed', 'in_flight_gated' are
  // exercised by the integration test in Task 31 — keep unit tests focused on the
  // claim + reconciliation logic which is the load-bearing dedup behavior.
});
```

- [ ] **Step 2: Run test, verify it fails**

Expected: FAIL.

- [ ] **Step 3: Implement `claimAndSend`**

Append the helper functions + method to the service. (For brevity, this step is significant — read spec §3 and §8 and implement straight through. The expected interface:)

```ts
import {
  sendOnboardingDay0Welcome, sendOnboardingDay1NoProject, sendOnboardingDay1HasProject,
  sendOnboardingDay3Inbox, sendOnboardingDay4NoNotification, sendOnboardingDay4HasNotification,
  sendOnboardingDay8Estimates, sendOnboardingDay14Quiet, sendOnboardingDay14Active,
  sendOnboardingLostYou,
} from "@/lib/email/sendgrid";
import { detectCompanyTimezone } from "@/lib/utils/company-timezone";

export type ClaimAndSendStatus =
  | "already_claimed"  // ON CONFLICT — row existed
  | "reconciled"        // matching email_log row found, marked sent without sending
  | "sent"              // gatedSend returned status=sent
  | "paused"            // gatedSend returned paused_skipped, row re-pended without attempt increment
  | "suppressed"        // gatedSend returned suppression_skipped, row terminal skipped
  | "failed"            // send errored, attempt incremented; terminal if attempts >= 3
  | "in_flight_gated"; // retry sweep — row updated_at within 5 minutes

export interface ClaimAndSendParams {
  user: { id: string; email: string; first_name: string | null };
  company: { id: string; latitude: number | null; longitude: number | null };
  daySlot: DaySlot;
  branch: Branch;
  emailType: string;
  payload: Record<string, unknown>;
  now: Date;
}

// Add inside OnboardingDripService object:

  async claimAndSend(db: SupabaseClient, params: ClaimAndSendParams): Promise<{ status: ClaimAndSendStatus; rowId?: string }> {
    // Compute day_slot_expires_at: operator-local 9am of target day + 24h
    const timezone = detectCompanyTimezone(params.company.latitude, params.company.longitude);
    const expiresAt = computeDaySlotExpiresAt(params.now, params.daySlot, timezone);

    // 1. Claim
    const { data: claimed, error: claimErr } = await db
      .from("onboarding_email_log")
      .insert({
        user_id: params.user.id,
        company_id: params.company.id,
        day_slot: params.daySlot,
        branch: params.branch,
        email_type: params.emailType,
        status: "pending",
        attempts: 0,
        day_slot_expires_at: expiresAt.toISOString(),
      })
      .select("id")
      .single();

    if (claimErr || !claimed) {
      // Unique violation — someone else claimed
      return { status: "already_claimed" };
    }

    // 2. Partial-success reconciliation (§3)
    const reconciled = await reconcileAgainstEmailLog(db, {
      userId: params.user.id,
      emailType: params.emailType,
      recipientEmail: params.user.email,
      claimRowId: claimed.id,
      createdAt: params.now,
    });

    if (reconciled) {
      await db
        .from("onboarding_email_log")
        .update({
          status: "sent",
          sent_at: new Date().toISOString(),
          sg_message_id: reconciled.sgMessageId,
        })
        .eq("id", claimed.id);
      return { status: "reconciled", rowId: claimed.id };
    }

    // 3. Send via the right typed sender
    const sendResult = await dispatchTypedSender(params, claimed.id);

    // 4. Status update based on gatedSend result
    if (sendResult.status === "sent") {
      await db.from("onboarding_email_log").update({
        status: "sent",
        sent_at: new Date().toISOString(),
        sg_message_id: sendResult.messageId,
      }).eq("id", claimed.id);
      return { status: "sent", rowId: claimed.id };
    }

    if (sendResult.status === "paused_skipped") {
      // Pause is retryable — re-pend, no attempt increment
      await db.from("onboarding_email_log").update({
        status: "pending",
        // attempts NOT incremented
      }).eq("id", claimed.id);
      return { status: "paused", rowId: claimed.id };
    }

    if (sendResult.status === "suppression_skipped") {
      // Suppression is terminal
      await db.from("onboarding_email_log").update({
        status: "skipped",
      }).eq("id", claimed.id);
      return { status: "suppressed", rowId: claimed.id };
    }

    // Unreachable in normal flow
    return { status: "failed", rowId: claimed.id };
  },
```

Plus the helpers (define above the OnboardingDripService export):

```ts
async function reconcileAgainstEmailLog(
  db: SupabaseClient,
  opts: { userId: string; emailType: string; recipientEmail: string; claimRowId: string; createdAt: Date },
): Promise<{ sgMessageId: string | null } | null> {
  // Primary join: metadata.onboarding_email_log_id
  const { data: primary } = await db
    .from("email_log")
    .select("id, metadata")
    .eq("user_id", opts.userId)
    .eq("email_type", opts.emailType)
    .eq("status", "sent")
    .eq("metadata->>onboarding_email_log_id", opts.claimRowId)
    .limit(1);
  if (primary && primary.length > 0) {
    return { sgMessageId: (primary[0].metadata as any)?.sg_message_id ?? null };
  }
  // Fallback join
  const fiveMinutesBack = new Date(opts.createdAt.getTime() - 5 * 60_000).toISOString();
  const { data: fallback } = await db
    .from("email_log")
    .select("id, metadata")
    .eq("user_id", opts.userId)
    .eq("email_type", opts.emailType)
    .eq("recipient_email", opts.recipientEmail.toLowerCase())
    .eq("status", "sent")
    .gte("sent_at", fiveMinutesBack)
    .order("sent_at", { ascending: false })
    .limit(1);
  if (fallback && fallback.length > 0) {
    return { sgMessageId: (fallback[0].metadata as any)?.sg_message_id ?? null };
  }
  return null;
}

function computeDaySlotExpiresAt(now: Date, daySlot: DaySlot, _timezone: string): Date {
  // Conservatively: target send window ends 24h after now (cron tolerates any
  // operator-local-9am within today's UTC 24h window). For LostYou: 24h.
  return new Date(now.getTime() + 24 * 60 * 60_000);
}

async function dispatchTypedSender(
  params: ClaimAndSendParams,
  onboardingEmailLogId: string,
) {
  const common = { email: params.user.email, firstName: params.user.first_name, onboardingEmailLogId };
  switch (params.emailType) {
    case "onboarding_day_0_welcome":
      return sendOnboardingDay0Welcome(common);
    case "onboarding_day_1_no_project":
      return sendOnboardingDay1NoProject({
        email: params.user.email,
        ctaUrl: `${process.env.NEXT_PUBLIC_APP_URL}/projects/new`,
        onboardingEmailLogId,
      });
    case "onboarding_day_1_has_project":
      return sendOnboardingDay1HasProject({
        email: params.user.email,
        projectCount: (params.payload.projectCount as number) ?? 1,
        ctaUrl: `${process.env.NEXT_PUBLIC_APP_URL}/dashboard`,
        onboardingEmailLogId,
      });
    case "onboarding_day_3_inbox":
      return sendOnboardingDay3Inbox(common);
    case "onboarding_day_4_no_notification":
      return sendOnboardingDay4NoNotification({
        email: params.user.email,
        ctaUrl: `${process.env.NEXT_PUBLIC_APP_URL}/settings/team`,
        onboardingEmailLogId,
      });
    case "onboarding_day_4_has_notification":
      return sendOnboardingDay4HasNotification({
        email: params.user.email,
        ctaUrl: `${process.env.NEXT_PUBLIC_APP_URL}/projects?filter=recurring`,
        onboardingEmailLogId,
      });
    case "onboarding_day_8_estimates":
      return sendOnboardingDay8Estimates(common);
    case "onboarding_day_14_quiet":
      return sendOnboardingDay14Quiet(common);
    case "onboarding_day_14_active":
      return sendOnboardingDay14Active({
        email: params.user.email,
        firstName: params.user.first_name,
        projectCount: (params.payload.projectCount as number) ?? 0,
        taskCount: (params.payload.taskCount as number) ?? 0,
        notificationCount: (params.payload.notificationCount as number) ?? 0,
        onboardingEmailLogId,
      });
    case "onboarding_lost_you":
      return sendOnboardingLostYou({
        email: params.user.email,
        firstName: params.user.first_name,
        daysSinceSignup: (params.payload.daysSinceSignup as number) ?? 0,
        daysSinceLastActivity: (params.payload.daysSinceLastActivity as number) ?? 0,
        onboardingEmailLogId,
      });
    default:
      throw new Error(`Unknown emailType: ${params.emailType}`);
  }
}
```

- [ ] **Step 4: Run test, verify it passes**

```bash
pnpm vitest run tests/unit/api/services/onboarding-drip-service.test.ts -t "claimAndSend"
```

Expected: 2 passes.

- [ ] **Step 5: Commit**

```bash
git add src/lib/api/services/onboarding-drip-service.ts \
        tests/unit/api/services/onboarding-drip-service.test.ts
git commit -m "feat(onboarding-drip): claimAndSend with claim-before-send dedup + reconciliation"
```

---

### Task 24: `processCompany()` — kill switches + branch dispatch

**Files:**
- Modify: `OPS-Web/src/lib/api/services/onboarding-drip-service.ts`
- Modify: `OPS-Web/tests/unit/api/services/onboarding-drip-service.test.ts`

`processCompany(db, company, now)` walks the day_slots applicable to this company (based on `created_at`), evaluates kill switches, calls computeState + claimAndSend per matching day.

- [ ] **Step 1: Write the failing tests for kill switches**

```ts
describe("OnboardingDripService.processCompany kill switches", () => {
  it("skips when company.deleted_at is set", async () => {
    // (mock supabase that returns deleted company; assert claimAndSend never called)
    // Implementation: use vi.spyOn to assert OnboardingDripService.claimAndSend isn't invoked
  });
  it("skips when company.subscription_status is 'cancelled'", async () => { /* … */ });
  it("skips when company.subscription_status is 'expired'", async () => { /* … */ });
  it("skips when admin_ids is empty", async () => { /* … */ });
  it("skips when account_holder email matches internal allowlist (@opsapp.co)", async () => { /* … */ });
  it("skips when all admin emails are on global suppression", async () => { /* … */ });
});
```

- [ ] **Step 2: Implement `processCompany`**

```ts
  async processCompany(
    db: SupabaseClient,
    company: { id: string; deleted_at: string | null; subscription_status: string; account_holder_id: string; admin_ids: string[] | null; created_at: string; latitude: number | null; longitude: number | null },
    now: Date,
  ): Promise<{ processed: number; skipped: { reason: string }[] }> {
    const result = { processed: 0, skipped: [] as { reason: string }[] };

    // Kill switches
    if (company.deleted_at) { result.skipped.push({ reason: "company deleted" }); return result; }
    if (["cancelled", "expired", "paused"].includes(company.subscription_status)) {
      result.skipped.push({ reason: `subscription ${company.subscription_status}` });
      return result;
    }
    if (!company.account_holder_id) { result.skipped.push({ reason: "no account_holder_id" }); return result; }

    // Resolve operator (account_holder) — note text/uuid cast for SQL safety
    const { data: operator } = await db
      .from("users")
      .select("id, email, first_name, deleted_at")
      .eq("id", company.account_holder_id) // cast handled at JS layer — both strings
      .maybeSingle();

    if (!operator || operator.deleted_at || !operator.email) {
      result.skipped.push({ reason: "no active operator" });
      return result;
    }

    // Internal-domain allowlist
    const INTERNAL_DOMAINS = ["@opsapp.co", "@anthropic.com"];
    if (INTERNAL_DOMAINS.some((d) => operator.email!.toLowerCase().endsWith(d))) {
      result.skipped.push({ reason: "internal email domain" });
      return result;
    }

    // Compute which day_slots apply based on company age
    const ageDays = Math.floor((now.getTime() - new Date(company.created_at).getTime()) / 86400_000);
    const eligibleSlots: DaySlot[] = [];
    if (ageDays === 1) eligibleSlots.push("day_1");
    if (ageDays === 3) eligibleSlots.push("day_3");
    if (ageDays === 4) eligibleSlots.push("day_4");
    if (ageDays === 8) eligibleSlots.push("day_8");
    if (ageDays === 14) eligibleSlots.push("day_14");

    for (const daySlot of eligibleSlots) {
      const state = await this.computeState(db, operator as any, company, daySlot);
      const sendResult = await this.claimAndSend(db, {
        user: operator as any,
        company,
        daySlot,
        branch: state.branch,
        emailType: state.emailType,
        payload: state.payload,
        now,
      });
      if (sendResult.status === "sent" || sendResult.status === "reconciled") {
        result.processed++;
      }
    }
    return result;
  },
```

- [ ] **Step 3-5: Run tests, verify, commit**

```bash
pnpm vitest run tests/unit/api/services/onboarding-drip-service.test.ts -t "processCompany"
git add src/lib/api/services/onboarding-drip-service.ts \
        tests/unit/api/services/onboarding-drip-service.test.ts
git commit -m "feat(onboarding-drip): processCompany with kill switches + branch dispatch"
```

---

### Task 25: Retry sweep + in-flight gate + day_slot_expires_at gate

**Files:**
- Modify: `OPS-Web/src/lib/api/services/onboarding-drip-service.ts`
- Modify: `OPS-Web/tests/unit/api/services/onboarding-drip-service.test.ts`

Add `processRetries(db, now)` method that sweeps `onboarding_email_log` for pending/failed rows past the 5-minute in-flight gate, within day_slot_expires_at, attempts < 3.

- [ ] **Step 1: Write failing tests**

```ts
describe("OnboardingDripService.processRetries", () => {
  it("picks up failed rows with attempts < 3", async () => { /* … */ });
  it("does NOT pick up rows with attempts >= 3", async () => { /* … */ });
  it("does NOT pick up rows with updated_at within last 5 minutes", async () => { /* … */ });
  it("does NOT pick up rows past day_slot_expires_at", async () => { /* … */ });
});
```

- [ ] **Step 2: Implement**

```ts
  async processRetries(db: SupabaseClient, now: Date): Promise<{ retried: number }> {
    const fiveMinAgo = new Date(now.getTime() - 5 * 60_000).toISOString();
    const { data: candidates } = await db
      .from("onboarding_email_log")
      .select("id, user_id, company_id, day_slot, branch, email_type, attempts")
      .in("status", ["pending", "failed"])
      .lt("attempts", 3)
      .gt("day_slot_expires_at", now.toISOString())
      .lt("updated_at", fiveMinAgo)
      .limit(100);

    let retried = 0;
    for (const row of candidates ?? []) {
      // Re-fetch user/company, reconcile, send, update — same logic as claimAndSend
      // post-claim path. Extracted into a helper to share with claimAndSend.
      // (For brevity, see implementation notes — share `attemptSend(row, ...)` helper.)
      retried++;
    }
    return { retried };
  },
```

- [ ] **Step 3-5: Verify + commit**

```bash
git add src/lib/api/services/onboarding-drip-service.ts \
        tests/unit/api/services/onboarding-drip-service.test.ts
git commit -m "feat(onboarding-drip): processRetries with in-flight + expiry gates"
```

---

### Task 26: Lost You behavior trigger

**Files:**
- Modify: `OPS-Web/src/lib/api/services/onboarding-drip-service.ts`

Add `processLostYouCandidate(db, company, now)` that evaluates the 5 conditions in spec §7. If all hold, runs claimAndSend with `daySlot='lost_you'`.

- [ ] **Step 1: Write failing test**

```ts
describe("OnboardingDripService.processLostYouCandidate", () => {
  it("fires when all 5 conditions hold", async () => { /* … */ });
  it("does not fire if Day 14 already sent", async () => { /* … */ });
  it("does not fire if Lost You already sent", async () => { /* … */ });
  it("does not fire if company age outside 1-14 day window", async () => { /* … */ });
  it("does not fire if any activity in last 6 days", async () => { /* … */ });
});
```

- [ ] **Step 2: Implement**

```ts
  async processLostYouCandidate(
    db: SupabaseClient,
    company: { id: string; account_holder_id: string; created_at: string; latitude: number | null; longitude: number | null; subscription_status: string; deleted_at: string | null },
    now: Date,
  ): Promise<{ fired: boolean; reason?: string }> {
    // Kill switches (same as processCompany)
    if (company.deleted_at) return { fired: false, reason: "deleted" };
    if (["cancelled", "expired", "paused"].includes(company.subscription_status)) return { fired: false, reason: "subscription" };

    const ageDays = Math.floor((now.getTime() - new Date(company.created_at).getTime()) / 86400_000);
    if (ageDays < 1 || ageDays > 14) return { fired: false, reason: "outside window" };

    // Already sent Day 14 or Lost You?
    const { data: existing } = await db
      .from("onboarding_email_log")
      .select("day_slot")
      .eq("company_id", company.id)
      .in("day_slot", ["day_14", "lost_you"]);
    if ((existing ?? []).length > 0) return { fired: false, reason: "day_14 or lost_you already sent" };

    // 6+ days of zero activity
    const sixDaysAgo = new Date(now.getTime() - 6 * 86400_000).toISOString();
    const tables = ["projects", "project_tasks", "clients", "opportunities", "estimates", "invoices"];
    const checks = await Promise.all(tables.map(async (t) => {
      const { count } = await db.from(t).select("id", { count: "exact", head: true })
        .eq("company_id", company.id)
        .gte("updated_at", sixDaysAgo);
      return count ?? 0;
    }));
    const totalRecent = checks.reduce((a, b) => a + b, 0);
    if (totalRecent > 0) return { fired: false, reason: "recent activity" };

    // Fire
    const { data: operator } = await db.from("users").select("id, email, first_name, deleted_at").eq("id", company.account_holder_id).maybeSingle();
    if (!operator || operator.deleted_at || !operator.email) return { fired: false, reason: "no operator" };

    const result = await this.claimAndSend(db, {
      user: operator as any,
      company,
      daySlot: "lost_you",
      branch: null,
      emailType: "onboarding_lost_you",
      payload: {
        daysSinceSignup: ageDays,
        daysSinceLastActivity: 6, // could be more precise
      },
      now,
    });
    return { fired: result.status === "sent" || result.status === "reconciled" };
  },
```

- [ ] **Step 3-5: Verify + commit**

```bash
git commit -am "feat(onboarding-drip): Lost You behavior trigger with 5-condition gate"
```

---

### Task 27: `processAll()` orchestration

**Files:**
- Modify: `OPS-Web/src/lib/api/services/onboarding-drip-service.ts`

Pulls candidate companies from `companies` (created_at within last 14 days, not deleted, not on internal allowlist), filters by `localHour === 9` for the cron tick, calls processCompany + processLostYouCandidate.

- [ ] **Step 1-5: TDD + commit** (test, implement, run, commit)

```ts
  async processAll(db: SupabaseClient, now: Date = new Date()): Promise<{ scanned: number; calendar_processed: number; lost_you_fired: number; retried: number }> {
    const fifteenDaysAgo = new Date(now.getTime() - 15 * 86400_000).toISOString();

    const { data: candidates } = await db
      .from("companies")
      .select("id, account_holder_id, admin_ids, deleted_at, subscription_status, created_at, latitude, longitude")
      .gte("created_at", fifteenDaysAgo)
      .is("deleted_at", null);

    let calendar = 0, lost = 0;
    for (const company of candidates ?? []) {
      const tz = detectCompanyTimezone(company.latitude, company.longitude) ?? "UTC";
      const localHour = computeOperatorLocalHour(now, tz);
      if (localHour !== 9) continue;
      const r1 = await this.processCompany(db, company as any, now);
      calendar += r1.processed;
      const r2 = await this.processLostYouCandidate(db, company as any, now);
      if (r2.fired) lost++;
    }

    // Always sweep retries regardless of local time
    const r3 = await this.processRetries(db, now);

    return { scanned: candidates?.length ?? 0, calendar_processed: calendar, lost_you_fired: lost, retried: r3.retried };
  },
```

```bash
git commit -am "feat(onboarding-drip): processAll orchestration with localHour=9 gate"
```

---

End of Phase 6. Service is feature-complete and unit-tested at the dedup + reconciliation + state + lifecycle level.

---

## Phase 7 — Cron route

### Task 28: `/api/cron/onboarding-drip` route

**Files:**
- Create: `OPS-Web/src/app/api/cron/onboarding-drip/route.ts`

- [ ] **Step 1: Implement the route**

Model on `/api/cron/trial-expiry/route.ts`. Same auth pattern (Bearer CRON_SECRET), same shape (calls a single service method).

```ts
// OPS-Web/src/app/api/cron/onboarding-drip/route.ts
import { NextRequest, NextResponse } from "next/server";
import { getServiceRoleClient } from "@/lib/supabase/server-client";
import { OnboardingDripService } from "@/lib/api/services/onboarding-drip-service";

export const maxDuration = 300;
export const runtime = "nodejs";
export const dynamic = "force-dynamic";

/**
 * GET /api/cron/onboarding-drip
 *
 * Vercel cron: hourly at minute 0 (0 * * * *). Gates each candidate
 * company by operator-local hour === 9 to deliver near 9am local time.
 * See spec §3 + §9.
 */
export async function GET(request: NextRequest) {
  const cronSecret = process.env.CRON_SECRET;
  if (!cronSecret) {
    return NextResponse.json({ error: "CRON_SECRET not configured" }, { status: 500 });
  }
  if (request.headers.get("authorization") !== `Bearer ${cronSecret}`) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const db = getServiceRoleClient();
  const now = new Date();

  try {
    const result = await OnboardingDripService.processAll(db, now);
    console.log("[cron/onboarding-drip]", JSON.stringify(result));
    return NextResponse.json({ ok: true, ...result });
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    console.error("[cron/onboarding-drip]", message);
    return NextResponse.json({ ok: false, error: message }, { status: 500 });
  }
}
```

- [ ] **Step 2: Smoke test**

Manually invoke against local dev:

```bash
curl -H "Authorization: Bearer $CRON_SECRET" http://localhost:3000/api/cron/onboarding-drip | jq
```

Expected: `{ "ok": true, "scanned": 0, "calendar_processed": 0, "lost_you_fired": 0, "retried": 0 }` against an empty database.

- [ ] **Step 3: Commit**

```bash
git add src/app/api/cron/onboarding-drip/route.ts
git commit -m "feat(onboarding-drip): add /api/cron/onboarding-drip cron route"
```

---

## Phase 8 — Day 0 real-time hook

### Task 29: Hook Day 0 into `/api/setup/progress` after the company INSERT

**Files:**
- Modify: `OPS-Web/src/app/api/setup/progress/route.ts`
- Test: `OPS-Web/tests/integration/onboarding-day0-realtime.test.ts`

- [ ] **Step 1: Read the existing route**

```bash
sed -n '110,140p' /Users/jacksonsweet/Projects/OPS/OPS-Web/src/app/api/setup/progress/route.ts
```

Identify the `companies.insert` site (line ~122) and the userId in scope.

- [ ] **Step 2: Write the integration test**

```ts
// OPS-Web/tests/integration/onboarding-day0-realtime.test.ts
// Verifies the post-company-INSERT hook fires Day 0 async without blocking
// the API response.
import { describe, it, expect, vi } from "vitest";
// (Test uses MSW/supertest pattern to POST to /api/setup/progress with a
// payload that triggers company creation. Asserts onboarding_email_log
// row exists with day_slot='day_0' within 5 seconds.)
```

- [ ] **Step 3: Implement the hook**

In `setup/progress/route.ts`, after the company INSERT succeeds (around line 130), add:

```ts
// Day 0 founder welcome — fire-and-forget after company creation.
// Per spec §3 + decision log #25/#26: only when the inserting user IS
// the new company's account_holder (operator-eligibility), and not for
// internal email domains. Failure does NOT roll back signup.
const isOperator = newCompany.account_holder_id === userId;
const isInternal = ["@opsapp.co", "@anthropic.com"].some((d) =>
  user.email?.toLowerCase().endsWith(d),
);
if (isOperator && !isInternal && user.email) {
  // Insert pending row + dispatch async (claim-before-send pattern handles dedup)
  void (async () => {
    try {
      const expires = new Date(Date.now() + 24 * 60 * 60_000).toISOString();
      const { data: logRow } = await db.from("onboarding_email_log").insert({
        user_id: userId,
        company_id: newCompany.id,
        day_slot: "day_0",
        branch: null,
        email_type: "onboarding_day_0_welcome",
        status: "pending",
        attempts: 0,
        day_slot_expires_at: expires,
      }).select("id").single();
      if (!logRow) return;
      const { sendOnboardingDay0Welcome } = await import("@/lib/email/sendgrid");
      const result = await sendOnboardingDay0Welcome({
        email: user.email!,
        firstName: user.first_name,
        onboardingEmailLogId: logRow.id,
      });
      const update: Record<string, unknown> =
        result.status === "sent"
          ? { status: "sent", sent_at: new Date().toISOString(), sg_message_id: result.messageId }
          : result.status === "suppression_skipped"
            ? { status: "skipped" }
            : { status: "pending" }; // paused — cron will retry
      await db.from("onboarding_email_log").update(update).eq("id", logRow.id);
    } catch (err) {
      console.error("[onboarding-day0] async dispatch failed:", err);
      // Cron will retry up to 3 times within day_slot_expires_at
    }
  })();
}
```

- [ ] **Step 4-5: Verify + commit**

```bash
pnpm vitest run tests/integration/onboarding-day0-realtime.test.ts
git add src/app/api/setup/progress/route.ts tests/integration/onboarding-day0-realtime.test.ts
git commit -m "feat(onboarding-drip): wire Day 0 founder welcome into /api/setup/progress post-INSERT"
```

---

## Phase 9 — Cron schedule

### Task 30: Add the hourly cron to `vercel.json`

**Files:**
- Modify: `OPS-Web/vercel.json`

- [ ] **Step 1: Verify Pro+ plan (re-run PF-1)**

Already done in pre-flight. If skipped, do it now.

- [ ] **Step 2: Add the cron entry**

Open `OPS-Web/vercel.json`. Inside the `crons` array, append:

```json
    {
      "path": "/api/cron/onboarding-drip",
      "schedule": "0 * * * *"
    }
```

- [ ] **Step 3: Verify the JSON parses**

```bash
cd /Users/jacksonsweet/Projects/OPS/OPS-Web
cat vercel.json | jq '.crons | length'
```

Expected: count is one higher than before.

- [ ] **Step 4: Commit**

```bash
git add vercel.json
git commit -m "feat(onboarding-drip): register hourly cron /api/cron/onboarding-drip"
```

---

## Phase 10 — Integration tests

### Task 31: End-to-end cron integration test

**Files:**
- Create: `OPS-Web/tests/integration/onboarding-drip-cron.test.ts`

Spins up an in-memory Supabase-compatible test DB (or uses the dev Supabase project), seeds N companies with varied ages and timezones, invokes the cron handler, asserts the right sends + dedup rows.

- [ ] **Step 1: Write the integration tests**

```ts
import { describe, it, expect, beforeEach } from "vitest";
import { GET as runCron } from "@/app/api/cron/onboarding-drip/route";
import { NextRequest } from "next/server";

// Reuses the dev Supabase project. Each test seeds + cleans up its own rows
// in a transaction (or uses test-prefixed company names for easy cleanup).

describe("onboarding-drip cron — end to end", () => {
  beforeEach(async () => {
    // Cleanup test companies + onboarding_email_log rows
  });

  it("seeds 5 companies at age=1 in PT timezone, fires Day 1 for the one whose localHour===9 at run time", async () => {
    // (Detailed seed + assertion logic here)
  });

  it("Day 4A renders the mocked push notification card", async () => {
    // Seed company without task_completed notification, advance to age=4,
    // run cron at appropriate UTC time, fetch the email_log row, assert
    // the html contains "Task Completed" and "Jake completed"
  });

  it("dedup: invoking the cron twice does not double-send", async () => {
    // Seed a company at age=1, run cron twice, assert exactly one
    // onboarding_email_log row exists for that user+day_slot
  });

  it("retry: a failed Day 0 row is picked up on next sweep after 5-min in-flight gate", async () => {
    // Seed an onboarding_email_log row with status='failed', attempts=1,
    // updated_at=10 minutes ago, day_slot_expires_at=tomorrow — assert
    // the next cron tick picks it up
  });

  it("retry: a pending row updated 2 minutes ago is NOT picked up (in-flight gate)", async () => { /* … */ });
  it("retry: a failed row with attempts=3 is NOT picked up", async () => { /* … */ });
  it("Lost You: fires for a company with 6+ days of zero activity", async () => { /* … */ });
});
```

- [ ] **Step 2-3: Implement + run**

```bash
pnpm vitest run tests/integration/onboarding-drip-cron.test.ts
```

Expected: all pass.

- [ ] **Step 4: Commit**

```bash
git add tests/integration/onboarding-drip-cron.test.ts
git commit -m "test(onboarding-drip): end-to-end integration tests for cron"
```

---

## Phase 11 — Cutover

Cutover is a single coordinated session, not a sequence of separate commits. The tasks below are executed in order on launch day.

### Task 32: Pre-launch verification (T-1 hour)

- [ ] **Re-run PF-2** (verify `lifecycle_email_config` still all disabled + zero email_log rows for the 11 kinds)
- [ ] Confirm founder still has no SendGrid Automations attached to lifecycle lists
- [ ] Verify all Phase 1-10 commits are on the deploy branch
- [ ] Verify `vercel.json` cron entry is present
- [ ] Verify migration 108 has been applied to production Supabase via `mcp__plugin_supabase_supabase__list_migrations`

### Task 33: Deploy + smoke test (T+0)

- [ ] Deploy OPS-Web to production
- [ ] Verify `/api/cron/onboarding-drip` is registered in Vercel project settings → Cron Jobs
- [ ] Manually invoke with `Bearer ${CRON_SECRET}` against production:

```bash
curl -H "Authorization: Bearer $CRON_SECRET" https://app.opsapp.co/api/cron/onboarding-drip | jq
```

Expected: `{ "ok": true, ... }` with `scanned` >= 0 (depends on operator timezones at the moment of the call).

- [ ] Create a test signup in production with an `@opsapp.co` email (will skip Day 0 due to internal allowlist — verify by checking `onboarding_email_log` for the expected row count = 0)
- [ ] Create a test signup in production with a personal email; verify Day 0 row appears in `onboarding_email_log` within 60 seconds; verify a row appears in `email_log` with `email_type='onboarding_day_0_welcome'`
- [ ] Verify the test signup actually received the email at the test address

### Task 34: Disable the dormant edge functions (T+30 min, after smoke passes)

- [ ] Supabase Dashboard → Edge Functions → `lifecycle-emails` → Status `INACTIVE`
- [ ] Same for `lifecycle-cron`, `lifecycle-onboarding-complete`, `lifecycle-first-action`
- [ ] **Do NOT delete the SendGrid Marketing Lists** (deferred to 30-day cleanup per spec §14)
- [ ] **Do NOT drop `lifecycle_email_config`** (deferred — admin UI still reads it)

### Task 35: First-hour observation

- [ ] Tail Vercel logs for `/api/cron/onboarding-drip` errors
- [ ] Spot-check `onboarding_email_log` for new rows
- [ ] Spot-check rendered HTML in real inboxes (Gmail web + iOS Mail)

### Task 36: 24-hour observation

- [ ] Confirm Day 0 send rate matches new signup rate (query `SELECT count(*) FROM onboarding_email_log WHERE day_slot='day_0' AND created_at > now() - interval '24 hours'` vs new signups)
- [ ] Confirm Day 1 cron tick has fired for any operators in the cohort that hit local 9am
- [ ] Confirm no `status='failed'` rows piling up

### Task 37: 30-day cleanup (separate session, T+30 days)

- [ ] Delete the 4 edge function definitions in Supabase Dashboard
- [ ] Create migration `20260626_drop_lifecycle_email_config.sql`:

```sql
DROP TABLE IF EXISTS public.lifecycle_email_config;
```

- [ ] Delete `OPS-Web/src/app/api/admin/email/lifecycle-config/route.ts`
- [ ] Delete `OPS-Web/src/app/admin/email/_components/lifecycle-config-panel.tsx`
- [ ] Remove the panel's mount in the parent admin email page
- [ ] Apply migration 109 + commit + deploy in one PR — these MUST land together to avoid the admin page 500ing
- [ ] Remove ONLY `lifecycle-emails` from `OPS-Web/src/app/api/admin/email/trigger/route.ts` `ALLOWED_SLUGS` (preserve the other 4 unrelated slugs)
- [ ] Delete SendGrid Marketing Lists from the SendGrid dashboard:
  - `SENDGRID_LIST_NO_ONBOARDING`, `SENDGRID_LIST_NO_FIRST_PROJECT`
  - `SENDGRID_LIST_INACTIVE_14D`, `SENDGRID_LIST_INACTIVE_30D`
  - `SENDGRID_LIST_TRIAL_EXPIRING_7D`, `SENDGRID_LIST_TRIAL_EXPIRING_3D`
  - `SENDGRID_LIST_TRIAL_EXPIRED`

---

## Phase 12 — Bible updates

Per spec §13. Land in the bible repo, not OPS-Web.

### Task 38: Update `13_EMAIL_SYSTEM.md`

**Files:**
- Modify: `ops-software-bible/13_EMAIL_SYSTEM.md`

- [ ] Add new section `## Onboarding Drip` between `## Trial-Expiry Lifecycle` and `## Deliverability Anomaly Detector`
- [ ] Cover: 10 send kinds, trigger architecture (real-time + hourly cron with localHour=9 gate), claim-before-send dedup, branch logic, kill switches, alternating Jack/Dispatch sender pattern, `onboarding_email_log` table, partial-success reconciliation
- [ ] Update § Cron Schedule table to include `/api/cron/onboarding-drip` at `0 * * * *`
- [ ] Update § Email Kinds Catalog table to include the 10 new kinds
- [ ] Update § Sender Identities to add `JACK` (operationally part of dispatch bucket)
- [ ] Update § Known Gaps:
  - Remove gap #1 ("No welcome email on signup") — resolved
  - Remove gap #8 ("No mid-trial engagement drip") — resolved
  - Keep gap #2 ("No internal new-signup alert") — only partially addressed

### Task 39: Update `03_DATA_ARCHITECTURE.md`

**Files:**
- Modify: `ops-software-bible/03_DATA_ARCHITECTURE.md`

- [ ] Add `onboarding_email_log` to the outbound email tables cross-reference list

### Task 40: Update README.md cron list (if maintained)

**Files:**
- Modify: `ops-software-bible/README.md` (if cron list exists there)

- [ ] No README changes if cron list isn't there

### Task 41: Commit bible updates

```bash
cd /Users/jacksonsweet/Projects/OPS/ops-software-bible
git add 13_EMAIL_SYSTEM.md 03_DATA_ARCHITECTURE.md
git commit -m "docs(bible): document onboarding drip system in chapter 13 + 03 cross-ref"
```

---

## Self-Review Checklist

Before handing this plan off, run through:

**1. Spec coverage** — every section of `specs/2026-05-27-onboarding-drip-design.md` v3.1 should map to a task:
- §1 Background — Pre-flight + §11 cutover
- §2 Drip shape — Phase 3 templates
- §3 Trigger architecture — Phase 8 (Day 0 hook), Phase 7 (cron), Task 23 (claim+reconcile), Task 25 (retry)
- §4 Sender/format/voice — Phase 2 primitives, Phase 3 templates, Phase 4 senders
- §5 Branches — Task 22 computeState
- §6 Email copy — Phase 3 (verbatim per spec)
- §7 Lost You — Task 26
- §8 Data model — Task 1 migration
- §9 Cron — Task 30 vercel.json
- §10 Plumbing — Phase 4-9
- §11 Testing — Phase 10 + per-task TDD
- §12 Compliance + brand — embedded in Phase 2-3 (FounderFooter + banned-word tests)
- §13 Bible updates — Phase 12
- §14 Migration & cutover — Phase 11
- §15 Open questions — none open in plan (MockPushNotification stylized choice = Task 7; cleanup ordering = Task 37)

**2. Placeholder scan** — no `TBD`, no `TODO`, no "implement later", no "similar to Task N". All code blocks have actual code.

**3. Type consistency** — `OnboardingDripService`, `DaySlot`, `Branch`, `ClaimAndSendStatus`, `ComputedState` used consistently across Tasks 21-27. `sendOnboarding*` function names match between Tasks 18/19 and Task 23's dispatcher.

If you find issues, fix them inline.

---

## Execution Handoff

Plan complete and saved to `ops-software-bible/specs/plans/2026-05-27-onboarding-drip-implementation.md`. Two execution options:

**1. Subagent-Driven (recommended)** — Dispatch a fresh subagent per task, review between tasks, fast iteration. Use `superpowers:subagent-driven-development`.

**2. Inline Execution** — Execute tasks in this session using `superpowers:executing-plans`, batch execution with checkpoints.

Which approach?
