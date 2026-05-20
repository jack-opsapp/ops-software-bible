-- Extend convert_lead_to_project to auto-attach site visit photos.
--
-- 10_JOB_LIFECYCLE_AND_DATA_RELATIONSHIPS.md § 'won' (line 289) and
-- Automation E (line 1314) document the canonical behavior:
--
--   For each SiteVisit WHERE site_visit.opportunity_id = opportunity.id:
--     For each photo URL in site_visit.photos:
--       Create ProjectPhoto {
--         projectId: opportunity.projectId,
--         url: photo,
--         source: 'site_visit',
--         siteVisitId: siteVisit.id,
--         uploadedBy: siteVisit.createdBy,
--         takenAt: null
--       }
--
-- The 2026-05-19 RPC explicitly deferred this step; this migration removes the
-- deferral. Signature is unchanged so iOS LeadConversionService keeps working
-- with no caller adjustments. Idempotency guard remains intact — re-running on
-- a lead that already converted returns the existing project id and does not
-- re-insert photos.
--
-- Behavior on historical wins (leads already converted before this migration
-- shipped): untouched. Their photos remain unattached. A one-time backfill is
-- a separate ticket if desired — explicitly out of scope here so the RPC's
-- idempotency contract stays unchanged.
--
-- Schema verified against OPS-Web/src/lib/types/database.types.ts (generated
-- from live Supabase introspection) and the source CREATE TABLE in
-- OPS-Web/supabase/migrations/EXECUTED/002_lifecycle_entities.sql:
--   site_visits.photos        TEXT[] DEFAULT '{}'
--   site_visits.opportunity_id UUID  (FK opportunities.id)
--   site_visits.created_by    TEXT NOT NULL
--   site_visits.deleted_at    TIMESTAMPTZ NULLABLE
--   project_photos.project_id TEXT NOT NULL
--   project_photos.company_id TEXT NOT NULL
--   project_photos.url        TEXT NOT NULL
--   project_photos.source     photo_source NOT NULL (includes 'site_visit')
--   project_photos.site_visit_id UUID NULLABLE (FK site_visits.id)
--   project_photos.uploaded_by TEXT NOT NULL
--   project_photos.taken_at   TIMESTAMPTZ NULLABLE
--   project_photos.created_at TIMESTAMPTZ DEFAULT NOW()
--
-- The new step lands between task materialization (step 3) and the
-- opportunities update (step 4) so the photos are attached to a fully-formed
-- project row but the lead is still in its pre-won state — matches the
-- bible's documented event ordering.

