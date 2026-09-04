# Supabase Migration Archive

Mirror of every migration applied to prod (`ijeekuhbatykdomumfjx`), keyed to the migration ledger
`supabase_migrations.schema_migrations`. One file per ledger row, named `<ledger_version>_<ledger_name>.sql`.

**Coverage guarantee (backfill of 2026-08-12):** all 651 ledger versions as of 2026-08-12 have a file here.
609 are byte-identical to the applied SQL stored in the ledger (md5-verified, trailing newline appended);
the exceptions are enumerated below. The ledger stores each migration exactly as submitted, so it is the
authority for *what actually ran*; this directory is its checked-in mirror.

## Rules going forward

- Applying a migration (MCP `apply_migration` or CLI) ⇒ mirror the exact applied SQL here **in the same session**,
  named `<ledger_version>_<ledger_name>.sql`. The ledger version is stamped at apply time — read it back from
  `supabase_migrations.schema_migrations`, do not reuse a locally chosen timestamp.
- Schema changes applied via `execute_sql` (no ledger row) still get a file here, named with the run timestamp;
  they are listed under *Out-of-ledger changes* below when discovered.
- Verify a mirror at any time:

```sql
select md5(statements[1]) from supabase_migrations.schema_migrations where version = '<version>';
-- equals md5 of the file with its single trailing newline stripped
```

## Naming quirks (historical)

- Ledger names sometimes embed an older working name, giving double-stamped or dated filenames, e.g.
  `20260528025638_20260527150000_onboarding_email_log.sql` and `20260506235148_2026_05_06_01_catalog_schema.sql`.
  The leading 14 digits are always the ledger version; the rest is the ledger name verbatim.
- Files dated `2026-05-*.sql` (no 14-digit stamp) predate this convention. Each is mapped below; where its content
  drifted from the applied text, the canonical `<version>_<name>.sql` produced by the backfill sits alongside it.

## Invisible Office day-closeout release (2026-08-31 UTC)

- `20260831042518_agent_day_closeout_foundation_zero.sql`
- `20260831042631_agent_day_closeout_routine_worker.sql`
- `20260831042924_agent_day_closeout_fk_indexes.sql`

All three are byte-exact against `supabase_migrations.schema_migrations.statements[1]`: 40,971 bytes / SHA-256 `ddc67ee5999b555cd3c6835ea408e66ce5764e9fef2b366f74b67c155947e7d7`; 27,377 bytes / `09a8649add196f172a1d68a0e862a91b59272d75c5f33a931228f1dd0c1d876a`; and 1,114 bytes / `2d1296ab7afeec4bd9fc96c0db04463d00e3d04b773893a3deeef59242669dc7`. They install the dormant, private day-closeout persistence/worker boundary and its covering foreign-key indexes. Application release does not register its cron, create or enable a routine, or activate MCP v3.

## Invisible Office Phases 3–7 release (2026-09-02 UTC)

- `20260902194603_agent_hiring_what_if_read.sql`
- `20260902194631_agent_promise_recovery_read.sql`
- `20260902194703_agent_sales_truth_read.sql`
- `20260902194727_agent_payroll_readiness.sql`
- `20260902194758_agent_recurring_service_price_change.sql`
- `20260902195149_agent_recurring_service_price_index_dedupe.sql`
- `20260902195335_agent_recurring_service_price_fk_indexes.sql`

All seven are byte-identical to the corresponding committed source under `supabase/migrations/` and the SQL submitted to production. They install the dormant v5–v9 database boundaries, remove one definition-equivalent provider-delivery index, and cover every recurring-price policy foreign key. Release does not create an OAuth client or grant, activate an exposure, send a notice, change a price, or make a capability customer-live. Full proof: `specs/2026-09-02-ops-mcp-phases-3-7-production-release.md`.

## Invisible Office Phase 8 release (2026-09-03 UTC)

- `20260903110828_agent_estimate_draft_preview.sql`

