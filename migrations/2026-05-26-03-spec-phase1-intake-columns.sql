-- SPEC Phase 1 — Stage C.4 (P1-2-9): Intake token + responses + files columns
--
-- Source spec: ops-software-bible/SPEC/07_ROLLOUT.md § 7 (Intake form).
-- Coordinated with Stage C.2 (P1-2-7) — the webhook issues the intake token at
-- deposit_paid and stamps these columns. Stage C.4 consumes the token via the
-- /spec/intake/[token] page + /api/spec/intake/submit route.
--
-- All adds are idempotent (`add column if not exists`) so Stage C.2 and Stage C.4
-- can land in either order without re-migrating.
--
-- intake_token_hash         text       SHA-256 hex (64 chars) of the plaintext
--                                      intake URL token. Plaintext is emitted in
--                                      the spec.deposit_confirmed email link
--                                      once; the DB stores only the hash.
-- intake_token_issued_at    timestamptz When the token was issued (deposit_paid
--                                      webhook, or owner-approval buyer-checkout
--                                      consumption per Stage C.3).
-- intake_files              jsonb      Array of Supabase Storage object paths
--                                      uploaded under spec-intake/{id}/. Default
--                                      '[]'.
-- regulated_workflow_flagged_at timestamptz  Stamped on intake submission when
--                                      any of the 5 regulated-workflow
--                                      attestations is true. Intake submission
--                                      is blocked; operator notification fires.
-- regulated_workflow_flags  jsonb      The {phi_phipa, pci_raw_card,
--                                      regulated_credit, surveillance,
--                                      casl_bulk_messaging} payload as
--                                      submitted; recorded for the operator
--                                      review queue.
--
-- Applied to live Supabase project ijeekuhbatykdomumfjx via MCP on 2026-05-26.

alter table public.spec_projects
  add column if not exists intake_token_hash text,
  add column if not exists intake_token_issued_at timestamptz,
  add column if not exists intake_files jsonb not null default '[]'::jsonb,
  add column if not exists regulated_workflow_flagged_at timestamptz,
  add column if not exists regulated_workflow_flags jsonb;

-- Unique on hash so the same token can never validate two projects.
-- Partial index — null hashes (pre-deposit / pre-issuance) don't collide.
create unique index if not exists spec_projects_intake_token_hash_idx
  on public.spec_projects (intake_token_hash)
  where intake_token_hash is not null;

-- Fast lookup for the regulated-workflow operator queue.
create index if not exists spec_projects_regulated_workflow_idx
  on public.spec_projects (regulated_workflow_flagged_at)
  where regulated_workflow_flagged_at is not null;
