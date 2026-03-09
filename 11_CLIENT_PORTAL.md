# 11_CLIENT_PORTAL.md

**Last Updated**: February 28, 2026

## Document Purpose

Complete reference for the OPS Client Portal — a client-facing web portal within the OPS web app where end customers (homeowners, property managers) can view project status, approve/decline estimates, answer line-item questions, pay invoices via Stripe, view project photos, and message the company. Company-customizable branding with 3 templates, light/dark mode, and accent colors.

---

## Overview

The Client Portal is a **public-facing route group** (`/portal`) within the existing ops-web Next.js app. It uses a **separate authentication system** (magic link + email verification) independent of the Firebase auth used by the dashboard. Portal operations use Supabase's **service role client** since portal users have no Firebase account.

### Key Differentiators
- **Line-item questions** — Unique feature: companies attach questions directly to estimate line items (e.g., "What color railings?" on the "Railing Installation" line item). 5 answer types: text, number, select, multiselect, color. No competitor offers this.
- **Company-customizable branding** — Logo, accent color, 3 templates (Modern, Classic, Bold), light/dark mode, custom welcome message.
- **Zero account creation** — Clients access via magic links, verify with email, get 30-day sessions. No passwords.

### Architecture
```
/portal/[token]              → Magic link landing (public)
/portal/verify               → Session expired fallback (public)
/portal/home                 → Dashboard: projects, estimates, invoices
/portal/estimates/[id]       → Estimate detail + approve/decline
/portal/estimates/[id]/questions → Answer line-item questions
/portal/invoices/[id]        → Invoice detail + Stripe payment
/portal/projects/[id]        → Project detail + photos + timeline
/portal/messages             → Two-way messaging
```

---

## Database Schema

Six new Supabase tables, all with RLS enabled. Migration file: `supabase/migrations/007_portal_schema.sql`

### portal_tokens
Magic link tokens for portal access. Generated when company shares portal or sends estimate/invoice.

| Column | Type | Notes |
|--------|------|-------|
| id | UUID PK | `gen_random_uuid()` |
| company_id | TEXT NOT NULL | |
| client_id | TEXT NOT NULL | |
| email | TEXT NOT NULL | |
| token | TEXT NOT NULL UNIQUE | `encode(gen_random_bytes(32), 'hex')` — 64 hex chars |
| expires_at | TIMESTAMPTZ | Default: now() + 7 days |
| verified_at | TIMESTAMPTZ | Set when email verified |
| created_at | TIMESTAMPTZ | |
| revoked_at | TIMESTAMPTZ | Soft-revoke |

**Indexes:** `idx_portal_tokens_token` (token), `idx_portal_tokens_client` (client_id, company_id)

### portal_sessions
Post-email-verification sessions. 30-day lifetime. Stored in `ops-portal-session` httpOnly cookie.

| Column | Type | Notes |
|--------|------|-------|
| id | UUID PK | |
| portal_token_id | UUID FK → portal_tokens | |
| session_token | TEXT NOT NULL UNIQUE | 64 hex chars |
| email | TEXT NOT NULL | |
| company_id | TEXT NOT NULL | |
| client_id | TEXT NOT NULL | |
| expires_at | TIMESTAMPTZ | Default: now() + 30 days |
| created_at | TIMESTAMPTZ | |

### portal_branding
Company-customizable portal appearance. One row per company (upsert pattern).

| Column | Type | Default | Notes |
|--------|------|---------|-------|
| id | UUID PK | | |
| company_id | TEXT NOT NULL UNIQUE | | |
| logo_url | TEXT | null | Company logo |
| accent_color | TEXT | `'#417394'` | Hex color |
| template | TEXT | `'modern'` | `modern`, `classic`, `bold` |
| theme_mode | TEXT | `'dark'` | `light`, `dark` |
| font_combo | TEXT | `'modern'` | Tied to template |
| welcome_message | TEXT | null | Shown on portal home |
| created_at, updated_at | TIMESTAMPTZ | | |

### line_item_questions
Questions attached to estimate line items. Created by the company in the estimate builder.

