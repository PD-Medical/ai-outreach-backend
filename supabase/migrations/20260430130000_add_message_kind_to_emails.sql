-- Issue #125 — Auto-reply detection
-- Adds emails.message_kind so OOO / vacation auto-replies are distinguishable from
-- human messages in the UI and downstream consumers. OOO workflow matching is
-- intentionally NOT changed (auto-replies must continue to fire OOO workflows).
--
-- Detection signals (RFC 3834 + practice):
--   - Auto-Submitted: auto-replied | auto-generated | auto-notified
--   - X-Autoreply: yes
--   - Precedence: auto_reply | bulk | junk
--   - X-Auto-Response-Suppress present
--   - Subject prefix: "Automatic reply:" / "Out of Office:" / "OOO:" / "Auto-Reply:"

DO $$ BEGIN
    CREATE TYPE public.email_message_kind AS ENUM ('human', 'auto_reply', 'bounce', 'system');
EXCEPTION
    WHEN duplicate_object THEN NULL;
END $$;

ALTER TABLE public.emails
    ADD COLUMN IF NOT EXISTS message_kind public.email_message_kind NOT NULL DEFAULT 'human';

CREATE INDEX IF NOT EXISTS idx_emails_message_kind
    ON public.emails (message_kind)
    WHERE message_kind <> 'human';

-- Backfill from existing emails.headers (jsonb) and subject. No IMAP re-fetch needed.
-- Keys in emails.headers are stored lowercase by lambda_email_sync.py.
WITH header_signal AS (
    SELECT
        id,
        lower(coalesce(headers->>'auto-submitted', '')) AS auto_submitted,
        lower(coalesce(headers->>'x-autoreply', ''))    AS x_autoreply,
        lower(coalesce(headers->>'precedence', ''))     AS precedence,
        headers ? 'x-auto-response-suppress'            AS has_x_auto_response_suppress,
        coalesce(subject, '')                           AS subject_text
    FROM public.emails
)
UPDATE public.emails e
   SET message_kind = 'auto_reply'
  FROM header_signal h
 WHERE h.id = e.id
   AND e.message_kind = 'human'
   AND (
        h.auto_submitted IN ('auto-replied', 'auto-generated', 'auto-notified')
     OR h.x_autoreply = 'yes'
     OR h.precedence  IN ('auto_reply', 'bulk', 'junk')
     OR h.has_x_auto_response_suppress
     OR h.subject_text ~* '^(automatic reply:|out of office:|ooo:|auto-reply:)'
   );

COMMENT ON COLUMN public.emails.message_kind IS
    'Structural classification: human | auto_reply | bounce | system. Set by email-sync lambda from RFC 3834 headers and subject patterns. Used for UI distinction and to anchor "latest human reply" — does NOT suppress workflow matching (OOO workflows still fire on auto_reply rows).';
