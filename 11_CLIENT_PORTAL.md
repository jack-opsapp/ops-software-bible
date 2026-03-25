# 11_CLIENT_PORTAL.md

**Last Updated**: March 25, 2026

## Document Purpose

Complete reference for the OPS Client Portal — a client-facing web portal within the OPS web app where end customers (homeowners, property managers) can view project status, approve/decline estimates, answer line-item questions, pay invoices via Stripe, view project photos, and message the company. Company-customizable branding with 3 templates, light/dark mode, accent colors, expanded CSS custom properties, and document field visibility overrides.

---

## Overview

The Client Portal is a **public-facing route group** (`/portal`) within the existing ops-web Next.js app. It uses a **separate authentication system** (magic link + email verification) independent of the Firebase auth used by the dashboard. Portal operations use Supabase's **service role client** since portal users have no Firebase account.

### Key Differentiators
- **Line-item questions** — Unique feature: companies attach questions directly to estimate line items (e.g., "What color railings?" on the "Railing Installation" line item). 5 answer types: text, number, select, multiselect, color. No competitor offers this.
- **Company-customizable branding** — Logo, accent color, 3 templates (Modern, Classic, Bold), light/dark mode, custom welcome message. **Expanded template skins** with 30+ CSS custom properties controlling cards, progress bars, galleries, bubbles, status badges, section dividers, and headers.
- **Zero account creation** — Clients access via magic links, verify with email, get 30-day sessions. No passwords.
- **Phase Timeline** — Tasks grouped by task type into phases with computed progress (completed/in-progress/upcoming). Collapsed on mobile, expanded on desktop.
- **Document visibility overrides** — Portal-level branding settings (show/hide quantities, unit prices, line totals, descriptions, tax, discount) override document template settings. Three-state control: "Use template" (null) / "Always show" (true) / "Always hide" (false).
- **Token-based branding** — The magic link landing page loads branding from the validate-token API response and applies CSS vars before rendering, so the email form is company-branded from the first frame.
- **Project switcher** — Multi-project clients can switch between projects from the project detail page without returning to home.

### Architecture
```
/portal/[token]              → Magic link landing (public, company-branded)
/portal/verify               → Session expired fallback (public)
/portal/home                 → Dashboard: projects, estimates, invoices
/portal/estimates/[id]       → Estimate detail + approve/decline
/portal/estimates/[id]/questions → Answer line-item questions
/portal/invoices/[id]        → Invoice detail + balance callout
/portal/projects/[id]        → Project detail + phase timeline + photos
/portal/messages             → Two-way messaging with project context
```

---

## Database Schema

Six Supabase tables, all with RLS enabled. Migration file: `supabase/migrations/007_portal_schema.sql`

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
| is_preview | BOOLEAN | For admin preview tokens |

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
| show_quantities | BOOLEAN | null | null=inherit from template |
| show_unit_prices | BOOLEAN | null | null=inherit from template |
| show_line_totals | BOOLEAN | null | null=inherit from template |
| show_descriptions | BOOLEAN | null | null=inherit from template |
| show_tax | BOOLEAN | null | null=inherit from template |
| show_discount | BOOLEAN | null | null=inherit from template |
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
Client <-> company messaging. Two sender types.

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

---

## Authentication Flow

