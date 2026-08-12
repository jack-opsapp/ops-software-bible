
-- Create deck_designs table for the Deck Builder feature.
-- Schema derived from iOS SwiftData model OPS/DataModels/DeckDesign.swift,
-- DTO OPS/Network/Supabase/DTOs/DeckDesignDTOs.swift, and the column allowlist
-- in OPS/Network/Sync/OutboundProcessor.swift (validDeckDesignColumns).
--
-- RLS mirrors the "company_isolation" policy used by the projects table
-- (role: public, qual: company_id = private.get_user_company_id()).

CREATE TABLE IF NOT EXISTS public.deck_designs (
  id            uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id    uuid        NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  project_id    uuid        REFERENCES public.projects(id) ON DELETE SET NULL,
  title         text        NOT NULL DEFAULT 'Untitled Deck',
  drawing_data  jsonb       NOT NULL DEFAULT '{}'::jsonb,
  thumbnail_url text,
  version       integer     NOT NULL DEFAULT 1,
  created_by    uuid        REFERENCES public.users(id) ON DELETE SET NULL,
  deleted_at    timestamptz,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz
);

CREATE INDEX IF NOT EXISTS deck_designs_company_id_idx   ON public.deck_designs (company_id);
CREATE INDEX IF NOT EXISTS deck_designs_project_id_idx   ON public.deck_designs (project_id) WHERE project_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS deck_designs_updated_at_idx   ON public.deck_designs (updated_at);
CREATE INDEX IF NOT EXISTS deck_designs_not_deleted_idx  ON public.deck_designs (company_id, created_at DESC) WHERE deleted_at IS NULL;

-- Keep updated_at fresh on every UPDATE (matches behaviour other tables rely on
-- via the shared trigger function if it exists; otherwise define inline).
CREATE OR REPLACE FUNCTION public.deck_designs_set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS deck_designs_set_updated_at ON public.deck_designs;
CREATE TRIGGER deck_designs_set_updated_at
  BEFORE UPDATE ON public.deck_designs
  FOR EACH ROW EXECUTE FUNCTION public.deck_designs_set_updated_at();

-- Enable RLS and apply company_isolation policy matching public.projects.
ALTER TABLE public.deck_designs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS company_isolation ON public.deck_designs;
CREATE POLICY company_isolation
  ON public.deck_designs
  FOR ALL
  TO public
  USING (company_id = (SELECT private.get_user_company_id()));

