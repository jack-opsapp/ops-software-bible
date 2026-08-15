-- content_plan: the authored weekly media manifest (one row per planned post)
create table if not exists public.content_plan (
  id uuid primary key default gen_random_uuid(),
  week_of date not null,
  program text not null,
  slot text not null default 'feed' check (slot in ('feed','story','reel')),
  publish_date date,
  status text not null default 'planned'
    check (status in ('planned','needs_image','rendering','ready','in_review','approved','published','skipped','killed')),
  title text,
  caption text,
  alt_text text,
  image_need text not null default 'none'
    check (image_need in ('none','codex','render_cli','real_photo','screenshot')),
  image_prompt text,
  image_url text,
  asset_urls jsonb,
  source_ref text,
  review_ts text,
  verbatim boolean not null default false,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists content_plan_week_idx on public.content_plan (week_of);
create index if not exists content_plan_publish_idx on public.content_plan (publish_date, status);
create index if not exists content_plan_codex_pending_idx
  on public.content_plan (created_at)
  where image_need = 'codex' and image_url is null;

-- humor_queue: the tribe-humor program (verbatim copy, run-state, §7 blocklist)
create table if not exists public.humor_queue (
  id uuid primary key default gen_random_uuid(),
  position int not null,
  kind text not null default 'anchor' check (kind in ('anchor','reserve')),
  card_type text not null check (card_type in ('bingo','table','list','profile','text')),
  title text not null,
  copy jsonb not null,
  caption text not null,
  alt_text text,
  has_bait boolean not null default false,
  bait_copy text,
  cleared boolean not null default true,
  run_week date,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists humor_queue_next_idx
  on public.humor_queue (position)
  where cleared = true and run_week is null;
