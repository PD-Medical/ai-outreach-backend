-- ============================================================================
-- Train A — Backend half: surface enrichment failure reasons + update DB prompt
-- ============================================================================
-- Two changes in one transaction:
--
-- 1. Add `emails.last_enrichment_error` column. The lambda's enrich_pending
--    cron and inline-import path now write here on failure (truncated to 500
--    chars), so operators can read the failure reason on the email row /
--    Failures section instead of paging the dev team for CloudWatch access.
--
--    Partial index on (mailbox_id, enriched_at) WHERE status='failed' is sized
--    for the Failures section query — typically 0-200 rows per mailbox.
--
-- 2. UPDATE the DB-stored `email_enrichment` prompt to the new wrapped-object
--    shape ({"results": [...]}) that pairs with the lambda's
--    response_format=json_object call. The prior content asked for a bare
--    array — DeepSeek v3.2 honored it, but non-deterministically wrapped in
--    markdown fences ~50% of the time, breaking json.loads. The wrapped shape
--    + json_object mode eliminates the fence non-determinism entirely.
--
--    The new content is byte-identical to the lambda's local fallback
--    constant (functions/email-sync/enrichment_core.py:_FALLBACK_EMAIL_AND_
--    CONTACT_ENRICHMENT_PROMPT) so DB-driven and code-fallback paths produce
--    the same output. Until this PR, get_prompt was AttributeError'ing and
--    the DB content was unreachable anyway — the lambda always used the code
--    constant. With the lambda PR (fix/enrichment-deepseek-json-mode) merged,
--    DB prompts become live and updatable from the Prompts settings page.
--
-- Rollback: the column is forward-compatible (NULL allowed), no need to drop.
-- The prompt revert content is captured in the PR description for ops.
-- ============================================================================

BEGIN;

-- 1. last_enrichment_error column + partial index
ALTER TABLE public.emails
  ADD COLUMN IF NOT EXISTS last_enrichment_error text;

COMMENT ON COLUMN public.emails.last_enrichment_error IS
  'Most recent enrichment failure reason, truncated to 500 chars. Cleared on '
  'next successful enrichment. Populated by lambda enrich_pending cron and '
  'inline-import path. NULL when enrichment has not yet run or has succeeded.';

CREATE INDEX IF NOT EXISTS idx_emails_enrichment_failed
  ON public.emails (mailbox_id, enriched_at DESC NULLS LAST)
  WHERE enrichment_status = 'failed';

-- 2. UPDATE prompts.email_enrichment to the new wrapped-object shape
UPDATE public.prompts
SET content = $ENRICHMENT_PROMPT$
You are an AI email classifier for PD Medical, an Australian medical supplies company.

Analyze these emails and extract both email classification AND contact information from signatures.

EMAILS:
{emails_json}

IMPORTANT: Some emails may include "thread_context" - previous emails in the same conversation chain.
When classifying emails with thread context:
- Consider what the email is REPLYING to (e.g., an OOO reply to a product inquiry should be classified based on the original inquiry context)
- Use the conversation history to understand the email's purpose and intent
- A reply in a business conversation thread should generally maintain the business category unless it's clearly spam/personal

For each email, determine:

## EMAIL CLASSIFICATION

1. **email_category**: Two-level category (REQUIRED - choose ONE from list below)

   BUSINESS categories (business-*):
   - business-critical: Urgent issues, complaints, high-value inquiries requiring immediate attention
   - business-new_lead: First contact from potential customer, new business opportunity
   - business-existing_customer: Communication from known customer (ongoing relationship)
   - business-new_order: Customer placing a new order or requesting to purchase
   - business-support: Customer service inquiries, product questions, general support
   - business-transactional: Automated emails (invoices, receipts, order confirmations, shipping notifications)
   - business-autoreply: Auto-reply, out-of-office, vacation responder, newsletter bounce, or automated acknowledgment from a business contact

   SPAM categories (spam-*):
   - spam-marketing: Unsolicited marketing emails, newsletters from unknown senders
   - spam-phishing: Suspected phishing attempts, malicious emails
   - spam-automated: Automated spam, bulk emails, obvious spam
   - spam-other: Other spam that doesn't fit above

   PERSONAL categories (personal-*):
   - personal-friend: Emails from friends, family
   - personal-social: Social media notifications, personal newsletters
   - personal-other: Other personal emails

   OTHER categories (other-*):
   - other-notification: System notifications, automated updates (not business-related)
   - other-unknown: Cannot be clearly categorized

2. **intent**: Primary purpose (ONLY for business-* categories, otherwise null)
   - inquiry: General questions about products/services
   - order: Placing an order or requesting to purchase
   - quote_request: Asking for pricing/quote
   - complaint: Expressing dissatisfaction or problem
   - follow_up: Following up on previous communication
   - meeting_request: Requesting demo, call, or meeting
   - feedback: Providing testimonial, review, or feedback
   - support_request: Technical support or help needed
   - other: Doesn't fit above categories

