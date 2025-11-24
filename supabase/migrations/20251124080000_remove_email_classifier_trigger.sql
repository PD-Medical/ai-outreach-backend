-- Remove email-classifier Lambda trigger since enrichment now handles classification
-- The email-sync Lambda performs enrichment which sets email_category
-- The trigger_match_workflows handles workflow matching when category is set

-- Drop the trigger that invokes email-classifier
DROP TRIGGER IF EXISTS trigger_classify_new_emails ON emails;

-- Drop the function that invokes email-classifier
DROP FUNCTION IF EXISTS trigger_email_classification();

COMMENT ON TABLE emails IS 'Email messages (classification handled by enrichment in email-sync, workflow matching triggered by trigger_match_workflows)';
