-- ============================================================================
-- Centralized Prompt Management System
-- Created: 2026-01-09
--
-- This migration creates tables for managing LLM prompts with version history.
-- Prompts are configurable via the Settings UI.
-- ============================================================================

-- ==========================================================================
-- TABLE: prompts (Current Active Prompts)
-- ==========================================================================

CREATE TABLE IF NOT EXISTS public.prompts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    key VARCHAR(100) NOT NULL UNIQUE,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    content TEXT NOT NULL,
    variables JSONB DEFAULT '[]'::jsonb,  -- Array of {name, description, sample_value, required}
    category VARCHAR(50),                  -- 'email', 'workflow', 'campaign', 'enrichment'
    used_in VARCHAR(255),                  -- File/function where prompt is used
    is_active BOOLEAN DEFAULT true,
    version INT DEFAULT 1,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now(),
    updated_by UUID REFERENCES auth.users(id)
);

CREATE INDEX IF NOT EXISTS idx_prompts_key ON prompts(key);
CREATE INDEX IF NOT EXISTS idx_prompts_category ON prompts(category);
CREATE INDEX IF NOT EXISTS idx_prompts_is_active ON prompts(is_active);

-- ==========================================================================
-- TABLE: prompt_versions (Version History)
-- ==========================================================================

CREATE TABLE IF NOT EXISTS public.prompt_versions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    prompt_id UUID NOT NULL REFERENCES prompts(id) ON DELETE CASCADE,
    version INT NOT NULL,
    content TEXT NOT NULL,
    variables JSONB DEFAULT '[]'::jsonb,
    created_at TIMESTAMPTZ DEFAULT now(),
    created_by UUID REFERENCES auth.users(id),
    change_reason TEXT  -- Optional note about why changed
);

CREATE INDEX IF NOT EXISTS idx_prompt_versions_prompt ON prompt_versions(prompt_id);
CREATE INDEX IF NOT EXISTS idx_prompt_versions_version ON prompt_versions(prompt_id, version DESC);

-- ==========================================================================
-- TRIGGER: Auto-update updated_at on prompts
-- ==========================================================================

CREATE OR REPLACE FUNCTION update_prompts_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS prompts_updated_at ON prompts;
CREATE TRIGGER prompts_updated_at
    BEFORE UPDATE ON prompts
    FOR EACH ROW
    EXECUTE FUNCTION update_prompts_updated_at();

-- ==========================================================================
-- RLS POLICIES
-- ==========================================================================

ALTER TABLE prompts ENABLE ROW LEVEL SECURITY;
ALTER TABLE prompt_versions ENABLE ROW LEVEL SECURITY;

-- All authenticated users can read active prompts
DROP POLICY IF EXISTS "Users can read prompts" ON prompts;
CREATE POLICY "Users can read prompts" ON prompts FOR SELECT
USING (auth.role() = 'authenticated' AND is_active = true);

-- Admins can manage prompts (full CRUD)
DROP POLICY IF EXISTS "Admins can manage prompts" ON prompts;
CREATE POLICY "Admins can manage prompts" ON prompts FOR ALL
USING (EXISTS (
    SELECT 1 FROM user_roles ur JOIN roles r ON ur.role_id = r.id
    WHERE ur.user_id = auth.uid() AND r.name = 'admin'
));

-- Admins can read version history
DROP POLICY IF EXISTS "Admins can read versions" ON prompt_versions;
CREATE POLICY "Admins can read versions" ON prompt_versions FOR SELECT
USING (EXISTS (
    SELECT 1 FROM user_roles ur JOIN roles r ON ur.role_id = r.id
    WHERE ur.user_id = auth.uid() AND r.name = 'admin'
));

-- Admins can insert version history
DROP POLICY IF EXISTS "Admins can insert versions" ON prompt_versions;
CREATE POLICY "Admins can insert versions" ON prompt_versions FOR INSERT
WITH CHECK (EXISTS (
    SELECT 1 FROM user_roles ur JOIN roles r ON ur.role_id = r.id
    WHERE ur.user_id = auth.uid() AND r.name = 'admin'
));

