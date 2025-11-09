-- ============================================================================
-- ENGAGEMENT TRACKING SYSTEM - Resend Integration
-- ============================================================================
-- Tracks automated behavioral signals from email campaigns
-- Calculates engagement scores based on 11 signal types
-- Triggers automated actions for high-priority events
-- ============================================================================

-- ============================================================================
-- ENGAGEMENT SIGNALS TABLE
-- ============================================================================
-- Stores individual engagement events from Resend webhooks
CREATE TABLE IF NOT EXISTS public.engagement_signals (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  
  -- Contact identification
  contact_id uuid,
  email character varying NOT NULL,
  
  -- Resend event data
  resend_event_id character varying UNIQUE,
  resend_email_id character varying NOT NULL,
  
  -- Signal type and metadata
  signal_type character varying NOT NULL CHECK (signal_type IN (
    'pricing_click',        -- Clicked pricing/quote link (+10)
    'product_click',        -- Clicked product page link (+8)
    'attachment_download',  -- Downloaded PDF/attachment (+8)
    'multiple_opens',       -- Opened 3+ times (+7)
    'case_study_click',     -- Clicked case study link (+6)
    'email_opened',         -- Email opened first time (+5)
    'quick_open',           -- Opened <1 hour (+3)
    'mobile_open',          -- Opened on mobile (+2)
    'unsubscribe',          -- Clicked unsubscribe (-50)
    'spam_report',          -- Marked as spam (-30)
    'not_opened'            -- Not opened after 7 days (0)
  )),
  
  -- Scoring
  score_value integer NOT NULL,
  priority character varying NOT NULL CHECK (priority IN ('LOW', 'MEDIUM', 'HIGH', 'CRITICAL')),
  
  -- Event metadata
  event_data jsonb DEFAULT '{}'::jsonb, -- Full Resend webhook payload
  link_url character varying,            -- For click events
  device_type character varying,         -- mobile/desktop/tablet
  user_agent text,
  ip_address character varying,
  
  -- Campaign context
  campaign_id uuid,
  email_subject character varying,
  
  -- Automated actions taken
  actions_triggered jsonb DEFAULT '[]'::jsonb, -- ["sales_notified", "segment_added"]
  actions_completed_at timestamp with time zone,
  
  -- Timestamps
  event_timestamp timestamp with time zone NOT NULL, -- When event happened
  created_at timestamp with time zone DEFAULT now(),
  processed_at timestamp with time zone,
  
  CONSTRAINT engagement_signals_pkey PRIMARY KEY (id),
  CONSTRAINT engagement_signals_contact_id_fkey 
    FOREIGN KEY (contact_id) 
    REFERENCES public.contacts(id) ON DELETE CASCADE
);

-- ============================================================================
-- ENGAGEMENT SCORES TABLE
-- ============================================================================
-- Aggregated engagement scores per contact
CREATE TABLE IF NOT EXISTS public.engagement_scores (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  contact_id uuid NOT NULL UNIQUE,
  
  -- Overall scores
  total_score integer DEFAULT 0,
  total_positive_score integer DEFAULT 0, -- Sum of positive signals only
  total_negative_score integer DEFAULT 0, -- Sum of negative signals only
  
  -- Signal counts by type
  pricing_clicks integer DEFAULT 0,
  product_clicks integer DEFAULT 0,
  attachment_downloads integer DEFAULT 0,
  multiple_opens integer DEFAULT 0,
  case_study_clicks integer DEFAULT 0,
  email_opens integer DEFAULT 0,
  quick_opens integer DEFAULT 0,
  mobile_opens integer DEFAULT 0,
  unsubscribes integer DEFAULT 0,
  spam_reports integer DEFAULT 0,
  not_opened integer DEFAULT 0,
  
  -- Engagement level (auto-calculated)
  engagement_level character varying CHECK (engagement_level IN (
    'COLD',          -- Score < 0 or spam/unsubscribe
    'NEUTRAL',       -- Score 0-10
    'WARM',          -- Score 11-30
    'HOT',           -- Score 31-50
    'VERY_HOT'       -- Score > 50
  )),
  
  -- Flags
  is_highly_engaged boolean DEFAULT false,     -- Score > 30
  is_ready_to_buy boolean DEFAULT false,        -- Has pricing clicks
  is_active_researcher boolean DEFAULT false,   -- Has downloads/clicks
  is_validation_phase boolean DEFAULT false,    -- Has case study clicks
  is_suppressed boolean DEFAULT false,          -- Unsubscribed or spam
  
  -- Timestamps
  last_engagement_at timestamp with time zone,
  first_engagement_at timestamp with time zone,
  suppression_date timestamp with time zone,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  
  CONSTRAINT engagement_scores_pkey PRIMARY KEY (id),
  CONSTRAINT engagement_scores_contact_id_fkey 
    FOREIGN KEY (contact_id) 
    REFERENCES public.contacts(id) ON DELETE CASCADE
);

