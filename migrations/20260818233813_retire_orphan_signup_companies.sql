-- Retire the orphan companies left by the non-atomic web signup company step.
--
-- Before create_company_for_owner_by_id, `/api/setup/progress` step "company"
-- ran four autocommit statements. A failure after the company insert committed
-- the company but left users.company_id NULL, and the retry re-entered the same
-- branch and inserted ANOTHER company. These are the survivors:
--
--   47ea553e-ae11-4081-bdf7-0366fa63c410 (johndanielkilpatrick@gmail.com) --
--     five companies created between 06:28:36 and 06:29:09 on 2026-06-29, one
--     per retry. The account holder still exists, is active, and is linked to
--     NONE of them (company_id NULL, role 'unassigned', no user_roles row).
--     All five trials started 2026-06-29 and expired 2026-07-29, so adopting
--     one would drop the operator into an already-expired trial. Retiring all
--     five lets the fixed route mint a clean company with a live trial if they
--     return.
--
--   ee9e6b68 (x2), d2670a00, 342a770d -- abandoned Feb/Mar 2026 signups whose
--     account-holder users rows no longer exist at all.
--
-- Verified before writing this: all nine hold zero projects, clients, invoices,
-- estimates, expenses, leads, or any other operator-authored row. Everything on
-- them is trigger-seeded defaults (task types, units, settings, saved views).
--
-- The two synthetic fixtures "TOCTOU RACE TARGET CO" / "TOCTOU RACE OTHER CO"
-- (account holder b0000000-0000-4000-8000-00000000dead) are test data and are
-- deliberately NOT touched.
do $retire$
declare
  v_ids constant uuid[] := array[
    'd4aaa217-3e99-424d-9b50-ceacd1f3d116',  -- VVS
    '1a0771bb-4aed-43ad-a005-2b4898207904',  -- VVs
    '01702eec-6be5-484e-a0af-8c0506bda17c',  -- House Painting
    '5fca97db-72da-4075-a241-8382e3e250a9',  -- House Painter
    '6ea1ea27-c640-48ea-a88c-72a89e9caab2',  -- House Painters
    '6802f078-9c49-40c9-8173-ff23eb7e8176',  -- Project Construction
    'cdff86fe-6a16-4e80-812f-516859d79e80',  -- Project Construction
    'c3e92e2b-9019-4daf-8675-672279d603c3',  -- Test
    'a0f20596-d81f-413e-bc70-77ce8df4d3ea'   -- Test Co
  ];
  v_n integer;
begin
  -- Re-assert the full orphan signature inside the transaction. If anything
  -- drifted since the snapshot -- an operator linked up, real work landed --
  -- abort rather than retire a company someone is using.
  select count(*) into v_n
    from public.companies c
   where c.id = any(v_ids)
     and c.deleted_at is null
     and not exists (select 1 from public.users u where u.company_id = c.id)
     and not exists (select 1 from public.projects p where p.company_id = c.id)
     and not exists (select 1 from public.clients cl where cl.company_id = c.id);

  if v_n <> 9 then
    raise exception
      'PRECONDITION_FAILED: expected 9 empty orphan companies, found %', v_n;
  end if;

  update public.companies
     set deleted_at = now(),
         updated_at = now()
   where id = any(v_ids);
end
$retire$;