-- Service role can do everything (for Lambda functions)
DROP POLICY IF EXISTS "Service role full access prompts" ON prompts;
CREATE POLICY "Service role full access prompts" ON prompts FOR ALL
USING (auth.role() = 'service_role');

DROP POLICY IF EXISTS "Service role full access prompt_versions" ON prompt_versions;
CREATE POLICY "Service role full access prompt_versions" ON prompt_versions FOR ALL
USING (auth.role() = 'service_role');

-- ==========================================================================
-- SEED DATA: Initial prompts from codebase
-- ==========================================================================

INSERT INTO prompts (key, name, description, category, used_in, content, variables) VALUES

-- 1. Email Classification (llm.py)
(
    'email_classification',
    'Email Classification',
    'Classify emails into categories (spam, personal, business, automated) with confidence score.',
    'workflow',
    'functions/shared/llm.py:PromptTemplates.email_classification()',
    'Classify this email into ONE category:

Categories:
- spam: Unsolicited marketing, phishing attempts, scams
- personal: Personal messages, non-business related
- business: Business-related, professional communication
- automated: Automated notifications, receipts, system messages

Email:
From: {from_email}
Subject: {subject}
Body: {body}

Analyze the content carefully and return JSON:
{{
  "category": "...",
  "confidence": 0.0-1.0,
  "reasoning": "Brief explanation of classification"
}}',
    '[
        {"name": "from_email", "description": "Sender email address", "sample_value": "john.smith@hospital.com.au", "required": true},
        {"name": "subject", "description": "Email subject line", "sample_value": "Quote request for sharps containers", "required": true},
        {"name": "body", "description": "Email body text (plain text)", "sample_value": "Hi, I''m looking for pricing on your sharps disposal units for our emergency department. We need approximately 50 units. Thanks, John", "required": true}
    ]'::jsonb
),

-- 2. Workflow Matching (llm.py)
(
    'workflow_matching',
    'Workflow Matching',
    'Match incoming emails to relevant automation workflows based on content analysis.',
    'workflow',
    'functions/shared/llm.py:PromptTemplates.workflow_matching()',
    'Match this email to relevant workflows.

Email:
From: {from_email}
Subject: {subject}
Body: {body}

Available workflows:
{workflow_list}

Analyze which workflows apply to this email. A workflow matches if the email content aligns with its trigger condition.

Return JSON array of matches:
{{
  "matches": [
    {{
      "workflow_id": "uuid",
      "confidence": 0.0-1.0,
      "reasoning": "Why this workflow matches"
    }}
  ]
}}

Return empty array if no workflows match.',
    '[
        {"name": "from_email", "description": "Sender email address", "sample_value": "jane@clinic.com.au", "required": true},
        {"name": "subject", "description": "Email subject line", "sample_value": "Out of Office: Jane Smith", "required": true},
        {"name": "body", "description": "Email body text", "sample_value": "I am currently out of the office until January 15th with limited access to email.", "required": true},
        {"name": "workflow_list", "description": "List of available workflows with IDs and trigger conditions", "sample_value": "1. OOO Detection (id: abc-123): Triggers when email indicates sender is out of office\n2. Quote Request (id: def-456): Triggers when email requests pricing or quote", "required": true}
    ]'::jsonb
),

