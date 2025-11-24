-- Add persona and signature support to mailboxes
-- Add scheduling support to email_drafts
-- Enables AI persona-driven email drafting with HTML signatures and scheduled sends

-- Mailbox enhancements for persona-driven drafting
ALTER TABLE mailboxes ADD COLUMN persona_description TEXT;
ALTER TABLE mailboxes ADD COLUMN signature_html TEXT;

-- Email draft scheduling support
ALTER TABLE email_drafts ADD COLUMN scheduled_send_offset_minutes INTEGER;
ALTER TABLE email_drafts ADD COLUMN scheduled_send_time TIMESTAMP WITH TIME ZONE;

-- Add helpful comments
COMMENT ON COLUMN mailboxes.persona_description IS 'AI persona description for email drafting (e.g., "You are a friendly sales rep...")';
COMMENT ON COLUMN mailboxes.signature_html IS 'HTML email signature automatically appended to all emails from this mailbox';
COMMENT ON COLUMN email_drafts.scheduled_send_offset_minutes IS 'Relative offset in minutes from creation time (e.g., 120 = +2 hours)';
COMMENT ON COLUMN email_drafts.scheduled_send_time IS 'Absolute timestamp when email should be sent (computed from offset)';