CREATE OR REPLACE FUNCTION public.convert_lead_to_project(
  p_opportunity_id uuid,
  p_actual_value  numeric,
  p_title         text,
  p_address       text,
  p_user_id       uuid
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_project_id        uuid;
  v_company_id        uuid;
  v_client_id         uuid;
  v_from_stage        text;
  v_stage_entered_at  timestamptz;
  v_now               timestamptz := now();
BEGIN
  -- Read the lead's company / client / current stage. Uses SECURITY DEFINER
  -- so this SELECT bypasses RLS — the same-company check below is what
  -- enforces authorization.
  SELECT company_id, client_id, stage, stage_entered_at
    INTO v_company_id, v_client_id, v_from_stage, v_stage_entered_at
    FROM opportunities
   WHERE id = p_opportunity_id
     AND deleted_at IS NULL;

  IF v_company_id IS NULL THEN
    RAISE EXCEPTION 'opportunity_not_found' USING ERRCODE = 'P0002';
  END IF;

  -- Authorization: the caller must be a member of the opportunity's company.
  -- p_user_id is taken on trust (callers pass their own auth.uid()); the RLS
  -- on users still applies to the rows the caller can see at app layer.
  IF NOT EXISTS (
    SELECT 1 FROM users
     WHERE id = p_user_id
       AND company_id = v_company_id
  ) THEN
    RAISE EXCEPTION 'access_denied' USING ERRCODE = '42501';
  END IF;

  -- Idempotency: a project may already back-link to this opportunity if a
  -- sibling client raced this call. Return the existing id without retrying.
  SELECT id INTO v_project_id
    FROM projects
   WHERE opportunity_id = p_opportunity_id::text
     AND deleted_at IS NULL
   LIMIT 1;

  IF v_project_id IS NOT NULL THEN
    RETURN v_project_id;
  END IF;

  v_project_id := gen_random_uuid();

  -- 1. Insert the project. opportunity_id is a legacy text column on
  --    projects (no FK), so we cast the uuid to text.
  INSERT INTO projects (
    id, company_id, client_id, opportunity_id,
    title, address, status, created_by, created_at, updated_at
  ) VALUES (
    v_project_id, v_company_id, v_client_id, p_opportunity_id::text,
    p_title, p_address, 'accepted', p_user_id, v_now, v_now
  );

  -- 2. Forward-link any estimates attached to this lead. estimates.project_id
  --    is the legacy text column; estimates.project_ref is the uuid FK to
  --    projects.id. Write both so iOS and web readers both resolve correctly.
  UPDATE estimates
     SET project_id  = v_project_id::text,
         project_ref = v_project_id,
         updated_at  = v_now
   WHERE opportunity_id = p_opportunity_id
     AND project_id IS NULL
     AND deleted_at IS NULL;

  -- 3. Materialize each LABOR line item across those estimates as a
  --    project_tasks row. task_type_id stays nullable: when the source line
  --    item has no task_type_ref the new task displays via custom_title
  --    (which always carries line_items.name — NOT NULL on the source table).
  --    sort_order → display_order; default_duration → duration (fallback 1);
  --    task_types.color → task_color (fallback to schema default '#417394').
  INSERT INTO project_tasks (
    id, company_id, project_id, task_type_id,
    custom_title, source_line_item_id, source_estimate_id,
    status, display_order, duration, task_color, created_at, updated_at
  )
  SELECT
    gen_random_uuid(),
    v_company_id,
    v_project_id,
    li.task_type_ref,
    li.name,
    li.id::text,
    li.estimate_id::text,
    'active',
    COALESCE(li.sort_order, 0),
    COALESCE(tt.default_duration, 1),
    COALESCE(tt.color, '#417394'),
    v_now,
    v_now
  FROM line_items li
  LEFT JOIN task_types tt ON tt.id = li.task_type_ref
  WHERE li.estimate_id IN (
          SELECT id FROM estimates
           WHERE opportunity_id = p_opportunity_id
             AND deleted_at IS NULL
        )
    AND li.type = 'LABOR';

  -- 4. Site visit photo auto-attach (bible §10:289 + §10:1314 Automation E).
  --    Each non-deleted SiteVisit linked to this opportunity contributes its
  --    photos[] entries as project_photos rows with source='site_visit'.
  --    site_visit_id back-links so the gallery's "Site Visit" group renders.
  --    uploaded_by carries the site visit's created_by (whoever booked the
  --    visit), not the operator winning the lead — matches the bible spec.
  --    taken_at stays NULL because the photos array carries no EXIF/timestamp
  --    metadata at this layer; the timeline orders by created_at instead.
  --    is_client_visible defaults to false (column default) so the operator
  --    opts each photo into the portal via the per-photo toggle later.
  --    Empty/NULL photos arrays unnest to zero rows — safe; visits with no
  --    photos contribute nothing.
  INSERT INTO project_photos (
    id, project_id, company_id, url, source,
    site_visit_id, uploaded_by, taken_at, created_at
  )
  SELECT
    gen_random_uuid(),
    v_project_id::text,
    v_company_id::text,
    photo_url,
    'site_visit',
    sv.id,
    sv.created_by,
    NULL,
    v_now
  FROM site_visits sv
  CROSS JOIN LATERAL unnest(sv.photos) AS photo_url
  WHERE sv.opportunity_id = p_opportunity_id
    AND sv.deleted_at IS NULL
    AND photo_url IS NOT NULL
    AND photo_url <> '';

  -- 5. Update the lead. project_id on opportunities is a uuid column;
  --    project_ref is also uuid — both point at the new project.
  UPDATE opportunities
     SET stage              = 'won',
         stage_entered_at   = v_now,
         stage_manually_set = true,
         actual_value       = p_actual_value,
         actual_close_date  = v_now::date,
         project_id         = v_project_id,
         project_ref        = v_project_id,
         updated_at         = v_now
   WHERE id = p_opportunity_id;

  -- 6. Insert the stage_transitions row. Mirrors move_opportunity_stage's
  --    pattern (2026-05-07-01-move-opportunity-stage-rpc.sql): captures
  --    duration_in_stage so pipeline analytics remain consistent.
  INSERT INTO stage_transitions (
    company_id, opportunity_id, from_stage, to_stage,
    transitioned_at, transitioned_by, duration_in_stage
  ) VALUES (
    v_company_id, p_opportunity_id, v_from_stage, 'won',
    v_now, p_user_id, v_now - v_stage_entered_at
  );

  RETURN v_project_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.convert_lead_to_project(uuid, numeric, text, text, uuid) TO authenticated;