-- 3. Field Extraction (llm.py)
(
    'field_extraction',
    'Field Extraction',
    'Extract structured data fields from email content based on workflow configuration.',
    'workflow',
    'functions/shared/llm.py:PromptTemplates.field_extraction()',
    'Extract the following information from this email:

Email:
From: {from_email}
Subject: {subject}
Body: {body}

Fields to extract:
{fields_description}

Return JSON with extracted values. Use null if field not found or cannot be determined with confidence.
For date fields, ALWAYS return in ISO format (YYYY-MM-DD). Convert natural language dates like "Monday, December 2, 2025" to "2025-12-02".
Also include a "confidence" field (0.0-1.0) indicating your overall confidence in the extraction.

{{
  "field1": "value1",
  "date_field": "2025-12-02",
  "confidence": 0.85
}}',
    '[
        {"name": "from_email", "description": "Sender email address", "sample_value": "supplier@vendor.com", "required": true},
        {"name": "subject", "description": "Email subject line", "sample_value": "RE: Order #12345 delivery update", "required": true},
        {"name": "body", "description": "Email body text", "sample_value": "Your order will be delivered on Monday, January 20th, 2025. The tracking number is AU123456789.", "required": true},
        {"name": "fields_description", "description": "Description of fields to extract", "sample_value": "- delivery_date (date): Expected delivery date\n- tracking_number (string): Shipping tracking number\n- order_id (string): Order reference number", "required": true}
    ]'::jsonb
),

-- 4. Email Personalization (llm.py)
(
    'email_personalization',
    'Email Personalization',
    'Personalize email templates with context-aware content while maintaining core message.',
    'email',
    'functions/shared/llm.py:PromptTemplates.email_personalization()',
    'Personalize this email template:

Template:
Subject: {subject_template}
Body: {body_template}

Context:
{context}

Instructions:
{instructions}

Generate a personalized version of the email. Maintain the core message but adapt the tone, examples, and details based on the context provided.

Return ONLY the personalized email body text, no additional commentary.',
    '[
        {"name": "subject_template", "description": "Email subject template", "sample_value": "Following up on {product_name}", "required": true},
        {"name": "body_template", "description": "Email body template with placeholders", "sample_value": "Hi {first_name},\n\nI wanted to follow up on our conversation about {product_name}...", "required": true},
        {"name": "context", "description": "Context information for personalization", "sample_value": "Contact: John Smith, Biomedical Engineer at Royal Melbourne Hospital\nPrevious interaction: Expressed interest in sharps containers\nOrganization: 500-bed public hospital", "required": true},
        {"name": "instructions", "description": "Additional personalization instructions", "sample_value": "Keep tone professional but friendly. Mention the hospital''s size as relevant to bulk pricing.", "required": false}
    ]'::jsonb
),

-- 5. Email & Contact Enrichment (enrichment_core.py)
(
    'email_enrichment',
    'Email & Contact Enrichment',
    'Classify emails and extract contact/organization information from email signatures. This is the main enrichment prompt that processes incoming emails.',
    'enrichment',
    'functions/email-sync/enrichment_core.py:EMAIL_AND_CONTACT_ENRICHMENT_PROMPT',
    'You are an AI email classifier for PD Medical, an Australian medical supplies company.

Analyze these emails and extract both email classification AND contact information from signatures.

EMAILS:
{emails_json}

IMPORTANT: Some emails may include "thread_context" - previous emails in the same conversation chain.
When classifying emails with thread context:
- Consider what the email is REPLYING to (e.g., an OOO reply to a product inquiry should be classified based on the original inquiry context)
- Use the conversation history to understand the email''s purpose and intent
- A reply in a business conversation thread should generally maintain the business category unless it''s clearly spam/personal

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

   SPAM categories (spam-*):
   - spam-marketing: Unsolicited marketing emails, newsletters from unknown senders
   - spam-phishing: Suspected phishing attempts, malicious emails
   - spam-automated: Automated spam, bulk emails, obvious spam
   - spam-other: Other spam that doesn''t fit above

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
   - other: Doesn''t fit above categories

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

Extract the SENDER''s information from their email signature at the bottom of the email.

6. **contact_first_name**: Sender''s first name from signature (null if not found)
7. **contact_last_name**: Sender''s last name from signature (null if not found)
8. **contact_role**: Sender''s job title or role (exact as written, null if not found)
9. **contact_department**: Sender''s department or team name (null if not found)
10. **contact_phone**: Sender''s phone number in original format (null if not found)

## ORGANIZATION INFORMATION (for the sender''s company)

11. **org_name**: Full organization/company name (null if not found)
12. **org_industry**: Industry category (null if not found)
13. **org_phone**: Organization main phone (null if not found)
14. **org_address**: Organization address from signature (null if not found)

IMPORTANT:
- Use EXACT category names from the list above
- For non-business emails, set intent=null, sentiment=null, priority_score=0, and ALL org fields to null
- For spam emails (spam_score > 0.8 or category starts with "spam-"), set ALL org fields to null
- For generic email providers (gmail, outlook, yahoo, hotmail, icloud, etc.), set ALL org fields to null

Return ONLY valid JSON array (no markdown, no explanation):
[
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
]',
    '[
        {"name": "emails_json", "description": "JSON array of emails to process, each with email_id, contact_id, organization_id, subject, from_email, from_name, body, and optional thread_context", "sample_value": "[{\"email_id\": \"abc-123\", \"subject\": \"Quote request\", \"from_email\": \"john@hospital.com\", \"body\": \"Hi, I need pricing...\"}]", "required": true}
    ]'::jsonb
),