| Column | Type | Notes |
|--------|------|-------|
| id | UUID PK | |
| company_id | TEXT NOT NULL | |
| estimate_id | UUID FK → estimates | CASCADE delete |
| line_item_id | UUID FK → line_items | CASCADE delete |
| question_text | TEXT NOT NULL | |
| answer_type | TEXT | `text`, `select`, `multiselect`, `color`, `number` |
| options | JSONB | `'[]'` — array of option strings for select/multiselect/color |
| is_required | BOOLEAN | Default true |
| sort_order | INTEGER | For ordering |
| created_at | TIMESTAMPTZ | |

### line_item_answers
Client answers to questions. Upsert on (question_id, client_id).

| Column | Type | Notes |
|--------|------|-------|
| id | UUID PK | |
| question_id | UUID FK → line_item_questions | CASCADE delete |
| client_id | TEXT NOT NULL | |
| answer_value | TEXT NOT NULL | For multiselect: comma-separated |
| answered_at | TIMESTAMPTZ | |

### portal_messages
Client ↔ company messaging. Two sender types.

| Column | Type | Notes |
|--------|------|-------|
| id | UUID PK | |
| company_id | TEXT NOT NULL | |
| client_id | TEXT NOT NULL | |
| project_id | TEXT | Optional context link |
| estimate_id | UUID FK → estimates | Optional |
| invoice_id | UUID FK → invoices | Optional |
| sender_type | TEXT | `client` or `company` |
| sender_name | TEXT NOT NULL | |
| content | TEXT NOT NULL | |
| read_at | TIMESTAMPTZ | null = unread |
| created_at | TIMESTAMPTZ | |

### Migration 009: line_item_answers Unique Constraint Fix

Migration file: `supabase/migrations/009_fix_line_item_answers_unique.sql` (pending)

Adds the missing `UNIQUE` constraint on `(question_id, client_id)` to the `line_item_answers` table. This constraint is required for the upsert operations in `LineItemQuestionService.submitAnswer()`, which uses `ON CONFLICT (question_id, client_id)` to update existing answers rather than creating duplicates.

```sql
ALTER TABLE line_item_answers
  ADD CONSTRAINT uq_answer_question_client UNIQUE (question_id, client_id);
```

> **Migration numbering collision:** Two migration files share the `009` prefix. `009_blog_schema.sql` (blog categories, topics, and posts tables) has already been executed and lives in `EXECUTED/009_blog_schema.sql`. The pending `009_fix_line_item_answers_unique.sql` remains in the migrations root. These were authored independently and collided on the same sequence number.

---

## Authentication Flow

### Magic Link Flow
```
1. Company sends estimate/invoice → POST /api/portal/share
   → Creates portal_token (7-day expiry)
   → Sends branded email via SendGrid with magic link

2. Client clicks link → /portal/[64-char-hex-token]
   → Page validates token (GET /api/portal/auth/validate-token)
   → Shows email verification form

3. Client enters email → POST /api/portal/auth/verify
   → Server validates: token exists, not expired, not revoked, email matches client
   → Creates portal_session (30-day expiry)
   → Sets ops-portal-session httpOnly cookie
   → Redirects to /portal/home

4. All subsequent requests: cookie → session lookup → client_id + company_id
```

### Middleware
Portal middleware in `src/middleware.ts` runs before dashboard auth:

- **Public routes:** `/portal/verify`, `/portal/auth/*`, `/portal/[64-char-hex]`
- **Protected routes:** `/portal/home`, `/portal/projects/*`, `/portal/estimates/*`, `/portal/invoices/*`, `/portal/messages`
- Protection: checks `ops-portal-session` cookie, redirects to `/portal/verify` if missing

### Session Helper
`src/lib/api/portal-api-helpers.ts` exports `requirePortalSession(req)`:
- Reads `ops-portal-session` cookie
- Validates session via service role Supabase query
- Returns session (clientId, companyId) or 401 NextResponse

---

## Services

All portal services use `getServiceRoleClient()` (Supabase service role key) since portal users have no Firebase auth. Located in `src/lib/api/services/`.

### PortalAuthService (`portal-auth-service.ts`)
- `createPortalToken(companyId, clientId, email)` → token row
- `verifyAndCreateSession(token, email)` → validates + creates session + sets verified_at
- `getSessionFromCookie(sessionToken)` → session or null
- `revokeToken(tokenId)` → soft revoke

