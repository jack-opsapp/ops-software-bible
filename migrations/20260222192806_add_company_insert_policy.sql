
-- Allow authenticated users to INSERT a new company when they are the account holder
CREATE POLICY "company_insert_for_creator"
ON public.companies
FOR INSERT
TO authenticated
WITH CHECK (
  account_holder_id = auth.uid()::text
);

