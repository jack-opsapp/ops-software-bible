-- 055: Add 'auto_drafted' status to ai_draft_history for pre-generated drafts.
DO $$
BEGIN
  ALTER TABLE ai_draft_history DROP CONSTRAINT IF EXISTS ai_draft_history_status_check;
  ALTER TABLE ai_draft_history ADD CONSTRAINT ai_draft_history_status_check
    CHECK (status IN ('drafted', 'sent', 'discarded', 'auto_drafted'));
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Constraint update failed: %', SQLERRM;
END $$;
