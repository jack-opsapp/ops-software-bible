-- ============================================================================
-- TASK REMINDERS — bug 4f00c2d7-9133-412e-9293-a369bf582a63
--
-- Adds reminder templates on TaskType and per-task reminder instances.
-- Live-link propagation via triggers. Cron-driven rail dispatch via
-- fire_due_task_reminders(). iOS schedules its own UNCalendarNotificationTrigger
-- on top for on-device push.
--
-- All additions; no changes to existing tables. Safe under the iOS sync
-- constraint (pre-update iOS clients ignore the new tables until shipped).
-- ============================================================================

-- ---------------- TEMPLATES ------------------------------------------------

CREATE TABLE public.task_type_reminders (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  task_type_id      uuid NOT NULL REFERENCES public.task_types(id) ON DELETE CASCADE,
  company_id        uuid NOT NULL,
  label             text NOT NULL,
  lead_time_days    int  NOT NULL DEFAULT 1 CHECK (lead_time_days >= 0),
  fire_time_local   time NOT NULL DEFAULT '09:00:00',
  requires_ack      boolean NOT NULL DEFAULT true,
  recipient_mode    text NOT NULL DEFAULT 'task_crew'
    CHECK (recipient_mode IN ('task_crew','admins','permission','users')),
  recipient_config  jsonb NOT NULL DEFAULT '{}'::jsonb,
  display_order     int NOT NULL DEFAULT 0,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),
  deleted_at        timestamptz
);

