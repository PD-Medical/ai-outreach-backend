CREATE TABLE public.mailchimp_newsletter_events (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    event_type text,
    mailchimp_campaign_id text,
    payload jsonb NOT NULL DEFAULT '{}'::jsonb,
    processing_status text NOT NULL DEFAULT 'pending',
    processing_error text,
    processed_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.mailchimp_newsletters (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    mailchimp_campaign_id text NOT NULL UNIQUE,
    title text,
    subject text NOT NULL,
    normalized_subject text NOT NULL,
    from_name text,
    reply_to_email text,
    mailbox_id uuid REFERENCES public.mailboxes(id) ON DELETE SET NULL,
    audience_id text,
    archive_url text,
    status text NOT NULL DEFAULT 'sent',
    sent_at timestamp with time zone,
    html_content text,
    plain_content text,
    raw_payload jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE public.emails
    ADD COLUMN IF NOT EXISTS mailchimp_newsletter_id uuid REFERENCES public.mailchimp_newsletters(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS mailchimp_match_method text,
    ADD COLUMN IF NOT EXISTS mailchimp_match_confidence numeric(4,3),
    ADD COLUMN IF NOT EXISTS mailchimp_match_reason text;

CREATE INDEX idx_mailchimp_newsletters_normalized_subject
    ON public.mailchimp_newsletters (normalized_subject);

CREATE INDEX idx_mailchimp_newsletters_mailbox_sent_at
    ON public.mailchimp_newsletters (mailbox_id, sent_at DESC);

CREATE INDEX idx_mailchimp_newsletters_sent_at
    ON public.mailchimp_newsletters (sent_at DESC);

CREATE INDEX idx_mailchimp_newsletter_events_campaign_id
    ON public.mailchimp_newsletter_events (mailchimp_campaign_id, created_at DESC);

CREATE INDEX idx_emails_mailchimp_newsletter_id
    ON public.emails (mailchimp_newsletter_id)
    WHERE mailchimp_newsletter_id IS NOT NULL;

CREATE TRIGGER set_mailchimp_newsletters_updated_at
    BEFORE UPDATE ON public.mailchimp_newsletters
    FOR EACH ROW
    EXECUTE FUNCTION public.update_updated_at_column();

ALTER TABLE public.mailchimp_newsletter_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.mailchimp_newsletters ENABLE ROW LEVEL SECURITY;
