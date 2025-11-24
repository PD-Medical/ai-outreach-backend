-- Add 'ooo' as valid contact status
ALTER TABLE contacts
DROP CONSTRAINT IF EXISTS contacts_status_check;

ALTER TABLE contacts
ADD CONSTRAINT contacts_status_check
CHECK (status IN ('active', 'inactive', 'unsubscribed', 'bounced', 'ooo'));

COMMENT ON CONSTRAINT contacts_status_check ON contacts IS 'Valid contact statuses: active, inactive, unsubscribed, bounced, ooo';
