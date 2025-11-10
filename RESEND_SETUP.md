# 🚀 Resend Engagement Tracking - Quick Setup

## Your API Key
```
re_fGdBimAP_6KA2or2tPtE4tcVMjLEvjhPi
```

## ⚡ 5-Minute Setup

### 1. Install Docker Desktop (if not already done)
Download: https://www.docker.com/products/docker-desktop

### 2. Start Local Environment

```powershell
# In PowerShell
cd C:\Users\binil\Desktop\ai-outreach-backend

# Start Supabase (first time takes 2-3 minutes)
supabase start

# Apply migrations (includes engagement tracking)
supabase db reset
```

### 3. Deploy Functions

```powershell
# Deploy webhook handler
supabase functions deploy resend-webhook

# Deploy email sender
supabase functions deploy send-tracked-email

# Set Resend API key
supabase secrets set RESEND_API_KEY=re_fGdBimAP_6KA2or2tPtE4tcVMjLEvjhPi
```

### 4. Configure Resend Webhook

1. Go to: https://resend.com/webhooks
2. Click "Add Webhook"
3. Enter URL: `https://[your-project].supabase.co/functions/v1/resend-webhook`
4. Select events:
   - ✅ email.opened
   - ✅ email.clicked
   - ✅ email.complained
   - ✅ email.unsubscribed
5. Save

## 📊 How It Works

### Engagement Signals (11 Types)

| Action | Score | What Happens |
|--------|-------|--------------|
| **Click "Request Quote"** | +10 | 🔥 Sales team notified, flagged as hot lead |
| **Click Product Link** | +8 | 📧 Follow-up scheduled in 2 days |
| **Download PDF** | +8 | 📚 Nurture sequence started |
| **Open Email 3+ Times** | +7 | 🎯 Marked as highly interested |
| **Click Case Study** | +6 | 📖 Related content sent |
| **Open Email** | +5 | ✅ Basic engagement tracked |
| **Open <1 Hour** | +3 | ⚡ Bonus for quick response |
| **Open on Mobile** | +2 | 📱 Mobile user tagged |
| **Unsubscribe** | -50 | ⚠️ Suppressed immediately (LEGAL) |
| **Mark as Spam** | -30 | ⚠️ Permanently suppressed |
| **Not Opened (7 days)** | 0 | 😴 Re-engagement attempted |

### Engagement Levels

- **VERY_HOT** (>50) - Ready to buy, contact sales NOW
- **HOT** (31-50) - High interest, priority follow-up
- **WARM** (11-30) - Engaged, nurture campaign
- **NEUTRAL** (0-10) - Basic engagement
- **COLD** (<0) - Suppressed or negative

## 📧 Send Tracked Email

### Option 1: Via API

```powershell
# Send test email
curl -X POST https://[your-project].supabase.co/functions/v1/send-tracked-email \
  -H "Authorization: Bearer [YOUR_ANON_KEY]" \
  -H "Content-Type: application/json" \
  -d '{
    "to": "customer@hospital.com",
    "subject": "New Product Launch",
    "html": "<h1>Hi!</h1><p>Check out our new product:</p><a href=\"https://pdmedical.com.au/pricing\">Get a Quote</a>",
    "campaign_name": "Product Launch 2025"
  }'
```

### Option 2: Via Resend Dashboard

1. Go to https://resend.com/emails
2. Compose email
3. Add tracking links:
   - Pricing: `https://your-site.com/pricing` → Auto-tracked as +10
   - Product: `https://your-site.com/products/item` → Auto-tracked as +8
   - Download: `https://your-site.com/downloads/brochure.pdf` → Auto-tracked as +8

### Link Types Detected Automatically

The system auto-detects link types:

```html
<!-- HIGH PRIORITY: Pricing Links (+10) -->
<a href="https://pdmedical.com.au/pricing">Request Quote</a>
<a href="https://pdmedical.com.au/buy-now">Buy Now</a>

<!-- MEDIUM: Product Links (+8) -->
<a href="https://pdmedical.com.au/products/ultrasound">View Product</a>

<!-- MEDIUM: Downloads (+8) -->
<a href="https://pdmedical.com.au/downloads/brochure.pdf">Download PDF</a>

<!-- MEDIUM: Case Studies (+6) -->
<a href="https://pdmedical.com.au/case-studies/hospital-success">Read Story</a>
```

## 📈 View Engagement Data

### In Supabase Studio

1. Open: http://127.0.0.1:54323 (local) or https://supabase.com/dashboard
2. Go to Table Editor
3. View tables:
   - `engagement_signals` - Individual events
   - `engagement_scores` - Contact scores
   - `automated_actions_log` - Actions triggered

### SQL Queries

