WITH email_msgs AS (
  SELECT
    a.id, a.company_id, a.email_thread_id AS provider_thread_id,
    a.email_message_id, a.subject, a.from_email, a.to_emails, a.cc_emails,
    a.body_text, a.content, a.has_attachments, a.is_read, a.created_at,
    a.opportunity_id, a.client_id
  FROM public.activities a
  WHERE a.type = 'email'
    AND a.email_thread_id IS NOT NULL AND a.email_thread_id <> ''
    AND a.email_message_id IS NOT NULL AND a.email_message_id <> ''
),
msgs_ranked AS (
  SELECT m.*,
    row_number() OVER (PARTITION BY m.company_id, m.provider_thread_id ORDER BY m.created_at DESC) AS rn_desc,
    row_number() OVER (PARTITION BY m.company_id, m.provider_thread_id ORDER BY m.created_at ASC)  AS rn_asc
  FROM email_msgs m
),
latest_msg AS (SELECT * FROM msgs_ranked WHERE rn_desc = 1),
first_subject AS (
  SELECT DISTINCT ON (company_id, provider_thread_id) company_id, provider_thread_id, subject
  FROM msgs_ranked
  WHERE subject IS NOT NULL AND subject <> ''
  ORDER BY company_id, provider_thread_id, rn_asc
),
thread_stats AS (
  SELECT m.company_id, m.provider_thread_id,
    count(*) AS message_count,
    min(m.created_at) AS first_message_at,
    max(m.created_at) AS last_message_at,
    bool_or(COALESCE(m.has_attachments, false)) AS any_has_attachment,
    (array_agg(m.opportunity_id ORDER BY m.created_at DESC) FILTER (WHERE m.opportunity_id IS NOT NULL))[1] AS opportunity_id,
    (array_agg(m.client_id      ORDER BY m.created_at DESC) FILTER (WHERE m.client_id      IS NOT NULL))[1] AS client_id
  FROM msgs_ranked m
  GROUP BY m.company_id, m.provider_thread_id
),
thread_participants AS (
  SELECT m.company_id, m.provider_thread_id,
    array_agg(DISTINCT trim(lower(addr))) FILTER (WHERE addr IS NOT NULL AND trim(addr) <> '') AS participants
  FROM msgs_ranked m
  CROSS JOIN LATERAL unnest(
    array_append(COALESCE(m.to_emails, ARRAY[]::text[]), m.from_email)
    || COALESCE(m.cc_emails, ARRAY[]::text[])
  ) AS addr
  GROUP BY m.company_id, m.provider_thread_id
),
connection_pick AS (
  SELECT ts.company_id, ts.provider_thread_id,
    COALESCE(
      (SELECT ec.id FROM public.email_connections ec
       WHERE ec.company_id::text = ts.company_id::text AND ec.sync_enabled = true
         AND EXISTS (SELECT 1 FROM msgs_ranked m
           WHERE m.company_id = ts.company_id AND m.provider_thread_id = ts.provider_thread_id
             AND lower(m.from_email) = lower(ec.email))
       ORDER BY ec.created_at ASC LIMIT 1),
      (SELECT ec.id FROM public.email_connections ec
       WHERE ec.company_id::text = ts.company_id::text AND ec.sync_enabled = true
         AND EXISTS (SELECT 1 FROM msgs_ranked m
           WHERE m.company_id = ts.company_id AND m.provider_thread_id = ts.provider_thread_id
             AND (lower(ec.email) = ANY(SELECT lower(t) FROM unnest(COALESCE(m.to_emails, ARRAY[]::text[])) t)
                  OR lower(ec.email) = ANY(SELECT lower(t) FROM unnest(COALESCE(m.cc_emails, ARRAY[]::text[])) t)))
       ORDER BY ec.created_at ASC LIMIT 1),
      (SELECT ec.id FROM public.email_connections ec
       WHERE ec.company_id::text = ts.company_id::text AND ec.sync_enabled = true
       ORDER BY ec.created_at ASC LIMIT 1)
    ) AS connection_id
  FROM thread_stats ts
),
thread_final AS (
  SELECT ts.company_id, cp.connection_id, ts.provider_thread_id,
    CASE WHEN lower(l.from_email) = lower(ec.email) THEN 'outbound' ELSE 'inbound' END AS latest_direction_derived,
    l.from_email AS latest_sender_email,
    l.body_text, l.content,
    fs.subject AS first_subject,
    ts.message_count, ts.first_message_at, ts.last_message_at, ts.any_has_attachment,
    ts.opportunity_id, ts.client_id, tp.participants, l.is_read AS latest_is_read
  FROM thread_stats ts
  JOIN latest_msg l           ON l.company_id = ts.company_id AND l.provider_thread_id = ts.provider_thread_id
  JOIN connection_pick cp     ON cp.company_id = ts.company_id AND cp.provider_thread_id = ts.provider_thread_id
  LEFT JOIN first_subject fs  ON fs.company_id = ts.company_id AND fs.provider_thread_id = ts.provider_thread_id
  LEFT JOIN thread_participants tp ON tp.company_id = ts.company_id AND tp.provider_thread_id = ts.provider_thread_id
  LEFT JOIN public.email_connections ec ON ec.id = cp.connection_id
  WHERE cp.connection_id IS NOT NULL
)
INSERT INTO public.email_threads (
  company_id, connection_id, provider_thread_id,
  primary_category, category_confidence, category_classifier_version, category_manually_set,
  labels, subject, participants, first_message_at, last_message_at,
  message_count, unread_count, latest_direction, latest_sender_email,
  latest_sender_name, latest_snippet, opportunity_id, client_id, priority_score
)
SELECT
  tf.company_id, tf.connection_id, tf.provider_thread_id,
  'OTHER', 0.00, 'backfill-v1', false,
  (
    CASE WHEN tf.latest_direction_derived = 'inbound' AND (
        position('?' in COALESCE(tf.body_text, tf.content, '')) > 0
        OR COALESCE(tf.body_text, tf.content, '') ~* '(can you|could you|please|let me know|any chance|when|what time|confirm|awaiting|looking forward)'
      ) THEN ARRAY['AWAITING_REPLY']::text[] ELSE ARRAY[]::text[] END
    ||
    CASE WHEN tf.any_has_attachment THEN ARRAY['HAS_ATTACHMENT']::text[] ELSE ARRAY[]::text[] END
  ),
  COALESCE(NULLIF(tf.first_subject, ''), '(no subject)'),
  COALESCE(tf.participants, ARRAY[]::text[]),
  tf.first_message_at, tf.last_message_at, tf.message_count,
  CASE WHEN tf.latest_direction_derived = 'inbound' AND NOT COALESCE(tf.latest_is_read, false) THEN 1 ELSE 0 END,
  tf.latest_direction_derived, tf.latest_sender_email, split_part(tf.latest_sender_email, '@', 1),
  left(COALESCE(NULLIF(tf.body_text, ''), NULLIF(tf.content, ''), ''), 400),
  tf.opportunity_id, tf.client_id, 0.00
FROM thread_final tf
ON CONFLICT (connection_id, provider_thread_id) DO NOTHING;
