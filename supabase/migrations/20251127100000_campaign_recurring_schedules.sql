-- ============================================================================
-- RECURRING SCHEDULE SUPPORT FOR CAMPAIGNS
-- Migration: 20251127100000_campaign_recurring_schedules.sql
-- Description: Add recurring schedule columns and functions for campaigns
-- ============================================================================

-- Add recurrence columns to campaign_sequences
ALTER TABLE public.campaign_sequences
ADD COLUMN IF NOT EXISTS recurrence_pattern VARCHAR(20) DEFAULT 'none',
ADD COLUMN IF NOT EXISTS recurrence_config JSONB DEFAULT '{}',
ADD COLUMN IF NOT EXISTS recurrence_end_type VARCHAR(20) DEFAULT NULL,
ADD COLUMN IF NOT EXISTS recurrence_end_date TIMESTAMPTZ DEFAULT NULL,
ADD COLUMN IF NOT EXISTS recurrence_end_count INTEGER DEFAULT NULL,
ADD COLUMN IF NOT EXISTS recurrence_count INTEGER DEFAULT 0,
ADD COLUMN IF NOT EXISTS last_run_at TIMESTAMPTZ DEFAULT NULL,
ADD COLUMN IF NOT EXISTS next_run_at TIMESTAMPTZ DEFAULT NULL;

-- ============================================================================
-- CONSTRAINTS
-- ============================================================================

-- Constraint for recurrence_pattern
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'campaign_sequences_recurrence_pattern_check'
  ) THEN
    ALTER TABLE public.campaign_sequences
    ADD CONSTRAINT campaign_sequences_recurrence_pattern_check
    CHECK (recurrence_pattern IN ('none', 'daily', 'weekly', 'monthly'));
  END IF;
END $$;

-- Constraint for recurrence_end_type
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'campaign_sequences_recurrence_end_type_check'
  ) THEN
    ALTER TABLE public.campaign_sequences
    ADD CONSTRAINT campaign_sequences_recurrence_end_type_check
    CHECK (recurrence_end_type IS NULL OR recurrence_end_type IN ('never', 'after_count', 'by_date'));
  END IF;
END $$;

-- ============================================================================
-- INDEXES
-- ============================================================================

-- Index for scheduler to find due recurring campaigns
CREATE INDEX IF NOT EXISTS idx_campaign_sequences_next_run
ON public.campaign_sequences (next_run_at, status)
WHERE status IN ('scheduled', 'running') AND recurrence_pattern != 'none';

-- ============================================================================
-- RECURRENCE CONFIG JSONB STRUCTURE DOCUMENTATION
-- ============================================================================
--
-- For 'daily':
-- {
--   "interval": 1,           -- Every N days
--   "weekdaysOnly": true     -- Skip weekends
-- }
--
-- For 'weekly':
-- {
--   "interval": 1,           -- Every N weeks
--   "daysOfWeek": [1, 3, 5]  -- 0=Sun, 1=Mon, ... 6=Sat
-- }
--
-- For 'monthly':
-- {
--   "interval": 1,           -- Every N months
--   "dayType": "dayOfMonth", -- or "weekdayOfMonth"
--   "dayOfMonth": 1,         -- 1-31 (for dayOfMonth type)
--   "weekOfMonth": 1,        -- 1-4 or -1 for last (for weekdayOfMonth type)
--   "dayOfWeek": 1           -- 0-6 (for weekdayOfMonth type)
-- }

-- ============================================================================
-- FUNCTION: Calculate next run date based on recurrence pattern
-- ============================================================================

CREATE OR REPLACE FUNCTION calculate_next_run_date(
  p_last_run TIMESTAMPTZ,
  p_pattern VARCHAR(20),
  p_config JSONB,
  p_send_time TIME,
  p_timezone VARCHAR(50)
)
RETURNS TIMESTAMPTZ
LANGUAGE plpgsql
AS $$
DECLARE
  v_interval INTEGER;
  v_next_date DATE;
  v_result TIMESTAMPTZ;
  v_days_of_week INTEGER[];
  v_day_of_week INTEGER;
  v_current_dow INTEGER;
  v_days_ahead INTEGER;
  v_found BOOLEAN;
  v_week_of_month INTEGER;
  v_target_dow INTEGER;
  v_first_of_month DATE;
  v_first_dow INTEGER;
