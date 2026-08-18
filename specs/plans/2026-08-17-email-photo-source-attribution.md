# Email Photo Source Attribution Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use `custom-skills:executing-plans` to implement this plan task-by-task.

**Goal:** Photos imported by the email→project conversion pipeline are attributed to their email origin (`source='email'` + sender linkage) and that origin is visible in the web and iOS photo detail surfaces.

**Architecture:** Three prod migrations — (A) additive `photo_source` enum value `'email'`, (B) additive nullable provenance columns on `project_photos`, (C, **staged — apply only at web-deploy GO**) completion-function rewrite + backfill that actually flips pipeline photos to `source='email'`. Web widens the `PhotoSource` type, adds an "Email" gallery group and lightbox origin line. iOS adds an optional synced `origin_sender_email` field and an origin row in the photo viewer.

**Tech Stack:** Supabase Postgres (project `ijeekuhbatykdomumfjx`), Next.js 15 (ops-web), SwiftData/SwiftUI (ops-ios).

**Design System:** `ops-design-system/project/DESIGN.md` (+ `mobile/MOBILE.md` for iOS). No `.interface-design/system.md` in either repo.

**Required Skills:** `ops-design`, `frontend-design:frontend-design` (web task W4), `custom-skills:mobile-ux-design` (iOS task I4), `ops-copywriter:ops-copywriter` (all user-facing labels), `custom-skills:audit-design-system` (before calling UI done), `superpowers:test-driven-development`.

---

## Verified context (do NOT re-derive; verified live 2026-08-17)

- **Defect 1 (content dedupe) is ALREADY FIXED and live.** Unique index `email_conversion_photo_jobs_active_project_hash_unique (company_id, project_id, source_content_sha256) WHERE operation='materialize'` exists in prod; enqueue paths use `on conflict do nothing`; migration `20260811232704_quoted_email_photo_provenance_dedup.sql` is merged to `origin/main` (merge `719fcef9`) and applied to prod (ledger `20260817193948`). **No dedupe work in this plan.**
- Live `photo_source` enum values: `site_visit, in_progress, completion, other, measurement, deck_design`. No `'email'`.
- Live `public.complete_email_conversion_photo_job` (prosrc 7,385 chars) hardcodes `source='other'` in BOTH its insert path and its adopt/update path, and sets `uploaded_by = coalesce(conversion_event.actor_user_id::text, 'system')`. **Later 08-17 migrations may have touched it — build migration C from `pg_get_functiondef` pulled live at execution time, never from the July/August migration files.**
- `email_attachments` has `from_email text`, `provider_thread_id text`, `message_id text`, `occurred_at timestamptz`. `email_conversion_photo_jobs.email_attachment_id` links jobs → attachments; `project_photo_id` links jobs → photos.
- Backfill scope: exactly **12** completed materialize jobs with `project_photo_id`; all 12 photos exist, all `source='other'`, 1 soft-deleted (flip it too — harmless, keeps history honest).
- `project_photos` triggers: `trg_project_photos_00_write_guard` only guards soft-delete by `anon/authenticated`; migrations run as postgres — no interference. `update_project_photos_timestamp` bumps `updated_at` (good — iOS sync sees the change). `project_photos_bump_agent_operational_read_revision` bumps agent read revision (fine).
- iOS `ProjectPhotoDTO` decodes `source` as optional **String** (no enum) → a new enum value syncs through every installed build safely (additive-only constraint satisfied). iOS gallery filter is a **denylist** (`ProjectPhoto.nonGallerySources = ["deck_design"]`) so `'email'` photos remain visible everywhere they should be.
- Web `PhotoSource` union (`src/lib/types/pipeline.ts:1584`) is `"site_visit" | "in_progress" | "completion" | "other"` — already missing `measurement`/`deck_design`.
- Web gallery `src/components/ops/project-photo-gallery.tsx`: groups by `SOURCE_ORDER`, upload selector iterates `SOURCE_ORDER` too (must be split), unknown sources are silently dropped from groups (no crash) while `totalCount` still counts them. This silent-drop is WHY migration C is staged: flipping `source` before the new web bundle deploys would hide the 12 photos from the deployed gallery.
- Agent read RPCs (`read_agent_job_summary_as_system`, `read_agent_job_participant_snapshot_v5_impl`, `read_agent_job_readiness_issues_v4_impl`) reference `'other'` near `project_photos` — task W2 must inspect and confirm whether they filter by photo source; only touch them if they do.