-- 6. Conversation Summary (enrichment_core.py)
(
    'conversation_summary',
    'Conversation Summary',
    'Summarize email conversation threads for the sales team with action items.',
    'enrichment',
    'functions/email-sync/enrichment_core.py:CONVERSATION_SUMMARY_PROMPT',
    'Summarize this email conversation for PD Medical sales team.

THREAD:
{thread_json}

Provide:

1. **summary**: Concise 2-3 sentence overview of the entire conversation
   - What is the conversation about?
   - What has been discussed?
   - What is the current status?

2. **action_items**: Specific next steps or tasks (array of strings)
   - Example: ["Peter: Follow up on quote #1234", "Perry: Send product brochure", "John: Schedule demo"]
   - Only include actionable items and assignee
   - Be specific with details


Return ONLY valid JSON:
{{
  "conversation_id": "uuid-here",
  "summary": "Customer inquiring about sharps disposal products for a 200-bed hospital. Discussed pricing and delivery options. Waiting for formal quote.",
  "action_items": [
    "Prepare quote for sharps disposal units",
    "Follow up within 48 hours"
  ],
  "confidence": 0.88
}}',
    '[
        {"name": "thread_json", "description": "JSON object containing conversation_id, subject, email_count, and array of emails with from, date, and body", "sample_value": "{\"conversation_id\": \"conv-123\", \"subject\": \"RE: Quote request\", \"email_count\": 3, \"emails\": [{\"from\": \"john@hospital.com\", \"date\": \"2025-01-05\", \"body\": \"Hi, I need pricing...\"}]}", "required": true}
    ]'::jsonb
),

