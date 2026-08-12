-- Reconcile: bring the live-but-untracked 2026-05-30-01 grant into schema_migrations.
-- Idempotent: GRANT is repeatable; these grants are already live.
grant select, insert, update on table public.accept_estimate_to_job_requests to anon;

grant execute on function private.catalog_variant_available_stock_summary(uuid, uuid)                       to anon;
grant execute on function private.consume_task_materials_for_completed_task(uuid, text, jsonb)              to anon;
grant execute on function private.current_user_can_complete_task_material_consumption(uuid, uuid)           to anon;
grant execute on function private.current_user_can_write_project_material_workflow(uuid)                    to anon;
grant execute on function private.is_ops_admin()                                                            to anon;
grant execute on function private.persist_catalog_mapping_notifications_from_missing_mappings(uuid, jsonb)  to anon;
grant execute on function private.persist_estimate_material_booking_projection(uuid, uuid)                  to anon;
grant execute on function private.resolve_catalog_variant_for_material_demand(uuid, uuid, uuid, jsonb, jsonb) to anon;
grant execute on function private.resolve_estimate_material_demand_plan(uuid, uuid)                          to anon;
grant execute on function private.sync_accepted_estimate_project_tasks(uuid)                                to anon;
grant execute on function private.try_parse_uuid(text)                                                      to anon;

grant execute on function public.record_auto_bug(text, text, text, text, text, text, jsonb, text, text, text, text, text)          to anon;
grant execute on function public.record_auto_bug(text, text, text, text, text, text, jsonb, text, text, text, text, text, integer) to anon;
