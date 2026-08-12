-- INCIDENT FIX — lead disposition/archive UNDO could never succeed.
--
-- public.update_timestamp() is a BEFORE UPDATE trigger on public.opportunities
-- that stamps `NEW.updated_at = now()` — the TRANSACTION timestamp, fixed for
-- the whole transaction. The feedback RPCs captured `v_now := clock_timestamp()`
-- a few milliseconds later, wrote `updated_at = v_now`, and then recorded
-- `applied_opportunity_updated_at = v_now` as "the state I wrote".
--
-- The trigger silently overwrote the column with now(), so the recorded value
-- was NEVER the value that landed — observed drift ~3.4ms on every row, with
-- the feedback snapshot always LATER than the row.
--
-- undo_* compares opportunity.updated_at against applied_opportunity_updated_at
-- and raises `feedback_undo_conflict` (errcode 40001) when they differ. They
-- always differed, so undo failed 100% of the time, permanently, for every
-- disposition — and 40001 (serialization_failure) reads as transient, so the
-- client retried in a loop (~100 errors/second observed in prod postgres logs
-- on 2026-07-30 16:34:48 UTC).
--
-- FIX: capture v_now with now() instead of clock_timestamp(), so the value the
-- RPC records is byte-identical to the value the trigger writes. now() is
-- stable within a transaction, so the snapshot is exact by construction rather
-- than by luck. Applied to all four functions so apply and undo agree.
--
-- Surgical + drift-guarded: aborts loudly if the declaration is not present
-- exactly once in each function.

do $migration$
declare
  v_fn      text;
  v_def     text;
  v_hits    integer;
  v_needle  constant text := 'v_now timestamptz := clock_timestamp();';
  v_replace constant text := 'v_now timestamptz := now();';
begin
  foreach v_fn in array array[
    'apply_lead_disposition_feedback',
    'undo_lead_disposition_feedback',
    'apply_lead_archive_feedback',
    'undo_lead_archive_feedback'
  ]
  loop
    select pg_get_functiondef(p.oid)
      into v_def
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = v_fn;

    if v_def is null then
      raise exception 'function public.% not found — refusing to patch', v_fn;
    end if;

    v_hits := (length(v_def) - length(replace(v_def, v_needle, ''))) / length(v_needle);

    if v_hits <> 1 then
      raise exception
        'expected exactly 1 clock_timestamp declaration in public.%, found % — re-read the live definition before applying',
        v_fn, v_hits;
    end if;

    execute replace(v_def, v_needle, v_replace);
  end loop;
end
$migration$;