-- ============================================================================
-- EMAIL CAMPAIGNS TABLE
-- ============================================================================
-- Track email campaigns sent via Resend
CREATE TABLE IF NOT EXISTS public.email_campaigns (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  
  -- Campaign details
  name character varying NOT NULL,
  subject character varying NOT NULL,
  description text,
  
  -- Resend data
  resend_email_ids text[] DEFAULT ARRAY[]::text[], -- All Resend email IDs in campaign
  
  -- Campaign metrics
  total_sent integer DEFAULT 0,
  total_delivered integer DEFAULT 0,
  total_opened integer DEFAULT 0,
  total_clicked integer DEFAULT 0,
  total_bounced integer DEFAULT 0,
  total_unsubscribed integer DEFAULT 0,
  total_spam_reports integer DEFAULT 0,
  
  -- Calculated rates
  open_rate decimal(5,2),     -- percentage
  click_rate decimal(5,2),    -- percentage
  bounce_rate decimal(5,2),   -- percentage
  
  -- Status
  status character varying DEFAULT 'draft' CHECK (status IN ('draft', 'sending', 'sent', 'completed')),
  
  -- Timestamps
  scheduled_at timestamp with time zone,
  sent_at timestamp with time zone,
  completed_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  
  CONSTRAINT email_campaigns_pkey PRIMARY KEY (id)
);

-- ============================================================================
-- AUTOMATED ACTIONS LOG
-- ============================================================================
-- Track automated actions triggered by engagement signals
CREATE TABLE IF NOT EXISTS public.automated_actions_log (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  
  -- Trigger
  engagement_signal_id uuid NOT NULL,
  contact_id uuid NOT NULL,
  
  -- Action details
  action_type character varying NOT NULL CHECK (action_type IN (
    'sales_notification',       -- Notified sales team
    'segment_added',            -- Added to segment
    'workflow_triggered',       -- Started workflow
    'hot_lead_flag',           -- Flagged as hot lead
    'quote_prep',              -- Quote preparation started
    'suppression',             -- Suppressed contact
    'follow_up_scheduled',     -- Follow-up scheduled
    'content_sent',            -- Related content sent
    'nurture_enrolled'         -- Enrolled in nurture track
  )),
  
  action_description text,
  action_data jsonb DEFAULT '{}'::jsonb,
  
  -- Status
  status character varying DEFAULT 'pending' CHECK (status IN ('pending', 'completed', 'failed')),
  error_message text,
  
  -- Timestamps
  triggered_at timestamp with time zone DEFAULT now(),
  completed_at timestamp with time zone,
  
  CONSTRAINT automated_actions_log_pkey PRIMARY KEY (id),
  CONSTRAINT automated_actions_log_engagement_signal_id_fkey 
    FOREIGN KEY (engagement_signal_id) 
    REFERENCES public.engagement_signals(id) ON DELETE CASCADE,
  CONSTRAINT automated_actions_log_contact_id_fkey 
    FOREIGN KEY (contact_id) 
    REFERENCES public.contacts(id) ON DELETE CASCADE
);

-- ============================================================================
-- INDEXES FOR PERFORMANCE
-- ============================================================================

