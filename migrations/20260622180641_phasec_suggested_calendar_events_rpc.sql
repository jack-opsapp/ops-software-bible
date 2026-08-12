-- Phase-C calendar — iOS-facing read/resolve path for detected events (item 63144953)
--
-- iOS cannot read agent_memories directly: its RLS keys off auth.jwt()->>'company_id',
-- which is NULL for the Firebase-bridged mobile JWT. These two SECURITY DEFINER RPCs give
-- the iOS "Suggested events" surface a company-scoped, identity-resolved path WITHOUT
-- coupling the app to the (headless, Canpro-only) Phase C engine: when Phase C produces
-- nothing, the getter returns zero rows and the feature stays fully dormant.
--
-- Identity is resolved via the canonical get_user_company_id() helper, which matches
-- auth.jwt()->>'sub' against users.auth_id / users.firebase_uid (the established OPS pattern;
-- never auth.uid(), never the absent JWT company_id claim). Additive only — two new functions.

-- ── Getter: a company's unresolved, time-bearing, upcoming detected commitments ──────────
CREATE OR REPLACE FUNCTION public.get_suggested_calendar_events()
RETURNS TABLE (
  id          uuid,
  content     text,
  due_date    timestamptz,
  entity_id   uuid,
  confidence  numeric,
  resolved_at timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
  SELECT m.id, m.content, m.due_date, m.entity_id, m.confidence, m.resolved_at
  FROM public.agent_memories m
  WHERE m.company_id = public.get_user_company_id()::uuid  -- caller's company == the authorization boundary
    AND m.category   = 'commitment'                        -- detected events live as commitment rows
    AND m.due_date IS NOT NULL                             -- time-bearing only
    AND m.resolved_at IS NULL                              -- not already actioned ("not already in the calendar")
    AND m.due_date >= now()                                -- upcoming only — never suggest adding a past deadline
    AND m.confidence >= 0.5                                -- drop below-neutral-confidence noise
  ORDER BY m.due_date ASC, m.confidence DESC
  LIMIT 100
$$;

COMMENT ON FUNCTION public.get_suggested_calendar_events() IS
  'iOS Suggested-events surface (Phase-C calendar, item 63144953): returns the caller company''s '
  'unresolved, upcoming, time-bearing detected commitments. SECURITY DEFINER; company resolved via '
  'get_user_company_id() (firebase_uid/auth_id match). Returns zero rows when Phase C is idle — the '
  'app never depends on the engine running.';

-- ── Resolver: mark a detected commitment resolved once the user confirms it onto the calendar ──
CREATE OR REPLACE FUNCTION public.resolve_suggested_calendar_event(p_memory_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_company uuid := public.get_user_company_id()::uuid;
  v_matched boolean;
BEGIN
  IF v_company IS NULL THEN
    RETURN jsonb_build_object('resolved', false, 'reason', 'no_company');
  END IF;

  -- Stamp resolved_at idempotently (COALESCE preserves a prior resolution time on retry).
  -- Scoped to the caller's company + commitment category — the authorization boundary.
  UPDATE public.agent_memories
  SET resolved_at = COALESCE(resolved_at, now()),
      updated_at  = now()
  WHERE id         = p_memory_id
    AND company_id = v_company
    AND category   = 'commitment'
  RETURNING true INTO v_matched;

  RETURN jsonb_build_object('resolved', COALESCE(v_matched, false), 'id', p_memory_id);
END;
$$;

COMMENT ON FUNCTION public.resolve_suggested_calendar_event(uuid) IS
  'iOS Suggested-events surface (Phase-C calendar, item 63144953): marks a detected commitment '
  'resolved so it is not re-offered after the user adds it to their calendar. SECURITY DEFINER, '
  'company-scoped via get_user_company_id(); idempotent.';

-- ── Grants: authenticated mobile/web sessions only; never anon/public ───────────────────────
REVOKE ALL ON FUNCTION public.get_suggested_calendar_events()        FROM public, anon;
REVOKE ALL ON FUNCTION public.resolve_suggested_calendar_event(uuid) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.get_suggested_calendar_events()        TO authenticated;
GRANT EXECUTE ON FUNCTION public.resolve_suggested_calendar_event(uuid) TO authenticated;
