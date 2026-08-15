
DROP POLICY "company_insert_for_creator" ON public.companies;
CREATE POLICY "company_insert_for_creator"
ON public.companies
FOR INSERT
TO authenticated
WITH CHECK (
  lower(account_holder_id) = lower((auth.uid())::text)
);

