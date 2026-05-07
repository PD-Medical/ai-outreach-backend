-- ============================================================================
-- contacts.needs_follow_up — operator-managed follow-up flag
-- ============================================================================
-- Adds a boolean column so an operator (Jasmine et al.) can manually flag a
-- contact as "needs follow up" from the Edit Contact form, then filter the
-- Hot Leads list down to flagged contacts. Surfaces in the UI alongside the
-- existing free-text Follow Up Action field; this column is the searchable
-- counterpart that is not tied to whether the operator has typed an action.
--
-- Backfill: contacts whose custom_fields hold a non-empty followup_action
-- (under any of the legacy key spellings the form has accepted over time)
-- are flagged true so Jasmine doesn't lose the existing follow-up state when
-- the column ships.
-- ============================================================================

ALTER TABLE public.contacts
  ADD COLUMN IF NOT EXISTS needs_follow_up boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.contacts.needs_follow_up
  IS 'Operator-set flag. When true, the contact appears in the Hot Leads "Needs follow up" filter. Independent of any existing followup_action text.';

UPDATE public.contacts
   SET needs_follow_up = true
 WHERE needs_follow_up = false
   AND (
        COALESCE(NULLIF(custom_fields->>'followup_action', ''), NULL) IS NOT NULL
     OR COALESCE(NULLIF(custom_fields->>'Followup Action', ''), NULL) IS NOT NULL
   );
