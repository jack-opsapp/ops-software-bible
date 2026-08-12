-- Add correspondence tracking columns to opportunities for the sync engine stage evaluator.
-- These track email volume and direction to enable automatic pipeline stage advancement.

ALTER TABLE opportunities
  ADD COLUMN IF NOT EXISTS correspondence_count integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS outbound_count integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS inbound_count integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS last_inbound_at timestamptz,
  ADD COLUMN IF NOT EXISTS last_outbound_at timestamptz,
  ADD COLUMN IF NOT EXISTS last_message_direction text;

COMMENT ON COLUMN opportunities.correspondence_count IS 'Total email messages in this opportunity thread';
COMMENT ON COLUMN opportunities.outbound_count IS 'Total outbound emails sent by the company';
COMMENT ON COLUMN opportunities.inbound_count IS 'Total inbound emails received from the client';
COMMENT ON COLUMN opportunities.last_inbound_at IS 'Timestamp of the last inbound email';
COMMENT ON COLUMN opportunities.last_outbound_at IS 'Timestamp of the last outbound email';
COMMENT ON COLUMN opportunities.last_message_direction IS 'Direction of the most recent message: in or out';
