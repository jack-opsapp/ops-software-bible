alter table public.activities
  add column if not exists body_text_clean text;

comment on column public.activities.body_text_clean is
  'Quote- and signature-stripped clean body, computed at email ingestion (sync-engine.createActivity). Raw provider body remains in body_text. Consumed by the conversation-state clean-state layer. Nullable/additive (iOS-safe); NULL for rows ingested before this column existed.';
