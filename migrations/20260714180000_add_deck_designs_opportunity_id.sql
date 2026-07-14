-- Deck designs attach to leads: additive nullable FK so a deck can belong to
-- an opportunity before any project exists. Existing rows untouched; shipped
-- iOS builds ignore the new column (additive-only contract).
alter table public.deck_designs
  add column opportunity_id uuid references public.opportunities(id);

create index deck_designs_opportunity_id_idx
  on public.deck_designs(opportunity_id)
  where opportunity_id is not null;
