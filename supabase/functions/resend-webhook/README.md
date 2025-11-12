# Resend Webhook Function

This Supabase Edge Function ingests Resend webhook events (send, delivery, opens, clicks, bounces, complaints) and writes engagement data into the campaign tracking tables created by `20250210000000_campaign_tracking.sql`.

## Environment

Store secrets with Supabase CLI (never commit them):

```sh
supabase secrets set RESEND_WEBHOOK_SECRET="your_resend_webhook_signing_secret"
supabase secrets set SUPABASE_SERVICE_ROLE_KEY="your_service_role_key"
supabase secrets set SUPABASE_URL="https://<your-project-ref>.supabase.co"
```

If you also need to call Resend's REST API, add:

```sh
supabase secrets set RESEND_API_KEY="your_resend_api_key"
```

## Webhook Setup

1. In Resend, create a webhook pointing to the deployed function URL (e.g. `https://<project>.functions.supabase.co/resend-webhook`).
2. Copy the signing secret from Resend and set it as `RESEND_WEBHOOK_SECRET`.
3. Tag outgoing messages with either:
   - `campaign_id` equal to the UUID of the row in `public.campaigns`, **or**
   - `campaign_external_id` that matches the `campaigns.external_id` column.

## Event Mapping

| Resend event         | Stored `campaign_events.event_type` | Score delta |
|----------------------|--------------------------------------|-------------|
| `email.sent`         | `sent`                               | +1          |
| `email.delivered`    | `delivered`                          | +2      |
| `email.opened`       | `opened`                             | +3        |
| `email.clicked`      | `clicked`                            | +4       |
| `email.bounced`      | `bounced`                            | -10      |
| `email.complained`   | `complained`                         | -25       |

The function also keeps `campaign_contact_summary` in sync with cumulative scores and flags.