```sql
-- Top 20 most engaged contacts
SELECT 
  c.email,
  c.first_name,
  c.last_name,
  es.total_score,
  es.engagement_level,
  es.is_ready_to_buy,
  es.pricing_clicks,
  es.product_clicks,
  es.last_engagement_at
FROM contacts c
JOIN engagement_scores es ON es.contact_id = c.id
ORDER BY es.total_score DESC
LIMIT 20;

-- Hot leads (clicked pricing)
SELECT 
  c.email,
  es.total_score,
  es.pricing_clicks,
  es.last_engagement_at
FROM contacts c
JOIN engagement_scores es ON es.contact_id = c.id
WHERE es.is_ready_to_buy = true
ORDER BY es.last_engagement_at DESC;

-- Recent engagement activity
SELECT 
  email,
  signal_type,
  score_value,
  priority,
  link_url,
  event_timestamp
FROM engagement_signals
ORDER BY event_timestamp DESC
LIMIT 50;
```

## 🔄 Automated Actions

Each signal triggers specific actions:

### Pricing Click (+10) - HIGH PRIORITY
```
✅ Sales notification sent
✅ Quote preparation started
✅ Contact flagged as "Hot Lead"
✅ Added to "Ready to Buy" segment
```

### Product Click (+8) - MEDIUM PRIORITY
```
✅ Added to product interest segment
✅ Follow-up scheduled in 2 days
✅ Product-specific nurture track started
```

### Unsubscribe (-50) - CRITICAL
```
⚠️ IMMEDIATE suppression (<1 hour - LEGAL)
⚠️ ALL emails cancelled
⚠️ Contact status updated
⚠️ Confirmation sent
⚠️ Audit trail logged
```

## 🧪 Testing

### Test Webhook Locally

```powershell
# Terminal 1: Start function
supabase functions serve resend-webhook --env-file supabase/functions/.env.local --no-verify-jwt

# Terminal 2: Send test event
curl -X POST http://127.0.0.1:54321/functions/v1/resend-webhook \
  -H "Content-Type: application/json" \
  -d '{
    "type": "email.clicked",
    "created_at": "2025-01-01T10:00:00Z",
    "data": {
      "email_id": "test-123",
      "email": "test@hospital.com",
      "click": {
        "link": "https://pdmedical.com.au/pricing"
      }
    }
  }'
```

### Verify in Database

```sql
-- Check if signal was recorded
SELECT * FROM engagement_signals 
WHERE email = 'test@hospital.com' 
ORDER BY created_at DESC;

-- Check if score was calculated
SELECT * FROM engagement_scores 
WHERE contact_id IN (
  SELECT id FROM contacts WHERE email = 'test@hospital.com'
);

-- Check automated actions
SELECT * FROM automated_actions_log 
WHERE contact_id IN (
  SELECT id FROM contacts WHERE email = 'test@hospital.com'
);
```

## 📊 Dashboard Ideas

Build a dashboard showing:

1. **Engagement Overview**
   - Total contacts by engagement level
   - Average engagement score
   - Engagement trend over time

2. **Hot Leads**
   - Contacts with pricing clicks
   - Score > 30
   - Recent engagement < 7 days

3. **Campaign Performance**
   - Open rate, click rate
   - Engagement signals per campaign
   - ROI by signal type

4. **Automated Actions**
   - Actions triggered today
   - Pending actions
   - Success rate

## 🔐 Security & Compliance

### GDPR/CAN-SPAM Compliance

✅ **Automatic unsubscribe handling** (<1 hour)  
✅ **Audit trail** (IP, timestamp, all actions logged)  
✅ **Data retention policies** (configurable)  
✅ **Right to be forgotten** (cascade delete on contact removal)

### Webhook Security

For production, add signature verification:

```typescript
// Verify Resend/Svix webhook signature
const svixId = req.headers.get('svix-id');
const svixTimestamp = req.headers.get('svix-timestamp');
const svixSignature = req.headers.get('svix-signature');

// Verify signature using Svix library
// See: https://docs.svix.com/receiving/verifying-payloads/how
```

## 📞 Need Help?

**Common Issues:**

- **Docker not installed**: Install from https://www.docker.com/products/docker-desktop
- **Webhook not receiving**: Check URL, verify events selected in Resend
- **Scores not updating**: Check trigger is enabled, view function logs
- **Contact not found**: Create contact first or modify webhook to auto-create

**Resources:**

- Resend Docs: https://resend.com/docs
- Supabase Docs: https://supabase.com/docs
- Full Guide: See `supabase/functions/resend-webhook/README.md`

## ✅ Next Steps

1. ✅ Install Docker Desktop
2. ✅ Run `supabase start`
3. ✅ Deploy functions
4. ✅ Configure Resend webhook
5. ⬜ Send test email
6. ⬜ Verify tracking works
7. ⬜ Build dashboard
8. ⬜ Integrate with sales CRM