-- Engagement signals indexes
CREATE INDEX IF NOT EXISTS idx_engagement_signals_contact_id ON public.engagement_signals(contact_id);
CREATE INDEX IF NOT EXISTS idx_engagement_signals_signal_type ON public.engagement_signals(signal_type);
CREATE INDEX IF NOT EXISTS idx_engagement_signals_event_timestamp ON public.engagement_signals(event_timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_engagement_signals_resend_email_id ON public.engagement_signals(resend_email_id);
CREATE INDEX IF NOT EXISTS idx_engagement_signals_priority ON public.engagement_signals(priority);
CREATE INDEX IF NOT EXISTS idx_engagement_signals_email ON public.engagement_signals(email);

-- Engagement scores indexes
CREATE INDEX IF NOT EXISTS idx_engagement_scores_contact_id ON public.engagement_scores(contact_id);
CREATE INDEX IF NOT EXISTS idx_engagement_scores_total_score ON public.engagement_scores(total_score DESC);
CREATE INDEX IF NOT EXISTS idx_engagement_scores_engagement_level ON public.engagement_scores(engagement_level);
CREATE INDEX IF NOT EXISTS idx_engagement_scores_is_ready_to_buy ON public.engagement_scores(is_ready_to_buy);
CREATE INDEX IF NOT EXISTS idx_engagement_scores_is_suppressed ON public.engagement_scores(is_suppressed);

-- Automated actions log indexes
CREATE INDEX IF NOT EXISTS idx_automated_actions_log_contact_id ON public.automated_actions_log(contact_id);
CREATE INDEX IF NOT EXISTS idx_automated_actions_log_action_type ON public.automated_actions_log(action_type);
CREATE INDEX IF NOT EXISTS idx_automated_actions_log_status ON public.automated_actions_log(status);

-- ============================================================================
-- FUNCTION: Calculate Engagement Level
-- ============================================================================
CREATE OR REPLACE FUNCTION calculate_engagement_level(score integer, is_suppressed boolean)
RETURNS character varying AS $$
BEGIN
  IF is_suppressed THEN
    RETURN 'COLD';
  ELSIF score < 0 THEN
    RETURN 'COLD';
  ELSIF score <= 10 THEN
    RETURN 'NEUTRAL';
  ELSIF score <= 30 THEN
    RETURN 'WARM';
  ELSIF score <= 50 THEN
    RETURN 'HOT';
  ELSE
    RETURN 'VERY_HOT';
  END IF;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- ============================================================================
-- FUNCTION: Update Engagement Score
-- ============================================================================
CREATE OR REPLACE FUNCTION update_engagement_score()
RETURNS TRIGGER AS $$
DECLARE
  v_contact_id uuid;
  v_total_score integer;
  v_positive_score integer;
  v_negative_score integer;
  v_is_suppressed boolean;
BEGIN
  v_contact_id := NEW.contact_id;
  
  -- Calculate total scores
  SELECT 
    COALESCE(SUM(score_value), 0),
    COALESCE(SUM(CASE WHEN score_value > 0 THEN score_value ELSE 0 END), 0),
    COALESCE(SUM(CASE WHEN score_value < 0 THEN score_value ELSE 0 END), 0),
    COUNT(*) FILTER (WHERE signal_type IN ('unsubscribe', 'spam_report')) > 0
  INTO v_total_score, v_positive_score, v_negative_score, v_is_suppressed
  FROM engagement_signals
  WHERE contact_id = v_contact_id;
  
  -- Upsert engagement score
  INSERT INTO engagement_scores (
    contact_id,
    total_score,
    total_positive_score,
    total_negative_score,
    is_suppressed,
    engagement_level,
    last_engagement_at,
    first_engagement_at,
    -- Count each signal type
    pricing_clicks,
    product_clicks,
    attachment_downloads,
    multiple_opens,
    case_study_clicks,
    email_opens,
    quick_opens,
    mobile_opens,
    unsubscribes,
    spam_reports,
    not_opened,
    -- Flags
    is_highly_engaged,
    is_ready_to_buy,
    is_active_researcher,
    is_validation_phase
  )
  SELECT
    v_contact_id,
    v_total_score,
    v_positive_score,
    v_negative_score,
    v_is_suppressed,
    calculate_engagement_level(v_total_score, v_is_suppressed),
    MAX(event_timestamp),
    MIN(event_timestamp),
    COUNT(*) FILTER (WHERE signal_type = 'pricing_click'),
    COUNT(*) FILTER (WHERE signal_type = 'product_click'),
    COUNT(*) FILTER (WHERE signal_type = 'attachment_download'),
    COUNT(*) FILTER (WHERE signal_type = 'multiple_opens'),
    COUNT(*) FILTER (WHERE signal_type = 'case_study_click'),
    COUNT(*) FILTER (WHERE signal_type = 'email_opened'),
    COUNT(*) FILTER (WHERE signal_type = 'quick_open'),
    COUNT(*) FILTER (WHERE signal_type = 'mobile_open'),
    COUNT(*) FILTER (WHERE signal_type = 'unsubscribe'),
    COUNT(*) FILTER (WHERE signal_type = 'spam_report'),
    COUNT(*) FILTER (WHERE signal_type = 'not_opened'),
    v_total_score > 30,
    COUNT(*) FILTER (WHERE signal_type = 'pricing_click') > 0,
    COUNT(*) FILTER (WHERE signal_type IN ('attachment_download', 'product_click')) > 0,
    COUNT(*) FILTER (WHERE signal_type = 'case_study_click') > 0
  FROM engagement_signals
  WHERE contact_id = v_contact_id
  ON CONFLICT (contact_id) 
  DO UPDATE SET
    total_score = EXCLUDED.total_score,
    total_positive_score = EXCLUDED.total_positive_score,
    total_negative_score = EXCLUDED.total_negative_score,
    is_suppressed = EXCLUDED.is_suppressed,
    engagement_level = EXCLUDED.engagement_level,
    last_engagement_at = EXCLUDED.last_engagement_at,
    first_engagement_at = EXCLUDED.first_engagement_at,
    pricing_clicks = EXCLUDED.pricing_clicks,
    product_clicks = EXCLUDED.product_clicks,
    attachment_downloads = EXCLUDED.attachment_downloads,
    multiple_opens = EXCLUDED.multiple_opens,
    case_study_clicks = EXCLUDED.case_study_clicks,
    email_opens = EXCLUDED.email_opens,
    quick_opens = EXCLUDED.quick_opens,
    mobile_opens = EXCLUDED.mobile_opens,
    unsubscribes = EXCLUDED.unsubscribes,
    spam_reports = EXCLUDED.spam_reports,
    not_opened = EXCLUDED.not_opened,
    is_highly_engaged = EXCLUDED.is_highly_engaged,
    is_ready_to_buy = EXCLUDED.is_ready_to_buy,
    is_active_researcher = EXCLUDED.is_active_researcher,
    is_validation_phase = EXCLUDED.is_validation_phase,
    updated_at = now();
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- TRIGGER: Auto-update engagement scores on signal insert
-- ============================================================================
CREATE TRIGGER trigger_update_engagement_score
AFTER INSERT ON engagement_signals
FOR EACH ROW
EXECUTE FUNCTION update_engagement_score();

-- ============================================================================
-- COMMENTS
-- ============================================================================

COMMENT ON TABLE public.engagement_signals IS 'Individual engagement events from Resend webhooks - tracks all 11 signal types';
COMMENT ON TABLE public.engagement_scores IS 'Aggregated engagement scores per contact - auto-calculated from signals';
COMMENT ON TABLE public.email_campaigns IS 'Email campaigns sent via Resend';
COMMENT ON TABLE public.automated_actions_log IS 'Log of automated actions triggered by engagement signals';

COMMENT ON COLUMN public.engagement_signals.signal_type IS '11 types: pricing_click(+10), product_click(+8), attachment_download(+8), multiple_opens(+7), case_study_click(+6), email_opened(+5), quick_open(+3), mobile_open(+2), unsubscribe(-50), spam_report(-30), not_opened(0)';
COMMENT ON COLUMN public.engagement_scores.engagement_level IS 'Auto-calculated: COLD (<0), NEUTRAL (0-10), WARM (11-30), HOT (31-50), VERY_HOT (>50)';



