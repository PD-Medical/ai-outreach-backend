-- KAN-20: search improvement — extension + phone_search column
--
-- Adds:
--   pg_trgm extension                              — trigram indexable substring matching
--   compute_phone_search(text) SQL function        — AU-aware phone normalisation, IMMUTABLE
--   contacts.phone_search text GENERATED STORED    — auto-populated from contacts.phone
--
-- Auto-backfill: STORED generated columns are computed for every existing row
-- during ADD COLUMN, so phone_search is populated for the full contacts table
-- as part of this migration. No separate phone backfill script needed.
--
-- Does NOT touch emails.body_clean (already added by 20260430130100, issue #124).
-- Does NOT create indexes or RPCs. Those land in a follow-up migration AFTER the
-- pre-#124 body_clean backfill script populates legacy rows, so the trigram
-- index builds over fully-populated data.
--
-- See tasks/kan-20-search-improvement.html for the full plan.

CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- AU-aware phone normalisation. Emits a space-separated list of digit variants
-- so the same contact matches any reasonable format the operator types:
--   - "+61 412 345 678"  →  "61412345678 0412345678 +61412345678 412345678"
--   - "0412 345 678"     →  "0412345678 61412345678 +61412345678 412345678"
--   - "412345678"        →  "0412345678 61412345678 +61412345678 412345678"
--   - unrecognised       →  raw digits (best-effort)
--
-- IMMUTABLE so it can back a STORED generated column. AU-only by design;
-- non-AU mailboxes are not in current scope and will need additional branches.
CREATE OR REPLACE FUNCTION public.compute_phone_search(p_phone text)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  digits text;
  subscriber text;
BEGIN
  IF p_phone IS NULL OR p_phone = '' THEN
    RETURN NULL;
  END IF;

  digits := regexp_replace(p_phone, '[^0-9]', '', 'g');
  IF digits = '' THEN
    RETURN NULL;
  END IF;

  -- Full international: "61" + 9-digit subscriber  (e.g. "+61 412 345 678")
  IF length(digits) = 11 AND left(digits, 2) = '61' THEN
    subscriber := substring(digits FROM 3);
    RETURN digits           -- 61412345678
        || ' 0' || subscriber  -- 0412345678
        || ' +' || digits      -- +61412345678
        || ' ' || subscriber;  -- 412345678

  -- Full national: "0" + 9-digit subscriber  (e.g. "0412 345 678")
  ELSIF length(digits) = 10 AND left(digits, 1) = '0' THEN
    subscriber := substring(digits FROM 2);
    RETURN digits                      -- 0412345678
        || ' 61'  || subscriber        -- 61412345678
        || ' +61' || subscriber        -- +61412345678
        || ' ' || subscriber;          -- 412345678

  -- Bare subscriber, 9 digits  (e.g. "412345678")
  ELSIF length(digits) = 9 THEN
    RETURN '0' || digits               -- 0412345678
        || ' 61'  || digits            -- 61412345678
        || ' +61' || digits            -- +61412345678
        || ' ' || digits;              -- 412345678

  -- Unrecognised length / format. Keep digits-only as a best-effort target.
  ELSE
    RETURN digits;
  END IF;
END;
$$;

COMMENT ON FUNCTION public.compute_phone_search(text) IS
  'AU-aware phone normaliser. Returns a space-separated list of digit variants (raw, leading-0, +61, bare subscriber) so search matches regardless of input format. Used as the expression behind contacts.phone_search. IMMUTABLE — safe for STORED generated columns and expression indexes. AU-only by design; extend if non-AU mailboxes are ever added. See KAN-20.';

-- Generated column. Postgres computes it for every existing row during this
-- ALTER, so the contacts table is fully populated when the statement returns.
ALTER TABLE public.contacts
  ADD COLUMN IF NOT EXISTS phone_search text
    GENERATED ALWAYS AS (public.compute_phone_search(phone)) STORED;

COMMENT ON COLUMN public.contacts.phone_search IS
  'Space-separated normalised phone digit variants (raw, national with leading 0, E.164 with +, bare subscriber) computed from contacts.phone via compute_phone_search(). Maintained automatically as a STORED generated column. Used alongside phone as a substring-search target so any input format matches the contact. See KAN-20.';
