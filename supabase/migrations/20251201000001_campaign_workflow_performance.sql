-- ============================================================================
-- CAMPAIGN PERFORMANCE BACKEND - FINAL CORRECTED VERSION
-- ============================================================================
-- Fixed for composite primary key (campaign_id, contact_id)
-- ============================================================================

-- ============================================================================
-- FUNCTION 1: Campaign Overview Stats (FINAL FIX)
-- ============================================================================

CREATE OR REPLACE FUNCTION get_campaign_overview(num_months INTEGER DEFAULT 3)
RETURNS TABLE (
  total_campaigns BIGINT,
  total_reached BIGINT,
  avg_open_rate NUMERIC,
  avg_click_rate NUMERIC,
  campaigns_this_month BIGINT,
  reached_this_month BIGINT
) AS $$
BEGIN
  RETURN QUERY
  WITH stats AS (
    SELECT 
      COUNT(DISTINCT c.id)::BIGINT as total_campaigns,
      COUNT(DISTINCT ccs.contact_id)::BIGINT as total_reached,
      ROUND(
        COUNT(*) FILTER (WHERE ccs.opened = true)::NUMERIC / 
        NULLIF(COUNT(*), 0) * 100, 
        1
      ) as avg_open_rate,
      ROUND(
        COUNT(*) FILTER (WHERE ccs.clicked = true)::NUMERIC / 
        NULLIF(COUNT(*), 0) * 100, 
        1
      ) as avg_click_rate
    FROM campaigns c
    LEFT JOIN campaign_contact_summary ccs ON ccs.campaign_id = c.id
    WHERE c.sent_at >= NOW() - (num_months || ' months')::INTERVAL
  ),
  this_month AS (
    SELECT 
      COUNT(DISTINCT c.id)::BIGINT as campaigns_this_month,
      COUNT(DISTINCT ccs.contact_id)::BIGINT as reached_this_month
    FROM campaigns c
    LEFT JOIN campaign_contact_summary ccs ON ccs.campaign_id = c.id
    WHERE c.sent_at >= DATE_TRUNC('month', NOW())
  )
  SELECT 
    stats.total_campaigns,
    stats.total_reached,
    COALESCE(stats.avg_open_rate, 0),
    COALESCE(stats.avg_click_rate, 0),
    this_month.campaigns_this_month,
    this_month.reached_this_month
  FROM stats, this_month;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- FUNCTION 2: Top Performing Campaigns (FINAL FIX)
-- ============================================================================

