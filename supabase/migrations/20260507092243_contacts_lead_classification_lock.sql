-- ============================================================================
-- contacts.lead_classification_locked — operator manual override for tier
-- ============================================================================
-- Until now `lead_classification` was strictly a function of `lead_score`,
-- recomputed by the `update_lead_classification` trigger on every score
-- change. Issue #12 needs an operator (Jasmine) to be able to mark a
-- contact as Hot / Warm / Cold manually and have that override survive
-- subsequent engagement events. We introduce a boolean lock:
--
--   lead_classification_locked = true  → trigger leaves classification alone
--   lead_classification_locked = false → trigger recomputes from lead_score
--
-- The trigger now also fires when `lead_classification_locked` itself
-- changes, so flipping the lock back to false ("Reset to AI" in the UI)
-- causes an immediate recompute from the current lead_score.
-- ============================================================================

ALTER TABLE public.contacts
  ADD COLUMN IF NOT EXISTS lead_classification_locked boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.contacts.lead_classification_locked
  IS 'When true, the operator has manually set lead_classification and the trigger preserves it across score changes. Toggle false to let the trigger recompute from lead_score.';

CREATE OR REPLACE FUNCTION public.update_lead_classification() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  -- Operator-set classifications win — leave NEW.lead_classification alone.
  IF NEW.lead_classification_locked THEN
    RETURN NEW;
  END IF;

  IF NEW.lead_score >= 80 THEN
    NEW.lead_classification := 'hot';
  ELSIF NEW.lead_score >= 50 THEN
    NEW.lead_classification := 'warm';
  ELSE
    NEW.lead_classification := 'cold';
  END IF;

  RETURN NEW;
END;
$$;

-- Existing trigger only fires on UPDATE OF lead_score. We need it to also
-- fire when lead_classification_locked flips, so "Reset to AI" recomputes
-- immediately rather than waiting for the next scoring event. Drop and
-- re-create with the wider OF clause; the trigger body still keys off
-- NEW values, so behaviour is identical for score-driven updates.
DROP TRIGGER IF EXISTS trigger_update_lead_classification ON public.contacts;
CREATE TRIGGER trigger_update_lead_classification
  BEFORE INSERT OR UPDATE OF lead_score, lead_classification_locked
  ON public.contacts
  FOR EACH ROW
  EXECUTE FUNCTION public.update_lead_classification();
