# Local Development Guide

## ✅ Setup Complete!

Your local Supabase is running and all migrations have been applied.

## 🎯 Local Environment

### Access URLs

- **API URL**: http://127.0.0.1:54321
- **Database URL**: postgresql://postgres:postgres@127.0.0.1:54322/postgres
- **Studio URL**: http://127.0.0.1:54323 (Database UI)
- **Mailpit URL**: http://127.0.0.1:54324 (Email testing)

### Keys (for local development)

- **Anon Key**: `eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0`
- **Service Role Key**: `eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0.EGIM96RAZx35lJzdJsyH-qQwv8Hdp7fsn3W0YpN81IU`

---

## 🚀 Quick Start

### 1. View Database in Studio

Open in browser:
```
http://127.0.0.1:54323
```

Check that all tables are created:
- mailboxes
- organizations
- contacts
- conversations
- emails

### 2. Add a Test Mailbox

Open Studio SQL Editor (http://127.0.0.1:54323) and run:

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
  'test@pdmedical.com.au',
  'Test User',
  'personal',
  'mail.pdmedical.com.au',
  993,
  'test@pdmedical.com.au',
  true
) RETURNING id, email;
```

**Copy the returned mailbox ID** (e.g., `550e8400-e29b-41d4-a716-446655440000`)

### 3. Set IMAP Password

Edit `supabase/functions/.env.local` and add:

```bash
# Replace with your actual mailbox ID and password
IMAP_PASSWORD_550e8400_e29b_41d4_a716_446655440000=your-actual-password
```

**Note**: Replace hyphens with underscores in the mailbox ID!

### 4. Configure Database Settings for pg_cron

Run in Studio SQL Editor:

```sql
ALTER DATABASE postgres SET app.settings.supabase_url = 'http://host.docker.internal:54321';
ALTER DATABASE postgres SET app.settings.service_role_key = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0.EGIM96RAZx35lJzdJsyH-qQwv8Hdp7fsn3W0YpN81IU';
```

**Important**: Use `host.docker.internal` instead of `127.0.0.1` so pg_cron can reach Edge Functions from within Docker.

---

## 🧪 Testing Edge Functions Locally

### Test sync-emails Function

```bash
# Serve the function locally
supabase functions serve sync-emails --env-file supabase/functions/.env.local --no-verify-jwt
```

In another terminal:

```bash
curl -X POST http://127.0.0.1:54321/functions/v1/sync-emails \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0.EGIM96RAZx35lJzdJsyH-qQwv8Hdp7fsn3W0YpN81IU" \
  -d '{}'
```

### Test import-legacy-emails Function

```bash
# Serve the function
supabase functions serve import-legacy-emails --env-file supabase/functions/.env.local --no-verify-jwt
```

In another terminal:

```bash
curl -X POST http://127.0.0.1:54321/functions/v1/import-legacy-emails \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0.EGIM96RAZx35lJzdJsyH-qQwv8Hdp7fsn3W0YpN81IU" \
  -d '{
    "mailbox_id": "550e8400-e29b-41d4-a716-446655440000",
    "folders": ["INBOX"],
    "start_date": "2024-01-01"
  }'
```

### Test toggle-cron-job Function

```bash
# Serve the function
supabase functions serve toggle-cron-job --env-file supabase/functions/.env.local --no-verify-jwt
```

In another terminal:

```bash
# Get status
curl http://127.0.0.1:54321/functions/v1/toggle-cron-job \
  -H "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0.EGIM96RAZx35lJzdJsyH-qQwv8Hdp7fsn3W0YpN81IU"

# Enable cron
curl -X POST http://127.0.0.1:54321/functions/v1/toggle-cron-job \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0.EGIM96RAZx35lJzdJsyH-qQwv8Hdp7fsn3W0YpN81IU" \
  -d '{"enabled": true}'
```

---

## 📊 Monitoring Local Data

### View Data in Studio

http://127.0.0.1:54323

Navigate to:
- Table Editor → View/edit data
- SQL Editor → Run custom queries

### Common Queries

```sql
-- Check mailboxes
SELECT * FROM mailboxes;

-- Check imported emails
SELECT COUNT(*) FROM emails;

-- Check conversations
SELECT 
  c.subject,
  c.email_count,
  c.last_email_at
FROM conversations c
ORDER BY c.last_email_at DESC
LIMIT 10;

-- Check contacts
SELECT * FROM contacts LIMIT 10;

-- Check cron job status
SELECT * FROM cron.job WHERE jobname = 'sync-emails-every-minute';

-- Check recent cron runs
SELECT * FROM cron.job_run_details 
WHERE jobname = 'sync-emails-every-minute'
ORDER BY start_time DESC 
LIMIT 10;
```

---

## 🔄 Common Commands

### Restart Local Supabase

```bash
supabase stop
supabase start
```

### Reset Database (Reapply Migrations)

```bash
supabase db reset
```

### View Logs

```bash
# Database logs
supabase logs --db

# All logs
supabase logs
```

### Stop Local Supabase

```bash
supabase stop
```

### Connect to Local Database

```bash
# Using psql
psql postgresql://postgres:postgres@127.0.0.1:54322/postgres

# Or use Studio
open http://127.0.0.1:54323
```

---

## 🐛 Troubleshooting

### IMAP Connection Fails

1. Check `.env.local` has correct password
2. Verify secret name format (underscores not hyphens)
3. Test IMAP connection manually:

```bash
openssl s_client -connect mail.pdmedical.com.au:993
# Then type: a1 LOGIN username password
```

### Function Not Loading Environment Variables

Make sure to use `--env-file` flag:

```bash
supabase functions serve [function-name] --env-file supabase/functions/.env.local
```

### Cron Job Not Working

1. Check database settings:

```sql
SELECT current_setting('app.settings.supabase_url', true);
SELECT current_setting('app.settings.service_role_key', true);
```

2. Use `host.docker.internal` instead of `localhost` for pg_cron to reach functions

3. Check cron logs:

```sql
SELECT * FROM cron.job_run_details 
ORDER BY start_time DESC LIMIT 5;
```

### Migration Errors

```bash
# Reset and reapply
supabase db reset

# Or manually apply specific migration
supabase db push --file supabase/migrations/[migration-file].sql
```

---

## 📝 Development Workflow

### 1. Local Testing
```
Start local Supabase → Add test data → Test functions → Verify results
```

### 2. Make Changes
```
Edit code → Reset DB (if schema changed) → Test again
```

### 3. Deploy to Production
```
Link to remote → Push migrations → Deploy functions → Set secrets
```

---

## 🎯 Next Steps

1. ✅ Local Supabase running
2. ✅ Migrations applied
3. ⬜ Add test mailbox
4. ⬜ Set IMAP password in `.env.local`
5. ⬜ Test sync-emails function
6. ⬜ Test import-legacy-emails function
7. ⬜ Enable cron job (optional)
8. ⬜ When ready, deploy to production

---

## 🔐 Security Note

The local development keys shown here are **only for local testing** and are safe to commit.

**Never commit**:
- Production Supabase URL
- Production Service Role Key
- Real IMAP passwords
- `.env` file (use `.env.local` for local dev)

---

## 📚 Additional Resources

- [Supabase Local Development](https://supabase.com/docs/guides/cli/local-development)
- [Edge Functions Guide](https://supabase.com/docs/guides/functions)
- [Database Migrations](https://supabase.com/docs/guides/cli/local-development#database-migrations)


