-- ============================================================================
-- Complete the never-applied index portions of legacy migrations 041 & 057
--
-- 041_opportunity_images.sql and 057_project_tasks_date_columns.sql were
-- committed but only partially reached prod: the columns exist (added by the
-- canonical descriptive migrations) but these two indexes were never created.
-- Identified by the 2026-06-04 migration drift audit. Purely additive + idempotent.
-- ============================================================================

begin;

create index if not exists idx_opportunities_has_images
  on public.opportunities ((array_length(images, 1) > 0))
  where array_length(images, 1) > 0;

create index if not exists idx_project_tasks_start_date
  on public.project_tasks (company_id, start_date)
  where deleted_at is null and start_date is not null;

commit;