The archive is byte-identical to the committed source `supabase/migrations/20260902231632_agent_estimate_draft_preview.sql` and the one statement stored in production ledger `20260903110828`: 42,223 bytes, MD5 `a180b8ef634f6aec19b6734d3601a0bf`, SHA-256 `a24282619e24c5f0d14135940e7f88a226b93b237c71842d97e779f44c8ce9f7`. It installs only the dormant v10 estimate-draft snapshot and final authority functions. Release creates no estimate or preview row, reserves no number, sends nothing, and creates no v10 client or grant. Full proof: `specs/2026-09-02-ops-mcp-estimate-draft-vertical.md`.

## Canpro supplier bill clearance release (2026-09-04 UTC)

- `20260904171301_supplier_bill_intake_clearance.sql` — 52,199 bytes, MD5 `c1999781a038c5b4669780f3b0f02c9a`.
- `20260904171632_supplier_bill_intake_fk_indexes.sql` — 2,249 bytes, MD5 `7ebe982a2e7d05e1d6054f673a7c84a4`.

Both archives are byte-exact against `supabase_migrations.schema_migrations.statements[1]` and their committed OPS-Web source migrations. They install the pre-AP evidence, review, clearance, guarded mutation, and permission boundary plus covering indexes for all 13 introduced foreign keys. Release created no intake, write-intent, canonical AP link, or provider queue row. Full proof: `specs/2026-09-03-canpro-supplier-bill-clearance.md`.

## Ledger rows without stored SQL (file is the authority)

These 6 CLI-era ledger rows have an empty `statements` array; the version-named file is the only record of their SQL:

- `20260602200000_qbo_qb_id_unique_indexes.sql`
- `20260603000000_qbo_realm_lookup.sql`
- `20260603010000_accounting_connections_read_policy.sql`
- `20260604180000_email_templates_create_with_bridged_rls.sql`
- `20260604190000_complete_legacy_perf_indexes_041_057.sql`
- `20260604190001_fix_create_notification_if_new_onconflict.sql`

One row was applied via `supabase db push`, which split the file into 14 ledger statements:
- `20260527210000_lead_lifecycle_p4_guarded_action_audit.sql` — file verified equal to the recorded statement sequence.

## Out-of-ledger changes (no ledger row; file is the only record)

- `20260807123000_manual_project_link_any_address.sql`
- `20260807123500_authorize_lead_summary_refresh.sql`
- `20260811232704_quoted_email_photo_provenance_dedup.sql`
- `20260818052155_restore_claim_email_send_provider_delivery_grant.sql`
- `20260818224814_repair_web_onboarded_owner_role_rows.sql` — data repair (no DDL). Seeds the
  missing Owner `user_roles` row, `role`/`user_type`, and `company_code` for the 5 web-onboarded
  account holders of bug `bb4775c1-07a5-444c-a9b2-952e9b9b2f0e`. Re-running it is a no-op: its
  precondition block requires all 5 to still match the broken signature and aborts otherwise.

## Staged migrations (authored, deliberately NOT applied)

SQL that is written, reviewed, and committed in `ops-web` but held out of the auto-applied
`supabase/migrations/` path because applying it early would break a currently deployed client. It has no ledger
row and no file in this directory until it is actually applied — at which point it is mirrored here under its
real ledger version like any other migration.

A bounded repair may also be committed to **local-only** OPS-Web `main` while push/deploy/migration approval is
withheld. That source likewise has no production ledger row and no archive mirror until an approved apply is
read back. Once applied, remove it from this staged section and mirror the ledger's exact SQL under the stamped
version. The attachment-shadowing repair followed that path on 2026-08-21 and is archived as
`20260821202539_fix_related_attachment_record_shadowing.sql`.

- `ops-web/supabase/migrations/staged/20260817_STAGED_email_photo_source_attribution.sql` — flips the
  email→project photo pipeline to `source = 'email'` (+ provenance) and backfills the 12 photos already imported
  as `'other'`. **GO condition: the ops-web `main` push GO — apply it and push in the same action**, because the
  deployed gallery silently drops photos whose `source` it does not recognise. Its two additive prerequisites
  (`20260818053040`, `20260818053050`) are already applied, so nothing is half-shipped while it waits.
  See `10_JOB_LIFECYCLE_AND_DATA_RELATIONSHIPS.md` § project_photos.