CREATE INDEX idx_task_type_reminders_task_type
  ON public.task_type_reminders(task_type_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_task_type_reminders_company
  ON public.task_type_reminders(company_id);

ALTER TABLE public.task_type_reminders ENABLE ROW LEVEL SECURITY;

CREATE POLICY task_type_reminders_company_scope ON public.task_type_reminders
  FOR ALL
  USING (company_id = (SELECT private.get_user_company_id()))
  WITH CHECK (company_id = (SELECT private.get_user_company_id()));

-- ---------------- INSTANCES ------------------------------------------------

CREATE TABLE public.task_reminders (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  task_id             uuid NOT NULL REFERENCES public.project_tasks(id) ON DELETE CASCADE,
  company_id          uuid NOT NULL,
  source_template_id  uuid REFERENCES public.task_type_reminders(id) ON DELETE SET NULL,
  -- Snapshot/live-link mirror of the template:
  label               text NOT NULL,
  lead_time_days      int  NOT NULL CHECK (lead_time_days >= 0),
  fire_time_local     time NOT NULL DEFAULT '09:00:00',
  requires_ack        boolean NOT NULL,
  recipient_mode      text NOT NULL
    CHECK (recipient_mode IN ('task_crew','admins','permission','users')),
  recipient_config    jsonb NOT NULL DEFAULT '{}'::jsonb,
  -- State:
  fires_at            timestamptz,
  acknowledged_at     timestamptz,
  acknowledged_by     uuid,
  dismissed_at        timestamptz,
  notified_at         timestamptz,
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now(),
  deleted_at          timestamptz
);

CREATE INDEX idx_task_reminders_task
  ON public.task_reminders(task_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_task_reminders_due
  ON public.task_reminders(fires_at)
  WHERE acknowledged_at IS NULL
    AND dismissed_at    IS NULL
    AND notified_at     IS NULL
    AND deleted_at      IS NULL;
CREATE INDEX idx_task_reminders_template
  ON public.task_reminders(source_template_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_task_reminders_company
  ON public.task_reminders(company_id);

ALTER TABLE public.task_reminders ENABLE ROW LEVEL SECURITY;

CREATE POLICY task_reminders_company_scope ON public.task_reminders
  FOR ALL
  USING (company_id = (SELECT private.get_user_company_id()))
  WITH CHECK (company_id = (SELECT private.get_user_company_id()));

-- ---------------- updated_at triggers --------------------------------------

CREATE OR REPLACE FUNCTION public.set_updated_at_now()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_task_type_reminders_updated_at
  BEFORE UPDATE ON public.task_type_reminders
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at_now();

CREATE TRIGGER trg_task_reminders_updated_at
  BEFORE UPDATE ON public.task_reminders
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at_now();

-- ---------------- fires_at helper ------------------------------------------

-- Computes the absolute moment a reminder should fire, given:
--   - the parent task's start_date (timestamptz; may be NULL)
--   - the template's lead_time_days
--   - the template's fire_time_local (time-of-day in company timezone)
--   - the company's timezone string
--
-- Strategy:
--   1. Convert task start_date into the company's local date.
--   2. Subtract lead_time_days at the local-date level (avoids DST surprises).
--   3. Combine that local date with fire_time_local.
--   4. Convert back to a timestamptz using the company timezone.
--
-- Returns NULL when task_start_date is NULL (dormant reminder).
CREATE OR REPLACE FUNCTION public.compute_reminder_fires_at(
  p_task_start_date timestamptz,
  p_lead_time_days  int,
  p_fire_time_local time,
  p_company_id      uuid
) RETURNS timestamptz
LANGUAGE plpgsql STABLE AS $$
DECLARE
  v_tz text;
  v_local_date date;
BEGIN
  IF p_task_start_date IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT timezone INTO v_tz FROM public.companies WHERE id = p_company_id;
  IF v_tz IS NULL THEN
    v_tz := 'America/Vancouver';
  END IF;

  v_local_date := (p_task_start_date AT TIME ZONE v_tz)::date - p_lead_time_days;

  RETURN ((v_local_date + p_fire_time_local) AT TIME ZONE v_tz);
END;
$$;

-- ---------------- Trigger 1: new task → materialize ------------------------

CREATE OR REPLACE FUNCTION public.tg_project_tasks_materialize_reminders()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.deleted_at IS NOT NULL THEN
    RETURN NEW;
  END IF;
  IF NEW.status IN ('completed','cancelled') THEN
    RETURN NEW;
  END IF;

  INSERT INTO public.task_reminders (
    task_id, company_id, source_template_id,
    label, lead_time_days, fire_time_local, requires_ack,
    recipient_mode, recipient_config, fires_at
  )
  SELECT
    NEW.id, NEW.company_id, ttr.id,
    ttr.label, ttr.lead_time_days, ttr.fire_time_local, ttr.requires_ack,
    ttr.recipient_mode, ttr.recipient_config,
    public.compute_reminder_fires_at(NEW.start_date, ttr.lead_time_days, ttr.fire_time_local, NEW.company_id)
  FROM public.task_type_reminders ttr
  WHERE ttr.task_type_id = NEW.task_type_id
    AND ttr.deleted_at IS NULL;

  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_project_tasks_after_insert_reminders
  AFTER INSERT ON public.project_tasks
  FOR EACH ROW EXECUTE FUNCTION public.tg_project_tasks_materialize_reminders();

-- ---------------- Trigger 2: task rescheduled → recompute fires_at --------

CREATE OR REPLACE FUNCTION public.tg_project_tasks_reschedule_reminders()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  v_new_fires timestamptz;
BEGIN
  -- Freeze when terminal
  IF NEW.status IN ('completed','cancelled') THEN
    RETURN NEW;
  END IF;
  -- Only act when scheduling fields actually changed
  IF NEW.start_date IS NOT DISTINCT FROM OLD.start_date
     AND NEW.start_time IS NOT DISTINCT FROM OLD.start_time THEN
    RETURN NEW;
  END IF;

  UPDATE public.task_reminders tr
  SET fires_at = public.compute_reminder_fires_at(NEW.start_date, tr.lead_time_days, tr.fire_time_local, NEW.company_id),
      notified_at = CASE
        WHEN public.compute_reminder_fires_at(NEW.start_date, tr.lead_time_days, tr.fire_time_local, NEW.company_id) > now()
             AND tr.notified_at IS NOT NULL
          THEN NULL
        ELSE tr.notified_at
      END,
      updated_at = now()
  WHERE tr.task_id = NEW.id
    AND tr.acknowledged_at IS NULL
    AND tr.deleted_at IS NULL;

  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_project_tasks_after_update_reminders
  AFTER UPDATE ON public.project_tasks
  FOR EACH ROW EXECUTE FUNCTION public.tg_project_tasks_reschedule_reminders();

-- ---------------- Trigger 3: template upsert → propagate ------------------

CREATE OR REPLACE FUNCTION public.tg_task_type_reminders_propagate()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  -- Skip if the template itself is being soft-deleted in this UPDATE — trigger 4 handles that.
  IF (TG_OP = 'UPDATE'
      AND NEW.deleted_at IS NOT NULL
      AND OLD.deleted_at IS NULL) THEN
    RETURN NEW;
  END IF;
  IF NEW.deleted_at IS NOT NULL THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'INSERT' THEN
    -- Materialize one instance per open task of this type that doesn't already have one
    INSERT INTO public.task_reminders (
      task_id, company_id, source_template_id,
      label, lead_time_days, fire_time_local, requires_ack,
      recipient_mode, recipient_config, fires_at
    )
    SELECT
      pt.id, pt.company_id, NEW.id,
      NEW.label, NEW.lead_time_days, NEW.fire_time_local, NEW.requires_ack,
      NEW.recipient_mode, NEW.recipient_config,
      public.compute_reminder_fires_at(pt.start_date, NEW.lead_time_days, NEW.fire_time_local, pt.company_id)
    FROM public.project_tasks pt
    WHERE pt.task_type_id = NEW.task_type_id
      AND pt.deleted_at IS NULL
      AND pt.status NOT IN ('completed','cancelled')
      AND NOT EXISTS (
        SELECT 1 FROM public.task_reminders tr
        WHERE tr.task_id = pt.id
          AND tr.source_template_id = NEW.id
          AND tr.deleted_at IS NULL
      );

  ELSIF TG_OP = 'UPDATE' THEN
    -- Re-snapshot fields on unacknowledged instances of open tasks
    UPDATE public.task_reminders tr
    SET label           = NEW.label,
        lead_time_days  = NEW.lead_time_days,
        fire_time_local = NEW.fire_time_local,
        requires_ack    = NEW.requires_ack,
        recipient_mode  = NEW.recipient_mode,
        recipient_config = NEW.recipient_config,
        fires_at = public.compute_reminder_fires_at(pt.start_date, NEW.lead_time_days, NEW.fire_time_local, pt.company_id),
        notified_at = CASE
          WHEN public.compute_reminder_fires_at(pt.start_date, NEW.lead_time_days, NEW.fire_time_local, pt.company_id) > now()
               AND tr.notified_at IS NOT NULL
               AND (NEW.lead_time_days IS DISTINCT FROM OLD.lead_time_days
                    OR NEW.fire_time_local IS DISTINCT FROM OLD.fire_time_local)
            THEN NULL
          ELSE tr.notified_at
        END,
        updated_at = now()
    FROM public.project_tasks pt
    WHERE tr.source_template_id = NEW.id
      AND tr.task_id = pt.id
      AND tr.acknowledged_at IS NULL
      AND tr.deleted_at IS NULL
      AND pt.status NOT IN ('completed','cancelled');
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_task_type_reminders_after_insert
  AFTER INSERT ON public.task_type_reminders
  FOR EACH ROW EXECUTE FUNCTION public.tg_task_type_reminders_propagate();

CREATE TRIGGER trg_task_type_reminders_after_update
  AFTER UPDATE ON public.task_type_reminders
  FOR EACH ROW
  WHEN (NEW.deleted_at IS NULL)
  EXECUTE FUNCTION public.tg_task_type_reminders_propagate();

-- ---------------- Trigger 4: template soft-deleted → soft-delete instances

CREATE OR REPLACE FUNCTION public.tg_task_type_reminders_soft_delete()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.deleted_at IS NULL OR OLD.deleted_at IS NOT NULL THEN
    RETURN NEW;
  END IF;

  UPDATE public.task_reminders tr
  SET deleted_at = NEW.deleted_at,
      updated_at = now()
  FROM public.project_tasks pt
  WHERE tr.source_template_id = NEW.id
    AND tr.task_id = pt.id
    AND tr.acknowledged_at IS NULL
    AND tr.deleted_at IS NULL
    AND pt.status NOT IN ('completed','cancelled');

  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_task_type_reminders_after_soft_delete
  AFTER UPDATE ON public.task_type_reminders
  FOR EACH ROW
  WHEN (NEW.deleted_at IS NOT NULL AND OLD.deleted_at IS NULL)
  EXECUTE FUNCTION public.tg_task_type_reminders_soft_delete();

-- ---------------- Cron dispatch: fire due reminders -----------------------

-- Recipient resolution helper. Returns the set of user_ids that should be
-- notified for a given reminder, given the recipient_mode + recipient_config
-- and the task's team_member_ids.
CREATE OR REPLACE FUNCTION public.resolve_task_reminder_recipients(
  p_company_id        uuid,
  p_task_team_members uuid[],
  p_recipient_mode    text,
  p_recipient_config  jsonb
) RETURNS SETOF uuid
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, private AS $$
BEGIN
  IF p_recipient_mode = 'task_crew' THEN
    RETURN QUERY SELECT UNNEST(COALESCE(p_task_team_members, ARRAY[]::uuid[]));
  ELSIF p_recipient_mode = 'admins' THEN
    RETURN QUERY
      SELECT DISTINCT u.id
      FROM public.users u
      WHERE u.company_id = p_company_id
        AND u.deleted_at IS NULL
        AND (
          u.is_company_admin = true
          OR u.id::text = (SELECT account_holder_id FROM public.companies WHERE id = p_company_id)
          OR u.id::text = ANY(COALESCE((SELECT admin_ids FROM public.companies WHERE id = p_company_id), ARRAY[]::text[]))
        );
  ELSIF p_recipient_mode = 'permission' THEN
    RETURN QUERY
      SELECT * FROM public.users_with_permission(
        p_company_id,
        p_recipient_config->>'permission',
        'all'
      );
  ELSIF p_recipient_mode = 'users' THEN
    RETURN QUERY
      SELECT (jsonb_array_elements_text(p_recipient_config->'user_ids'))::uuid;
  END IF;
END;
$$;

-- Main cron entry point. Scans for due reminders, inserts notifications rows
-- for each resolved recipient, and stamps notified_at to dedupe future scans.
CREATE OR REPLACE FUNCTION public.fire_due_task_reminders()
RETURNS int
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, private AS $$
DECLARE
  v_count int := 0;
  v_rec   record;
  v_uid   uuid;
  v_body  text;
BEGIN
  FOR v_rec IN
    SELECT tr.id           AS reminder_id,
           tr.task_id,
           tr.company_id,
           tr.label,
           tr.lead_time_days,
           tr.requires_ack,
           tr.recipient_mode,
           tr.recipient_config,
           pt.project_id,
           pt.team_member_ids,
           tt.display       AS task_type_display,
           p.title          AS project_title
    FROM public.task_reminders tr
    JOIN public.project_tasks pt ON pt.id = tr.task_id AND pt.deleted_at IS NULL
    JOIN public.task_types   tt ON tt.id = pt.task_type_id
    JOIN public.projects     p  ON p.id  = pt.project_id
    WHERE tr.fires_at <= now()
      AND tr.notified_at    IS NULL
      AND tr.acknowledged_at IS NULL
      AND tr.dismissed_at    IS NULL
      AND tr.deleted_at      IS NULL
      AND pt.status NOT IN ('completed','cancelled')
    FOR UPDATE OF tr SKIP LOCKED
  LOOP
    v_body := v_rec.lead_time_days || 'd before ' || COALESCE(v_rec.task_type_display,'task')
              || ' — ' || COALESCE(v_rec.project_title,'project');

    FOR v_uid IN
      SELECT public.resolve_task_reminder_recipients(
        v_rec.company_id,
        ARRAY(SELECT (UNNEST(v_rec.team_member_ids))::uuid),
        v_rec.recipient_mode,
        v_rec.recipient_config
      )
    LOOP
      INSERT INTO public.notifications (
        user_id, company_id, type, title, body,
        project_id, deep_link_type, persistent, action_url, action_label
      ) VALUES (
        v_uid::text,
        v_rec.company_id::text,
        'task_reminder',
        v_rec.label,
        v_body,
        v_rec.project_id::text,
        'project_task_reminder',
        v_rec.requires_ack,
        '/projects/' || v_rec.project_id || '?task=' || v_rec.task_id || '&reminder=' || v_rec.reminder_id,
        CASE WHEN v_rec.requires_ack THEN 'CONFIRM' ELSE 'OPEN TASK' END
      );
    END LOOP;

    UPDATE public.task_reminders
       SET notified_at = now(), updated_at = now()
     WHERE id = v_rec.reminder_id;

    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END;
$$;

COMMENT ON FUNCTION public.fire_due_task_reminders() IS
  'Cron entry point for task reminders. Returns count of reminders fired.';

-- Schedule via pg_cron if available. If pg_cron is not installed in this
-- project, the Vercel cron should call this function instead.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.schedule(
      'fire_due_task_reminders_every_5min',
      '*/5 * * * *',
      'SELECT public.fire_due_task_reminders();'
    );
  END IF;
END$$;
