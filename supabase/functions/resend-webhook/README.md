# Resend Engagement Tracking Integration

Complete guide to track email engagement using Resend and automatically calculate engagement scores.

## 📊 What This Does

Tracks **11 types of engagement signals** from your email campaigns:

| Signal | Score | Priority | Description |
|--------|-------|----------|-------------|
| **Pricing Link Click** | +10 | HIGH | Clicked pricing/quote link - Ready to buy |
| **Product Link Click** | +8 | MEDIUM | Clicked product page - Active research |
| **Attachment Download** | +8 | MEDIUM | Downloaded PDF/brochure - Researching |
| **Multiple Opens** | +7 | MEDIUM | Opened 3+ times - Strong interest |
| **Case Study Click** | +6 | MEDIUM | Clicked case study - Validation phase |
| **Email Opened** | +5 | LOW | First open - Basic engagement |
| **Quick Open** | +3 | LOW | Opened <1 hour - Highly responsive |
| **Mobile Open** | +2 | LOW | Opened on mobile - On-the-go |
| **Unsubscribe** | -50 | CRITICAL | Unsubscribed - Suppress immediately |
| **Spam Report** | -30 | CRITICAL | Marked spam - Suppress immediately |
| **Not Opened** | 0 | LOW | Not opened after 7 days - No interest |

## 🚀 Setup Guide

### Step 1: Apply Database Migration

```bash
# Start local Supabase (if not already running)
supabase start

# Apply the engagement tracking migration
supabase db reset  # This will apply all migrations including the new one
```

### Step 2: Deploy Webhook Function

```bash
# Deploy the Resend webhook handler
supabase functions deploy resend-webhook

# Set your Resend API key
supabase secrets set RESEND_API_KEY=re_fGdBimAP_6KA2or2tPtE4tcVMjLEvjhPi
```

### Step 3: Configure Resend Webhook

1. Go to Resend Dashboard: https://resend.com/webhooks
2. Click "Add Webhook"
3. Enter your webhook URL:
   ```
   https://[your-project-ref].supabase.co/functions/v1/resend-webhook
   ```
4. Select events to track:
   - ✅ `email.opened`
   - ✅ `email.clicked`
   - ✅ `email.complained` (spam reports)
   - ✅ `email.unsubscribed`
5. Save the webhook

### Step 4: Test the Integration

Send a test email via Resend and open/click it to verify tracking works.

## 📧 How to Send Tracked Emails via Resend

### Example: Send Email with Tracking Links

```typescript
// Example using Resend SDK
import { Resend } from 'resend';

const resend = new Resend('re_fGdBimAP_6KA2or2tPtE4tcVMjLEvjhPi');

await resend.emails.send({
  from: 'peter@pdmedical.com.au',
  to: 'customer@hospital.com',
  subject: 'New Product Launch - Medical Supplies',
  html: `
    <h1>New Product Launch</h1>
    <p>We're excited to introduce our latest medical equipment...</p>
    
    <!-- PRICING LINK (will score +10) -->
    <a href="https://pdmedical.com.au/pricing?product=ultrasound">
      Request a Quote
    </a>
    
    <!-- PRODUCT LINK (will score +8) -->
    <a href="https://pdmedical.com.au/products/ultrasound-machine">
      View Product Details
    </a>
    
    <!-- CASE STUDY LINK (will score +6) -->
    <a href="https://pdmedical.com.au/case-studies/melbourne-hospital">
      Read Customer Success Story
    </a>
    
    <!-- DOWNLOAD LINK (will score +8) -->
    <a href="https://pdmedical.com.au/downloads/product-brochure.pdf">
      Download Product Brochure
    </a>
  `,
  tags: [
    { name: 'campaign', value: 'product-launch-2025' },
    { name: 'category', value: 'ultrasound' }
  ]
});
```

### Link Detection Rules

The system automatically detects link types based on URL patterns:

**Pricing Links** (Score: +10):
- URLs containing: `pricing`, `quote`, `price`, `buy`, `purchase`, `order`
- Examples: `/pricing`, `/request-quote`, `/buy-now`

