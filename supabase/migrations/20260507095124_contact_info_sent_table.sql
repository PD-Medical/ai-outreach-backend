-- ============================================================================
-- contact_info_sent — what we've physically sent to a contact
-- ============================================================================
-- Issue #7: the existing free-text "Info Sent" field on Edit Contact
-- (custom_fields->>'info_sent') is opaque — operators type things like
-- "Flyer / Sample / Trial Pack" and the data isn't queryable for follow-up
-- ("how many Medical Oxygen Hose info-outs went last month?").
--
-- Replace it with a structured join from contacts to products. One row per
-- (contact, product) combination tracks WHEN the info was sent, BY WHOM, and
-- carries an optional notes field for free-form context that doesn't map to
-- a product (e.g. "Sent printed brochure pack").
--
-- Best-effort backfill: walk existing custom_fields.info_sent strings,
-- attempt a case-insensitive match against products.product_name. Anything
-- that doesn't match becomes a notes-only row so no operator data is lost.
--
-- The existing contact_product_interests table is for engagement state
-- (interest_level, status, quote_date) — different semantic. This table is
-- the simpler "we mailed them this; here's the timestamp" log.
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.contact_info_sent (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  contact_id uuid NOT NULL REFERENCES public.contacts(id) ON DELETE CASCADE,
  product_id uuid REFERENCES public.products(id) ON DELETE SET NULL,
  sent_at timestamptz NOT NULL DEFAULT now(),
  sent_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT contact_info_sent_product_or_notes
    CHECK (product_id IS NOT NULL OR notes IS NOT NULL)
);

CREATE INDEX IF NOT EXISTS idx_contact_info_sent_contact
  ON public.contact_info_sent(contact_id);

CREATE INDEX IF NOT EXISTS idx_contact_info_sent_product
  ON public.contact_info_sent(product_id)
  WHERE product_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_contact_info_sent_sent_at
  ON public.contact_info_sent(sent_at DESC);

COMMENT ON TABLE public.contact_info_sent
  IS 'Log of marketing/sales material sent to a contact. One row per (contact, product) hand-off, or a notes-only row when the material is free-form.';

-- RLS — mirror contact_product_interests pattern.
ALTER TABLE public.contact_info_sent ENABLE ROW LEVEL SECURITY;

CREATE POLICY contact_info_sent_select_policy
  ON public.contact_info_sent
  FOR SELECT
  USING (public.has_permission('view_contacts'::text));

CREATE POLICY contact_info_sent_insert_policy
  ON public.contact_info_sent
  FOR INSERT
  WITH CHECK (public.has_permission('manage_contacts'::text));

CREATE POLICY contact_info_sent_update_policy
  ON public.contact_info_sent
  FOR UPDATE
  USING (public.has_permission('manage_contacts'::text));

CREATE POLICY contact_info_sent_delete_policy
  ON public.contact_info_sent
  FOR DELETE
  USING (public.has_permission('manage_contacts'::text));

-- Best-effort backfill from custom_fields.info_sent text.
-- Splits on commas / slashes, case-insensitive match against products.product_name.
-- Unmatched fragments fall through to a single notes-only row per contact so
-- no information is lost; the operator can clean up from the UI.
WITH parsed AS (
  SELECT
    c.id AS contact_id,
    trim(token) AS token
  FROM public.contacts c
  CROSS JOIN LATERAL regexp_split_to_table(
    COALESCE(c.custom_fields->>'info_sent', c.custom_fields->>'Info Sent', ''),
    '[,/]+'
  ) AS token
  WHERE COALESCE(NULLIF(c.custom_fields->>'info_sent', ''), c.custom_fields->>'Info Sent') IS NOT NULL
),
matched AS (
  SELECT
    p.contact_id,
    pr.id AS product_id
  FROM parsed p
  JOIN public.products pr
    ON lower(pr.product_name) = lower(p.token)
   AND length(p.token) > 0
),
unmatched AS (
  SELECT
    p.contact_id,
    string_agg(p.token, ', ') AS notes_blob
  FROM parsed p
  WHERE length(p.token) > 0
    AND NOT EXISTS (
      SELECT 1 FROM public.products pr
      WHERE lower(pr.product_name) = lower(p.token)
    )
  GROUP BY p.contact_id
)
INSERT INTO public.contact_info_sent (contact_id, product_id)
SELECT DISTINCT contact_id, product_id FROM matched
ON CONFLICT DO NOTHING;

WITH unmatched AS (
  SELECT
    c.id AS contact_id,
    string_agg(trim(token), ', ') AS notes_blob
  FROM public.contacts c
  CROSS JOIN LATERAL regexp_split_to_table(
    COALESCE(c.custom_fields->>'info_sent', c.custom_fields->>'Info Sent', ''),
    '[,/]+'
  ) AS token
  WHERE COALESCE(NULLIF(c.custom_fields->>'info_sent', ''), c.custom_fields->>'Info Sent') IS NOT NULL
    AND length(trim(token)) > 0
    AND NOT EXISTS (
      SELECT 1 FROM public.products pr
      WHERE lower(pr.product_name) = lower(trim(token))
    )
  GROUP BY c.id
)
INSERT INTO public.contact_info_sent (contact_id, product_id, notes)
SELECT contact_id, NULL, 'Migrated from custom_fields.info_sent: ' || notes_blob
FROM unmatched;