BEGIN
  -- Handle NULL last_run - use current time
  IF p_last_run IS NULL THEN
    p_last_run := NOW();
  END IF;

  -- Default timezone
  IF p_timezone IS NULL OR p_timezone = '' THEN
    p_timezone := 'Australia/Sydney';
  END IF;

  -- Default interval to 1 if not specified
  v_interval := COALESCE((p_config->>'interval')::INTEGER, 1);
  IF v_interval < 1 THEN v_interval := 1; END IF;

  CASE p_pattern
    WHEN 'daily' THEN
      IF COALESCE((p_config->>'weekdaysOnly')::BOOLEAN, false) = true THEN
        -- Find next weekday
        v_next_date := (p_last_run AT TIME ZONE p_timezone)::DATE + v_interval;
        -- Skip weekends (0=Sunday, 6=Saturday)
        WHILE EXTRACT(DOW FROM v_next_date) IN (0, 6) LOOP
          v_next_date := v_next_date + 1;
        END LOOP;
      ELSE
        v_next_date := (p_last_run AT TIME ZONE p_timezone)::DATE + v_interval;
      END IF;

    WHEN 'weekly' THEN
      -- Get days of week from config (e.g., [1, 3, 5] for Mon, Wed, Fri)
      SELECT array_agg(elem::INTEGER ORDER BY elem::INTEGER)
      INTO v_days_of_week
      FROM jsonb_array_elements_text(p_config->'daysOfWeek') AS elem;

      -- Default to Monday if no days specified
      IF v_days_of_week IS NULL OR array_length(v_days_of_week, 1) IS NULL THEN
        v_days_of_week := ARRAY[1];
      END IF;

      v_current_dow := EXTRACT(DOW FROM (p_last_run AT TIME ZONE p_timezone)::DATE)::INTEGER;
      v_next_date := (p_last_run AT TIME ZONE p_timezone)::DATE;
      v_found := false;

      -- Look for next matching day in current week first
      FOREACH v_day_of_week IN ARRAY v_days_of_week LOOP
        v_days_ahead := v_day_of_week - v_current_dow;
        IF v_days_ahead > 0 THEN
          v_next_date := (p_last_run AT TIME ZONE p_timezone)::DATE + v_days_ahead;
          v_found := true;
          EXIT;
        END IF;
      END LOOP;

      -- If not found in current week, go to first day of next interval week
      IF NOT v_found THEN
        -- Move to next week boundary and then add interval weeks
        v_next_date := (p_last_run AT TIME ZONE p_timezone)::DATE + (7 * v_interval);
        -- Adjust to first matching day of week
        v_current_dow := EXTRACT(DOW FROM v_next_date)::INTEGER;
        v_days_ahead := v_days_of_week[1] - v_current_dow;
        IF v_days_ahead < 0 THEN
          v_days_ahead := v_days_ahead + 7;
        END IF;
        v_next_date := v_next_date + v_days_ahead;
      END IF;

    WHEN 'monthly' THEN
      IF COALESCE(p_config->>'dayType', 'dayOfMonth') = 'dayOfMonth' THEN
        -- Specific day of month (e.g., 1st, 15th)
        v_next_date := DATE_TRUNC('month', (p_last_run AT TIME ZONE p_timezone)::DATE + INTERVAL '1 day')::DATE
                      + INTERVAL '1 month' * v_interval;
        -- Set to the specified day of month (clamped to month length)
        v_next_date := v_next_date + (LEAST(
          COALESCE((p_config->>'dayOfMonth')::INTEGER, 1),
          EXTRACT(DAY FROM (v_next_date + INTERVAL '1 month' - INTERVAL '1 day'))::INTEGER
        ) - 1) * INTERVAL '1 day';
      ELSE
        -- Nth weekday of month (e.g., first Monday, last Friday)
        v_week_of_month := COALESCE((p_config->>'weekOfMonth')::INTEGER, 1);
        v_target_dow := COALESCE((p_config->>'dayOfWeek')::INTEGER, 1);

        -- Get first day of target month
        v_first_of_month := DATE_TRUNC('month', (p_last_run AT TIME ZONE p_timezone)::DATE + INTERVAL '1 day')::DATE
                           + INTERVAL '1 month' * v_interval;
        v_first_dow := EXTRACT(DOW FROM v_first_of_month)::INTEGER;

        IF v_week_of_month = -1 THEN
          -- Last occurrence of weekday in month
          v_next_date := (v_first_of_month + INTERVAL '1 month' - INTERVAL '1 day')::DATE;
          WHILE EXTRACT(DOW FROM v_next_date) != v_target_dow LOOP
            v_next_date := v_next_date - 1;
          END LOOP;
        ELSE
          -- Nth occurrence of weekday
          v_days_ahead := v_target_dow - v_first_dow;
          IF v_days_ahead < 0 THEN v_days_ahead := v_days_ahead + 7; END IF;
          v_next_date := v_first_of_month + v_days_ahead + (7 * (v_week_of_month - 1));
        END IF;
      END IF;

    ELSE
      -- 'none' or unknown - return NULL
      RETURN NULL;
  END CASE;

  -- Combine date with send time in the specified timezone
  IF p_send_time IS NULL THEN
    p_send_time := '09:00:00'::TIME;
  END IF;

  v_result := (v_next_date::TEXT || ' ' || p_send_time::TEXT)::TIMESTAMP AT TIME ZONE p_timezone;

  RETURN v_result;
