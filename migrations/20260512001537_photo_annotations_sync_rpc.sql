CREATE OR REPLACE FUNCTION public.get_photo_annotations_since(
  p_since timestamptz DEFAULT NULL
)
RETURNS SETOF public.project_photo_annotations
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_company_id uuid;
BEGIN
  v_company_id := private.get_user_company_id();
  IF v_company_id IS NULL THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT *
  FROM public.project_photo_annotations
  WHERE company_id = v_company_id::text
    AND (p_since IS NULL OR updated_at >= p_since)
  ORDER BY created_at DESC;
END;
$$;

REVOKE ALL ON FUNCTION public.get_photo_annotations_since(timestamptz) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_photo_annotations_since(timestamptz) TO authenticated;

COMMENT ON FUNCTION public.get_photo_annotations_since IS
  'Company-scoped pull of project_photo_annotations including soft-deleted rows so iOS InboundProcessor can propagate tombstones to local SwiftData. SECURITY DEFINER bypasses the strict SELECT policy that hides deleted_at IS NOT NULL rows; the function applies its own company scoping via private.get_user_company_id().';
