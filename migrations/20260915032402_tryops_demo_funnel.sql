-- Additive demo diagnostics. No experiment activation, exposure, company, trial,
-- growth milestone or welcome-email mutation. Requires the released TryOps schema.
begin;
create table public.tryops_demo_sessions (
 id uuid primary key default gen_random_uuid(),
 token_hash text not null unique check (token_hash ~ '^[a-f0-9]{64}$'),
 version text not null default 'crew-job-v1' check (version='crew-job-v1'),
 created_at timestamptz not null default now(),
 expires_at timestamptz not null default now()+interval '30 days',
 assignment_id uuid references public.tryops_assignments(id) on delete set null,
 check (expires_at>created_at and expires_at<=created_at+interval '30 days')
);
create index tryops_demo_session_assignment on public.tryops_demo_sessions(assignment_id) where assignment_id is not null;
create table public.tryops_demo_events (
 event_id uuid primary key,
 session_id uuid not null references public.tryops_demo_sessions(id) on delete cascade,
 action text not null check (action in ('started','job_assigned','crew_viewed','task_completed','back','restart','exit','signup_clicked','error')),
 step text not null check (step in ('assign','crew','complete')),
 elapsed_ms integer not null check (elapsed_ms between 0 and 86400000),
 error_code text check (error_code in ('asset_unavailable','storage_unavailable','render_failed')),
 received_at timestamptz not null default now(),
 check (error_code is null or action='error'),
 check ((action<>'job_assigned' or step='assign') and (action<>'crew_viewed' or step='crew') and (action<>'task_completed' or step='complete'))
);
create index tryops_demo_events_session on public.tryops_demo_events(session_id,received_at);
-- Re-render, refresh, Back and restart cannot inflate reach/completion counts.
create unique index tryops_demo_milestone_once on public.tryops_demo_events(session_id,action) where action in ('started','job_assigned','crew_viewed','task_completed');
create table public.tryops_demo_bindings (
 actor_id uuid primary key references public.users(id) on delete cascade,
 session_id uuid not null unique references public.tryops_demo_sessions(id) on delete cascade,
 first_received_at timestamptz not null default now(),
 state text not null default 'pending' check (state in ('pending','attached','rejected')),
 next_attempt_at timestamptz not null default now(),
 attempts integer not null default 0,
 last_reason text
);
create index tryops_demo_pending on public.tryops_demo_bindings(next_attempt_at,actor_id) where state='pending';
create table public.tryops_demo_trials (
 company_id uuid primary key references public.companies(id) on delete cascade,
 actor_id uuid not null unique references public.users(id) on delete cascade,
 session_id uuid not null unique references public.tryops_demo_sessions(id) on delete cascade,
 trial_started_at timestamptz not null,
 attached_at timestamptz not null default now()
);

create function public.create_tryops_demo_session(p_token_hash text,p_assignment_token_hash text default null,p_create boolean default false)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare s public.tryops_demo_sessions; assignment uuid;
begin
 if p_token_hash is null or p_token_hash !~ '^[a-f0-9]{64}$' then return jsonb_build_object('status','rejected','reason','invalid_token'); end if;
 select * into s from public.tryops_demo_sessions where token_hash=p_token_hash;
 if found then
  if now()>=s.expires_at then return jsonb_build_object('status','rejected','reason','expired_session'); end if;
  return jsonb_build_object('status','ready');
 end if;
 if p_create is distinct from true then return jsonb_build_object('status','rejected','reason','invalid_token'); end if;
 -- Lookup only. Never allocate an arm or synthesize exposure on demo arrival.
 select id into assignment from public.tryops_assignments where token_hash=p_assignment_token_hash and not excluded and expires_at>now();
 insert into public.tryops_demo_sessions(token_hash,assignment_id) values(p_token_hash,assignment) on conflict(token_hash) do nothing;
 return jsonb_build_object('status','ready');
end $$;

