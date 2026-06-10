-- Workflow auto-reply stability fixes.
--
-- Keep this migration idempotent and key-based: older OOO config updates used
-- fixed JSON array positions, but production workflow rows may have fields in a
-- different order.

BEGIN;

-- ---------------------------------------------------------------------------
-- Out-of-Office Reply: use contact object extraction and only run dependent
-- alternate-contact actions when an alternate email exists.
-- ---------------------------------------------------------------------------

UPDATE public.workflows w
SET extract_fields = fields.updated_fields,
    updated_at = now()
FROM (
  SELECT w_inner.id,
         jsonb_agg(
           CASE
             WHEN field.value ->> 'variable' = 'alternate_contact' THEN
               jsonb_set(
                 jsonb_set(
                   field.value,
                   '{field_type}',
                   '"contact"'::jsonb
                 ),
                 '{description}',
                 '"Alternate contact mentioned in the auto-reply. Extract name, email, and phone when available."'::jsonb
               )
             ELSE field.value
           END
           ORDER BY field.ordinality
         ) AS updated_fields
  FROM public.workflows w_inner
  CROSS JOIN LATERAL jsonb_array_elements(w_inner.extract_fields) WITH ORDINALITY AS field(value, ordinality)
  WHERE w_inner.id = 'fcc2ade4-535f-4608-b317-25020d2fd69d'
  GROUP BY w_inner.id
) fields
WHERE w.id = fields.id;

UPDATE public.workflows w
SET actions = actions.updated_actions,
    updated_at = now()
FROM (
  SELECT w_inner.id,
         jsonb_agg(
           CASE
             WHEN action.value ->> 'tool' IN ('create_contact', 'contact:create')
               AND action.value -> 'params' ->> 'email' IN ('{alternate_contact}', '{alternate_contact.email}') THEN
               jsonb_set(
                 jsonb_set(
                   action.value,
                   '{params,email}',
                   '"{alternate_contact.email}"'::jsonb,
                   true
                 ),
                 '{condition}',
                 '"{alternate_contact.email} != null"'::jsonb,
                 true
               )
             WHEN action.value ->> 'tool' IN ('send_email', 'draft_email', 'reply_email', 'forward_email')
               AND action.value -> 'params' ->> 'to' IN ('{alternate_contact}', '{alternate_contact.email}') THEN
               jsonb_set(
                 jsonb_set(
                   action.value,
                   '{params,to}',
                   '"{alternate_contact.email}"'::jsonb,
                   true
                 ),
                 '{condition}',
                 '"{alternate_contact.email} != null"'::jsonb,
                 true
               )
             ELSE action.value
           END
           ORDER BY action.ordinality
         ) AS updated_actions
  FROM public.workflows w_inner
  CROSS JOIN LATERAL jsonb_array_elements(w_inner.actions) WITH ORDINALITY AS action(value, ordinality)
  WHERE w_inner.id = 'fcc2ade4-535f-4608-b317-25020d2fd69d'
  GROUP BY w_inner.id
) actions
WHERE w.id = actions.id;

UPDATE public.workflows w
SET lead_score_rules = rules.updated_rules,
    updated_at = now()
FROM (
  SELECT w_inner.id,
         jsonb_agg(
           CASE
             WHEN rule.value ->> 'contact_target' IN ('alternate_contact', '{alternate_contact}') THEN
               jsonb_set(
                 jsonb_set(
                   rule.value,
                   '{contact_target}',
                   '"alternate_contact.email"'::jsonb,
                   true
                 ),
                 '{condition}',
                 '"{alternate_contact.email} != null"'::jsonb,
                 true
               )
             ELSE rule.value
           END
           ORDER BY rule.ordinality
         ) AS updated_rules
  FROM public.workflows w_inner
  CROSS JOIN LATERAL jsonb_array_elements(w_inner.lead_score_rules) WITH ORDINALITY AS rule(value, ordinality)
  WHERE w_inner.id = 'fcc2ade4-535f-4608-b317-25020d2fd69d'
  GROUP BY w_inner.id
) rules
WHERE w.id = rules.id;

-- ---------------------------------------------------------------------------
-- No Longer in Role (Referral): fix typo that prevents new_contact_email
-- condition from passing.
-- ---------------------------------------------------------------------------

UPDATE public.workflows w
SET actions = actions.updated_actions,
    updated_at = now()
FROM (
  SELECT w_inner.id,
         jsonb_agg(
           CASE
             WHEN action.value ->> 'condition' = '@new_contact_emai != null' THEN
               jsonb_set(
                 action.value,
                 '{condition}',
                 '"{new_contact_email} != null"'::jsonb,
                 true
               )
             WHEN action.value ->> 'condition' = '@new_contact_email == null' THEN
               jsonb_set(
                 action.value,
                 '{condition}',
                 '"{new_contact_email} == null"'::jsonb,
                 true
               )
             ELSE action.value
           END
           ORDER BY action.ordinality
         ) AS updated_actions
  FROM public.workflows w_inner
  CROSS JOIN LATERAL jsonb_array_elements(w_inner.actions) WITH ORDINALITY AS action(value, ordinality)
  WHERE w_inner.id = 'b83b4120-9cc4-4dbe-94c2-af3644ba470e'
  GROUP BY w_inner.id
) actions
WHERE w.id = actions.id;

UPDATE public.workflows w
SET lead_score_rules = rules.updated_rules,
    updated_at = now()
FROM (
  SELECT w_inner.id,
         jsonb_agg(
           CASE
             WHEN rule.value ->> 'contact_target' = 'new_contact_email' THEN
               jsonb_set(
                 rule.value,
                 '{condition}',
                 '"{new_contact_email} != null"'::jsonb,
                 true
               )
             ELSE rule.value
           END
           ORDER BY rule.ordinality
         ) AS updated_rules
  FROM public.workflows w_inner
  CROSS JOIN LATERAL jsonb_array_elements(w_inner.lead_score_rules) WITH ORDINALITY AS rule(value, ordinality)
  WHERE w_inner.id = 'b83b4120-9cc4-4dbe-94c2-af3644ba470e'
  GROUP BY w_inner.id
) rules
WHERE w.id = rules.id;

-- ---------------------------------------------------------------------------
-- Email Agent global instructions consumed by load_context.py.
-- ---------------------------------------------------------------------------

INSERT INTO public.prompts (key, name, description, category, used_in, content, variables)
VALUES (
  'email_agent_instructions',
  'Email Agent Instructions',
  'Global email drafting instructions loaded by the LangGraph email agent planner.',
  'email',
  'functions/email-agent/load_context.py:email_agent_instructions',
  $PROMPT$General drafting policy for PD Medical:

- Create drafts for human approval; do not imply an email has already been sent.
- Use only facts available in the trigger email, thread context, contact records, product tools, or newsletter context.
- Keep outreach to healthcare contacts concise, professional, and respectful.
- For Mailchimp newsletter auto-replies, treat the reply as a routing signal. If the auto-reply explicitly names an alternate contact or inbox, a cautious draft may be appropriate; otherwise choose info_insufficient or skip.
- For generic department inboxes, draft only when the auto-reply explicitly asks senders to contact that inbox, and keep the message low-pressure.
- Do not draft to mailer-daemon, bounce, no-reply, or system addresses.
- If the recipient cannot be identified safely, return info_insufficient with the missing detail.$PROMPT$,
  '[]'::jsonb
)
ON CONFLICT (key) DO NOTHING;

COMMIT;
