/**
 * Task-Specific Prompts
 * Prompts for specific tasks and workflows
 */

export const EMAIL_PERSONALIZATION_PROMPT = `Generate a personalized email based on the following information:

Recipient: {recipientName}
Company: {companyName}
Context: {context}

The email should:
- Address the recipient by name
- Reference their company or role
- Be relevant to the provided context
- Include a clear call-to-action
- Be professional but friendly

Email:`

export const LEAD_QUALIFICATION_PROMPT = `Analyze the following lead information and determine qualification:

Lead Information:
{leadInfo}

Assess based on:
- Company size and industry fit
- Budget indicators
- Decision-making authority
- Timeline and urgency
- Pain points alignment

Provide a qualification score (1-10) and reasoning.`

export const MEETING_SUMMARY_PROMPT = `Summarize the following meeting or conversation:

Conversation:
{conversation}

Include:
- Key discussion points
- Decisions made
- Action items with owners
- Next steps
- Follow-up required

Summary:`

export const CONTACT_ENRICHMENT_PROMPT = `Enrich the following contact information:

Current Information:
{contactInfo}

Research and provide:
- Company details
- Role and responsibilities
- Recent news or updates
- Social media profiles
- Relevant interests or background

Enriched Profile:`

