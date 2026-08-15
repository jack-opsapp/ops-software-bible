
-- Allow users to read their own row (needed during onboarding before company_id is set)
CREATE POLICY "user_self_select"
ON public.users
FOR SELECT
TO authenticated
USING (id = auth.uid());

-- Allow users to update their own row (needed to set company_id after company creation/join)
CREATE POLICY "user_self_update"
ON public.users
FOR UPDATE
TO authenticated
USING (id = auth.uid())
WITH CHECK (id = auth.uid());

-- Allow users to insert their own row during signup
CREATE POLICY "user_self_insert"
ON public.users
FOR INSERT
TO authenticated
WITH CHECK (id = auth.uid());

