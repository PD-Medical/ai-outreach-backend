-- 20260501010500_emails_enrichment_backfill.sql
-- Backfill: emails with non-null ai_processed_at are 'enriched';
-- old ones (>30 days) without are 'skipped'; the rest stay 'pending' so the
-- enrich_pending cron can drain them at a sustainable rate.
--
-- Both UPDATEs run in 5,000-row chunks to avoid holding row locks for minutes
-- on tables with millions of rows. Each chunk is its own statement; progress
-- is logged via RAISE NOTICE so a long backfill is observable in the migration log.
--
-- The 30-day cutoff is a deployment cutover heuristic, not a long-term retention
-- policy — operators can manually flip specific rows back to 'pending' to enrich
-- older emails on demand.

DO $$
DECLARE
  v_rows  INTEGER;
  v_total INTEGER := 0;
BEGIN
  LOOP
    WITH chunk AS (
      SELECT id
      FROM emails
      WHERE enrichment_status = 'pending'
        AND ai_processed_at IS NOT NULL
      LIMIT 5000
    )
    UPDATE emails AS e
    SET enrichment_status = 'enriched',
        enriched_at = COALESCE(e.ai_processed_at, e.updated_at, e.created_at)
    FROM chunk
    WHERE e.id = chunk.id;

    GET DIAGNOSTICS v_rows = ROW_COUNT;
    v_total := v_total + v_rows;
    EXIT WHEN v_rows = 0;
    RAISE NOTICE 'enrichment backfill (enriched): % rows updated this batch, % so far', v_rows, v_total;
  END LOOP;
  RAISE NOTICE 'enrichment backfill complete: % rows marked enriched', v_total;
END $$;

DO $$
DECLARE
  v_rows  INTEGER;
  v_total INTEGER := 0;
  v_cutoff TIMESTAMPTZ := now() - interval '30 days';
BEGIN
  LOOP
    WITH chunk AS (
      SELECT id
      FROM emails
      WHERE enrichment_status = 'pending'
        AND created_at < v_cutoff
      LIMIT 5000
    )
    UPDATE emails AS e
    SET enrichment_status = 'skipped'
    FROM chunk
    WHERE e.id = chunk.id;

    GET DIAGNOSTICS v_rows = ROW_COUNT;
    v_total := v_total + v_rows;
    EXIT WHEN v_rows = 0;
    RAISE NOTICE 'enrichment backfill (skipped): % rows updated this batch, % so far', v_rows, v_total;
  END LOOP;
  RAISE NOTICE 'enrichment backfill complete: % rows marked skipped (>30 days old)', v_total;
END $$;