-- 7. SQL Generation for Campaign Targeting (campaign-sql-agent/handler.py)
(
    'sql_generation',
    'Campaign SQL Generation',
    'Generate safe SQL queries for campaign targeting from natural language requests. Includes confidence scoring and clarification questions for ambiguous queries.',
    'campaign',
    'functions/campaign-sql-agent/handler.py:build_sql_generation_prompt()',
    'Convert this campaign targeting request to SQL.

User request: "{full_query}"
{clarification_history}

Available schema:
{schema}

Valid values in database:
{valid_values_str}

CONFIDENCE SCORING RULES:
1. Score 0.9-1.0: Query is completely clear, all terms map directly to schema values
2. Score 0.7-0.89: Minor ambiguity but reasonable assumptions can be made
3. Score 0.5-0.69: Ambiguous terms detected (e.g., "large", "recent", "active") - ASK CLARIFICATION
4. Score 0.3-0.49: Terms don''t match database values - ASK CLARIFICATION
5. Score 0.0-0.29: Query is too vague to interpret meaningfully

CLARIFICATION QUESTION RULES:
- If confidence < 0.7, set needs_clarification=true and provide questions
- Each question should have 3-5 specific suggestions based on actual database values
- Questions should be actionable and specific
- Use question IDs like "q1", "q2", etc.
- Focus on the most impactful ambiguities first (max 3 questions)

Ambiguous terms to watch for:
- Size terms: "large", "small", "big" → Ask about specific bed_count ranges
- Time terms: "recent", "new", "old" → Ask about specific date ranges
- Engagement terms: "active", "engaged" → Ask about engagement_level or lead_classification
- Geography terms: Check if state/region values exist in database

Rules:
1. ONLY SELECT statements allowed
2. MUST include: c.id as contact_id, c.email, c.first_name, c.last_name, o.name as organization_name, c.lead_classification, c.engagement_level, c.lead_score
3. ONLY query these tables: contacts, organizations, emails, campaign_events, campaign_enrollments
4. Use lead_score and lead_classification for lead-based targeting
5. ALWAYS include: c.status = ''active'' AND c.status != ''unsubscribed''
6. Use proper JOINs with ON clauses (LEFT JOIN for organizations)
7. Use table aliases (c for contacts, o for organizations)
8. EVEN IF confidence is low, still generate best-effort SQL based on your interpretation

Current clarification round: {clarification_round} of {max_clarification_rounds}
{final_round_instruction}

Return structured output with sql, estimated_count, explanation, confidence_score, interpretation, needs_clarification, and clarification_questions.',
    '[
        {"name": "full_query", "description": "User''s natural language targeting request, possibly with exclusion context appended", "sample_value": "Hot leads from NSW hospitals with more than 200 beds", "required": true},
        {"name": "clarification_history", "description": "Previous Q&A pairs from clarification rounds (empty string if none)", "sample_value": "\n\nUser has clarified the following:\n- Q: What do you mean by \"large\" hospitals?\n  A: More than 200 beds", "required": false},
        {"name": "schema", "description": "Database schema context with table and column descriptions", "sample_value": "Available Tables: contacts (id, email, first_name, last_name, lead_score, lead_classification...), organizations (id, name, state, bed_count...)", "required": true},
        {"name": "valid_values_str", "description": "Valid enum values from database for validation", "sample_value": "- lead_classification: cold, lukewarm, warm, hot\n- states: NSW, VIC, QLD, SA, WA", "required": true},
        {"name": "clarification_round", "description": "Current clarification round number (0-based)", "sample_value": "0", "required": true},
        {"name": "max_clarification_rounds", "description": "Maximum allowed clarification rounds", "sample_value": "3", "required": true},
        {"name": "final_round_instruction", "description": "Instruction shown on final round to proceed without further questions", "sample_value": "This is the final round - do not ask more questions, proceed with best interpretation.", "required": false}
    ]'::jsonb
),

-- 8. Email Agent Draft (email-agent/handler.py)
(
    'email_agent_draft',
    'Email Agent Draft Instructions',
    'Base instructions for the email drafting agent. The full prompt is dynamically built with persona, context, and specific instructions. This template provides the core guidance.',
    'email',
    'functions/email-agent/handler.py:build_agent_prompt()',
    'You are an AI email drafting assistant for PD Medical, an Australian medical supplies company.

Your task is to draft professional emails based on the context provided. Follow these guidelines:

1. **Tone**: Match the tone specified (professional, friendly, formal, or concise)
2. **Context Awareness**: Use conversation history and contact information for personalization
3. **Product Knowledge**: When products are mentioned, use the search_products_tool to get accurate information
4. **Brevity**: Keep emails concise but complete - busy healthcare professionals appreciate efficiency
5. **Call to Action**: Include a clear next step when appropriate

IMPORTANT TOOL USAGE:
- If the email mentions any product names or asks about products, you MUST use search_products_tool to search for them BEFORE drafting a response
- Never assume a product doesn''t exist without searching first
- Use get_email_thread_tool to understand conversation context for replies
- Use get_contact_info_tool for new email personalization

When drafting the email:
1. Gather all necessary context using appropriate tools (unless context is already provided)
2. Draft a response that addresses the inquiry professionally
3. Use draft_email_tool with the required parameters to save the draft

The draft will be saved for human review and approval before sending.',
    '[
        {"name": "persona", "description": "Mailbox persona description for tone/style guidance", "sample_value": "Peter from PD Medical - friendly and knowledgeable sales representative", "required": false},
        {"name": "email_purpose", "description": "Purpose of the email being drafted", "sample_value": "Follow up on product inquiry about sharps containers", "required": false},
        {"name": "instructions", "description": "Additional drafting instructions from workflow", "sample_value": "Mention our bulk pricing discount for orders over 100 units", "required": false},
        {"name": "email_context", "description": "The incoming email content to reply to", "sample_value": "{\"from_email\": \"john@hospital.com\", \"subject\": \"Product inquiry\", \"body_plain\": \"Hi, I need information about...\"}", "required": false},
        {"name": "conversation_summary", "description": "Summary of the conversation thread", "sample_value": "Customer from Royal Melbourne Hospital inquiring about sharps containers. Previous discussion about delivery timelines.", "required": false},
        {"name": "extracted_data", "description": "Data extracted from the incoming email by workflow", "sample_value": "{\"return_date\": \"2025-01-15\", \"alternate_contact\": \"jane@hospital.com\"}", "required": false}
    ]'::jsonb
),

