-- Workflow-bucket fixes for AO212794 incident (issues #121 + #122).
--
-- Part 1 (#121): Switch the "Out-of-Office Reply" workflow's `alternate_contact`
-- field from `email` to the new hybrid `contact` type. OOO bodies typically
-- reference alternates by NAME ("contact Bhumi Brahmbhatt"), not email — the
-- email field used to extract null. The lambda's contact resolver now extracts
-- {name, email, phone} and falls back to org-scoped contact lookup when the
-- email is missing. Action templates that consumed `{alternate_contact}` must
-- now use `{alternate_contact.email}` for dotted access into the resolved dict.
--
-- Part 2 (#122): Backfill `workflow_execution_id` on existing orphan drafts
-- where the linkage exists in `source_details->>'workflow_execution_id'` but
-- the dedicated FK column was never populated (the lambda fix lands at the
-- same time but historical rows stay orphaned without this).

BEGIN;

-- ---------------------------------------------------------------------------
-- Part 1: OOO workflow row update (#121)
-- ---------------------------------------------------------------------------

-- Flip alternate_contact field type: email -> contact
UPDATE public.workflows
SET extract_fields = jsonb_set(
        extract_fields,
        '{1,field_type}',
        '"contact"'::jsonb
    )
WHERE id = 'fcc2ade4-535f-4608-b317-25020d2fd69d'
  AND extract_fields -> 1 ->> 'variable' = 'alternate_contact';

-- Update create_contact action to use dotted access into the resolved dict.
UPDATE public.workflows
SET actions = jsonb_set(
        actions,
        '{1,params,email}',
        '"{alternate_contact.email}"'::jsonb
    )
WHERE id = 'fcc2ade4-535f-4608-b317-25020d2fd69d'
  AND actions -> 1 ->> 'tool' IN ('create_contact', 'contact:create')
  AND actions -> 1 -> 'params' ->> 'email' = '{alternate_contact}';

-- Update send_email action's `to` to use dotted access into the resolved dict.
UPDATE public.workflows
SET actions = jsonb_set(
        actions,
        '{2,params,to}',
        '"{alternate_contact.email}"'::jsonb
    )
WHERE id = 'fcc2ade4-535f-4608-b317-25020d2fd69d'
  AND actions -> 2 ->> 'tool' = 'send_email'
  AND actions -> 2 -> 'params' ->> 'to' = '{alternate_contact}';

-- ---------------------------------------------------------------------------
-- Part 2: Orphan draft backfill (#122)
-- ---------------------------------------------------------------------------
-- Drafts whose source_details JSON already records workflow_execution_id
-- but never set the FK column. JOIN against workflow_executions so we don't
-- write a stale uuid that would violate the FK.

UPDATE public.email_drafts d
SET workflow_execution_id = we.id
FROM public.workflow_executions we
WHERE d.workflow_execution_id IS NULL
  AND d.source_type = 'workflow'
  AND d.source_details ? 'workflow_execution_id'
  AND we.id::text = d.source_details ->> 'workflow_execution_id';

COMMIT;
