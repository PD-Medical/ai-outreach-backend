ALTER TABLE public.mailchimp_newsletters ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.mailchimp_newsletter_events ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS mailchimp_newsletters_select_policy
ON public.mailchimp_newsletters;

CREATE POLICY mailchimp_newsletters_select_policy
ON public.mailchimp_newsletters
FOR SELECT
USING (public.has_permission('view_analytics'::text));

DROP POLICY IF EXISTS mailchimp_newsletter_events_select_policy
ON public.mailchimp_newsletter_events;

CREATE POLICY mailchimp_newsletter_events_select_policy
ON public.mailchimp_newsletter_events
FOR SELECT
USING (public.has_permission('view_analytics'::text));