### PortalService (`portal-service.ts`)
Main data aggregation service (~660 lines).
- `getPortalData(clientId, companyId)` → `PortalClientData` (client, company, branding, projects, estimates, invoices, unread count)
- `getEstimateForPortal(estimateId, clientId)` → estimate + line items + questions/answers
- `getInvoiceForPortal(invoiceId, clientId)` → invoice + line items + payments
- `markEstimateViewed(estimateId)` → updates viewed_at
- `approveEstimate(estimateId, clientId)` → status → approved
- `declineEstimate(estimateId, clientId, reason?)` → status → declined

### LineItemQuestionService (`line-item-question-service.ts`)
- `getQuestionsForEstimate(estimateId)` → questions + answers
- `createQuestion(data)` / `updateQuestion(id, data)` / `deleteQuestion(id)`
- `submitAnswer(questionId, clientId, answerValue)` → upserts on (question_id, client_id)
- `getUnansweredQuestions(estimateId, clientId)` → required questions without answers

### PortalMessageService (`portal-message-service.ts`)
- `getMessages(clientId, companyId, options?)` → paginated, optionally filtered by project/estimate/invoice
- `sendMessage(data)` → insert
- `markRead(messageId)` / `markAllRead(clientId, companyId)`
- `getUnreadCount(clientId, companyId)` / `getUnreadCountForCompany(companyId)`
- `getConversations(companyId)` → grouped by client for admin inbox

### PortalBrandingService (`portal-branding-service.ts`)
- `getBranding(companyId)` → get or create default
- `updateBranding(companyId, data)` → upsert

### PortalActivityService (`portal-activity-service.ts`)
Non-blocking activity logging for portal events. Catches errors and logs them but never throws.
- `logEstimateViewed(params)` → ActivityType.EstimateSent
- `logEstimateApproved(params)` → ActivityType.EstimateAccepted
- `logEstimateDeclined(params)` → ActivityType.EstimateDeclined
- `logQuestionsAnswered(params)` → ActivityType.Note
- `logPaymentReceived(params)` → ActivityType.PaymentReceived
- `logClientMessage(params)` → ActivityType.Note (direction: inbound)

---

## API Routes

All portal API routes at `src/app/api/portal/`. Every protected route:
1. Reads `ops-portal-session` cookie
2. Validates via `requirePortalSession(req)`
3. Extracts clientId + companyId
4. Calls service method
5. Returns JSON

| Route | Method | Purpose |
|-------|--------|---------|
| `/api/portal/auth/send-link` | POST | Create token + send magic link email |
| `/api/portal/auth/verify` | POST | Validate token+email, create session, set cookie |
| `/api/portal/auth/validate-token` | GET | Check if token is valid/expired/revoked |
| `/api/portal/data` | GET | Full PortalClientData aggregate |
| `/api/portal/estimates/[id]` | GET | Estimate detail + mark as viewed |
| `/api/portal/estimates/[id]/approve` | POST | Approve estimate |
| `/api/portal/estimates/[id]/decline` | POST | Decline estimate (optional reason) |
| `/api/portal/estimates/[id]/questions` | GET/POST | Get questions+answers / Submit answers |
| `/api/portal/invoices/[id]` | GET | Invoice detail + payments |
| `/api/portal/invoices/[id]/pay` | POST | Create Stripe PaymentIntent |
| `/api/portal/projects/[id]` | GET | Project detail |
| `/api/portal/messages` | GET/POST | Get paginated messages / Send message |
| `/api/portal/share` | POST | Admin sends magic link to client |

---

## Branding & Theme System

### Templates

| Template | Heading Font | Body Font | Radius | Vibe |
|----------|-------------|-----------|--------|------|
| **Modern** | Inter (500) | Inter | 12px | Clean SaaS, generous whitespace |
| **Classic** | Merriweather (700) | Inter | 8px | Professional serif headings |
| **Bold** | Oswald (600) | Open Sans | 4px | Trade/construction, uppercase headings |

### CSS Custom Properties
`generatePortalTheme(branding)` in `src/lib/portal/theme.ts` returns CSS vars applied to the portal shell:

```typescript
'--portal-bg'             // Background (dark: #0A0A0A, light: #FAFAFA)
'--portal-card'           // Card background (dark: #191919, light: #FFFFFF)
'--portal-text'           // Primary text (dark: #E5E5E5, light: #1A1A1A)
'--portal-text-secondary' // (dark: #A7A7A7, light: #6B7280)
'--portal-text-tertiary'  // (dark: #737373, light: #9CA3AF)
'--portal-accent'         // Company accent color
'--portal-accent-hover'   // Lightened 10%
'--portal-border'         // (dark: rgba(255,255,255,0.1), light: rgba(0,0,0,0.1))
'--portal-success'        // #059669
'--portal-warning'        // #D97706
'--portal-error'          // #DC2626
'--portal-heading-font'   // Template-specific
'--portal-body-font'      // Template-specific
'--portal-heading-weight' // Template-specific
'--portal-heading-transform' // Template-specific (e.g., uppercase for Bold)
'--portal-radius'         // Card border radius
```

All portal components use `var(--portal-xxx)` via inline styles, with Tailwind for layout.

---

## Portal Pages

### Magic Link Landing (`/portal/[token]`)
- Validates token on load
- Shows branded email verification form
- On verify: creates session, redirects to `/portal/home`
- Expired/revoked: shows error with company contact

### Portal Home (`/portal/home`)
- Welcome: "Hi, [FirstName]" + company welcome message
- **Estimates needing attention**: status `sent`/`viewed` or `hasUnansweredQuestions`
- **Invoices due**: balance > 0, not void/written_off
- **Your projects**: grid of project cards

### Estimate Detail (`/portal/estimates/[id]`)
- Header: number, title, status badge, dates, expiration warning
- Client message from company
- Line items: name, qty, unit price, line total. Optional items section.
- Question indicator badges on line items with questions
- Totals: subtotal, discount, tax, total, deposit
- **Actions** (when status is sent/viewed/changes_requested):
  - **Approve** (green) → confirmation dialog → redirects to questions if any
  - **Request Changes** (amber) → dialog with reason textarea
  - **Decline** (red) → dialog with optional reason

### Line Item Questions (`/portal/estimates/[id]/questions`)
- Grouped by line item with section headers
- Progress indicator: "X of Y required questions answered"
- 5 answer types:
  - `text` → text input
  - `number` → number input
  - `select` → dropdown from options
  - `multiselect` → checkbox group as styled button cards
  - `color` → color swatches (resolves names to hex) or hex input
- Pre-fills existing answers
- Submit validates all required answered

### Invoice Detail (`/portal/invoices/[id]`)
- Header: number, dates, status, due date
- Line items table
- Totals: subtotal, discount, tax, total
- Payment history
- Balance due (highlighted)
- **Pay Now**: amount input + payment form (Stripe PaymentIntent integration)

### Project Detail (`/portal/projects/[id]`)
- Header: title, address, status, dates
- Task timeline: vertical timeline with status-colored dots
- Photo gallery: grid with fullscreen lightbox, keyboard navigation
- Linked estimates and invoices with status badges

### Messages (`/portal/messages`)
- Threaded view: client messages right, company messages left
- Date-grouped separators
- Auto-scroll to latest
- Compose area: textarea + send button
- Context tags (project, estimate, invoice linked)

---

## Admin-Side Portal Features

### Portal Branding Settings Tab
`src/components/settings/portal-branding-tab.tsx` — added to Settings page as "Client Portal" tab.

Sections:
1. **Company Logo** — URL input + live preview
2. **Accent Color** — 6 preset swatches + custom hex input
3. **Portal Template** — 3 radio cards (Modern, Classic, Bold)
4. **Theme Mode** — Light/Dark toggle
5. **Welcome Message** — Textarea

### Line Item Question Editor
`src/components/ops/line-item-question-editor.tsx` — controlled component used in the estimate builder.

- Each line item gets a `?` icon button with question count badge (integrated into `LineItemEditor`)
- Question form: text input, answer type selector, options editor, required toggle
- Answer types: text, number, single select, multi select, color
- Options editor for select/multiselect/color types with tag-pill UI

### Share Portal Button
`src/components/ops/share-portal-button.tsx` — reusable button for sending magic links.

- Used on project detail, estimate detail, invoice detail
- Pre-fills client email
- Posts to `/api/portal/share`
- Shows success toast

### Admin Portal Inbox
`src/app/(dashboard)/portal-inbox/page.tsx` — split-view inbox for all client messages.