## Rollout sequence (the point of the staging)

1. Migrations A + B apply to prod **immediately** (pure additive, invisible to every deployed client).
2. All web + iOS code lands in repos now, ready to ship.
3. Migration C (function flip + backfill) is authored, committed, and archived now, but **applied only when Jackson gives the push GO for ops-web main** — apply C, then push, in the same action. Until then pipeline photos keep landing as `'other'` (current behavior, no regression).
4. iOS origin UI ships with the next App Store release; until then installed builds show email photos exactly as today.

---

## Part W — ops-web + database (one Opus agent, fresh worktree off `origin/main`)

Worktree: `git worktree add .claude/worktrees/email-photo-attribution -b feat/email-photo-source-attribution origin/main` from `/Users/jacksonsweet/Projects/OPS/ops-web`. Run `npm ci` inside the worktree (shared `node_modules` follows the primary's branch manifest — never reuse it). Never touch the primary checkout (it carries sibling WIP on `feat/inbox-dark-launch`).

### Task W1: Migration A — enum value

**Files:** Create `supabase/migrations/20260817220000_photo_source_email_enum.sql`

```sql
-- Additive enum value for email-pipeline photo attribution.
-- Safe for every deployed client: web narrows unknown sources out of
-- gallery groups; iOS decodes source as a plain string.
alter type public.photo_source add value if not exists 'email';
```

One statement, its own migration (a new enum value cannot be used in the transaction that adds it). Commit: `feat(db): add email photo_source enum value`.

### Task W2: Migration B — provenance columns

**Files:** Create `supabase/migrations/20260817220100_project_photo_email_provenance.sql`

```sql
-- Email-origin provenance for pipeline-imported project photos.
-- Nullable + additive: invisible to deployed iOS builds (additive-only
-- sync constraint) and to the deployed web bundle.
alter table public.project_photos
  add column if not exists email_attachment_id uuid
    references public.email_attachments(id) on delete set null,
  add column if not exists origin_sender_email text;

create index if not exists project_photos_email_attachment_idx
  on public.project_photos (email_attachment_id)
  where email_attachment_id is not null;
```

Also in this task: pull the three agent read RPC bodies via `pg_get_functiondef` and grep for photo-source filtering; report findings in the final summary (expected: `'other'` refs are unrelated). Commit: `feat(db): project photo email provenance columns`.

### Task W3: Migration C — STAGED completion-function flip + backfill

**Files:** Create `supabase/migrations/staged/20260817_STAGED_email_photo_source_attribution.sql` (note the `staged/` directory — this file must NOT sit in the auto-applied migrations path until GO. Create the directory; add a `README.md` inside explaining the GO condition.)

Construction procedure (do exactly this):
1. `select pg_get_functiondef(oid) from pg_proc join pg_namespace n on n.oid=pronamespace where nspname='public' and proname='complete_email_conversion_photo_job';` — via Supabase MCP `execute_sql`, at authoring time.
2. Take that LIVE definition verbatim. Make only these edits:
   - Declare `attachment_from_email text;` and populate it after the job row is loaded: `select att.from_email into attachment_from_email from public.email_attachments att where att.id = job.email_attachment_id;`
   - Insert path: `'other'` → `'email'`; add `email_attachment_id` and `origin_sender_email` to the column list with values `job.email_attachment_id`, `nullif(btrim(coalesce(attachment_from_email,'')),'')`.
   - Adopt/update path: `source = 'other'` → `source = 'email'`; add `email_attachment_id = job.email_attachment_id, origin_sender_email = nullif(btrim(coalesce(attachment_from_email,'')),'')`.
   - Nothing else changes — byte-identical otherwise.
3. Append the backfill:

```sql
update public.project_photos ph
   set source = 'email',
       email_attachment_id = j.email_attachment_id,
       origin_sender_email = nullif(btrim(coalesce(att.from_email, '')), '')
  from public.email_conversion_photo_jobs j
  left join public.email_attachments att on att.id = j.email_attachment_id
 where j.project_photo_id = ph.id
   and j.operation = 'materialize';
```

(12 rows expected; include a trailing `-- expect: UPDATE 12` comment.)

Commit: `feat(db): staged email photo attribution flip + backfill`.

### Task W4: Web types + gallery + lightbox origin

**Skills:** `ops-design`, `frontend-design:frontend-design`, `ops-copywriter:ops-copywriter`, then `custom-skills:audit-design-system`.

**Files:**
- Modify `src/lib/types/pipeline.ts:1584` — widen to the full DB enum: `export type PhotoSource = "site_visit" | "in_progress" | "completion" | "other" | "measurement" | "deck_design" | "email";` Add `emailAttachmentId: string | null` and `originSenderEmail: string | null` to the `ProjectPhoto` interface.
- Modify `src/lib/types/database.types.ts` — hand-add `"email"` to the `photo_source` enum union only. Do NOT full-regenerate (prod carries unrelated agent-wave schema).
- Modify `src/lib/api/services/project-photo-service.ts` — `mapFromDb` gains `emailAttachmentId: (row.email_attachment_id as string) ?? null, originSenderEmail: (row.origin_sender_email as string) ?? null`.
- Modify `src/components/ops/project-photo-gallery.tsx`:
  - Split constants: `DISPLAY_SOURCES` (site_visit, in_progress, completion, email, other) drives grouping/rendering; `UPLOAD_SOURCES` (site_visit, in_progress, completion, other) drives the upload selector — `'email'` is pipeline-only and must never be a manual choice. `measurement`/`deck_design` stay out of both (today's behavior, now type-honest).
  - `SOURCE_CONFIG` typed `Record<DisplaySource, …>` gains the email entry. Color: steel-blue accent family per DESIGN.md — trace to a token/utility the codebase already uses (check `globals.css` / tailwind config before writing any hex; the existing hexes in this file are legacy — do not add a new hardcoded hex).
  - Lightbox receives the whole photo and renders an origin line for `source === 'email'` with `originSenderEmail` (fall back to nothing if null): terse product register, e.g. `From mark@client.com` — final wording via `ops-copywriter`. JetBrains Mono for the address is correct (it's data).
  - Group label wording via `ops-copywriter` (candidate: `From Email` — answers "where did these come from" at scan level; match the title-case style of sibling labels).
- Inspect (change only if they narrow by source): `src/lib/api/services/project-table-photo-service.ts`, `src/lib/api/services/project-preview-service.ts`, `src/app/api/portal/projects/[id]/route.ts`, `src/lib/hooks/use-client-files.ts`, `src/app/(dashboard)/projects/_components/table-v2/cells/cell-photos.tsx`, `src/lib/hooks/use-project-photos.ts`, `src/app/api/uploads/share-photo/route.ts` (+ `file_share_photo_as_system` is DB-side, untouched).

TDD: write/extend a unit test first for the gallery grouping (email photos land in the email group, never in upload options) and for `mapFromDb` provenance mapping. Targeted vitest runs only (`npx vitest run <files>`) — full-suite runs are unreliable in this repo (cross-file pollution). Then `npm run build` (use `NODE_OPTIONS=--max-old-space-size=8192`). Commit: `feat(photos): email origin group + lightbox provenance`.

### Task W5: Migration tests

**Files:** Extend `tests/unit/supabase/email-conversion-photo-materialization-migration.test.ts` (read it first; follow its existing harness pattern) to assert the STAGED migration file: contains `'email'` source in both write paths, provenance columns in insert list, backfill statement present, and — critically — that the staged file's function definition matches live-def-modulo-the-planned-edits (the test can at minimum assert the staged file never reintroduces `'other'` in the two write paths). Run those test files targeted. Commit with W3 if more natural: keep commits atomic per logical change.

### Task W6: Bible + migration archive

**Files (repo `ops-software-bible/`):**
- Follow `ops-software-bible/migrations/README.md` (it governs; read it first) to archive migrations A, B, and C — mark C **STAGED / NOT APPLIED** exactly as the README's convention allows; if it has no staged convention, add the two applied ones and note C in the section doc.
- Update `10_JOB_LIFECYCLE_AND_DATA_RELATIONSHIPS.md`: pipeline paragraph (~line 1470) gains the attribution behavior; photo table section (~line 3170) enum list gains `email` + the two provenance columns.
- Update `07_SPECIALIZED_FEATURES.md` (~line 1122 enum mention, ~8528 enum-history note).
Commit in bible repo: `docs(photos): email photo source attribution + staged migration archive`.

## Part I — ops-ios (one Opus agent, fresh worktree)

Worktree: `git worktree add .claude/worktrees/email-photo-origin -b feat/email-photo-origin main` from `/Users/jacksonsweet/Projects/OPS/ops-ios`. Copy `OPS/Utilities/Secrets.xcconfig` in; build with `-clonedSourcePackagesDirPath .spm-local`. Check `ps aux | grep xcodebuild` before builds (parallel sessions).

### Task I1: DTO + fetch paths

**Files:** Modify `OPS/Network/Supabase/DTOs/ProjectPhotoDTOs.swift` — add `let originSenderEmail: String?` with key `"origin_sender_email"`, thread into `toModel()`. Verify every `from("project_photos")` fetch (`ImageSyncManager.swift` ×5, `ProjectPhotoRepository.swift` ×2, `DimensionedPhotoSyncManager.swift:187`) uses `select("*")` or add the column to explicit select lists. Preserve CRLF/whitespace conventions.

### Task I2: Model + SwiftData schema compliance

**Files:** Modify `OPS/DataModels/Supabase/ProjectPhoto.swift` — add `var originSenderEmail: String?` (+ init param, default nil). **This is a @Model edit:** read `OPS/DataModels/Migrations/` (OPSSchemaV9/OPSSchemaCommon/OPSMigrationPlan) first and follow the established versioning pattern for additive optional properties; then run `AppUpdateMigrationTests` in the sim — mandatory, non-negotiable (V23 live-model-widening incident rule). Also confirm inbound merge code (wherever DTO→model updates apply field-by-field, likely in ImageSyncManager or a merge helper) copies the new field on update, not just insert.

### Task I3: Tests first

Extend the existing DTO/sync test coverage (find `ProjectPhoto` tests under `OPSTests/`): decode fixture with `source: "email"` + `origin_sender_email`, assert model fields; assert unknown-source string passes through; assert gallery eligibility for `'email'` (denylist untouched). Run targeted tests via sim destination; remember xcresult over stdout (SUCCEEDED can mean 0 tests — verify the xcresult shows the new tests ran).

### Task I4: Viewer origin row

**Skills:** `ops-design`, `custom-skills:mobile-ux-design`, `ops-copywriter:ops-copywriter`, then `custom-skills:audit-design-system`.

**Files:** `OPS/Views/Components/Images/PhotoCommentViewer.swift` (the photo detail surface — read its metadata region first; if caption/date render elsewhere, e.g. `ZoomablePhotoView` or `ProjectPhotosGrid` detail overlay, put the origin row where the photo's other metadata lives, not a new surface). When `photo.source == "email"` and `originSenderEmail` is non-nil: one terse metadata row — `envelope` SF Symbol via `OPSStyle.Icons` conventions + sender address in `OPSStyle.Typography` caption/mono per MOBILE.md data-typography rules, all colors/spacing from OPSStyle tokens. Nothing on grid tiles (invisible helpfulness — detail-level answer to a detail-level question). Sender missing → row absent entirely (no `—` here; the row is optional context, not a data field).

### Task I5: Build proof + commit

Device-generic build (`xcodebuild -scheme OPS -destination 'generic/platform=iOS'` with `.spm-local`), targeted test run green (xcresult-verified), snapshot/screenshot proof of the origin row if the harness allows (AppHostWindow rules). Atomic commits on the worktree branch: `feat(photos): sync email origin sender`, `feat(photos): email origin row in photo viewer`. Do NOT merge to local main — report back; the coordinating session merges after checking sibling state.

## Verification (coordinating session, after both parts land)

1. Apply A then B to prod via MCP `apply_migration`; verify: enum has `email`, columns exist, index exists.
2. Confirm staged C file parses (`psql`-free check: the migration test from W5 is the gate) and its backfill targets exactly 12 rows (`select count(*) …` dry-run of the join).
3. Web worktree: targeted vitest green + production build green (evidence: command output).
4. iOS worktree: build + tests green (evidence: xcresult summary), AppUpdateMigrationTests green.
5. Bible updated + migrations archived; `scripts/sync-agent-docs.sh` NOT needed (no CLAUDE.md edits).
6. Report to Jackson: what customers will see, what ships at his push GO (apply C + push together), what ships at next App Store release.
