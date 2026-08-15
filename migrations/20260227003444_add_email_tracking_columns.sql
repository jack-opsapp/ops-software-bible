
-- Add email tracking columns to users table
ALTER TABLE public.users 
ADD COLUMN IF NOT EXISTS email_domain_valid BOOLEAN DEFAULT NULL,
ADD COLUMN IF NOT EXISTS removed_from_email_list BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS removed_from_email_list_at TIMESTAMPTZ;

-- Index for email queries
CREATE INDEX IF NOT EXISTS idx_users_email_domain_valid ON public.users(email_domain_valid);
CREATE INDEX IF NOT EXISTS idx_users_removed_from_email ON public.users(removed_from_email_list);

-- Comments
COMMENT ON COLUMN public.users.email_domain_valid IS 'NULL=unchecked, TRUE=valid MX records, FALSE=invalid domain';
COMMENT ON COLUMN public.users.removed_from_email_list IS 'Auto-removed after final email in sequence (90 days for Bubble, 180 days for Unverified)';

