-- ============================================================================
-- Train C.1.1 — Summary hardening
--
-- Adds:
--   1. claim_conversation_for_summary RPC — atomic claim that prevents
--      concurrent SQS workers from running redundant LLM calls on the same
--      conversation. Replaces the read-then-LLM-then-write race in the
--      enrich_conversation staleness guard.
--   2. user_rate_limits table + check_and_increment_rate_limit RPC —
--      per-user per-minute rate limiting for LLM-generating edge functions.
--      Used by conversation-summary-invoke and contact-engagement-summary-invoke
--      to bound abuse / runaway frontend retry loops.
--
-- Both are SECURITY DEFINER because they need to bypass RLS for accounting.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 1. Conversation summary claim (race-free staleness guard)
-- ----------------------------------------------------------------------------
-- Returns the conversation_id if this caller won the claim (LLM call should
-- proceed); returns NULL if another worker already advanced the staleness
-- counter past p_email_count (LLM call should be skipped).
--
-- The claim works by setting email_count_at_last_summary to p_email_count - 1
-- as a "claimed but not yet completed" marker. Concurrent workers reading the
-- same row see the marker, see their own p_email_count <= last_summary_count,
-- and bail. The actual final counter (= p_email_count) is written by
-- update_conversation_summary on success, or restored on failure.
--
-- Rows that have already been summarized at p_email_count or higher are
-- bypassed (true cache hit, no LLM call needed).

CREATE OR REPLACE FUNCTION public.claim_conversation_for_summary(
  p_conversation_id uuid,
  p_email_count integer
)
RETURNS TABLE(claimed boolean, prior_count integer)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_prior integer;
BEGIN
  UPDATE public.conversations
  SET email_count_at_last_summary = p_email_count - 1
  WHERE id = p_conversation_id
    AND COALESCE(email_count_at_last_summary, 0) < p_email_count - 1
  RETURNING COALESCE(email_count_at_last_summary, 0) INTO v_prior;

  IF FOUND THEN
    -- Won the claim. v_prior is the value AFTER the update (claim marker),
    -- but enrich_conversation only needs to know it claimed successfully.
    RETURN QUERY SELECT true, v_prior;
  ELSE
    -- Either the row doesn't exist, or another worker already claimed/
    -- completed at this email_count or higher. Bail.
    SELECT COALESCE(email_count_at_last_summary, 0) INTO v_prior
    FROM public.conversations
    WHERE id = p_conversation_id;
    RETURN QUERY SELECT false, COALESCE(v_prior, 0);
  END IF;
END;
$$;

COMMENT ON FUNCTION public.claim_conversation_for_summary(uuid, integer) IS
  'Train C.1.1: atomic claim for conversation summary generation. Returns claimed=true if this caller should run the LLM call, claimed=false if another worker already won. See enrich_conversation in lambda enrichment_core.py.';


-- ----------------------------------------------------------------------------
-- 2. User rate limits (per-user, per-resource, per-minute)
-- ----------------------------------------------------------------------------
-- Simple bucketing: one row per (user, resource, minute) with a count.
-- Check + increment is a single upsert. Edge functions call the RPC and
-- branch on the boolean.

CREATE TABLE IF NOT EXISTS public.user_rate_limits (
  user_id uuid NOT NULL,
  resource text NOT NULL,
  minute_bucket timestamptz NOT NULL,
  request_count integer NOT NULL DEFAULT 1,
  PRIMARY KEY (user_id, resource, minute_bucket)
);

COMMENT ON TABLE public.user_rate_limits IS
  'Train C.1.1: per-user per-resource per-minute request counts. Cleaned up by a cron or just left to accumulate (rows are tiny).';

-- Index for cleanup queries (DELETE WHERE minute_bucket < now() - 1 hour).
CREATE INDEX IF NOT EXISTS idx_user_rate_limits_bucket
  ON public.user_rate_limits (minute_bucket);

-- RLS: only service-role writes; users can read their own.
ALTER TABLE public.user_rate_limits ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "user_rate_limits read own" ON public.user_rate_limits;
CREATE POLICY "user_rate_limits read own"
  ON public.user_rate_limits FOR SELECT
  USING (auth.uid() = user_id);


CREATE OR REPLACE FUNCTION public.check_and_increment_rate_limit(
  p_user_id uuid,
  p_resource text,
  p_max_per_minute integer
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_bucket timestamptz := date_trunc('minute', now());
  v_count integer;
BEGIN
  INSERT INTO public.user_rate_limits (user_id, resource, minute_bucket, request_count)
  VALUES (p_user_id, p_resource, v_bucket, 1)
  ON CONFLICT (user_id, resource, minute_bucket)
  DO UPDATE SET request_count = public.user_rate_limits.request_count + 1
  RETURNING request_count INTO v_count;

  RETURN jsonb_build_object(
    'allowed', v_count <= p_max_per_minute,
    'count', v_count,
    'limit', p_max_per_minute,
    'window_start', v_bucket
  );
END;
$$;

COMMENT ON FUNCTION public.check_and_increment_rate_limit(uuid, text, integer) IS
  'Train C.1.1: atomic check+increment for per-user per-minute rate limits. Returns { allowed, count, limit, window_start }.';
