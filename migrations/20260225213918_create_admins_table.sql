CREATE TABLE admins (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email text UNIQUE NOT NULL,
  name text,
  created_at timestamptz DEFAULT now()
);

INSERT INTO admins (email, name) VALUES
  ('jack@opsapp.co', 'Jackson Sweet'),
  ('canprojack@gmail.com', 'Jackson Sweet');