- Left panel: conversation list (grouped by client, unread badges)
- Right panel: message thread with compose
- Real-time polling: conversations every 30s, active thread every 15s
- Auto-marks client messages as read when conversation opened
- Added to sidebar as "Portal Inbox" nav item

---

## Email Templates

SendGrid-powered branded emails. Located in `src/lib/email/`.

| Template | Trigger | Content |
|----------|---------|---------|
| **Magic Link** | Company shares portal / sends estimate/invoice | "Access Your Portal" with branded button |
| **Estimate Ready** | Estimate sent to client | "New Estimate Available" with amount + link |
| **Questions Reminder** | Manual reminder | "Please Answer Questions" to unblock project |
| **Invoice Ready** | Invoice sent to client | "New Invoice" with amount + due date + link |

All emails use:
- Company logo in header
- Company accent color for CTA buttons
- Responsive HTML with inline CSS

---

## TanStack Query Hooks

Portal-specific hooks in `src/lib/hooks/`. All use `portalFetch()` helper (adds `credentials: "include"` for cookie auth) and `portalKeys` factory for cache keys.

| Hook | Purpose |
|------|---------|
| `usePortalData()` | Full portal data aggregate |
| `usePortalEstimate(id)` | Estimate detail |
| `useApproveEstimate()` | Mutation: approve |
| `useDeclineEstimate()` | Mutation: decline with reason |
| `usePortalInvoice(id)` | Invoice detail |
| `useCreatePaymentIntent()` | Mutation: Stripe payment |
| `usePortalProject(id)` | Project detail |
| `usePortalMessages(options?)` | Paginated messages |
| `useSendPortalMessage()` | Mutation: send message |
| `usePortalQuestions(estimateId)` | Questions + answers |
| `useSubmitPortalAnswers()` | Mutation: submit answers |

---

## Dependencies

| Package | Purpose |
|---------|---------|
| `@sendgrid/mail` | Email delivery for magic links and notifications |
| `stripe` | Server-side Stripe API (PaymentIntent creation) |
| `@stripe/stripe-js` | Client-side Stripe.js loader |
| `@stripe/react-stripe-js` | React Stripe Elements components |

---

## File Inventory

### New Files (~50)

**Database:**
- `supabase/migrations/007_portal_schema.sql`
- `supabase/migrations/009_fix_line_item_answers_unique.sql` — unique constraint fix for line_item_answers upsert

**Types:**
- `src/lib/types/portal.ts`

**Services (6):**
- `src/lib/api/services/portal-auth-service.ts`
- `src/lib/api/services/portal-service.ts`
- `src/lib/api/services/line-item-question-service.ts`
- `src/lib/api/services/portal-message-service.ts`
- `src/lib/api/services/portal-branding-service.ts`
- `src/lib/api/services/portal-activity-service.ts`

**Email (5):**
- `src/lib/email/sendgrid.ts`
- `src/lib/email/templates/layout.ts`
- `src/lib/email/templates/magic-link.ts`
- `src/lib/email/templates/estimate-ready.ts`
- `src/lib/email/templates/questions-reminder.ts`
- `src/lib/email/templates/invoice-ready.ts`

**API Routes (12):**
- `src/app/api/portal/auth/send-link/route.ts`
- `src/app/api/portal/auth/verify/route.ts`
- `src/app/api/portal/auth/validate-token/route.ts`
- `src/app/api/portal/data/route.ts`
- `src/app/api/portal/estimates/[id]/route.ts`
- `src/app/api/portal/estimates/[id]/approve/route.ts`
- `src/app/api/portal/estimates/[id]/decline/route.ts`
- `src/app/api/portal/estimates/[id]/questions/route.ts`
- `src/app/api/portal/invoices/[id]/route.ts`
- `src/app/api/portal/invoices/[id]/pay/route.ts`
- `src/app/api/portal/projects/[id]/route.ts`
- `src/app/api/portal/messages/route.ts`
- `src/app/api/portal/share/route.ts`

**Theme (2):**
- `src/lib/portal/theme.ts`
- `src/lib/portal/templates.ts`

