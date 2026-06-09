-- Exact email category counts for the Emails page tabs.
--
-- The frontend previously fetched conversation IDs directly from PostgREST.
-- PostgREST caps result sets at 1000 rows by default, which made the "All"
-- tab look static once production had more than 1000 active conversations.

CREATE OR REPLACE FUNCTION public.get_conversation_category_counts(
  p_mailbox_id uuid DEFAULT NULL,
  p_show_internal boolean DEFAULT FALSE
)
RETURNS TABLE(
  all_count bigint,
  business_count bigint,
  spam_count bigint,
  personal_count bigint,
  other_count bigint
)
LANGUAGE sql
STABLE
SECURITY INVOKER
AS $$
  WITH active_conversations AS (
    SELECT c.id
    FROM public.conversations c
    WHERE c.status = 'active'
      AND c.email_count > 0
      AND (p_mailbox_id IS NULL OR c.mailbox_id = p_mailbox_id)
  ),
  ranked_emails AS (
    SELECT
      e.conversation_id,
      COALESCE(e.email_category, '') AS email_category,
      COALESCE(e.is_internal, FALSE) AS is_internal,
      ROW_NUMBER() OVER (
        PARTITION BY e.conversation_id
        ORDER BY
          CASE
            WHEN COALESCE(e.message_kind::text, 'human') <> 'auto_reply' THEN 0
            ELSE 1
          END,
          e.received_at DESC,
          e.created_at DESC,
          e.id DESC
      ) AS rn
    FROM public.emails e
    JOIN active_conversations c ON c.id = e.conversation_id
    WHERE COALESCE(e.is_deleted, FALSE) = FALSE
  ),
  latest_emails AS (
    SELECT email_category
    FROM ranked_emails
    WHERE rn = 1
      AND (p_show_internal OR is_internal = FALSE)
  )
  SELECT
    COUNT(*) AS all_count,
    COUNT(*) FILTER (WHERE email_category LIKE 'business-%') AS business_count,
    COUNT(*) FILTER (WHERE email_category LIKE 'spam-%') AS spam_count,
    COUNT(*) FILTER (WHERE email_category LIKE 'personal-%') AS personal_count,
    COUNT(*) FILTER (
      WHERE email_category NOT LIKE 'business-%'
        AND email_category NOT LIKE 'spam-%'
        AND email_category NOT LIKE 'personal-%'
    ) AS other_count
  FROM latest_emails;
$$;

COMMENT ON FUNCTION public.get_conversation_category_counts(uuid, boolean) IS
  'Returns exact active conversation counts by latest display email category for the Emails page. Avoids PostgREST 1000-row caps and mirrors the UI preference for latest non-auto-reply messages.';

GRANT EXECUTE ON FUNCTION public.get_conversation_category_counts(uuid, boolean) TO authenticated;