**Case Study Links** (Score: +6):
- URLs containing: `case-study`, `testimonial`, `success-story`, `customer-story`
- Examples: `/case-studies/`, `/testimonials`, `/success-stories/`

**Download Links** (Score: +8):
- URLs containing: `download`, `attachment`, `pdf`, `brochure`, `catalog`
- Examples: `/downloads/`, `/brochure.pdf`, `/catalog`

**Product Links** (Score: +8):
- All other links default to product clicks

## 📊 Engagement Scoring System

### Engagement Levels

Contacts are automatically categorized based on total score:

- **VERY_HOT** (>50) - Extremely engaged, ready to buy
- **HOT** (31-50) - Highly engaged, strong interest
- **WARM** (11-30) - Moderately engaged
- **NEUTRAL** (0-10) - Low engagement
- **COLD** (<0) - Negative engagement or suppressed

### Flags

Contacts are automatically flagged based on behavior:

- `is_highly_engaged` - Total score > 30
- `is_ready_to_buy` - Has pricing link clicks
- `is_active_researcher` - Has downloads or product clicks
- `is_validation_phase` - Has case study clicks
- `is_suppressed` - Unsubscribed or spam report

## 🤖 Automated Actions

Each engagement signal triggers automated actions:

### HIGH Priority: Pricing Link Click (+10)
- ✅ Notify sales team within 4 hours
- ✅ Start quote preparation workflow
- ✅ Flag as "Hot Lead"
- ✅ Add to "Ready to Buy" segment

### MEDIUM Priority: Product/Download Click (+8)
- ✅ Add to product interest segment
- ✅ Schedule follow-up in 2 days
- ✅ Enroll in nurture track
- ✅ Send related content

### CRITICAL Priority: Unsubscribe/Spam (-50/-30)
- ⚠️ **IMMEDIATE suppression** (<1 hour - LEGAL REQUIREMENT)
- ⚠️ Cancel ALL scheduled emails
- ⚠️ Update contact status to unsubscribed/bounced
- ⚠️ Log IP and timestamp for audit

## 📈 View Engagement Data

### SQL Queries

```sql
-- View top engaged contacts
SELECT 
  c.email,
  c.first_name,
  c.last_name,
  es.total_score,
  es.engagement_level,
  es.is_ready_to_buy,
  es.last_engagement_at
FROM contacts c
JOIN engagement_scores es ON es.contact_id = c.id
ORDER BY es.total_score DESC
LIMIT 20;

-- View recent engagement signals
SELECT 
  email,
  signal_type,
  score_value,
  priority,
  event_timestamp,
  link_url
FROM engagement_signals
ORDER BY event_timestamp DESC
LIMIT 50;

-- View hot leads (ready to buy)
SELECT 
  c.email,
  c.first_name,
  c.last_name,
  es.total_score,
  es.pricing_clicks,
  es.product_clicks,
  es.last_engagement_at
FROM contacts c
JOIN engagement_scores es ON es.contact_id = c.id
WHERE es.is_ready_to_buy = true
ORDER BY es.last_engagement_at DESC;

-- View automated actions triggered
SELECT 
  al.action_type,
  al.action_description,
  al.status,
  c.email,
  es.signal_type,
  al.triggered_at
FROM automated_actions_log al
JOIN contacts c ON c.id = al.contact_id
JOIN engagement_signals es ON es.id = al.engagement_signal_id
ORDER BY al.triggered_at DESC
LIMIT 20;
```

### Dashboard Metrics

```sql
-- Campaign performance summary
SELECT 
  signal_type,
  COUNT(*) as count,
  SUM(score_value) as total_score,
  AVG(score_value) as avg_score
FROM engagement_signals
WHERE event_timestamp > NOW() - INTERVAL '30 days'
GROUP BY signal_type
ORDER BY total_score DESC;

-- Engagement level distribution
SELECT 
  engagement_level,
  COUNT(*) as contact_count,
  ROUND(AVG(total_score), 2) as avg_score
FROM engagement_scores
GROUP BY engagement_level
ORDER BY 
  CASE engagement_level
    WHEN 'VERY_HOT' THEN 1
    WHEN 'HOT' THEN 2
    WHEN 'WARM' THEN 3
    WHEN 'NEUTRAL' THEN 4
    WHEN 'COLD' THEN 5
  END;
```

