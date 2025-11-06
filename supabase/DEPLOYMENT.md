# Email Sync System - Deployment Guide

Complete guide for deploying and configuring the email synchronization system.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Initial Setup](#initial-setup)
3. [Database Migration](#database-migration)
4. [IMAP Password Management](#imap-password-management)
5. [Deploy Edge Functions](#deploy-edge-functions)
6. [Configure pg_cron](#configure-pg_cron)
7. [Testing](#testing)
8. [Monitoring](#monitoring)
9. [Troubleshooting](#troubleshooting)

---

## Prerequisites

- Supabase project created
- Supabase CLI installed: `npm install -g supabase`
- Git repository initialized
- Access to IMAP server credentials

### Install Supabase CLI

```bash
npm install -g supabase
```

### Login to Supabase

```bash
supabase login
```

### Link to Your Project

```bash
cd ai-outreach-backend
supabase link --project-ref [your-project-ref]
```

---

## Initial Setup

### 1. Get Your Project Details

From Supabase Dashboard → Project Settings → API:

- **Project URL**: `https://[your-project-ref].supabase.co`
- **Service Role Key**: `eyJhbG...` (keep secret!)

### 2. Set Local Environment Variables

Create `.env` file in `supabase/functions/`:

```bash
SUPABASE_URL=https://[your-project-ref].supabase.co
SUPABASE_SERVICE_ROLE_KEY=eyJhbG...
```

---

## Database Migration

### 1. Apply Migrations

```bash
# Apply all migrations
supabase db push

# Or apply specific migration
supabase db push --file supabase/migrations/20250101000000_initial_email_schema.sql
```

### 2. Verify Extensions

Run in Supabase SQL Editor:

```sql
-- Check extensions
SELECT * FROM pg_extension WHERE extname IN ('pg_cron', 'pg_net', 'pgcrypto');
```

Expected output:
```
extname   | extversion
----------|------------
pg_cron   | 1.4
pg_net    | 0.7.1
pgcrypto  | 1.3
```

### 3. Configure pg_cron Database Settings

**IMPORTANT**: Configure these settings for pg_cron to call Edge Functions.

In Supabase SQL Editor:

```sql
-- Set your Supabase URL
ALTER DATABASE postgres 
SET app.settings.supabase_url = 'https://[your-project-ref].supabase.co';

-- Set your service role key
ALTER DATABASE postgres 
SET app.settings.service_role_key = 'eyJhbG...';
```

**Verify configuration:**

```sql
SELECT current_setting('app.settings.supabase_url', true);
SELECT current_setting('app.settings.service_role_key', true);
```

---

## IMAP Password Management

### Strategy

IMAP passwords are stored as Supabase secrets with format: `IMAP_PASSWORD_{mailbox_id_with_underscores}`

**Why?**
- Secure: Not stored in database
- Per-mailbox: Each mailbox has its own secret
- Easy rotation: Update secrets without database changes

### 1. Add Mailbox to Database

```sql
INSERT INTO mailboxes (
  email, 
  name, 
  type, 
  imap_host, 
  imap_port, 
  imap_username,
  is_active
) VALUES (
  'john@pdmedical.com.au',
  'John Smith',
  'personal',
  'mail.pdmedical.com.au',
  993,
  'john@pdmedical.com.au',
  true
) RETURNING id;
```

**Copy the returned UUID** (e.g., `550e8400-e29b-41d4-a716-446655440000`)

### 2. Set IMAP Password Secret

Replace hyphens with underscores in the mailbox UUID:

```bash
# Example: mailbox_id = 550e8400-e29b-41d4-a716-446655440000
# Secret name = IMAP_PASSWORD_550e8400_e29b_41d4_a716_446655440000

supabase secrets set IMAP_PASSWORD_550e8400_e29b_41d4_a716_446655440000="your-imap-password"
```

### 3. Verify Secret

```bash
supabase secrets list
```

### Batch Secret Setup Script

For multiple mailboxes, create a script:

```bash
#!/bin/bash
# setup-imap-secrets.sh

# Mailbox 1
supabase secrets set IMAP_PASSWORD_550e8400_e29b_41d4_a716_446655440000="password1"

# Mailbox 2
supabase secrets set IMAP_PASSWORD_661f9511_f3ac_52e5_b827_557766551111="password2"

# Mailbox 3
supabase secrets set IMAP_PASSWORD_772fa622_g4bd_63f6_c938_668877662222="password3"
```

---

## Deploy Edge Functions

### 1. Deploy sync-emails Function

```bash
supabase functions deploy sync-emails
```

**Expected output:**
```
✓ Function sync-emails deployed successfully
Function URL: https://[project-ref].supabase.co/functions/v1/sync-emails
```

### 2. Deploy import-legacy-emails Function

```bash
supabase functions deploy import-legacy-emails
```

### 3. Verify Functions

```bash
supabase functions list
```

### 4. Test Functions Locally (Optional)

```bash
# Start local Supabase
supabase start

# Serve function locally
supabase functions serve sync-emails --env-file supabase/functions/.env

# Test with curl
curl -X POST http://localhost:54321/functions/v1/sync-emails \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer [your-anon-key]" \
  -d '{}'
```

---

## Configure pg_cron

### Verify Cron Job

The cron job should be created by the migration. Verify:

```sql
SELECT * FROM cron.job WHERE jobname = 'sync-emails-every-minute';
```

Expected output:
```
jobid | schedule     | command                    | nodename
------|--------------|----------------------------|----------
1     | * * * * *    | SELECT net.http_post(...)  | localhost
```

### Manual Cron Job Creation (if needed)

If the job wasn't created by migration:

```sql
SELECT cron.schedule(
  'sync-emails-every-minute',
  '* * * * *',  -- Every minute
  $$
  SELECT net.http_post(
    url := current_setting('app.settings.supabase_url', true) || '/functions/v1/sync-emails',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || current_setting('app.settings.service_role_key', true)
    ),
    body := jsonb_build_object(
      'triggered_at', now(),
      'source', 'pg_cron'
    ),
    timeout_milliseconds := 55000
  ) AS request_id;
  $$
);
```

### Modify Cron Schedule

Change from every minute to every 5 minutes:

```sql
-- Unschedule existing
SELECT cron.unschedule('sync-emails-every-minute');

-- Schedule with new interval
SELECT cron.schedule(
  'sync-emails-every-5-minutes',
  '*/5 * * * *',  -- Every 5 minutes
  $$ [same command as above] $$
);
```

---

## Testing

### 1. Test Sync Function Manually

```bash
curl -X POST https://[project-ref].supabase.co/functions/v1/sync-emails \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer [service-role-key]" \
  -d '{}'
```

**Expected response:**
```json
{
  "success": true,
  "message": "Synced 2 mailbox(es)",
  "stats": {
    "mailboxes_synced": 2,
    "successful_syncs": 2,
    "total_emails_imported": 15,
    "duration_ms": 8234
  }
}
```

### 2. Test Legacy Import Function

```bash
curl -X POST https://[project-ref].supabase.co/functions/v1/import-legacy-emails \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer [service-role-key]" \
  -d '{
    "mailbox_id": "550e8400-e29b-41d4-a716-446655440000",
    "folders": ["INBOX", "Sent"],
    "start_date": "2024-01-01",
    "end_date": "2025-01-01"
  }'
```

**Expected response:**
```json
{
  "completed": false,
  "processed": 50,
  "total_imported": 48,
  "resume_token": "INBOX:5050:1",
  "next_folder": "INBOX"
}
```

**Continue import with resume token:**
```bash
curl -X POST https://[project-ref].supabase.co/functions/v1/import-legacy-emails \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer [service-role-key]" \
  -d '{
    "mailbox_id": "550e8400-e29b-41d4-a716-446655440000",
    "folders": ["INBOX", "Sent"],
    "resume_token": "INBOX:5050:1"
  }'
```

### 3. Verify Data in Database

```sql
-- Check imported emails
SELECT COUNT(*) FROM emails;

-- Check conversations
SELECT 
  c.subject,
  c.email_count,
  c.last_email_at,
  m.email as mailbox_email
FROM conversations c
JOIN mailboxes m ON m.id = c.mailbox_id
ORDER BY c.last_email_at DESC
LIMIT 10;

-- Check contacts
SELECT COUNT(*) FROM contacts;

-- Check organizations
SELECT name, domain, (
  SELECT COUNT(*) FROM contacts WHERE organization_id = co.id
) as contact_count
FROM organizations co
ORDER BY contact_count DESC;
```

---

## Monitoring

### View Cron Job Runs

```sql
-- Last 10 cron job runs
SELECT 
  jobid,
  runid,
  job_pid,
  database,
  username,
  command,
  status,
  return_message,
  start_time,
  end_time
FROM cron.job_run_details 
WHERE jobname = 'sync-emails-every-minute'
ORDER BY start_time DESC 
LIMIT 10;
```

### Check for Failed Runs

```sql
-- Failed cron runs
SELECT *
FROM cron.job_run_details 
WHERE jobname = 'sync-emails-every-minute'
  AND status = 'failed'
ORDER BY start_time DESC;
```

### View Mailbox Sync Status

```sql
-- Check sync status for all mailboxes
SELECT 
  email,
  name,
  is_active,
  last_synced_at,
  last_synced_uid,
  sync_status
FROM mailboxes
ORDER BY last_synced_at DESC;
```

### View Edge Function Logs

From Supabase Dashboard:
1. Go to **Edge Functions**
2. Select **sync-emails** or **import-legacy-emails**
3. Click **Logs** tab
4. Filter by time range and log level

Or use CLI:

```bash
supabase functions logs sync-emails
```

### Monitor Email Import Stats

```sql
-- Emails imported per day (last 7 days)
SELECT 
  DATE(created_at) as date,
  COUNT(*) as emails_imported,
  COUNT(DISTINCT mailbox_id) as mailboxes,
  COUNT(DISTINCT conversation_id) as conversations
FROM emails
WHERE created_at > NOW() - INTERVAL '7 days'
GROUP BY DATE(created_at)
ORDER BY date DESC;

-- Emails per mailbox
SELECT 
  m.email,
  COUNT(e.id) as email_count,
  COUNT(DISTINCT e.conversation_id) as conversation_count,
  MAX(e.received_at) as latest_email
FROM mailboxes m
LEFT JOIN emails e ON e.mailbox_id = m.id
GROUP BY m.email
ORDER BY email_count DESC;
```

---

## Troubleshooting

### Issue: Cron Job Not Running

**Check if job is scheduled:**
```sql
SELECT * FROM cron.job;
```

**Check database settings:**
```sql
SELECT current_setting('app.settings.supabase_url', true);
SELECT current_setting('app.settings.service_role_key', true);
```

**Check recent runs:**
```sql
SELECT * FROM cron.job_run_details 
ORDER BY start_time DESC LIMIT 5;
```

### Issue: IMAP Connection Failed

**Check secret name format:**
- Must use underscores, not hyphens
- Format: `IMAP_PASSWORD_{mailbox_id_with_underscores}`

**Verify secret exists:**
```bash
supabase secrets list
```

**Check mailbox credentials:**
```sql
SELECT id, email, imap_host, imap_port, imap_username, is_active 
FROM mailboxes WHERE id = '[mailbox-id]';
```

**Test IMAP connection manually:**
```bash
# Use openssl to test IMAP connection
openssl s_client -connect mail.pdmedical.com.au:993

# Then try to login
a1 LOGIN username@domain.com password
a2 LIST "" "*"
a3 LOGOUT
```

### Issue: No Emails Being Imported

**Check CC deduplication:**
- Emails where mailbox is only CC'd are skipped
- Verify `to_emails` field contains the mailbox email

**Check last_synced_uid:**
```sql
SELECT email, last_synced_uid FROM mailboxes;
```

**Reset last_synced_uid to re-import:**
```sql
UPDATE mailboxes 
SET last_synced_uid = '{}'::jsonb 
WHERE id = '[mailbox-id]';
```

### Issue: Edge Function Timeout

**For sync-emails:**
- Reduce number of concurrent mailboxes (MAX_CONCURRENT in code)
- Reduce batch size (limit parameter in fetchEmails)

**For import-legacy-emails:**
- Already supports resume tokens
- Continue calling with resume_token until completed

### Issue: Duplicate Emails

**Check constraints:**
```sql
-- Should show unique constraints
\d emails
```

**Find duplicates:**
```sql
SELECT message_id, COUNT(*) 
FROM emails 
GROUP BY message_id 
HAVING COUNT(*) > 1;
```

**Remove duplicates (keep newest):**
```sql
DELETE FROM emails
WHERE id IN (
  SELECT id FROM (
    SELECT id, ROW_NUMBER() OVER (
      PARTITION BY message_id 
      ORDER BY created_at DESC
    ) as rn
    FROM emails
  ) t
  WHERE rn > 1
);
```

---

## Performance Optimization

### Add Additional Indexes

If queries are slow, add more indexes:

```sql
-- For searching emails by sender
CREATE INDEX IF NOT EXISTS idx_emails_from_email_received 
ON emails(from_email, received_at DESC);

-- For folder-specific queries
CREATE INDEX IF NOT EXISTS idx_emails_folder_received 
ON emails(mailbox_id, imap_folder, received_at DESC);

-- For unread emails
CREATE INDEX IF NOT EXISTS idx_emails_seen_received 
ON emails(is_seen, received_at DESC) WHERE NOT is_seen;
```

### Database Maintenance

```sql
-- Vacuum and analyze tables
VACUUM ANALYZE emails;
VACUUM ANALYZE conversations;
VACUUM ANALYZE contacts;
VACUUM ANALYZE organizations;
```

---

## Security Best Practices

1. **Service Role Key**: Never commit to git or expose publicly
2. **IMAP Passwords**: Always use Supabase secrets, never store in database
3. **RLS Policies**: Consider adding Row Level Security for production
4. **API Keys**: Rotate periodically
5. **Audit Logs**: Monitor Edge Function logs for suspicious activity

---

## Backup and Recovery

### Backup Database

```bash
# Export all data
supabase db dump -f backup.sql

# Or use pg_dump directly
pg_dump -h [db-host] -U postgres -d postgres > backup.sql
```

### Restore from Backup

```bash
psql -h [db-host] -U postgres -d postgres < backup.sql
```

---

## Support

For issues or questions:

1. Check [Supabase Documentation](https://supabase.com/docs)
2. Review Edge Function logs
3. Check cron job execution history
4. Test IMAP connection manually

---

## Quick Reference

### Essential Commands

```bash
# Deploy functions
supabase functions deploy sync-emails
supabase functions deploy import-legacy-emails

# View logs
supabase functions logs sync-emails

# Set secrets
supabase secrets set IMAP_PASSWORD_[mailbox_id]="password"

# Apply migrations
supabase db push
```

### Essential Queries

```sql
-- Check cron job
SELECT * FROM cron.job;

-- Check recent runs
SELECT * FROM cron.job_run_details ORDER BY start_time DESC LIMIT 10;

-- Check sync status
SELECT email, last_synced_at, sync_status FROM mailboxes;

-- Count emails
SELECT COUNT(*) FROM emails;
```


