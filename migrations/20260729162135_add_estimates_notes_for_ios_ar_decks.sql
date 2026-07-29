-- Applied to prod ijeekuhbatykdomumfjx 2026-07-29 (SYSTEMS REPAIR W1-2).
-- iOS CreateEstimateDTO sends `notes` (AR-deck accuracy note,
-- DeckBuilder/DeckBuilderViewModel.swift:4169-4177). Column never existed -> PGRST204 -> every
-- AR-measured deck estimate failed. Additive nullable column; shipped builds unbreak instantly.
ALTER TABLE public.estimates ADD COLUMN notes text;