### Applied by the 2026-08-28 bug-sweep PM (mirrored below, md5-verified)

- `20260829022150_reschedule_site_visit_scheduled_at_null_keeps.sql` — Cluster B; `p_scheduled_at` NULL-keeps.
- `20260829074612_lead_won_prompt_decline_columns.sql` — Cluster F 1/3; additive decline columns (bug `9a89b951`, D3).
- `20260829074731_win_linked_opportunity_rpc.sql` — Cluster F 2/3; SECURITY INVOKER win-with-actor RPC (D3).
- `20260829074744_project_photos_client_update_grant.sql` — iOS bug sweep 2026-08-28 (Cluster D, bug
  `1154fe67`). Widens the client `UPDATE` grant on `public.project_photos` from the three columns granted by
  ledger `20260729162950` to `(deleted_at, is_client_visible, caption, taken_at, thumbnail_url, rendered_url)`.
  The three added columns let the iOS reconciler back-fill capture metadata onto the photo rows
  `private.execute_opportunity_conversion_core` mirrors server-side with `taken_at` NULL and no thumbnails
  (bug `ba75732a`; 214 of 931 rows carry a NULL `taken_at`). **Correction to the bug thread:** the sweep's
  planning probe read `information_schema.role_table_grants`, which reports only TABLE-level grants and is
  blind to column-scoped ones — the original trio has in fact been granted since 2026-07-29, so photo
  soft-delete and client-visibility writes were never grant-blocked. Verified against
  `information_schema.column_privileges` on 2026-08-29. `GRANT` is idempotent, so re-granting the original
  three is a no-op. Row rules (company_isolation RLS, `trg_project_photos_00_write_guard`, the RESTRICTIVE
  hard-DELETE denial) are untouched; `url`/ids/`uploaded_by`/`source` stay non-updatable by client roles.
  See `07_SPECIALIZED_FEATURES.md` § project photos.
  **Applied 2026-08-29, ledger `20260829074744`; mirror md5-verified against `statements[1]`.**

Cluster F 3/3 — the link-trigger surgery that STOPS auto-winning linked leads
(`ops-ios` worktree `docs/migrations/2026-08-28-03-project-opportunity-link-stop-stage-side-effect.staged.sql`)
— is deliberately HELD: applying it before the prompt-bearing clients exist would leave a window where nothing
wins a linked lead. GO condition: the sweep's iOS build verified AND the ops-web won-prompt ships. Apply order
3 of 3; post-apply verification steps are in the file header.

### Authored here, awaiting approval (NOT YET APPLIED)

Fix SQL authored directly in this directory because it targets prod objects rather than riding an `ops-web`
deploy. Each filename carries an **authoring** timestamp, not a ledger version. On apply, read the stamped
version back out of `supabase_migrations.schema_migrations` and rename the file to
`<ledger_version>_<ledger_name>.sql` like any other mirror. Until applied these have no ledger row at all —
verify them by object, never by version key.

- `20260818184224_project_opportunity_link_crew_status_unblock.sql` — H2 crew unblock. Narrows the
  `pipeline.manage @ all` requirement in `public.enforce_project_opportunity_link()` to writes that actually
  mutate the link contract, so an ordinary project status write stops raising `access_denied` for crew.
  Company isolation, link integrity, the `service_role` bypass and the `stage='won'` activation block are all
  preserved unchanged. See `10_JOB_LIFECYCLE_AND_DATA_RELATIONSHIPS.md` § project ↔ opportunity link.