END;
$$;

-- ============================================================================
-- VIEW: Campaigns due for recurring execution
-- ============================================================================

CREATE OR REPLACE VIEW v_campaigns_due_for_run AS
SELECT
  cs.id,
  cs.name,
  cs.recurrence_pattern,
  cs.recurrence_config,
  cs.recurrence_end_type,
  cs.recurrence_end_date,
  cs.recurrence_end_count,
  cs.recurrence_count,
  cs.next_run_at,
  cs.last_run_at,
  cs.target_sql,
  cs.action_type,
  cs.action_config,
  cs.daily_limit,
  cs.batch_size,
  cs.send_time,
  cs.timezone,
  cs.from_mailbox_id,
  cs.approval_required,
  cs.exclusion_config
FROM campaign_sequences cs
WHERE cs.status IN ('scheduled', 'running')
  AND cs.recurrence_pattern != 'none'
  AND cs.next_run_at <= NOW()
  AND (
    cs.recurrence_end_type IS NULL
    OR cs.recurrence_end_type = 'never'
    OR (cs.recurrence_end_type = 'after_count' AND cs.recurrence_count < cs.recurrence_end_count)
    OR (cs.recurrence_end_type = 'by_date' AND cs.recurrence_end_date > NOW())
  );

-- ============================================================================
-- FUNCTION: Get campaigns due for recurring run (RPC endpoint)
-- ============================================================================

CREATE OR REPLACE FUNCTION get_campaigns_due_for_run()
RETURNS SETOF v_campaigns_due_for_run
LANGUAGE sql
SECURITY DEFINER
AS $$
  SELECT * FROM v_campaigns_due_for_run;
$$;

-- ============================================================================
-- FUNCTION: Update campaign after recurring run
-- ============================================================================

CREATE OR REPLACE FUNCTION update_campaign_after_run(
  p_campaign_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_campaign RECORD;
  v_next_run TIMESTAMPTZ;
  v_should_end BOOLEAN := false;
BEGIN
  -- Get current campaign state
  SELECT * INTO v_campaign
  FROM campaign_sequences
  WHERE id = p_campaign_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Campaign not found');
  END IF;

  -- Calculate next run date
  v_next_run := calculate_next_run_date(
    NOW(),
    v_campaign.recurrence_pattern,
    v_campaign.recurrence_config,
    v_campaign.send_time,
    v_campaign.timezone
  );

  -- Check if recurrence should end
  IF v_campaign.recurrence_end_type = 'after_count' AND (v_campaign.recurrence_count + 1) >= v_campaign.recurrence_end_count THEN
    v_should_end := true;
  ELSIF v_campaign.recurrence_end_type = 'by_date' AND v_next_run > v_campaign.recurrence_end_date THEN
    v_should_end := true;
  END IF;

  -- Update campaign
  IF v_should_end THEN
    UPDATE campaign_sequences
    SET
      last_run_at = NOW(),
      next_run_at = NULL,
      recurrence_count = recurrence_count + 1,
      status = 'completed'
    WHERE id = p_campaign_id;

    RETURN jsonb_build_object(
      'success', true,
      'completed', true,
      'recurrence_count', v_campaign.recurrence_count + 1
    );
  ELSE
    UPDATE campaign_sequences
    SET
      last_run_at = NOW(),
      next_run_at = v_next_run,
      recurrence_count = recurrence_count + 1
    WHERE id = p_campaign_id;

    RETURN jsonb_build_object(
      'success', true,
      'completed', false,
      'next_run_at', v_next_run,
      'recurrence_count', v_campaign.recurrence_count + 1
    );
  END IF;
END;
$$;

-- ============================================================================
-- Grant permissions
-- ============================================================================

GRANT EXECUTE ON FUNCTION calculate_next_run_date TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION get_campaigns_due_for_run TO service_role;
GRANT EXECUTE ON FUNCTION update_campaign_after_run TO service_role;
GRANT SELECT ON v_campaigns_due_for_run TO service_role;