create function public.collect_tryops_demo_event(p_token_hash text,p_event_id uuid,p_action text,p_step text,p_elapsed_ms integer,p_error_code text default null)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare s public.tryops_demo_sessions; e public.tryops_demo_events;
begin
 if p_event_id is null or p_action is null or p_action not in ('started','job_assigned','crew_viewed','task_completed','back','restart','exit','signup_clicked','error') or p_step is null or p_step not in ('assign','crew','complete') or p_elapsed_ms is null or p_elapsed_ms not between 0 and 86400000 or (p_error_code is not null and (p_action<>'error' or p_error_code not in ('asset_unavailable','storage_unavailable','render_failed'))) or (p_action='job_assigned' and p_step<>'assign') or (p_action='crew_viewed' and p_step<>'crew') or (p_action='task_completed' and p_step<>'complete') then return jsonb_build_object('status','rejected','reason','invalid_event'); end if;
 select * into s from public.tryops_demo_sessions where token_hash=p_token_hash for update;
 if not found then return jsonb_build_object('status','rejected','reason','invalid_token'); end if;
 if now()>=s.expires_at then return jsonb_build_object('status','rejected','reason','expired_session'); end if;
 select * into e from public.tryops_demo_events where event_id=p_event_id;
 if found then
  if (e.session_id,e.action,e.step,e.elapsed_ms,e.error_code) is distinct from (s.id,p_action,p_step,p_elapsed_ms,p_error_code) then return jsonb_build_object('status','rejected','reason','event_conflict'); end if;
  return jsonb_build_object('status','duplicate');
 end if;
 if p_action in ('started','job_assigned','crew_viewed','task_completed') and exists(select 1 from public.tryops_demo_events where session_id=s.id and action=p_action) then return jsonb_build_object('status','duplicate'); end if;
 if (select count(*) from public.tryops_demo_events where session_id=s.id)>=256 then return jsonb_build_object('status','rejected','reason','session_limit'); end if;
 insert into public.tryops_demo_events(event_id,session_id,action,step,elapsed_ms,error_code) values(p_event_id,s.id,p_action,p_step,p_elapsed_ms,p_error_code) on conflict(event_id) do nothing;
 if not found then return jsonb_build_object('status','rejected','reason','event_conflict'); end if;
 return jsonb_build_object('status','recorded');
end $$;

create function public.stage_tryops_demo_signup(p_token_hash text,p_actor_id uuid)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare s public.tryops_demo_sessions; b public.tryops_demo_bindings; u public.users;
begin
 if p_actor_id is null then return jsonb_build_object('status','rejected','reason','invalid_actor'); end if;
 perform pg_advisory_xact_lock(hashtextextended('tryops-demo:'||p_actor_id::text,0));
 select * into u from public.users where id=p_actor_id;
 if not found or u.deleted_at is not null or u.is_active is distinct from true or exists(select 1 from public.tryops_exclusions where (kind='actor' and subject_hash=p_actor_id::text) or (kind='company' and subject_hash=u.company_id::text)) then return jsonb_build_object('status','rejected','reason','invalid_actor'); end if;
 select * into s from public.tryops_demo_sessions where token_hash=p_token_hash for update;
 if not found then return jsonb_build_object('status','rejected','reason','invalid_token'); end if;
 select * into b from public.tryops_demo_bindings where actor_id=p_actor_id;
 if found then
  if b.session_id=s.id then return jsonb_build_object('status','already_staged'); end if;
  return jsonb_build_object('status','rejected','reason','actor_already_staged');
 end if;
 if now()>=s.expires_at then return jsonb_build_object('status','rejected','reason','expired_session'); end if;
 if exists(select 1 from public.tryops_demo_bindings where session_id=s.id) then return jsonb_build_object('status','rejected','reason','session_already_staged'); end if;
 -- A returning owner can finish a trial started after this demo. Old trials
 -- never become new demo conversions just because their owner signs in again.
 if u.company_id is not null and exists(select 1 from public.companies where id=u.company_id and (account_holder_id is distinct from p_actor_id::text or trial_start_date<s.created_at)) then return jsonb_build_object('status','rejected','reason','existing_company'); end if;
 insert into public.tryops_demo_bindings(actor_id,session_id) values(p_actor_id,s.id);
 return jsonb_build_object('status','staged');
end $$;