- `20260819163000_remaining_read_policy_row_columns.sql` — finishes the self-lookup read-policy class. The
  `project_tasks` repair (`20260818014340`) fixed one table; the clients/projects repair shipped as ledger
  `20260819152448`; this repoints the last five — `sub_clients.role_scope_read`,
  `calendar_events.calendar_event_read_scope_guard`,
  `calendar_user_events.calendar_user_event_read_scope_guard`, `opportunities.role_scope_read` (first conjunct
  only, merge-target conjunct preserved verbatim) and `job_conversations.job_conversations_job_scope_select` —
  at row-column predicates so no policy re-reads its own table. A catalog scan confirms these were the complete
  remaining set. Note the trigger is `ACL_SELECT`, not `RETURNING` specifically: an `INSERT … ON CONFLICT DO
  UPDATE` with **no** RETURNING is refused too, which is what has kept `calendar_user_events` at 0 inserts in
  30 days despite the client sending `return=minimal`. Authorization ladders preserved exactly; all nine by-id
  functions left in place for their other callers. Proven on a local PostgreSQL 17.11 replica loaded with the
  prod bodies (before = rejected naming each guard, after = accepted, 25/25 visibility cells byte-identical
  across five personas, cross-tenant / born-deleted / deactivated / out-of-scope inserts still refused).
  `job_conversations` is hygiene only — `authenticated` has no INSERT grant there, and its anchor gate is a
  deliberate authorization rule left untouched. See `03_DATA_ARCHITECTURE.md` § Remaining read policies.
- `20260818184300_revoke_legacy_convert_lead_to_project.sql` — H10 dead-code cleanup. Revokes EXECUTE on the
  legacy `public.convert_lead_to_project` shim, the only entry point into the convert transaction that skips
  the `p_expected_stage` / `p_expected_assignment_version` guards and silently discards `p_address`. Revoked
  rather than dropped so a stale client fails loudly (42501) instead of quietly bypassing the guards. Zero
  callers: the shim stamps `legacy_shim` into `opportunity_dispositions.evidence` on every call and none of
  the 26 conversions recorded since 2026-06-02 carries it.
## Legacy files whose content differs from the applied text

Session-written mirrors sometimes drifted from what was actually applied: a prepended doc header, a stray blank
line, or a revision saved to the file after (or applied outside) the ledger apply. The ledger text is the applied
truth; these files are kept untouched as session sources.

**Sole-copy drift (36):** the named file is this archive's only copy for its version and differs from the
applied text — recover the applied text with the SQL recipe above if it matters:

- `20260531200227_fix_expenses_rls_company_and_role_scope.sql` ← ledger `20260531200227`
- `20260531200501_fix_payments_opportunities_permission_scope.sql` ← ledger `20260531200501`
- `20260601163354_fix_cross_tenant_rls_always_true_breaches.sql` ← ledger `20260601163354`
- `20260601163537_inventory_compat_views_security_invoker.sql` ← ledger `20260601163537`
- `20260601163600_rls_no_policy_revoke_client_grants.sql` ← ledger `20260601163600`
- `20260601163641_harden_function_search_path_mutable.sql` ← ledger `20260601163641`
- `20260601163917_revoke_anon_execute_server_only_functions.sql` ← ledger `20260601163917`
- `20260601164310_lock_server_only_functions_to_service_role.sql` ← ledger `20260601164310`
- `20260601210311_expense_envelope_schema.sql` ← ledger `20260601210311`
- `20260601210428_expense_envelope_period_fn.sql` ← ledger `20260601210428`
- `20260601210601_get_or_create_open_batch_v2.sql` ← ledger `20260601210601`
- `20260601210846_place_expense_trigger.sql` ← ledger `20260601210846`
- `20260601211633_expense_envelope_sweep_notify_dedupe.sql` ← ledger `20260601211633`
- `20260601211914_expense_batches_rls_approve_scope.sql` ← ledger `20260601211914`
- `20260601212520_backfill_expense_orphans.sql` ← ledger `20260601212520`
- `20260601213757_expense_envelope_sweep_deep_link_expense.sql` ← ledger `20260601213757`
- `20260601215524_expense_envelope_sweep_cron.sql` ← ledger `20260601215524`
- `20260601215540_lock_tg_place_expense_to_trigger_only.sql` ← ledger `20260601215540`
- `20260602042258_expense_approval_rpcs.sql` ← ledger `20260602042258`
- `20260602042530_expense_envelope_sweep_v3_deeplink_perjob.sql` ← ledger `20260602042530`
- `20260602042658_place_expense_under_threshold_autoclear.sql` ← ledger `20260602042658`
- `20260602202519_expense_realtime_publication.sql` ← ledger `20260602202519`
- `20260714230000_email_attachment_persistence.sql` ← ledger `20260714230000`
- `20260714232000_guarded_email_thread_reassignment.sql` ← ledger `20260714232000`
- `20260716233055_add_projects_vinyl_color_po.sql` ← ledger `20260716233055`
- `20260722225326_create_link_deck_design_to_opportunity_guarded.sql` ← ledger `20260722225326`
- `20260729162135_add_estimates_notes_for_ios_ar_decks.sql` ← ledger `20260729162135`
- `20260729162940_fix_feature_requests_insert_policy_anon_bridge.sql` ← ledger `20260729162940`
- `20260729162950_project_photos_update_grants_and_write_guard.sql` ← ledger `20260729162950`
- `20260730220727_fix_unusable_status_column_defaults.sql` ← ledger `20260730220727`
- `20260731014758_company_purge_definer_for_owner_only_tables.sql` ← ledger `20260731014758`
- `20260731023347_company_purge_definer_full_manifest_coverage.sql` ← ledger `20260731023347`
- `20260731183127_fix_manual_outbound_follow_up_lifecycle_conflict_target.sql` ← ledger `20260731183127`
- `20260731202250_notification_company_id_integrity.sql` ← ledger `20260731202250`
- `20260802_add_email_connections_outreach_subject.sql` ← ledger `20260803015347`
- `20260803015347_add_email_connections_outreach_subject.sql` ← ledger `20260803015347`

