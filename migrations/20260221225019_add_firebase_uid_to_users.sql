-- Add firebase_uid column to users table for Firebase Auth linkage
ALTER TABLE public.users
  ADD COLUMN firebase_uid text;

-- Index for fast lookup by firebase_uid
CREATE INDEX idx_users_firebase_uid ON public.users (firebase_uid)
  WHERE firebase_uid IS NOT NULL;

-- Unique constraint to prevent duplicate Firebase accounts
ALTER TABLE public.users
  ADD CONSTRAINT uq_users_firebase_uid UNIQUE (firebase_uid);