**Portal Pages (8):**
- `src/app/(portal)/layout.tsx`
- `src/app/(portal)/portal/layout.tsx`
- `src/app/(portal)/portal/providers.tsx`
- `src/app/(portal)/portal/[token]/page.tsx`
- `src/app/(portal)/portal/verify/page.tsx`
- `src/app/(portal)/portal/home/page.tsx`
- `src/app/(portal)/portal/estimates/[id]/page.tsx`
- `src/app/(portal)/portal/estimates/[id]/questions/page.tsx`
- `src/app/(portal)/portal/invoices/[id]/page.tsx`
- `src/app/(portal)/portal/projects/[id]/page.tsx`
- `src/app/(portal)/portal/messages/page.tsx`

**Portal Components (10):**
- `src/components/portal/portal-shell.tsx`
- `src/components/portal/portal-header.tsx`
- `src/components/portal/portal-nav.tsx`
- `src/components/portal/portal-project-card.tsx`
- `src/components/portal/portal-status-badge.tsx`
- `src/components/portal/portal-estimate-view.tsx`
- `src/components/portal/portal-line-item-card.tsx`
- `src/components/portal/portal-question-field.tsx`
- `src/components/portal/portal-invoice-view.tsx`
- `src/components/portal/portal-payment-form.tsx`
- `src/components/portal/portal-photo-gallery.tsx`
- `src/components/portal/portal-task-timeline.tsx`

**Admin Components (4):**
- `src/components/settings/portal-branding-tab.tsx`
- `src/components/ops/line-item-question-editor.tsx`
- `src/components/ops/portal-inbox.tsx`
- `src/components/ops/share-portal-button.tsx`
- `src/app/(dashboard)/portal-inbox/page.tsx`

**Hooks (6):**
- `src/lib/hooks/use-portal-data.ts`
- `src/lib/hooks/use-portal-estimate.ts`
- `src/lib/hooks/use-portal-invoice.ts`
- `src/lib/hooks/use-portal-project.ts`
- `src/lib/hooks/use-portal-messages.ts`
- `src/lib/hooks/use-portal-questions.ts`

**Helpers:**
- `src/lib/api/portal-api-helpers.ts`

### Modified Files
- `src/middleware.ts` — portal route handling
- `src/app/(dashboard)/settings/page.tsx` — added Portal tab
- `src/components/layouts/sidebar.tsx` — added Portal Inbox nav item
- `src/components/ops/line-item-editor.tsx` — added question button per line item
- `src/lib/hooks/index.ts` — barrel exports for portal hooks

---

## Environment Variables

| Variable | Purpose |
|----------|---------|
| `SENDGRID_API_KEY` | SendGrid email delivery |
| `SENDGRID_FROM_EMAIL` | Sender email address |
| `STRIPE_SECRET_KEY` | Stripe server-side API |
| `NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY` | Stripe client-side |
| `NEXT_PUBLIC_APP_URL` | Base URL for magic links (e.g., `https://app.opsapp.co`) |

---

## Business Rules

1. **Token expiry:** 7 days. Session expiry: 30 days.
2. **Email verification:** Client must enter the exact email associated with their client record.
3. **Data isolation:** All service methods verify `client_id` matches session to prevent cross-client access.
4. **Activity logging is non-blocking:** Errors are logged but never thrown, so portal operations aren't blocked.
5. **Estimate actions:** Only available when status is `sent`, `viewed`, or `changes_requested`.
6. **Questions required:** All required questions must be answered before submission; optional questions can be skipped.
7. **Branding defaults:** New companies get Modern template, dark mode, #417394 accent.
8. **Message read tracking:** Company messages marked read when client opens thread. Client messages marked read when admin opens conversation.
9. **Stripe payments:** PaymentIntent created server-side, completed client-side via Stripe Elements. Webhook records payment.

---

## Testing Checklist

1. Create test company with portal branding (logo, accent, Modern template, dark mode)
2. Create client with email
3. Create estimate with line items and questions
4. Send estimate → verify magic link email received
5. Click magic link → verify email → land on portal home
6. View estimate → verify line items, totals, question indicator badges
7. Approve estimate → verify status change + activity logged
8. Answer questions → verify answers saved + progress tracking
9. Create invoice → send → verify client sees it in portal
10. Pay invoice via Stripe → verify payment recorded
11. Send message → verify appears in admin inbox
12. Switch branding to Classic + light mode → verify portal updates
13. Verify 30-day session persists
14. Verify expired magic link shows error
15. Verify wrong email shows error
