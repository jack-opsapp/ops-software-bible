CREATE TABLE IF NOT EXISTS public.email_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email text NOT NULL,
  event text NOT NULL,
  sg_message_id text,
  "timestamp" timestamptz NOT NULL,
  url text,
  useragent text,
  ip text,
  reason text,
  raw jsonb,
  created_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_email_events_email ON public.email_events (email);
CREATE INDEX IF NOT EXISTS idx_email_events_event ON public.email_events (event);
CREATE INDEX IF NOT EXISTS idx_email_events_timestamp ON public.email_events ("timestamp");
CREATE INDEX IF NOT EXISTS idx_email_events_sg_message_id ON public.email_events (sg_message_id);

DELETE FROM public.email_events e
USING (
  SELECT id
  FROM (
    SELECT id,
           ROW_NUMBER() OVER (
             PARTITION BY sg_message_id, event, "timestamp"
             ORDER BY created_at NULLS LAST, id
           ) AS rn
    FROM public.email_events
    WHERE sg_message_id IS NOT NULL
  ) ranked
  WHERE rn > 1
) dups
WHERE e.id = dups.id;

CREATE UNIQUE INDEX IF NOT EXISTS uq_email_events_idempotency
  ON public.email_events (sg_message_id, event, "timestamp")
  WHERE sg_message_id IS NOT NULL;

COMMENT ON TABLE public.email_events IS
  'SendGrid Event Webhook persistence. Every email event (delivered, open, click, bounce, dropped, deferred, spam_report, unsubscribe, processed) is upserted here. Idempotent on (sg_message_id, event, timestamp).';

COMMENT ON COLUMN public.email_events.event IS
  'SendGrid event type. Canonical values: delivered, open, click, bounce, dropped, deferred, spamreport, unsubscribe, processed, group_unsubscribe, group_resubscribe.';

COMMENT ON COLUMN public.email_events.raw IS
  'Full SendGrid event payload as received. Persist for forensics.';
