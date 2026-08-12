-- Inbox functional refactor — Phase 1 columns
--
-- Adds:
--   email_threads.ball_settled_at      — user-set "settled" override for ball-in-court
--   email_threads.agent_paused_until   — per-thread auto-send pause
--   email_connections.agent_can_send_from — connection authorized for agent send
--   activities.sent_by_agent           — distinguishes auto-sent activities
--   companies.ai_enabled               — per-company AI toggle (subscription tier)
--
-- All columns use IF NOT EXISTS so the migration is idempotent.

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='email_threads' AND column_name='ball_settled_at') THEN
    ALTER TABLE email_threads ADD COLUMN ball_settled_at timestamptz DEFAULT NULL;
  END IF;
END $$;

COMMENT ON COLUMN email_threads.ball_settled_at IS
  'User-set "settled" override. Suppresses AWAITING_REPLY-derived ball-in-court=us until next inbound message. Cleared (set to NULL) when a new inbound arrives or the user un-settles.';

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='email_threads' AND column_name='agent_paused_until') THEN
    ALTER TABLE email_threads ADD COLUMN agent_paused_until timestamptz DEFAULT NULL;
  END IF;
END $$;

COMMENT ON COLUMN email_threads.agent_paused_until IS
  'Per-thread auto-send pause. NULL = not paused. Far-future timestamp = paused indefinitely. Near-future timestamp = one-shot intervention (auto-resumes after the timestamp passes).';

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='email_connections' AND column_name='agent_can_send_from') THEN
    ALTER TABLE email_connections ADD COLUMN agent_can_send_from boolean NOT NULL DEFAULT false;
  END IF;
END $$;

COMMENT ON COLUMN email_connections.agent_can_send_from IS
  'User has authorized the agent to send from this mailbox. Default false (especially on personal mailboxes). User explicitly opts in per connection.';

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='activities' AND column_name='sent_by_agent') THEN
    ALTER TABLE activities ADD COLUMN sent_by_agent boolean NOT NULL DEFAULT false;
  END IF;
END $$;

COMMENT ON COLUMN activities.sent_by_agent IS
  'True when this activity was generated and sent by the AI agent (Phase 3 auto-send). Used for distinct visual treatment in the chat stream and audit reporting.';

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='companies' AND column_name='ai_enabled') THEN
    ALTER TABLE companies ADD COLUMN ai_enabled boolean NOT NULL DEFAULT true;
  END IF;
END $$;

COMMENT ON COLUMN companies.ai_enabled IS
  'Master switch for AI features at the company level. When false, no AI summaries, drafts, classifications, closed-opp banners, or auto-send. Categories become user-applied labels. Default true (most tiers have AI).';

-- Index hint: queries filtering on agent_paused_until are common (pause check before auto-send).
CREATE INDEX IF NOT EXISTS email_threads_agent_paused_idx
  ON email_threads (agent_paused_until)
  WHERE agent_paused_until IS NOT NULL;
