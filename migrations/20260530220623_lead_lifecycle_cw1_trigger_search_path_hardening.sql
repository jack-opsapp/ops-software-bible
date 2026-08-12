-- Lead Lifecycle CW1 — trigger-function search_path hardening.
-- Resolves the `function_search_path_mutable` security advisor (lint 0011) for the
-- two CW1 blank-provider rewrite trigger functions (origin migration
-- lead_lifecycle_p5_blank_provider_rewrite_trigger). Both bodies reference only
-- built-in functions (btrim, coalesce) and the trigger NEW record — no
-- schema-qualified objects — so an empty search_path resolves everything safely
-- and changes no behavior. Additive + idempotent (CREATE OR REPLACE), iOS-safe.

create or replace function public.email_threads_rewrite_blank_provider()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  -- Defensive: NOT NULL is already enforced, so this guards the empty-string
  -- and all-whitespace cases. coalesce keeps the predicate null-safe.
  if btrim(coalesce(new.provider_thread_id, '')) = '' then
    new.provider_thread_id := 'legacy:' || new.id::text;
  end if;
  return new;
end;
$$;

create or replace function public.opportunity_email_threads_rewrite_blank_thread()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if btrim(coalesce(new.thread_id, '')) = '' then
    new.thread_id := 'legacy:' || new.id::text;
  end if;
  return new;
end;
$$;
