-- HIGH-1: lookup_company_by_code was anon+PUBLIC executable, used ILIKE (so '%'
-- returned an arbitrary company incl. its join code), and SELECT *'d the full
-- companies row (leaking stripe_customer_id, subscription + billing fields,
-- account_holder_id) to any caller.
--
-- Fix: exact case-insensitive/trimmed match (no wildcard), a constrained column
-- set (mirrors what the iOS join flow actually consumes), and execution
-- restricted to authenticated (REVOKE anon, PUBLIC). The iOS CompanyRepository
-- decodes this into SupabaseCompanyDTO whose only required fields are id+name;
-- every field the join flow reads (id, name, company_code, email, phone,
-- address, logo_url, industries, admin_ids, seated_employee_ids, max_seats) is
-- preserved. Web does not call this RPC; iOS calls it with an authenticated
-- Firebase JWT.
DROP FUNCTION IF EXISTS public.lookup_company_by_code(text);

CREATE FUNCTION public.lookup_company_by_code(lookup_code text)
RETURNS TABLE(
  id uuid,
  name text,
  company_code text,
  logo_url text,
  industries text[],
  email text,
  phone text,
  address text,
  admin_ids text[],
  seated_employee_ids text[],
  max_seats integer
)
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
  SELECT c.id, c.name, c.company_code, c.logo_url, c.industries,
         c.email, c.phone, c.address, c.admin_ids, c.seated_employee_ids, c.max_seats
  FROM public.companies c
  WHERE lower(trim(c.company_code)) = lower(trim(lookup_code))
    AND c.deleted_at IS NULL
  LIMIT 1;
$fn$;

REVOKE EXECUTE ON FUNCTION public.lookup_company_by_code(text) FROM anon, PUBLIC;
GRANT  EXECUTE ON FUNCTION public.lookup_company_by_code(text) TO authenticated;