**Superseded legacy duplicates (46):** a byte-verified canonical `<version>_<name>.sql` exists alongside;
prefer the canonical file:

- `2026-05-06-01-catalog-schema.sql` → canonical `20260506235148`
- `2026-05-06-03-catalog-data-canpro-maverick.sql` → canonical `20260507003149`
- `2026-05-06-02-catalog-views-triggers.sql` → canonical `20260507003412`
- `2026-05-06-04-permission-rename.sql` → canonical `20260507130217`
- `2026-05-19-convert-lead-to-project-rpc.sql` → canonical `20260520010938`
- `2026-05-20-extend-convert-lead-to-project-site-visit-photos.sql` → canonical `20260520201313`
- `2026-05-20-activities-first-log-auto-advance-trigger.sql` → canonical `20260521004340`
- `2026-05-21-canpro-catalog-reorg.sql` → canonical `20260521171710`
- `2026-05-21-project-vinyl-order-marker.sql` → canonical `20260521222504`
- `2026-05-21-project-vinyl-order-marker.sql` → canonical `20260521223216`
- `2026-05-21-project-vinyl-order-marker.sql` → canonical `20260521224550`
- `2026-05-25-01-catalog-setup-save-rpc.sql` → canonical `20260525234500`
- `2026-05-25-spec-phase1-01-enums-and-capacity.sql` → canonical `20260526061047`
- `2026-05-25-spec-phase1-02-internal-company.sql` → canonical `20260526061103`
- `2026-05-25-spec-phase1-03-operator-gate.sql` → canonical `20260526061148`
- `2026-05-25-spec-phase1-04-core-tables.sql` → canonical `20260526061235`
- `2026-05-25-spec-phase1-03b-operator-gate-jackson-override.sql` → canonical `20260526061337`
- `2026-05-25-spec-phase1-05-money-tables.sql` → canonical `20260526061414`
- `2026-05-25-spec-phase1-06-workflow-tables.sql` → canonical `20260526061441`
- `2026-05-25-spec-phase1-07-snapshot-and-rls.sql` → canonical `20260526061526`
- `2026-05-25-spec-phase1-08-storage.sql` → canonical `20260526061553`
- `2026-05-26-01-spec-phase1-rls-audit-lockdown.sql` → canonical `20260526200213`
- `2026-05-26-02-spec-phase1-email-templates.sql` → canonical `20260526204134`
- `2026-05-26-01-spec-stage-c1-outboxes.sql` → canonical `20260526205030`
- `2026-05-26-03-spec-phase1-intake-columns.sql` → canonical `20260526231421`
- `2026-05-26-04-spec-stage-c5-cron-columns.sql` → canonical `20260527003736`
- `2026-05-26-03-spec-stage-f1-board-refresh-wrapper.sql` → canonical `20260527003915`
- `2026-05-26-05-spec-stage-f3-refund-deny-columns.sql` → canonical `20260527012754`
- `2026-05-26-06-spec-stage-f2b-internal-notes.sql` → canonical `20260527160838`
- `2026-05-26-07-spec-h-supplement-entitlement-templates.sql` → canonical `20260527163243`
- `2026-05-26-08-spec-internal-notes-fk-fix.sql` → canonical `20260527163256`
- `2026-05-27-01-spec-h-supplement-cron-templates.sql` → canonical `20260527190345`
- `2026-05-27-04-ios-catalog-p6-material-demand-engine.sql` → canonical `20260528062117`
- `2026-05-29-03-ios-catalog-p6-anon-role-grants.sql` → canonical `20260530005401`
- `2026-05-30-02-ios-catalog-p6-fix-try-parse-uuid-regex.sql` → canonical `20260531013103`
- `2026-05-30-03-ios-catalog-p6-completion-requests-anon-rls.sql` → canonical `20260531013109`
- `2026-05-30-04-ios-catalog-p6-inventory-off-release-allocations.sql` → canonical `20260531063325`
- `2026-05-30-01-ios-catalog-p6-accept-request-anon-grant.sql` → canonical `20260531063415`
- `20260602000000_inbox_dark_launch_draft_mailbox_tracking.sql` → canonical `20260602191740`
- `20260602010000_inbox_dark_launch_draft_status_values.sql` → canonical `20260602211243`
- `20260604205950_fix_convert_created_by_fkey.sql` → canonical `20260604210114`
- `20260604212206_drop_guarded_conversion_rpc.sql` → canonical `20260604212225`
- `20260616205309_catalog_setup_save_persist_unit_cost.sql` → canonical `20260616204817`
- `20260714180500_convert_rpc_lead_deck_and_photo_carryover.sql` → canonical `20260714202212`
- `20260805190000_add_email_connections_signature_logo_url.sql` → canonical `20260805185129`
- `20260805230000_fix_email_signature_hash_check_null_character.sql` → canonical `20260805224149`

