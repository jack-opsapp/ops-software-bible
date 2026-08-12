-- W3 security posture sweep (bug c5ff388e): remove anon/public read (+ one update)
-- exposure on the leadership-assessment / learning tables. Every real accessor is
-- service_role (RLS-bypass); these USING(true) policies are vestigial attack surface.
-- Sentinel-proven: anon 662/9315/1/206 -> 0/0/0/0; service-role unchanged.

alter table public.assessment_responses   enable row level security;
alter table public.assessment_sessions    enable row level security;
alter table public.assessment_submissions enable row level security;
alter table public.enrollments            enable row level security;

drop policy if exists "responses_select" on public.assessment_responses;
drop policy if exists "sessions_select_by_token" on public.assessment_sessions;
drop policy if exists "sessions_update_own" on public.assessment_sessions;
drop policy if exists "Users can read own submissions" on public.assessment_submissions;
drop policy if exists "Users can read own enrollments" on public.enrollments;
