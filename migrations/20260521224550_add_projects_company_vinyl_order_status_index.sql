-- Partial index for company-scoped Deck Builder vinyl-order-status
-- filtering, from the considered design in ops-software-bible/migrations/
-- 2026-05-21-project-vinyl-order-marker.sql. Additive; matches the
-- deleted_at IS NULL partial-index convention used elsewhere on projects.
-- User-approved 2026-05-21.
CREATE INDEX IF NOT EXISTS idx_projects_company_vinyl_order_status
  ON public.projects(company_id, vinyl_order_status)
  WHERE deleted_at IS NULL;
