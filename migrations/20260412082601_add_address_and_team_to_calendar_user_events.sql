-- Add address and team_member_ids columns to calendar_user_events
-- Supports personal event location and team assignment features
ALTER TABLE calendar_user_events ADD COLUMN IF NOT EXISTS address text;
ALTER TABLE calendar_user_events ADD COLUMN IF NOT EXISTS team_member_ids text[] DEFAULT '{}';
