CREATE TABLE contact_messages (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  name text,
  email text NOT NULL,
  message text NOT NULL,
  created_at timestamptz DEFAULT now()
);