## 🧪 Testing Locally

### 1. Start Local Services

```bash
# Start Supabase
supabase start

# Apply migrations
supabase db reset

# Serve webhook function
supabase functions serve resend-webhook --env-file supabase/functions/.env.local --no-verify-jwt
```

### 2. Send Test Webhook

```bash
# Test pricing click (HIGH priority)
curl -X POST http://127.0.0.1:54321/functions/v1/resend-webhook \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0.EGIM96RAZx35lJzdJsyH-qQwv8Hdp7fsn3W0YpN81IU" \
  -d '{
    "type": "email.clicked",
    "created_at": "'$(date -u +"%Y-%m-%dT%H:%M:%SZ")'",
    "data": {
      "email_id": "test-123",
      "email": "test@hospital.com",
      "click": {
        "link": "https://pdmedical.com.au/pricing"
      },
      "user_agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"
    }
  }'

# Test email open
curl -X POST http://127.0.0.1:54321/functions/v1/resend-webhook \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0.EGIM96RAZx35lJzdJsyH-qQwv8Hdp7fsn3W0YpN81IU" \
  -d '{
    "type": "email.opened",
    "created_at": "'$(date -u +"%Y-%m-%dT%H:%M:%SZ")'",
    "data": {
      "email_id": "test-123",
      "email": "test@hospital.com",
      "user_agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 14_0 like Mac OS X)"
    }
  }'
```

### 3. Verify in Database

Go to http://127.0.0.1:54323 (Supabase Studio) and check:
- `engagement_signals` table - Should see the test signals
- `engagement_scores` table - Should see calculated scores
- `automated_actions_log` table - Should see triggered actions

## 🔒 Security & Compliance

### GDPR/CAN-SPAM Compliance

- **Unsubscribe**: Automatically suppressed within 1 hour (LEGAL REQUIREMENT)
- **Spam Reports**: Immediately suppressed and logged
- **Audit Trail**: All actions logged with timestamps and IP addresses
- **Data Retention**: Configure retention policies for engagement data

### Webhook Security

Add webhook signature verification (recommended for production):

```typescript
// In resend-webhook/index.ts, add:
const svixId = req.headers.get('svix-id');
const svixTimestamp = req.headers.get('svix-timestamp');
const svixSignature = req.headers.get('svix-signature');

// Verify webhook signature (Resend uses Svix)
// See: https://docs.svix.com/receiving/verifying-payloads/how
```

## 📚 Additional Resources

- **Resend Docs**: https://resend.com/docs
- **Resend Webhooks**: https://resend.com/docs/dashboard/webhooks/introduction
- **Supabase Edge Functions**: https://supabase.com/docs/guides/functions

## 🆘 Troubleshooting

### Webhook not receiving events

1. Check Resend webhook configuration
2. Verify webhook URL is correct
3. Check Supabase function logs: `supabase functions logs resend-webhook`
4. Test with curl command above

### Scores not updating

1. Check `engagement_signals` table for new records
2. Verify trigger is enabled: `SELECT * FROM pg_trigger WHERE tgname = 'trigger_update_engagement_score'`
3. Check for errors in function logs

### Contact not found

The webhook handler looks for existing contacts by email. If no contact exists:
- The signal is still recorded (with `contact_id` = NULL)
- Create contact first or modify webhook handler to auto-create

## 📝 Next Steps

1. ✅ Apply database migration
2. ✅ Deploy webhook function
3. ✅ Configure Resend webhook
4. ⬜ Send test campaign
5. ⬜ Verify tracking works
6. ⬜ Build dashboard to view engagement data
7. ⬜ Integrate automated actions with your CRM/sales tools



