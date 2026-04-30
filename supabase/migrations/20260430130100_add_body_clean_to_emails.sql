-- Issue #124 — body_clean column for cleanly-stripped reply text
-- The current body_plain stores compounded reply chains when the parser fails
-- (lambda_email_sync.py extract_replies_and_signature() falls back to the full
-- original body). This causes quadratic content growth on long threads and
-- pollutes downstream LLM context windows.
--
-- The fix: a parallel column body_clean populated by a multi-stage stripping
-- pipeline in the email-sync lambda. Consumers prefer body_clean and fall back
-- to body_plain for rows that haven't been re-processed yet. body_plain is
-- kept raw for forensic value.
--
-- No SQL backfill — the cleaning pipeline is Python (mailparser_reply +
-- HTML→text). NULL body_clean rows fall back to body_plain in consumers; a
-- separate Python backfill job can repopulate historical rows later.

ALTER TABLE public.emails
    ADD COLUMN IF NOT EXISTS body_clean text;

COMMENT ON COLUMN public.emails.body_clean IS
    'Multi-stage-stripped reply text (mailparser_reply + Outlook separator + RFC reply markers + > quoted lines + HTML→text fallback). Consumers should prefer this over body_plain, which is kept raw. NULL means the row pre-dates the cleaning pipeline; consumer falls back to body_plain.';
