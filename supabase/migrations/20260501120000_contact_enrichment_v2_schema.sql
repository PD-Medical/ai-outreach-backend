-- ============================================================================
-- Contact Enrichment v2 — Schema additions
-- ============================================================================
-- This migration is purely additive. All four contact-creation paths continue
-- to work unchanged after this migration applies; the new RPC and helpers in
-- subsequent migrations / PRs gradually replace the per-path logic.
--
-- Spec: docs/superpowers/specs/2026-04-30-contact-enrichment-design.md
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 1. Hierarchical organisations: parent_organization_id self-FK
-- ----------------------------------------------------------------------------
ALTER TABLE public.organizations
  ADD COLUMN IF NOT EXISTS parent_organization_id uuid
    REFERENCES public.organizations(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS organizations_parent_id_idx
  ON public.organizations (parent_organization_id);

COMMENT ON COLUMN public.organizations.parent_organization_id IS
  'Optional parent org. Facilities (e.g. individual hospitals) link up to a parent network (e.g. NSW Health, Ramsay Health Care). Null = top-level / standalone org.';

-- ----------------------------------------------------------------------------
-- 2. Multi-domain alias table
-- ----------------------------------------------------------------------------
-- One organisation can own many domains (NSW Health spans 17+ LHD subdomains
-- plus the bare parent). Lookups during contact intake walk this table; if
-- exact subdomain misses, the caller strips one label and tries again.
CREATE TABLE IF NOT EXISTS public.organization_domains (
  organization_id uuid NOT NULL
    REFERENCES public.organizations(id) ON DELETE CASCADE,
  domain          varchar NOT NULL,
  is_primary      boolean NOT NULL DEFAULT false,
  source          varchar NOT NULL DEFAULT 'seed',  -- seed | manual | auto-derived
  created_at      timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (organization_id, domain)
);

CREATE UNIQUE INDEX IF NOT EXISTS organization_domains_domain_lower_idx
  ON public.organization_domains (lower(domain));

CREATE INDEX IF NOT EXISTS organization_domains_org_id_idx
  ON public.organization_domains (organization_id);

-- RLS — mirror the existing public.organizations policy pattern
ALTER TABLE public.organization_domains ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS organization_domains_select_policy ON public.organization_domains;
CREATE POLICY organization_domains_select_policy ON public.organization_domains
  FOR SELECT USING (public.has_permission('view_contacts'::text));
DROP POLICY IF EXISTS organization_domains_insert_policy ON public.organization_domains;
CREATE POLICY organization_domains_insert_policy ON public.organization_domains
  FOR INSERT WITH CHECK (public.has_permission('manage_contacts'::text));
DROP POLICY IF EXISTS organization_domains_update_policy ON public.organization_domains;
CREATE POLICY organization_domains_update_policy ON public.organization_domains
  FOR UPDATE USING (public.has_permission('manage_contacts'::text));
DROP POLICY IF EXISTS organization_domains_delete_policy ON public.organization_domains;
CREATE POLICY organization_domains_delete_policy ON public.organization_domains
  FOR DELETE USING (public.has_permission('manage_contacts'::text));

GRANT SELECT, INSERT, UPDATE, DELETE ON public.organization_domains TO authenticated;
GRANT ALL ON public.organization_domains TO service_role;

COMMENT ON TABLE public.organization_domains IS
  'All domains owned by an organisation (primary + aliases). Domain-based contact-org linking queries this table, not organizations.domain.';
COMMENT ON COLUMN public.organization_domains.is_primary IS
  'True for the canonical domain shown in UI. Each org should have exactly one primary; not enforced by constraint to allow zero-domain placeholder orgs.';
COMMENT ON COLUMN public.organization_domains.source IS
  'How this alias was added: seed (initial bulk load), manual (user via UI), auto-derived (intake helper inferred from email signature).';

-- ----------------------------------------------------------------------------
-- 3. New organization_types: Government and Education
-- ----------------------------------------------------------------------------
INSERT INTO public.organization_types (id, name, description, is_active) VALUES
  ('00000000-0000-4000-8000-000000000001', 'Government', 'Government health body or department', true),
  ('00000000-0000-4000-8000-000000000002', 'Education',  'University, college, or training institution', true)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  description = EXCLUDED.description;

-- ----------------------------------------------------------------------------
-- 4. Contact provenance: contacts.field_sources JSONB
-- ----------------------------------------------------------------------------
-- Per-field source/confidence/timestamp. Drives the trust-merge rule:
-- new write applies if source_rank * confidence > current_rank * current_confidence,
-- with manual writes always winning over non-manual.
ALTER TABLE public.contacts
  ADD COLUMN IF NOT EXISTS field_sources jsonb NOT NULL DEFAULT '{}'::jsonb;

COMMENT ON COLUMN public.contacts.field_sources IS
  'Per-field provenance. Shape: {field_name: {source, confidence, set_at}} where source ∈ {manual, csv_import, signature_ai, mailchimp, from_header, imap_envelope}. Tracked fields: first_name, last_name, job_title, department, phone, facility_hint.';

-- ----------------------------------------------------------------------------
-- 5. Engagement summary columns
-- ----------------------------------------------------------------------------
-- Mirrors the conversations.summary / last_summarized_at / email_count_at_last_summary
-- pattern. Lazy regeneration on contact-detail-page view, only when underlying
-- conversation summaries have advanced since the last engagement summary.
ALTER TABLE public.contacts
  ADD COLUMN IF NOT EXISTS engagement_summary           text,
  ADD COLUMN IF NOT EXISTS engagement_action_items      text[],
  ADD COLUMN IF NOT EXISTS engagement_summary_at        timestamptz,
  ADD COLUMN IF NOT EXISTS engagement_conv_count_at_last_summary integer NOT NULL DEFAULT 0;

COMMENT ON COLUMN public.contacts.engagement_summary IS
  'AI-generated narrative paragraph: who they are, key threads, current status. Generated lazily on first contact-detail view; regenerated only when underlying conversation summaries advance.';
COMMENT ON COLUMN public.contacts.engagement_conv_count_at_last_summary IS
  'Sum of conversation.email_count_at_last_summary across this contact''s conversations at the time the engagement summary was generated. Used to detect staleness without recomputing the rollup.';

-- ----------------------------------------------------------------------------
-- 6. Role-address pattern reference table
-- ----------------------------------------------------------------------------
-- The new RPC filters out role/system addresses (noreply@, postmaster@, etc.)
-- before creating a contact. The pattern list is data-driven so ops can tune
-- without a code deploy.
CREATE TABLE IF NOT EXISTS public.role_address_patterns (
  pattern    varchar PRIMARY KEY,        -- regex anchored to local-part start
  description text,
  is_active  boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);

INSERT INTO public.role_address_patterns (pattern, description) VALUES
  ('^noreply@',           'Standard no-reply address'),
  ('^no-reply@',          'Standard no-reply address (hyphenated)'),
  ('^donotreply@',        'Do-not-reply address'),
  ('^do-not-reply@',      'Do-not-reply address (hyphenated)'),
  ('^postmaster@',        'RFC 5321 postmaster address'),
  ('^mailer-daemon@',     'Bounce daemon'),
  ('^bounce@',            'Bounce handling'),
  ('^bounces@',           'Bounce handling (plural)'),
  ('^abuse@',             'RFC 2142 abuse contact'),
  ('^unsubscribe@',       'Unsubscribe handling'),
  ('^notification@',      'System notifications'),
  ('^notifications@',     'System notifications (plural)'),
  ('^alert@',             'System alerts'),
  ('^alerts@',            'System alerts (plural)'),
  ('^webmaster@',         'RFC 2142 webmaster contact'),
  ('^hostmaster@',        'RFC 2142 hostmaster contact'),
  ('^root@',              'System root'),
  ('^null@',              'System null')
ON CONFLICT (pattern) DO UPDATE SET description = EXCLUDED.description;

-- RLS — reference data. Authenticated users can read; only admins manage.
ALTER TABLE public.role_address_patterns ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS role_address_patterns_select_policy ON public.role_address_patterns;
CREATE POLICY role_address_patterns_select_policy ON public.role_address_patterns
  FOR SELECT USING (auth.role() = 'authenticated');
DROP POLICY IF EXISTS role_address_patterns_admin_policy ON public.role_address_patterns;
CREATE POLICY role_address_patterns_admin_policy ON public.role_address_patterns
  FOR ALL USING (public.has_permission('manage_users'::text));

GRANT SELECT ON public.role_address_patterns TO authenticated;
GRANT ALL ON public.role_address_patterns TO service_role;

COMMENT ON TABLE public.role_address_patterns IS
  'Regex patterns for role/system email addresses that should not become contacts. Active rows checked by upsert_contact_with_org_v2 RPC at intake time.';

-- ----------------------------------------------------------------------------
-- 7. (Reserved) v_contact_engagement_profile view will be added by Step 7
--    (engagement summary feature). Schema-only PR doesn't include it.
-- ----------------------------------------------------------------------------

COMMIT;