### Magic Link Flow
```
1. Company sends estimate/invoice → POST /api/portal/share
   → Creates portal_token (7-day expiry)
   → Sends branded email via SendGrid with magic link

2. Client clicks link → /portal/[64-char-hex-token]
   → Page calls GET /api/portal/auth/validate-token
   → Response includes branding: { logoUrl, accentColor, template, themeMode, companyName }
   → Page generates CSS vars from branding and applies BEFORE rendering form
   → Shows company-branded email verification form (logo, company name, accent CTA)

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
Main data aggregation service.
- `getPortalData(clientId, companyId)` → `PortalClientData` (client, company, branding, projects, estimates, invoices, unread count)
- `getEstimateForPortal(estimateId, clientId)` → estimate + line items + questions/answers + template
- `getInvoiceForPortal(invoiceId, clientId)` → invoice + line items + payments + template
- `getProjectForPortal(projectId, clientId)` → project + tasks (with taskType) + photos (structured: id, url, thumbnailUrl, source, caption, is_client_visible) + estimates + invoices
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
- `sendMessage(data)` → insert (supports `projectId` context from URL param)
- `markRead(messageId)` / `markAllRead(clientId, companyId)`
- `getUnreadCount(clientId, companyId)` / `getUnreadCountForCompany(companyId)`
- `getConversations(companyId)` → grouped by client for admin inbox

### PortalBrandingService (`portal-branding-service.ts`)
- `getBranding(companyId)` → get or create default
- `updateBranding(companyId, data)` → upsert (now includes visibility override fields)

### PortalActivityService (`portal-activity-service.ts`)
Non-blocking activity logging for portal events. Catches errors and logs them but never throws.

---

## Branding & Theme System

### Templates

| Template | Heading Font | Body Font | Radius | Vibe |
|----------|-------------|-----------|--------|------|
| **Modern** | Inter (500) | Inter | 12px | Clean SaaS, generous whitespace |
| **Classic** | Merriweather (700) | Inter | 8px | Professional serif headings |
| **Bold** | Oswald (600) | Open Sans | 4px | Trade/construction, uppercase headings |

### CSS Custom Properties (Expanded)

`generatePortalTheme(branding)` in `src/lib/portal/theme.ts` returns 30+ CSS vars applied to the portal shell:

**Standard properties:**
```
--portal-bg, --portal-card, --portal-text, --portal-text-secondary, --portal-text-tertiary
--portal-accent, --portal-accent-text, --portal-accent-hover
--portal-border, --portal-success, --portal-warning, --portal-error
--portal-heading-font, --portal-body-font, --portal-heading-weight
--portal-heading-transform, --portal-letter-spacing
--portal-radius, --portal-radius-sm, --portal-radius-lg
--portal-card-padding
```

**Card properties:**
```
--portal-card-shadow, --portal-card-border
--portal-card-accent-edge, --portal-card-accent-edge-width
```

**Progress properties:**
```
--portal-progress-height, --portal-progress-radius
```

**Gallery properties:**
```
--portal-gallery-gap, --portal-gallery-item-radius
```

**Bubble properties (messages):**
```
--portal-bubble-radius
```

**Status badge properties:**
```
--portal-status-style  (pill-rounded | pill-bordered | text-bold)
```

**Section properties:**
```
--portal-section-divider, --portal-section-divider-color, --portal-section-divider-height
```

**Header properties:**
```
--portal-header-style, --portal-header-border
```

All portal components use `var(--portal-xxx)` via inline styles, with Tailwind for layout.

### Document Visibility Overrides

Portal branding settings include 6 visibility override fields. Resolution order:
1. Portal branding override (non-null) → takes precedence
2. Document template setting → used when portal override is null
3. Default → true (show everything)

Resolved by `resolvePortalVisibility()` in `src/lib/portal/resolve-visibility.ts`.

---

## Portal Pages

### Magic Link Landing (`/portal/[token]`)
- Validates token on load → gets branding from API response
- Generates CSS vars from branding data BEFORE rendering
- Shows company-branded form: logo centered, company name, email input, accent CTA
- Error states maintain company branding
- "powered by OPS" subtle at bottom
- Preview tokens auto-verify (no email needed)

### Session Expired (`/portal/verify`)
- Same visual treatment as landing page
- Clock icon + "Your session has expired" messaging
- Contact provider hint
- "powered by OPS" subtle at bottom

### Portal Home (`/portal/home`)
- Welcome: "Hi, [FirstName]" + company welcome message
- **Estimates needing attention**: status `sent`/`viewed` or `hasUnansweredQuestions`
- **Invoices due**: balance > 0, not void/written_off
- **Your projects**: grid of project cards

### Project Detail (`/portal/projects/[id]`)
Sections in order:
1. **Project Header** — title, status badge, address, date range. Project switcher if client has 2+ projects.
2. **Project Progress** — `PortalPhaseTimeline` component. Tasks grouped by taskType into phases. Phase status computed: all completed → completed, any in progress → in progress, all upcoming → upcoming. Collapsed on mobile, expanded on desktop.
3. **Photos** — `PortalPhotoGallery` component. Default: horizontal scroll row of latest 4-6 photos. "See All" expands to full gallery grouped by source (Site Visit / In Progress / Completion). Only shows photos where `is_client_visible = true`. Hidden if no photos.
4. **Documents** — flat list of linked estimates/invoices. Action-needed items highlighted with accent border + AlertCircle icon.
5. **Contact** — "Send a Message" CTA linking to `/portal/messages?projectId=${id}`.

### Estimate Detail (`/portal/estimates/[id]`)
- Header: number, title, status badge, dates, expiration warning
- From/To party sections
- Client message from company
- Line items: conditionally show/hide quantity, unit price, line total, description based on `resolvePortalVisibility()`
- Question callout card above actions if unanswered questions exist
- **Action hierarchy** (when status is sent/viewed/changes_requested):
  - **Approve**: full-width accent CTA at top
  - **Request Changes**: half-width muted button (left)
  - **Decline**: half-width muted button (right)
- All dialogs at z-[3000] (modal layer)

### Line Item Questions (`/portal/estimates/[id]/questions`)
- Grouped by line item with section headers
- Progress indicator: "X of Y required questions answered"
- 5 answer types: text, number, select, multiselect, color
- Pre-fills existing answers
- Submit validates all required answered

### Invoice Detail (`/portal/invoices/[id]`)
- Header: number, dates, status, due date
- From/To party sections
- Line items with visibility overrides from `resolvePortalVisibility()`
- **Balance Due Callout** — prominent visual block pulled out of totals:
  - Balance > 0: large centered balance amount. No Pay button (deferred until Stripe integration).
  - Balance = 0: green "Paid in Full — Thank You" confirmation block with check icon.
  - Overdue: due date in warning color, warning border on balance block.
- Totals summary (subtotal, discount, tax, total, amount paid)
- Payment history: chronological list with date, method, reference, amount

### Messages (`/portal/messages`)
- Reads `projectId` from URL search params for context tagging
- Auto-attaches `projectId` to the first message sent if present
- Skin-aware bubble radius (`--portal-bubble-radius`)
- Threaded view: client messages right (accent), company messages left (card)
- Date-grouped separators
- Auto-scroll to latest
- Compose area: textarea + send button

---

## Portal Components

### Status Badge (`portal-status-badge.tsx`)
Reads `--portal-status-style` CSS var to determine rendering:
- `pill-rounded`: rounded-full background with text (default)
- `pill-bordered`: rounded-full border with text, no background fill
- `text-bold`: no pill, just bold colored text

Status → color mapping: approved/paid=success, sent=accent, viewed/awaiting_payment=warning, declined/past_due=error, etc.

### Phase Timeline (`portal-phase-timeline.tsx`)
Groups tasks by `taskType.name`. Each group is a "phase." Phase status computed from task statuses. Tasks with no taskType go into an "Other" phase. Mobile: collapsed by default, tap to expand. Desktop: all expanded.

### Photo Gallery (`portal-photo-gallery.tsx`)
Accepts structured photos (id, url, thumbnailUrl, source, caption). Default: horizontal scroll row. "See All" expands grouped by source. Lightbox at z-[3000] with keyboard/swipe navigation and captions.

### Project Switcher (`portal-project-switcher.tsx`)
Only rendered when client has 2+ projects. Dropdown showing project title + status. Navigates to new project on select.

---

## Admin-Side Portal Features

### Portal Branding Settings Tab
`src/components/settings/portal-branding-tab.tsx`

Sections:
1. **Company Logo** — toggle company logo vs custom upload
2. **Accent Color** — preset swatches + custom hex input
3. **Portal Template** — 3 radio cards (Modern, Classic, Bold)
4. **Theme Mode** — Light/Dark toggle
5. **Welcome Message** — Textarea
6. **Document Display** — 6 toggle groups (quantities, unit prices, line totals, descriptions, tax, discount). Each has 3 states: "Use template setting" (null) / "Always show" (true) / "Always hide" (false). Implemented as segmented controls.

Preview: inline mockup shows template + accent + theme changes in real-time. Full preview via "Preview Portal" button creates a preview token and opens in new tab.

---

## i18n Keys

All portal text uses `useDictionary("portal")`. Dictionaries at:
- `src/i18n/dictionaries/en/portal.json`
- `src/i18n/dictionaries/es/portal.json`

Key namespaces:
- `nav.*` — navigation labels
- `home.*` — home page
- `project.*` — project detail (includes `progress`, `documents`, `contact`, `switchProject`)
- `estimate.*` — estimate detail
- `invoice.*` — invoice detail (includes `paidInFull`)
- `messages.*` — messages page
- `landing.*` — magic link landing (includes `validating`, `verifyTitle`, `verifyDesc`, `emailPlaceholder`, `accessPortal`, `expiredTitle`, `invalidTitle`, `poweredBy`)
- `verify.*` — session expired (includes `subtitle`, `contactProvider`)
- `phaseTimeline.*` — phase timeline (includes `other`, `current`)
- `taskTimeline.*` — task status labels
- `gallery.*` — photo gallery (includes `seeAll`, `showLess`, `sourceSiteVisit`, `sourceInProgress`, `sourceCompletion`)
- `questions.*` — question flow
- `payment.*` — payment flow
- `toggle.*` — language toggle

Settings i18n (`useDictionary("settings")`):
- `portalBranding.visibilityTitle` — "Document Display"
- `portalBranding.visibilityDesc` — description
- `portalBranding.useTemplate`, `alwaysShow`, `alwaysHide` — segmented control labels
- `portalBranding.quantities`, `unitPrices`, `lineTotals`, `descriptions`, `tax`, `discount` — field labels

---

## Z-Index Scale (Portal)

| Layer | z-index | Usage |
|-------|---------|-------|
| Content | 0-10 | Normal page flow |
| Dropdown | 1000 | Project switcher dropdown |
| Modal | 3000 | Lightbox, approve/decline dialogs |

---

## Deferred Features

1. **Stripe payment integration** — Pay Now button hidden on invoice detail until Stripe Elements integration is complete.
2. **Real-time messaging** — Currently polling every 15s. Supabase Realtime subscription planned.
3. **Photo upload from portal** — Clients can view but not upload photos. Planned for future release.
4. **Portal notifications** — Push/email notifications for portal events (new estimate, message reply). Currently email-only via SendGrid.

---

## File Inventory

### Portal-Specific Files

**Theme & Visibility (4):**
- `src/lib/portal/theme.ts` — generates CSS custom properties from branding
- `src/lib/portal/templates.ts` — template configs (fonts, radii, weights)
- `src/lib/portal/resolve-visibility.ts` — portal branding visibility overrides
- `src/lib/portal/resolve-template-branding.ts` — template branding merger

**Portal Pages (11):**
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

**Portal Components (14):**
- `src/components/portal/portal-shell.tsx`
- `src/components/portal/portal-header.tsx`
- `src/components/portal/portal-nav.tsx`
- `src/components/portal/portal-project-card.tsx`
- `src/components/portal/portal-status-badge.tsx` — skin-aware (pill-rounded/pill-bordered/text-bold)
- `src/components/portal/portal-estimate-view.tsx`
- `src/components/portal/portal-line-item-card.tsx`
- `src/components/portal/portal-question-field.tsx`
- `src/components/portal/portal-invoice-view.tsx` — with balance due callout
- `src/components/portal/portal-payment-form.tsx`
- `src/components/portal/portal-photo-gallery.tsx` — structured photos, source grouping, lightbox
- `src/components/portal/portal-task-timeline.tsx`
- `src/components/portal/portal-phase-timeline.tsx` — task type grouping, phase progress
- `src/components/portal/portal-project-switcher.tsx` — multi-project navigation

---

## Business Rules

1. **Token expiry:** 7 days. Session expiry: 30 days.
2. **Email verification:** Client must enter the exact email associated with their client record.
3. **Data isolation:** All service methods verify `client_id` matches session to prevent cross-client access.
4. **Activity logging is non-blocking:** Errors are logged but never thrown.
5. **Estimate actions:** Only available when status is `sent`, `viewed`, or `changes_requested`.
6. **Questions required:** All required questions must be answered before submission.
7. **Branding defaults:** New companies get Modern template, dark mode, #417394 accent, all visibility overrides null (inherit from template).
8. **Message context:** Messages can be tagged with projectId from URL search params on first send.
9. **Photo visibility:** Only photos with `is_client_visible = true` are shown in the portal.
10. **Visibility cascade:** Portal branding overrides (non-null) → document template settings → default (show all).
