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
-- FUNCTION 1: Workflow Overview Stats (NO CHANGES NEEDED)
-- ============================================================================

CREATE OR REPLACE FUNCTION get_workflow_overview(num_months INTEGER DEFAULT 3)
RETURNS TABLE (
  active_workflows BIGINT,
  contacts_in_workflows BIGINT,
  workflow_emails_sent BIGINT,
  workflow_open_rate NUMERIC,
  workflow_click_rate NUMERIC,
  executions_this_month BIGINT
) AS $$
BEGIN
  RETURN QUERY
  WITH workflow_stats AS (
    SELECT 
      COUNT(DISTINCT w.id) FILTER (WHERE w.is_active = true)::BIGINT as active,
      COUNT(DISTINCT ccs.contact_id) FILTER (WHERE ccs.workflow_emails_sent > 0)::BIGINT as contacts,
      SUM(ccs.workflow_emails_sent)::BIGINT as sent,
      ROUND(
        SUM(ccs.workflow_emails_opened)::NUMERIC / 
        NULLIF(SUM(ccs.workflow_emails_sent), 0) * 100, 
        1
      ) as open_rate,
      ROUND(
        SUM(ccs.workflow_emails_clicked)::NUMERIC / 
        NULLIF(SUM(ccs.workflow_emails_sent), 0) * 100, 
        1
      ) as click_rate
    FROM campaign_contact_summary ccs
    CROSS JOIN workflows w
    WHERE ccs.last_event_at >= NOW() - (num_months || ' months')::INTERVAL
      AND ccs.workflow_emails_sent > 0
  ),
  this_month AS (
    SELECT 
      COUNT(DISTINCT we.id)::BIGINT as executions_this_month
    FROM workflow_executions we
    WHERE we.started_at >= DATE_TRUNC('month', NOW())
      AND we.status = 'completed'
  )
  SELECT 
    ws.active,
    ws.contacts,
    ws.sent,
    COALESCE(ws.open_rate, 0),
    COALESCE(ws.click_rate, 0),
    tm.executions_this_month
  FROM workflow_stats ws, this_month tm;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- FUNCTION 2: Top Performing Workflows (FIXED)
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
  contacts_reached BIGINT,
  emails_sent BIGINT,
  emails_opened BIGINT,
  emails_clicked BIGINT,
  open_rate NUMERIC,
  click_rate NUMERIC,
  engagement_score BIGINT
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    w.id,
    w.name::TEXT,                        -- Cast VARCHAR to TEXT
    COALESCE(w.description, '')::TEXT,   -- Cast VARCHAR to TEXT, handle NULL
    w.trigger_condition::TEXT,           -- Cast to TEXT
    w.is_active,
    COUNT(DISTINCT we.id)::BIGINT as executions,
    COUNT(DISTINCT we.contact_id)::BIGINT as contacts,
    COUNT(*) FILTER (WHERE ce.event_type = 'sent')::BIGINT as sent,
    COUNT(*) FILTER (WHERE ce.event_type = 'opened')::BIGINT as opens,
    COUNT(*) FILTER (WHERE ce.event_type = 'clicked')::BIGINT as clicks,
    ROUND(
      COUNT(*) FILTER (WHERE ce.event_type = 'opened')::NUMERIC / 
      NULLIF(COUNT(*) FILTER (WHERE ce.event_type = 'sent'), 0) * 100,
      1
    ) as open_rate,
    ROUND(
      COUNT(*) FILTER (WHERE ce.event_type = 'clicked')::NUMERIC / 
      NULLIF(COUNT(*) FILTER (WHERE ce.event_type = 'sent'), 0) * 100,
      1
    ) as click_rate,
    (
      COUNT(*) FILTER (WHERE ce.event_type = 'opened') * 10 +
      COUNT(*) FILTER (WHERE ce.event_type = 'clicked') * 25
    )::BIGINT as score
  FROM workflows w
  LEFT JOIN workflow_executions we ON we.workflow_id = w.id
  LEFT JOIN campaign_events ce ON ce.workflow_execution_id = we.id
  WHERE we.started_at >= NOW() - (num_months || ' months')::INTERVAL
    AND we.started_at IS NOT NULL
  GROUP BY w.id, w.name, w.description, w.trigger_condition, w.is_active
  HAVING COUNT(*) FILTER (WHERE ce.event_type = 'sent') > 0
  ORDER BY (
    COUNT(*) FILTER (WHERE ce.event_type = 'opened') * 10 +
    COUNT(*) FILTER (WHERE ce.event_type = 'clicked') * 25
  ) DESC
  LIMIT limit_count;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- FUNCTION 3: Workflow Trends (NO CHANGES NEEDED)
