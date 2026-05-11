-- ============================================================================
-- Train M — domain_resolution_attempts (miss cache for the org name resolver)
-- ============================================================================
-- The resolver tries: AI signature → homepage scrape → domain stem fallback.
-- Without a miss cache, every email from a domain that has no public
-- homepage (e.g. mail-only domains, parked Wix sites) would re-hit the
-- homepage scrape on every enrichment batch — wasted bandwidth, latency,
-- and politeness.
--
-- This table records each attempt's outcome. The lambda's
-- _get_or_create_org_from_email_content checks here before scraping; if
-- there's a recent miss/error, it skips straight to the domain_stem
-- fallback for now. The TTL makes us retry once a week so transient
-- network failures eventually resolve.
--
-- Hits don't need recording here — they go into organization_domains
-- (the existing alias table) and are looked up via _resolve_org_by_domain.
-- This table is for misses and errors only.
-- ============================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS public.domain_resolution_attempts (
  domain text PRIMARY KEY,
  last_attempted_at timestamptz NOT NULL DEFAULT now(),
  attempt_count integer NOT NULL DEFAULT 1,
  last_status text NOT NULL,
  last_error text,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.domain_resolution_attempts
  DROP CONSTRAINT IF EXISTS domain_resolution_attempts_status_check;

ALTER TABLE public.domain_resolution_attempts
  ADD CONSTRAINT domain_resolution_attempts_status_check
  CHECK (last_status IN ('homepage_unreachable', 'homepage_no_metadata', 'homepage_error', 'rejected_parking_page'));

CREATE INDEX IF NOT EXISTS idx_domain_resolution_attempts_last_attempted_at
  ON public.domain_resolution_attempts(last_attempted_at);

COMMENT ON TABLE public.domain_resolution_attempts IS
  'Miss cache for the homepage org-name resolver. Lambda enrichment skips '
  'a homepage fetch when the same domain failed within TTL_DAYS (default 7). '
  'Hits land in organization_domains, not here.';

COMMENT ON COLUMN public.domain_resolution_attempts.last_status IS
  'homepage_unreachable: connection refused or DNS failure. '
  'homepage_no_metadata: 200 OK but no og:site_name / JSON-LD / usable title. '
  'homepage_error: 4xx/5xx from the homepage. '
  'rejected_parking_page: response identified as a domain-parking placeholder.';

-- Helper: record an attempt (upsert, increment attempt_count on conflict)
CREATE OR REPLACE FUNCTION public.record_domain_resolution_miss(
  p_domain text,
  p_status text,
  p_error  text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_norm text := lower(trim(p_domain));
BEGIN
  IF v_norm IS NULL OR v_norm = '' THEN
    RETURN;
  END IF;

  INSERT INTO public.domain_resolution_attempts (domain, last_attempted_at, attempt_count, last_status, last_error)
  VALUES (v_norm, now(), 1, p_status, left(p_error, 500))
  ON CONFLICT (domain) DO UPDATE
    SET last_attempted_at = now(),
        attempt_count = public.domain_resolution_attempts.attempt_count + 1,
        last_status = EXCLUDED.last_status,
        last_error = EXCLUDED.last_error;
END;
$$;

GRANT EXECUTE ON FUNCTION public.record_domain_resolution_miss(text, text, text)
  TO service_role, authenticated;

-- Helper: should we skip the resolver for this domain?
-- Returns true when there's a recent miss within TTL.
CREATE OR REPLACE FUNCTION public.should_skip_domain_resolver(
  p_domain text,
  p_ttl_days integer DEFAULT 7
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.domain_resolution_attempts
    WHERE domain = lower(trim(p_domain))
      AND last_attempted_at > now() - (p_ttl_days || ' days')::interval
  );
$$;

GRANT EXECUTE ON FUNCTION public.should_skip_domain_resolver(text, integer)
  TO service_role, authenticated;

COMMIT;

-- Smoke test
DO $smoke$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc
    WHERE proname = 'record_domain_resolution_miss'
      AND pronamespace = 'public'::regnamespace
  ) THEN
    RAISE EXCEPTION 'Train M smoke: record_domain_resolution_miss missing';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_proc
    WHERE proname = 'should_skip_domain_resolver'
      AND pronamespace = 'public'::regnamespace
  ) THEN
    RAISE EXCEPTION 'Train M smoke: should_skip_domain_resolver missing';
  END IF;

  -- Round-trip check
  PERFORM public.record_domain_resolution_miss('train-m-smoke.example', 'homepage_unreachable', 'smoke test');
  IF NOT public.should_skip_domain_resolver('train-m-smoke.example', 1) THEN
    RAISE EXCEPTION 'Train M smoke: round-trip skip check failed';
  END IF;
  DELETE FROM public.domain_resolution_attempts WHERE domain = 'train-m-smoke.example';
END
$smoke$;
