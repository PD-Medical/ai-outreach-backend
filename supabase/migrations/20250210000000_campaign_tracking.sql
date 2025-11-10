-- ============================================================================
-- CAMPAIGN ENGAGEMENT CORE SCHEMA
-- ============================================================================
-- Minimal, provider-agnostic structure for tracking campaign performance.
-- 1) campaigns                - metadata for each outbound campaign
-- 2) campaign_events          - append-only interaction log (scored)
-- 3) campaign_contact_summary - derived per-campaign/per-contact snapshot
-- ============================================================================

-- --------------------------------------------------------------------------
-- Create enum for canonical event types (idempotent)
-- --------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'event_type') THEN
    CREATE TYPE public.event_type AS ENUM (
      'sent',
      'delivered',
      'opened',
      'clicked',
      'bounced',
      'complained',
      'website_visit',
      'form_submit',
      'demo_request',
      'purchase'
    );
  END IF;
END;
$$;

-- --------------------------------------------------------------------------
-- campaigns table
-- --------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.campaigns (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  name text NOT NULL,
  subject text,
  provider text,
  external_id text,

  created_at timestamptz NOT NULL DEFAULT now(),
  scheduled_at timestamptz,
  sent_at timestamptz
);

CREATE INDEX IF NOT EXISTS idx_campaigns_provider ON public.campaigns(provider);
CREATE INDEX IF NOT EXISTS idx_campaigns_sent_at ON public.campaigns(sent_at DESC);

-- --------------------------------------------------------------------------
-- campaign_events table
-- --------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.campaign_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  campaign_id uuid REFERENCES public.campaigns(id) ON DELETE SET NULL,
  contact_id uuid NOT NULL REFERENCES public.contacts(id) ON DELETE CASCADE,
  email text NOT NULL,

  event_type public.event_type NOT NULL,
  event_timestamp timestamptz NOT NULL DEFAULT now(),
  score integer NOT NULL DEFAULT 0,

  source jsonb NOT NULL DEFAULT '{}'::jsonb,
  external_id text,
  inserted_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_campaign_events_external_id
  ON public.campaign_events(external_id)
  WHERE external_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_campaign_events_campaign_type
  ON public.campaign_events(campaign_id, event_type);

CREATE INDEX IF NOT EXISTS idx_campaign_events_contact_timestamp
  ON public.campaign_events(contact_id, event_timestamp DESC);

CREATE INDEX IF NOT EXISTS idx_campaign_events_event_timestamp
  ON public.campaign_events(event_timestamp DESC);

-- --------------------------------------------------------------------------
-- campaign_contact_summary table (derived convenience snapshot)
-- --------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.campaign_contact_summary (
  campaign_id uuid NOT NULL REFERENCES public.campaigns(id) ON DELETE CASCADE,
  contact_id uuid NOT NULL REFERENCES public.contacts(id) ON DELETE CASCADE,
  email text NOT NULL,

  total_score integer NOT NULL DEFAULT 0,
  opened boolean NOT NULL DEFAULT false,
  clicked boolean NOT NULL DEFAULT false,
  converted boolean NOT NULL DEFAULT false,

  first_event_at timestamptz,
  last_event_at timestamptz,
  updated_at timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT campaign_contact_summary_pkey PRIMARY KEY (campaign_id, contact_id)
);

CREATE INDEX IF NOT EXISTS idx_campaign_contact_summary_campaign_score
  ON public.campaign_contact_summary(campaign_id, total_score DESC);

CREATE INDEX IF NOT EXISTS idx_campaign_contact_summary_opened
  ON public.campaign_contact_summary(campaign_id)
  WHERE opened = true;

CREATE INDEX IF NOT EXISTS idx_campaign_contact_summary_clicked
  ON public.campaign_contact_summary(campaign_id)
  WHERE clicked = true;

-- ============================================================================