-- 9. Campaign Template Generation (email-agent/handler.py)
(
    'campaign_template_generation',
    'Campaign Template Generation',
    'Instructions for generating campaign email templates with merge fields. The agent analyzes target audience to determine which fields are well-populated.',
    'campaign',
    'functions/email-agent/handler.py:build_template_prompt()',
    '=== CAMPAIGN TEMPLATE GENERATION ===

You are generating an email TEMPLATE for a campaign.
The template will be sent to MULTIPLE recipients with personalized merge fields.

EMAIL PURPOSE: {email_purpose}

TONE: {tone}

TARGET AUDIENCE: {contact_count} contacts

=== INSTRUCTIONS ===
1. FIRST call analyze_audience_fields_tool to see which contact/org fields have data
2. If product_ids provided, fetch product info for context
3. Generate a template using ONLY merge fields that are well-populated (70%+)
4. Use merge field syntax: {{first_name}}, {{company}}, {{job_title}}, {{city}}, etc.
5. Call draft_template_tool with subject, body, and merge_fields_used list

IMPORTANT:
- Do NOT use merge fields that have low population (<70%)
- Always have a fallback for first_name like "Hi there" if unsure
- Keep subject line concise and engaging
- Body should be professional but personalized

Available merge fields:
- Contact: {{first_name}}, {{last_name}}, {{full_name}}, {{job_title}}, {{department}}
- Organization: {{company}}, {{organization_name}}, {{industry}}, {{city}}, {{state}}, {{region}}, {{facility_type}}, {{hospital_category}}

=== END INSTRUCTIONS ===',
    '[
        {"name": "email_purpose", "description": "The purpose/goal of the campaign email", "sample_value": "Introduce our new sharps container product line to infection control nurses", "required": true},
        {"name": "tone", "description": "Desired email tone", "sample_value": "professional", "required": true},
        {"name": "contact_count", "description": "Number of contacts in target audience", "sample_value": "150", "required": false},
        {"name": "product_ids", "description": "Product IDs to reference in the email", "sample_value": "[\"prod-123\", \"prod-456\"]", "required": false},
        {"name": "feedback", "description": "User feedback for template regeneration", "sample_value": "Make it shorter and more casual", "required": false}
    ]'::jsonb
)

ON CONFLICT (key) DO UPDATE SET
    name = EXCLUDED.name,
    description = EXCLUDED.description,
    content = EXCLUDED.content,
    variables = EXCLUDED.variables,
    category = EXCLUDED.category,
    used_in = EXCLUDED.used_in,
    updated_at = now();

-- ==========================================================================
-- Grant permissions for service role (Lambda functions)
-- ==========================================================================

GRANT ALL ON prompts TO service_role;
GRANT ALL ON prompt_versions TO service_role;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO service_role;