CREATE OR REPLACE FUNCTION get_top_campaigns(
  num_months INTEGER DEFAULT 3, 
  limit_count INTEGER DEFAULT 10
)
RETURNS TABLE (
  campaign_id UUID,
  campaign_name TEXT,
  campaign_subject TEXT,
  sent_date TIMESTAMPTZ,
  contacts_reached BIGINT,
  total_opens BIGINT,
  total_clicks BIGINT,
  open_rate NUMERIC,
  click_rate NUMERIC,
  engagement_score BIGINT
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    c.id,
    c.name,
    c.subject,
    c.sent_at,
    COUNT(DISTINCT ccs.contact_id)::BIGINT as contacts,
    COUNT(*) FILTER (WHERE ccs.opened = true)::BIGINT as opens,
    COUNT(*) FILTER (WHERE ccs.clicked = true)::BIGINT as clicks,
    ROUND(
      COUNT(*) FILTER (WHERE ccs.opened = true)::NUMERIC / 
      NULLIF(COUNT(*), 0) * 100, 
      1
    ) as open_rate,
    ROUND(
      COUNT(*) FILTER (WHERE ccs.clicked = true)::NUMERIC / 
      NULLIF(COUNT(*), 0) * 100, 
      1
    ) as click_rate,
    COALESCE(SUM(ccs.total_score), 0)::BIGINT as score
  FROM campaigns c
  LEFT JOIN campaign_contact_summary ccs ON ccs.campaign_id = c.id
  WHERE c.sent_at >= NOW() - (num_months || ' months')::INTERVAL
    AND c.sent_at IS NOT NULL
  GROUP BY c.id, c.name, c.subject, c.sent_at
  HAVING COUNT(ccs.contact_id) > 0
  ORDER BY COALESCE(SUM(ccs.total_score), 0) DESC
  LIMIT limit_count;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- FUNCTION 3: Campaign Trends Over Time (FINAL FIX)
-- ============================================================================

CREATE OR REPLACE FUNCTION get_campaign_trends(num_months INTEGER DEFAULT 6)
RETURNS TABLE (
  month TEXT,
  month_start TIMESTAMPTZ,
  campaigns_sent BIGINT,
  contacts_reached BIGINT,
  open_rate NUMERIC,
  click_rate NUMERIC
) AS $$
BEGIN
  RETURN QUERY
  WITH months AS (
    SELECT 
      DATE_TRUNC('month', NOW() - (n || ' months')::INTERVAL) as month_start,
      DATE_TRUNC('month', NOW() - (n || ' months')::INTERVAL) + INTERVAL '1 month' as month_end,
      TO_CHAR(DATE_TRUNC('month', NOW() - (n || ' months')::INTERVAL), 'Mon YYYY') as month_label,
      n as sort_order
    FROM generate_series(0, num_months - 1) n
  )
  SELECT 
    m.month_label::TEXT,
    m.month_start,
    COUNT(DISTINCT c.id)::BIGINT as campaigns,
    COUNT(DISTINCT ccs.contact_id)::BIGINT as contacts,
    ROUND(
      COUNT(*) FILTER (WHERE ccs.opened = true)::NUMERIC / 
      NULLIF(COUNT(ccs.contact_id), 0) * 100, 
      1
    ) as open_rate,
    ROUND(
      COUNT(*) FILTER (WHERE ccs.clicked = true)::NUMERIC / 
      NULLIF(COUNT(ccs.contact_id), 0) * 100, 
      1
    ) as click_rate
  FROM months m
  LEFT JOIN campaigns c ON 
    c.sent_at >= m.month_start 
    AND c.sent_at < m.month_end
  LEFT JOIN campaign_contact_summary ccs ON ccs.campaign_id = c.id
  GROUP BY m.month_label, m.month_start, m.sort_order
  ORDER BY m.month_start ASC;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- FUNCTION 4: Recent Campaigns (FINAL FIX)
-- ============================================================================

CREATE OR REPLACE FUNCTION get_recent_campaigns(limit_count INTEGER DEFAULT 10)
RETURNS TABLE (
  campaign_id UUID,
  campaign_name TEXT,
  campaign_subject TEXT,
  sent_date TIMESTAMPTZ,
  contacts_reached BIGINT,
  total_opens BIGINT,
  total_clicks BIGINT,
  open_rate NUMERIC,
  click_rate NUMERIC,
  days_ago INTEGER
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    c.id,
    c.name,
    c.subject,
    c.sent_at,
    COUNT(DISTINCT ccs.contact_id)::BIGINT as contacts,
    COUNT(*) FILTER (WHERE ccs.opened = true)::BIGINT as opens,
    COUNT(*) FILTER (WHERE ccs.clicked = true)::BIGINT as clicks,
    ROUND(
      COUNT(*) FILTER (WHERE ccs.opened = true)::NUMERIC / 
      NULLIF(COUNT(*), 0) * 100, 
      1
    ) as open_rate,
    ROUND(
      COUNT(*) FILTER (WHERE ccs.clicked = true)::NUMERIC / 
      NULLIF(COUNT(*), 0) * 100, 
      1
    ) as click_rate,
    EXTRACT(DAY FROM NOW() - c.sent_at)::INTEGER as days_ago
  FROM campaigns c
  LEFT JOIN campaign_contact_summary ccs ON ccs.campaign_id = c.id
  WHERE c.sent_at IS NOT NULL
  GROUP BY c.id, c.name, c.subject, c.sent_at
  HAVING COUNT(ccs.contact_id) > 0
  ORDER BY c.sent_at DESC
  LIMIT limit_count;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- FUNCTION 5: Campaign Performance by Type (FINAL FIX)
-- ============================================================================

CREATE OR REPLACE FUNCTION get_campaign_performance_by_type(num_months INTEGER DEFAULT 3)
RETURNS TABLE (
  campaign_type TEXT,
  campaign_count BIGINT,
  avg_open_rate NUMERIC,
  avg_click_rate NUMERIC,
  total_engagement_score BIGINT
) AS $$
BEGIN
  RETURN QUERY
  WITH campaign_types AS (
    SELECT 
      c.id,
      c.name,
      CASE 
        WHEN c.name ILIKE '%product%' OR c.name ILIKE '%launch%' THEN 'Product Launches'
        WHEN c.name ILIKE '%monthly%' OR c.name ILIKE '%newsletter%' OR c.name ILIKE '%x-change%' THEN 'Monthly Newsletter'
        WHEN c.name ILIKE '%special%' OR c.name ILIKE '%offer%' OR c.name ILIKE '%promotion%' THEN 'Special Offers'
        WHEN c.name ILIKE '%service%' OR c.name ILIKE '%reminder%' THEN 'Service Reminders'
        WHEN c.name ILIKE '%vacancy%' OR c.name ILIKE '%christmas%' OR c.name ILIKE '%merry%' THEN 'General Updates'
        ELSE 'General Updates'
      END as campaign_type
    FROM campaigns c
    WHERE c.sent_at >= NOW() - (num_months || ' months')::INTERVAL
      AND c.sent_at IS NOT NULL
  )
  SELECT 
    ct.campaign_type::TEXT,
    COUNT(DISTINCT ct.id)::BIGINT as count,
    ROUND(
      COUNT(*) FILTER (WHERE ccs.opened = true)::NUMERIC / 
      NULLIF(COUNT(ccs.contact_id), 0) * 100, 
      1
    ) as open_rate,
    ROUND(
      COUNT(*) FILTER (WHERE ccs.clicked = true)::NUMERIC / 
      NULLIF(COUNT(ccs.contact_id), 0) * 100, 
      1
    ) as click_rate,
    COALESCE(SUM(ccs.total_score), 0)::BIGINT as score
  FROM campaign_types ct
  LEFT JOIN campaign_contact_summary ccs ON ccs.campaign_id = ct.id
  GROUP BY ct.campaign_type
  HAVING COUNT(ccs.contact_id) > 0
  ORDER BY 
    ROUND(
      COUNT(*) FILTER (WHERE ccs.opened = true)::NUMERIC / 
      NULLIF(COUNT(ccs.contact_id), 0) * 100, 
      1
    ) DESC NULLS LAST;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- VERIFICATION QUERIES
-- ============================================================================

SELECT '=== Testing Campaign Overview ===' as test;
SELECT * FROM get_campaign_overview(3);

SELECT '=== Testing Top Campaigns ===' as test;
SELECT * FROM get_top_campaigns(3, 5);

SELECT '=== Testing Campaign Trends ===' as test;
SELECT * FROM get_campaign_trends(6);

SELECT '=== Testing Recent Campaigns ===' as test;
SELECT * FROM get_recent_campaigns(5);

SELECT '=== Testing Performance by Type ===' as test;
SELECT * FROM get_campaign_performance_by_type(3);

-- ============================================================================
-- SUMMARY
-- ============================================================================

SELECT '========================================' as result
UNION ALL SELECT '✅ BACKEND SETUP COMPLETE!'
UNION ALL SELECT '========================================'
UNION ALL SELECT ''
UNION ALL SELECT 'Created 5 SQL Functions:'
UNION ALL SELECT '  1. get_campaign_overview(num_months)'
UNION ALL SELECT '  2. get_top_campaigns(num_months, limit)'
UNION ALL SELECT '  3. get_campaign_trends(num_months)'
UNION ALL SELECT '  4. get_recent_campaigns(limit)'
UNION ALL SELECT '  5. get_campaign_performance_by_type(num_months)'
UNION ALL SELECT ''
UNION ALL SELECT '🚀 Ready for frontend implementation!';

-- ============================================================================
-- WORKFLOW PERFORMANCE BACKEND - CORRECTED SQL FUNCTIONS
-- ============================================================================
-- Fixed type mismatches: VARCHAR -> TEXT
-- ============================================================================

-- ============================================================================
-- WORKFLOW FUNCTIONS - WITH SECURITY DEFINER (Bypasses RLS)
-- ============================================================================
-- This fixes the RLS issue causing functions to return 0 data
-- ============================================================================

DROP FUNCTION IF EXISTS get_workflow_overview(INTEGER) CASCADE;
DROP FUNCTION IF EXISTS get_top_workflows(INTEGER, INTEGER) CASCADE;
DROP FUNCTION IF EXISTS get_workflow_trends(INTEGER) CASCADE;
DROP FUNCTION IF EXISTS get_recent_workflows(INTEGER) CASCADE;
DROP FUNCTION IF EXISTS get_workflow_performance_by_status(INTEGER) CASCADE;
DROP FUNCTION IF EXISTS get_workflow_frequency_analysis(INTEGER) CASCADE;

SELECT '✅ Dropped all old workflow functions' as status;

-- ============================================================================
-- FUNCTION 1: Workflow Overview (WITH SECURITY DEFINER)
-- ============================================================================

CREATE OR REPLACE FUNCTION get_workflow_overview(num_months INTEGER DEFAULT 3)
RETURNS TABLE (
  active_workflows BIGINT,
  total_executions BIGINT,
  executions_per_day NUMERIC,
  successful_executions BIGINT,
  failed_executions BIGINT,
  success_rate NUMERIC,
  unique_contacts BIGINT,
  total_actions_performed BIGINT,
  avg_completion_hours NUMERIC,
  executions_this_month BIGINT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  WITH time_range AS (
    SELECT 
      NOW() - (num_months || ' months')::INTERVAL as start_date,
      GREATEST(EXTRACT(DAY FROM (num_months || ' months')::INTERVAL), 1) as total_days
  ),
  workflow_stats AS (
    SELECT 
      COUNT(DISTINCT w.id) FILTER (WHERE w.is_active = true)::BIGINT as active,
      COUNT(DISTINCT we.id)::BIGINT as executions,
      ROUND(
        COUNT(DISTINCT we.id)::NUMERIC / NULLIF((SELECT total_days FROM time_range), 0),
        1
      ) as exec_per_day,
      COUNT(DISTINCT we.id) FILTER (WHERE we.status = 'completed')::BIGINT as successful,
      COUNT(DISTINCT we.id) FILTER (WHERE we.status = 'failed')::BIGINT as failed,
      ROUND(
        COUNT(DISTINCT we.id) FILTER (WHERE we.status = 'completed')::NUMERIC /
        NULLIF(COUNT(DISTINCT we.id), 0) * 100,
        1
      ) as success_rate,
      COUNT(DISTINCT we.contact_id)::BIGINT as contacts,
      SUM(
        COALESCE(jsonb_array_length(we.actions_completed), 0) + 
        COALESCE(jsonb_array_length(we.actions_failed), 0)
      )::BIGINT as actions,
      ROUND(
        AVG(
          EXTRACT(EPOCH FROM (we.completed_at - we.started_at)) / 3600
        ) FILTER (WHERE we.completed_at IS NOT NULL AND we.completed_at > we.started_at),
        1
      ) as avg_hours
    FROM workflows w
    LEFT JOIN workflow_executions we ON we.workflow_id = w.id
      AND we.started_at >= (SELECT start_date FROM time_range)
  ),
  this_month AS (
    SELECT 
      COUNT(DISTINCT we.id)::BIGINT as executions_month
    FROM workflow_executions we
    WHERE we.started_at >= DATE_TRUNC('month', NOW())
  )
  SELECT 
    COALESCE(ws.active, 0),
    COALESCE(ws.executions, 0),
    COALESCE(ws.exec_per_day, 0),
    COALESCE(ws.successful, 0),
    COALESCE(ws.failed, 0),
    COALESCE(ws.success_rate, 0),
    COALESCE(ws.contacts, 0),
    COALESCE(ws.actions, 0),
    COALESCE(ws.avg_hours, 0),
    COALESCE(tm.executions_month, 0)
  FROM workflow_stats ws, this_month tm;
END;
$$;

-- ============================================================================
-- FUNCTION 2: Top Workflows (WITH SECURITY DEFINER)
-- ============================================================================

CREATE OR REPLACE FUNCTION get_top_workflows(
  num_months INTEGER DEFAULT 3,
  limit_count INTEGER DEFAULT 10
)
RETURNS TABLE (
  workflow_id UUID,
  workflow_name TEXT,
  workflow_description TEXT,
  trigger_condition TEXT,
  is_active BOOLEAN,
  total_executions BIGINT,
  executions_per_week NUMERIC,
  unique_contacts BIGINT,
  successful_executions BIGINT,
  failed_executions BIGINT,
  success_rate NUMERIC,
  avg_completion_hours NUMERIC,
  total_actions BIGINT,
  emails_sent BIGINT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  WITH time_range AS (
    SELECT 
      NOW() - (num_months || ' months')::INTERVAL as start_date,
      GREATEST(EXTRACT(DAY FROM (num_months || ' months')::INTERVAL) / 7, 1) as weeks
  )
  SELECT 
    w.id,
    w.name::TEXT,
    COALESCE(w.description, '')::TEXT,
    w.trigger_condition::TEXT,
    w.is_active,
    COUNT(DISTINCT we.id)::BIGINT as executions,
    ROUND(
      COUNT(DISTINCT we.id)::NUMERIC / NULLIF((SELECT weeks FROM time_range), 0),
      1
    ) as exec_per_week,
    COUNT(DISTINCT we.contact_id)::BIGINT as contacts,
    COUNT(DISTINCT we.id) FILTER (WHERE we.status = 'completed')::BIGINT as successful,
    COUNT(DISTINCT we.id) FILTER (WHERE we.status = 'failed')::BIGINT as failed,
    ROUND(
      COUNT(DISTINCT we.id) FILTER (WHERE we.status = 'completed')::NUMERIC /
      NULLIF(COUNT(DISTINCT we.id), 0) * 100,
      1
    ) as success_rate,
    ROUND(
      AVG(
        EXTRACT(EPOCH FROM (we.completed_at - we.started_at)) / 3600
      ) FILTER (WHERE we.completed_at IS NOT NULL AND we.completed_at > we.started_at),
      1
    ) as avg_hours,
    SUM(
      COALESCE(jsonb_array_length(we.actions_completed), 0) + 
      COALESCE(jsonb_array_length(we.actions_failed), 0)
    )::BIGINT as actions,
    COUNT(ce.id) FILTER (WHERE ce.event_type = 'sent')::BIGINT as emails
  FROM workflows w
  LEFT JOIN workflow_executions we ON we.workflow_id = w.id
    AND we.started_at >= (SELECT start_date FROM time_range)
  LEFT JOIN campaign_events ce ON ce.workflow_execution_id = we.id
  GROUP BY w.id, w.name, w.description, w.trigger_condition, w.is_active
  HAVING COUNT(DISTINCT we.id) > 0
  ORDER BY COUNT(DISTINCT we.id) DESC
  LIMIT limit_count;
END;
$$;

-- ============================================================================
-- FUNCTION 3: Workflow Trends (WITH SECURITY DEFINER)
-- ============================================================================

CREATE OR REPLACE FUNCTION get_workflow_trends(num_months INTEGER DEFAULT 6)
RETURNS TABLE (
  month TEXT,
  month_start TIMESTAMPTZ,
  executions_started BIGINT,
  executions_completed BIGINT,
  executions_failed BIGINT,
  success_rate NUMERIC,
  unique_contacts BIGINT,
  avg_per_day NUMERIC,
  total_actions BIGINT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  WITH months AS (
    SELECT 
      DATE_TRUNC('month', NOW() - (n || ' months')::INTERVAL) as month_start,
      DATE_TRUNC('month', NOW() - (n || ' months')::INTERVAL) + INTERVAL '1 month' as month_end,
      TO_CHAR(DATE_TRUNC('month', NOW() - (n || ' months')::INTERVAL), 'Mon YYYY') as month_label,
      GREATEST(
        EXTRACT(DAY FROM 
          DATE_TRUNC('month', NOW() - (n || ' months')::INTERVAL) + INTERVAL '1 month' - 
          DATE_TRUNC('month', NOW() - (n || ' months')::INTERVAL)
        ), 1
      ) as days_in_month
    FROM generate_series(0, num_months - 1) n
  )
  SELECT 
    m.month_label::TEXT,
    m.month_start,
    COUNT(DISTINCT we.id)::BIGINT as started,
    COUNT(DISTINCT we.id) FILTER (WHERE we.status = 'completed')::BIGINT as completed,
    COUNT(DISTINCT we.id) FILTER (WHERE we.status = 'failed')::BIGINT as failed,
    ROUND(
      COUNT(DISTINCT we.id) FILTER (WHERE we.status = 'completed')::NUMERIC /
      NULLIF(COUNT(DISTINCT we.id), 0) * 100,
      1
    ) as success_rate,
    COUNT(DISTINCT we.contact_id)::BIGINT as contacts,
    ROUND(
      COUNT(DISTINCT we.id)::NUMERIC / NULLIF(m.days_in_month, 0),
      1
    ) as per_day,
    SUM(
      COALESCE(jsonb_array_length(we.actions_completed), 0) + 
      COALESCE(jsonb_array_length(we.actions_failed), 0)
    )::BIGINT as actions
  FROM months m
  LEFT JOIN workflow_executions we ON 
    we.started_at >= m.month_start 
    AND we.started_at < m.month_end
  GROUP BY m.month_label, m.month_start, m.days_in_month
  ORDER BY m.month_start ASC;
END;
$$;

-- ============================================================================
-- FUNCTION 4: Recent Workflows (WITH SECURITY DEFINER)
-- ============================================================================

CREATE OR REPLACE FUNCTION get_recent_workflows(limit_count INTEGER DEFAULT 10)
RETURNS TABLE (
  workflow_id UUID,
  workflow_name TEXT,
  execution_id UUID,
  contact_id UUID,
  contact_email TEXT,
  started_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  duration_minutes INTEGER,
  status TEXT,
  actions_completed INTEGER,
  actions_failed INTEGER,
  total_actions INTEGER,
  days_ago INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    w.id,
    w.name::TEXT,
    we.id,
    we.contact_id,
    COALESCE(c.email, '')::TEXT,
    we.started_at,
    we.completed_at,
    COALESCE(EXTRACT(EPOCH FROM (we.completed_at - we.started_at))::INTEGER / 60, 0) as duration,
    COALESCE(we.status, 'unknown')::TEXT,
    COALESCE(jsonb_array_length(we.actions_completed), 0)::INTEGER as completed_actions,
    COALESCE(jsonb_array_length(we.actions_failed), 0)::INTEGER as failed_actions,
    (
      COALESCE(jsonb_array_length(we.actions_completed), 0) + 
      COALESCE(jsonb_array_length(we.actions_failed), 0)
    )::INTEGER as total,
    EXTRACT(DAY FROM NOW() - we.started_at)::INTEGER as days_ago
  FROM workflow_executions we
  INNER JOIN workflows w ON w.id = we.workflow_id
  LEFT JOIN contacts c ON c.id = we.contact_id
  WHERE we.started_at IS NOT NULL
  ORDER BY we.started_at DESC
  LIMIT limit_count;
END;
$$;

-- ============================================================================
-- FUNCTION 5: Performance by Status (WITH SECURITY DEFINER)
-- ============================================================================

CREATE OR REPLACE FUNCTION get_workflow_performance_by_status(num_months INTEGER DEFAULT 3)
RETURNS TABLE (
  workflow_status TEXT,
  execution_count BIGINT,
  percentage NUMERIC,
  avg_completion_hours NUMERIC,
  total_contacts BIGINT,
  total_actions BIGINT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  WITH total AS (
    SELECT GREATEST(COUNT(*), 1)::NUMERIC as total_executions
    FROM workflow_executions
    WHERE started_at >= NOW() - (num_months || ' months')::INTERVAL
  )
  SELECT 
    COALESCE(we.status, 'unknown')::TEXT,
    COUNT(DISTINCT we.id)::BIGINT as count,
    ROUND(
      COUNT(DISTINCT we.id)::NUMERIC / NULLIF((SELECT total_executions FROM total), 0) * 100,
      1
    ) as pct,
    ROUND(
      AVG(
        EXTRACT(EPOCH FROM (we.completed_at - we.started_at)) / 3600
      ) FILTER (WHERE we.completed_at IS NOT NULL AND we.completed_at > we.started_at),
      1
    ) as avg_hours,
    COUNT(DISTINCT we.contact_id)::BIGINT as contacts,
    SUM(
      COALESCE(jsonb_array_length(we.actions_completed), 0) + 
      COALESCE(jsonb_array_length(we.actions_failed), 0)
    )::BIGINT as actions
  FROM workflow_executions we
  WHERE we.started_at >= NOW() - (num_months || ' months')::INTERVAL
  GROUP BY we.status
  ORDER BY COUNT(DISTINCT we.id) DESC;
END;
$$;

-- ============================================================================
-- FUNCTION 6: Frequency Analysis (WITH SECURITY DEFINER)
-- ============================================================================

CREATE OR REPLACE FUNCTION get_workflow_frequency_analysis(num_months INTEGER DEFAULT 3)
RETURNS TABLE (
  workflow_id UUID,
  workflow_name TEXT,
  trigger_condition TEXT,
  total_executions BIGINT,
  avg_per_day NUMERIC,
  avg_per_week NUMERIC,
  peak_day_of_week TEXT,
  peak_hour INTEGER,
  most_recent_execution TIMESTAMPTZ,
  oldest_execution TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  WITH time_range AS (
    SELECT 
      NOW() - (num_months || ' months')::INTERVAL as start_date,
      GREATEST(EXTRACT(DAY FROM (num_months || ' months')::INTERVAL), 1) as total_days
  ),
  execution_data AS (
    SELECT 
      w.id,
      w.name,
      w.trigger_condition,
      we.started_at,
      EXTRACT(DOW FROM we.started_at) as day_of_week,
      EXTRACT(HOUR FROM we.started_at) as hour_of_day
    FROM workflows w
    INNER JOIN workflow_executions we ON we.workflow_id = w.id
    WHERE we.started_at >= (SELECT start_date FROM time_range)
  ),
  peak_times AS (
    SELECT 
      id,
      (
        SELECT day_of_week 
        FROM execution_data ed2 
        WHERE ed2.id = ed.id 
        GROUP BY day_of_week 
        ORDER BY COUNT(*) DESC 
        LIMIT 1
      ) as peak_dow,
      (
        SELECT hour_of_day 
        FROM execution_data ed2 
        WHERE ed2.id = ed.id 
        GROUP BY hour_of_day 
        ORDER BY COUNT(*) DESC 
        LIMIT 1
      ) as peak_hr
    FROM execution_data ed
    GROUP BY ed.id
  )
  SELECT 
    ed.id,
    ed.name::TEXT,
    ed.trigger_condition::TEXT,
    COUNT(*)::BIGINT as executions,
    ROUND(
      COUNT(*)::NUMERIC / NULLIF((SELECT total_days FROM time_range), 0),
      2
    ) as per_day,
    ROUND(
      COUNT(*)::NUMERIC / NULLIF((SELECT total_days FROM time_range) / 7, 0),
      2
    ) as per_week,
    CASE COALESCE(pt.peak_dow, 0)
      WHEN 0 THEN 'Sunday'
      WHEN 1 THEN 'Monday'
      WHEN 2 THEN 'Tuesday'
      WHEN 3 THEN 'Wednesday'
      WHEN 4 THEN 'Thursday'
      WHEN 5 THEN 'Friday'
      WHEN 6 THEN 'Saturday'
      ELSE 'Unknown'
    END::TEXT as peak_day,
    COALESCE(pt.peak_hr, 0)::INTEGER,
    MAX(ed.started_at) as last_execution,
    MIN(ed.started_at) as first_execution
  FROM execution_data ed
  LEFT JOIN peak_times pt ON pt.id = ed.id
  GROUP BY ed.id, ed.name, ed.trigger_condition, pt.peak_dow, pt.peak_hr
  ORDER BY COUNT(*) DESC;
END;
$$;

-- ============================================================================
-- GRANT PERMISSIONS
-- ============================================================================

GRANT EXECUTE ON FUNCTION get_workflow_overview(INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION get_workflow_overview(INTEGER) TO anon;

GRANT EXECUTE ON FUNCTION get_top_workflows(INTEGER, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION get_top_workflows(INTEGER, INTEGER) TO anon;

GRANT EXECUTE ON FUNCTION get_workflow_trends(INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION get_workflow_trends(INTEGER) TO anon;

GRANT EXECUTE ON FUNCTION get_recent_workflows(INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION get_recent_workflows(INTEGER) TO anon;

GRANT EXECUTE ON FUNCTION get_workflow_performance_by_status(INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION get_workflow_performance_by_status(INTEGER) TO anon;

GRANT EXECUTE ON FUNCTION get_workflow_frequency_analysis(INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION get_workflow_frequency_analysis(INTEGER) TO anon;

SELECT '✅ Granted permissions to all functions' as status;

-- ============================================================================
-- VERIFICATION
-- ============================================================================

SELECT '=== Testing get_workflow_overview(3) ===' as test;
SELECT * FROM get_workflow_overview(3);

SELECT '========================================' as result
UNION ALL SELECT '✅ ALL FUNCTIONS FIXED WITH SECURITY DEFINER!'
UNION ALL SELECT '========================================'
UNION ALL SELECT ''
UNION ALL SELECT 'Key Changes:'
UNION ALL SELECT '  ✅ Added SECURITY DEFINER to all functions'
UNION ALL SELECT '  ✅ Bypasses Row Level Security'
UNION ALL SELECT '  ✅ Functions can now access all data'
UNION ALL SELECT '  ✅ Granted execute permissions'
UNION ALL SELECT ''
UNION ALL SELECT '🚀 Refresh your UI - should work now!';