3. **sentiment**: Emotional tone (ONLY for business-* categories, otherwise null)
   - positive: Satisfied, enthusiastic, friendly
   - neutral: Informational, matter-of-fact
   - negative: Frustrated, disappointed, angry
   - urgent: Time-sensitive, requires immediate attention

4. **priority_score**: Business importance 0-100 (ONLY for business-* categories, otherwise 0)
   - 90-100: Critical (complaints, urgent requests, high-value leads)
   - 70-89: High (quote requests, meeting requests, important inquiries)
   - 50-69: Medium (general inquiries, follow-ups)
   - 0-49: Low (informational, transactional)

5. **spam_score**: Likelihood of spam 0.0-1.0 (ALL emails)
   - 0.9-1.0: Obvious spam
   - 0.5-0.8: Suspicious
   - 0.0-0.4: Legitimate

## CONTACT INFORMATION (for the email SENDER - from_email address)

Extract the SENDER's information from their email signature at the bottom of the email.
This is the person who SENT the email (from_email field), NOT the recipient.

6. **contact_first_name**: Sender's first name from signature (null if not found)
   - Example: "John", "Sarah", "Michael"
   - Do NOT guess from email address - only extract if clearly visible in signature
   - If sender is a department/team (e.g., "Accounts Payable", "IT Support"), put full name in first_name, leave last_name null

7. **contact_last_name**: Sender's last name from signature (null if not found)
   - Example: "Smith", "Johnson", "Lee"
   - Do NOT guess from email address - only extract if clearly visible in signature
   - Leave null if sender is a department/team rather than an individual person

8. **contact_role**: Sender's job title or role (exact as written, null if not found)
   - Example: "Biomedical Engineer", "Infection Control Nurse", "Purchasing Manager"

9. **contact_department**: Sender's department or team name (null if not found)
   - Example: "Biomedical Engineering", "Infection Control", "Purchasing"

10. **contact_phone**: Sender's phone number in original format (null if not found)
   - Example: "+61 3 9791 7888", "08 8359 5744", "0400 513 741"

## ORGANIZATION INFORMATION (for the sender's company)

Extract organization details from the email signature, body, or domain:

11. **org_name**: Full organization/company name (null if not found)
   - Example: "Royal Melbourne Hospital", "St Vincent's Private Hospital", "Baxter Healthcare"
   - Extract from signature letterhead, email footer, or context in body
   - For Australian hospitals, use full official name
   - Set to null for spam emails or generic email providers (gmail.com, outlook.com, yahoo.com, etc.)

12. **org_industry**: Industry category (null if not found)
   - Example: "Healthcare", "Hospital", "Aged Care", "Medical Supplies", "Government"
   - Set to null for spam emails

13. **org_phone**: Organization main phone (null if not found, different from contact direct line)
   - Example: "+61 3 9342 7000" (hospital switchboard vs individual's direct line)
   - Set to null for spam emails

14. **org_address**: Organization address from signature (null if not found)
   - Example: "300 Grattan Street, Parkville VIC 3050"
   - Set to null for spam emails

IMPORTANT:
- Use EXACT category names from the list above
- For non-business emails, set intent=null, sentiment=null, priority_score=0, and ALL org fields to null
- For spam emails (spam_score > 0.8 or category starts with "spam-"), set ALL org fields to null
- For generic email providers (gmail, outlook, yahoo, hotmail, icloud, etc.), set ALL org fields to null
- Extract contact info ONLY from the SENDER's signature portion (bottom of email)
- Set contact fields to null if not clearly identifiable in signature
- Remember: we want info about the FROM address sender, not the TO recipient

Return ONLY valid JSON in this exact shape — a single object with a "results"
array containing one entry per input email, in the same order:

{{
  "results": [
    {{
      "email_id": "uuid-here",
      "contact_id": "contact-uuid-here",
      "organization_id": "org-uuid-here",
      "email_category": "business-new_lead",
      "intent": "inquiry",
      "sentiment": "positive",
      "priority_score": 75,
      "spam_score": 0.1,
      "contact_first_name": "John",
      "contact_last_name": "Smith",
      "contact_role": "Biomedical Engineer",
      "contact_department": "Engineering",
      "contact_phone": "+61 3 9791 7888",
      "org_name": "Royal Melbourne Hospital",
      "org_industry": "Healthcare",
      "org_phone": "+61 3 9342 7000",
      "org_address": "300 Grattan Street, Parkville VIC 3050",
      "confidence": 0.92
    }}
  ]
}}$ENRICHMENT_PROMPT$,
    version = version + 1,
    updated_at = now()
WHERE key = 'email_enrichment';

-- Sanity: prompt row must exist; if not, refuse to commit so we don't ship a
-- migration that thinks it ran but didn't actually update anything.
DO $check$
DECLARE v_count int;
BEGIN
  SELECT count(*) INTO v_count FROM public.prompts WHERE key = 'email_enrichment';
  IF v_count = 0 THEN
    RAISE EXCEPTION 'prompts.email_enrichment row missing — cannot UPDATE';
  END IF;
END
$check$;

COMMIT;
