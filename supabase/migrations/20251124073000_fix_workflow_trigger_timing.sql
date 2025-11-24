-- Fix workflow matcher trigger to be BEFORE trigger so it can modify NEW row
-- AFTER triggers cannot modify the row being inserted/updated

DROP TRIGGER IF EXISTS trigger_match_workflows ON emails;

CREATE TRIGGER trigger_match_workflows
  BEFORE INSERT OR UPDATE OF email_category ON emails
  FOR EACH ROW
  WHEN (NEW.email_category IS NOT NULL AND NEW.email_category LIKE 'business-%')
  EXECUTE FUNCTION trigger_workflow_matching();

COMMENT ON TRIGGER trigger_match_workflows ON emails IS 'Triggers workflow-matcher Lambda for business emails (BEFORE trigger to set workflow_matched_at)';
