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

## Provenance of the 2026-08-12 backfill

552 files were reconstructed from `supabase_migrations.schema_migrations.statements` (read-only export) and
md5-verified row-by-row; 4 came from local checkouts (the 3 empty-ledger 0604 files and the multi-statement
0527 file, cross-checked across 42 identical working copies). The six 2026-08-07 google-calendar migrations and
`20260807152233` carry their original applied definitions — in particular `enqueue_google_calendar_sync()` here is
the pre-booking-gate version, later replaced by `20260810194251_site_visit_booking.sql`.