## Accounting sync release — 2026-09-04

- `20260904025000_qbo_bidirectional_sync_hardening.sql` ← ledger `20260904182523_qbo_bidirectional_sync_hardening`
- `20260904040000_sage_connection_identity_and_oauth.sql` ← ledger `20260904182539_sage_connection_identity_and_oauth`
- `20260904050000_sage_queue_hardening.sql` ← ledger `20260904182556_sage_queue_hardening`
- `20260904060000_sage_reconciliation.sql` ← ledger `20260904182615_sage_reconciliation`

These four files are byte-identical to the OPS-Web release sources. Supabase assigned apply-time ledger versions; the source filenames retain the dependency order used by the application repository.

## Supplier bill account-closure integration — 2026-09-04

- `20260904184303_supplier_bill_company_data_lifecycle.sql` ← OPS-Web source `20260904190000_supplier_bill_company_data_lifecycle.sql`

The archive file is byte-identical to the OPS-Web source. Supabase assigned apply-time ledger version `20260904184303`.

## Provenance of the 2026-08-12 backfill

552 files were reconstructed from `supabase_migrations.schema_migrations.statements` (read-only export) and
md5-verified row-by-row; 4 came from local checkouts (the 3 empty-ledger 0604 files and the multi-statement
0527 file, cross-checked across 42 identical working copies). The six 2026-08-07 google-calendar migrations and
`20260807152233` carry their original applied definitions — in particular `enqueue_google_calendar_sync()` here is
the pre-booking-gate version, later replaced by `20260810194251_site_visit_booking.sql`.