-- ============================================================================

CREATE OR REPLACE FUNCTION get_workflow_trends(num_months INTEGER DEFAULT 6)
RETURNS TABLE (
  month TEXT,
  month_start TIMESTAMPTZ,
  workflows_executed BIGINT,
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
    COUNT(DISTINCT we.id)::BIGINT as executions,
    COUNT(DISTINCT we.contact_id)::BIGINT as contacts,
    ROUND(
      COUNT(*) FILTER (WHERE ce.event_type = 'opened')::NUMERIC / 
      NULLIF(COUNT(*) FILTER (WHERE ce.event_type = 'sent'), 0) * 100,
      1
    ) as open_rate,
    ROUND(
      COUNT(*) FILTER (WHERE ce.event_type = 'clicked')::NUMERIC / 
      NULLIF(COUNT(*) FILTER (WHERE ce.event_type = 'sent'), 0) * 100,
      1
    ) as click_rate
  FROM months m
  LEFT JOIN workflow_executions we ON 
    we.started_at >= m.month_start 
    AND we.started_at < m.month_end
  LEFT JOIN campaign_events ce ON ce.workflow_execution_id = we.id
  GROUP BY m.month_label, m.month_start, m.sort_order
  ORDER BY m.month_start ASC;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- FUNCTION 4: Recent Workflow Executions (FIXED)
-- ============================================================================

CREATE OR REPLACE FUNCTION get_recent_workflows(limit_count INTEGER DEFAULT 10)
RETURNS TABLE (
  workflow_id UUID,
  workflow_name TEXT,
  execution_id UUID,
  contact_id UUID,
  contact_email TEXT,           -- Changed from VARCHAR
  started_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  status TEXT,
  emails_sent BIGINT,
  emails_opened BIGINT,
  emails_clicked BIGINT,
  days_ago INTEGER
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    w.id,
    w.name::TEXT,                      -- Cast VARCHAR to TEXT
    we.id,
    we.contact_id,
    COALESCE(c.email, '')::TEXT,       -- Cast VARCHAR to TEXT, handle NULL
    we.started_at,
    we.completed_at,
    COALESCE(we.status, 'unknown')::TEXT,  -- Cast, handle NULL
    COUNT(*) FILTER (WHERE ce.event_type = 'sent')::BIGINT,
    COUNT(*) FILTER (WHERE ce.event_type = 'opened')::BIGINT,
    COUNT(*) FILTER (WHERE ce.event_type = 'clicked')::BIGINT,
    EXTRACT(DAY FROM NOW() - we.started_at)::INTEGER
  FROM workflow_executions we
  INNER JOIN workflows w ON w.id = we.workflow_id
  LEFT JOIN contacts c ON c.id = we.contact_id
  LEFT JOIN campaign_events ce ON ce.workflow_execution_id = we.id
  WHERE we.started_at IS NOT NULL
  GROUP BY w.id, w.name, we.id, we.contact_id, c.email, we.started_at, we.completed_at, we.status
  ORDER BY we.started_at DESC
  LIMIT limit_count;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- FUNCTION 5: Workflow Performance by Status (NO CHANGES NEEDED)
-- ============================================================================

CREATE OR REPLACE FUNCTION get_workflow_performance_by_status(num_months INTEGER DEFAULT 3)
RETURNS TABLE (
  workflow_status TEXT,
  execution_count BIGINT,
  avg_open_rate NUMERIC,
  avg_click_rate NUMERIC,
  total_engagement_score BIGINT
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    COALESCE(we.status, 'unknown')::TEXT,  -- Handle NULL status
    COUNT(DISTINCT we.id)::BIGINT as count,
    ROUND(
      COUNT(*) FILTER (WHERE ce.event_type = 'opened')::NUMERIC / 
      NULLIF(COUNT(*) FILTER (WHERE ce.event_type = 'sent'), 0) * 100,
      1
    ) as open_rate,
    ROUND(
      COUNT(*) FILTER (WHERE ce.event_type = 'clicked')::NUMERIC / 
      NULLIF(COUNT(*) FILTER (WHERE ce.event_type = 'sent'), 0) * 100,
      1
    ) as click_rate,
    (
      COUNT(*) FILTER (WHERE ce.event_type = 'opened') * 10 +
      COUNT(*) FILTER (WHERE ce.event_type = 'clicked') * 25
    )::BIGINT as score
  FROM workflow_executions we
  LEFT JOIN campaign_events ce ON ce.workflow_execution_id = we.id
  WHERE we.started_at >= NOW() - (num_months || ' months')::INTERVAL
  GROUP BY we.status
  HAVING COUNT(*) FILTER (WHERE ce.event_type = 'sent') > 0
  ORDER BY COUNT(DISTINCT we.id) DESC;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- BONUS FUNCTION: Workflow vs Campaign Comparison (NO CHANGES NEEDED)
-- ============================================================================

CREATE OR REPLACE FUNCTION get_workflow_campaign_comparison(num_months INTEGER DEFAULT 3)
RETURNS TABLE (
  metric TEXT,
  workflow_value BIGINT,
  campaign_value BIGINT,
  workflow_percentage NUMERIC
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    'Emails Sent'::TEXT,
    SUM(workflow_emails_sent)::BIGINT,
    SUM(emails_sent - workflow_emails_sent)::BIGINT,
    ROUND(100.0 * SUM(workflow_emails_sent) / NULLIF(SUM(emails_sent), 0), 2)
  FROM campaign_contact_summary
  WHERE last_event_at >= NOW() - (num_months || ' months')::INTERVAL
  
  UNION ALL
  
  SELECT 
    'Emails Opened'::TEXT,
    SUM(workflow_emails_opened)::BIGINT,
    SUM(emails_opened - workflow_emails_opened)::BIGINT,
    ROUND(100.0 * SUM(workflow_emails_opened) / NULLIF(SUM(emails_opened), 0), 2)
  FROM campaign_contact_summary
  WHERE last_event_at >= NOW() - (num_months || ' months')::INTERVAL
  
  UNION ALL
  
  SELECT 
    'Emails Clicked'::TEXT,
    SUM(workflow_emails_clicked)::BIGINT,
    SUM(emails_clicked - workflow_emails_clicked)::BIGINT,
    ROUND(100.0 * SUM(workflow_emails_clicked) / NULLIF(SUM(emails_clicked), 0), 2)
  FROM campaign_contact_summary
  WHERE last_event_at >= NOW() - (num_months || ' months')::INTERVAL;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- WORKFLOW VERIFICATION QUERIES
-- ============================================================================

SELECT '=== Testing Workflow Overview ===' as test;
SELECT * FROM get_workflow_overview(3);

SELECT '=== Testing Top Workflows ===' as test;
SELECT * FROM get_top_workflows(3, 5);

SELECT '=== Testing Workflow Trends ===' as test;
SELECT * FROM get_workflow_trends(6);

SELECT '=== Testing Recent Workflows ===' as test;
SELECT * FROM get_recent_workflows(5);

SELECT '=== Testing Performance by Status ===' as test;
SELECT * FROM get_workflow_performance_by_status(3);

SELECT '=== Testing Workflow vs Campaign Comparison ===' as test;
SELECT * FROM get_workflow_campaign_comparison(3);