create function public.retry_tryops_demo_trial(p_actor_id uuid,p_company_id uuid)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare s public.tryops_demo_sessions; b public.tryops_demo_bindings; c public.companies; u public.users; l public.tryops_demo_trials; reason text;
begin
 if p_actor_id is null then return jsonb_build_object('status','rejected','reason','invalid_actor'); end if;
 perform pg_advisory_xact_lock(hashtextextended('tryops-demo:'||p_actor_id::text,0));
 select * into b from public.tryops_demo_bindings where actor_id=p_actor_id for update;
 if not found then return jsonb_build_object('status','absent'); end if;
 select * into s from public.tryops_demo_sessions where id=b.session_id;
 select * into u from public.users where id=p_actor_id;
 if u.id is null or u.deleted_at is not null or u.is_active is distinct from true then
  update public.tryops_demo_bindings set state='rejected',last_reason='invalid_actor',attempts=attempts+1 where actor_id=p_actor_id;
  return jsonb_build_object('status','rejected','reason','invalid_actor');
 end if;
 if p_company_id is distinct from u.company_id then
  update public.tryops_demo_bindings set next_attempt_at=now()+interval '5 minutes',attempts=attempts+1,last_reason='company_mismatch' where actor_id=p_actor_id and state='pending';
  return jsonb_build_object('status','rejected','reason','company_mismatch');
 end if;
 select * into c from public.companies where id=p_company_id;
 if c.id is null or c.trial_start_date is null then reason:='trial_not_ready';
 elsif c.deleted_at is not null or c.account_holder_id is distinct from p_actor_id::text or exists(select 1 from public.tryops_exclusions where (kind='actor' and subject_hash=p_actor_id::text) or (kind='company' and subject_hash=p_company_id::text)) then reason:='ineligible_company';
 elsif c.trial_start_date<s.created_at then reason:='trial_before_demo';
 elsif c.trial_start_date>=s.expires_at or b.first_received_at>=s.expires_at then reason:='expired_session';
 end if;
 if reason='trial_not_ready' and now()>=s.expires_at+interval '1 day' then reason:='expired_session'; end if;
 if reason is not null then
  update public.tryops_demo_bindings set state=case when reason='trial_not_ready' then 'pending' else 'rejected' end,last_reason=reason,attempts=attempts+1,next_attempt_at=now()+interval '5 minutes' where actor_id=p_actor_id;
  return jsonb_build_object('status',case when reason='trial_not_ready' then 'pending' else 'rejected' end,'reason',reason);
 end if;
 select * into l from public.tryops_demo_trials where company_id=p_company_id;
 if found then
  if l.actor_id=p_actor_id and l.session_id=s.id then return jsonb_build_object('status','already_attached'); end if;
  update public.tryops_demo_bindings set state='rejected',last_reason='company_already_attributed',attempts=attempts+1 where actor_id=p_actor_id;
  return jsonb_build_object('status','rejected','reason','company_already_attributed');
 end if;
 insert into public.tryops_demo_trials(company_id,actor_id,session_id,trial_started_at) values(p_company_id,p_actor_id,s.id,c.trial_start_date) on conflict do nothing;
 if not found then
  update public.tryops_demo_bindings set state='rejected',last_reason='attribution_conflict',attempts=attempts+1 where actor_id=p_actor_id;
  return jsonb_build_object('status','rejected','reason','attribution_conflict');
 end if;
 update public.tryops_demo_bindings set state='attached',last_reason=null,attempts=attempts+1 where actor_id=p_actor_id;
 return jsonb_build_object('status','attached');
end $$;

create function public.reconcile_tryops_demo()
returns jsonb language plpgsql security invoker set search_path='' set statement_timeout='5s' as $$
declare b record; attempted integer:=0; failures integer:=0;
begin
 -- Exclusive worker lease is transaction scoped; a killed connection releases it.
 if not pg_try_advisory_xact_lock(hashtextextended('tryops-demo-reconcile',0)) then return jsonb_build_object('status','busy','attempted',0); end if;
 for b in select x.actor_id,u.company_id from public.tryops_demo_bindings x join public.users u on u.id=x.actor_id where x.state='pending' and x.next_attempt_at<=now() order by x.next_attempt_at,x.actor_id limit 100 loop
  begin
   perform public.retry_tryops_demo_trial(b.actor_id,b.company_id);
  exception when others then
   failures:=failures+1;
   update public.tryops_demo_bindings set next_attempt_at=now()+interval '5 minutes',attempts=attempts+1,last_reason='storage_unavailable' where actor_id=b.actor_id;
  end;
  attempted:=attempted+1;
 end loop;
 return jsonb_build_object('status','reconciled','attempted',attempted,'failed',failures);
end $$;

do $$ declare t text; f regprocedure; begin
 foreach t in array array['tryops_demo_sessions','tryops_demo_events','tryops_demo_bindings','tryops_demo_trials'] loop
  execute format('alter table public.%I enable row level security',t);
  execute format('revoke all on public.%I from public,anon,authenticated',t);
  execute format('grant select,insert,update,delete on public.%I to service_role',t);
 end loop;
 for f in select oid::regprocedure from pg_proc where pronamespace='public'::regnamespace and proname in ('create_tryops_demo_session','collect_tryops_demo_event','stage_tryops_demo_signup','retry_tryops_demo_trial','reconcile_tryops_demo') loop
  execute format('revoke all on function %s from public,anon,authenticated',f);
  execute format('grant execute on function %s to service_role',f);
 end loop;
end $$;
commit;
