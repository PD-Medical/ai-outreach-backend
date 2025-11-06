# Email Sync System - Quick Reference

## 🚀 Quick Start

### 1. Deploy Everything
```bash
# Apply migrations
supabase db push

# Deploy functions
supabase functions deploy sync-emails
supabase functions deploy import-legacy-emails
supabase functions deploy toggle-cron-job
```

### 2. Configure Database
```sql
ALTER DATABASE postgres SET app.settings.supabase_url = 'https://[project-ref].supabase.co';
ALTER DATABASE postgres SET app.settings.service_role_key = '[service-role-key]';
```

### 3. Add Mailbox & Set Password
```sql
INSERT INTO mailboxes (email, name, imap_host, imap_port, is_active)
VALUES ('john@company.com', 'John', 'mail.company.com', 993, true)
RETURNING id;
```

```bash
supabase secrets set IMAP_PASSWORD_[mailbox_id_with_underscores]="password"
```

### 4. Import Legacy Data
```bash
curl -X POST https://[project-ref].supabase.co/functions/v1/import-legacy-emails \
  -H "Authorization: Bearer [service-role-key]" \
  -H "Content-Type: application/json" \
  -d '{"mailbox_id": "[id]", "folders": ["INBOX", "Sent"]}'
```

### 5. Enable Automated Sync
```bash
curl -X POST https://[project-ref].supabase.co/functions/v1/toggle-cron-job \
  -H "Authorization: Bearer [service-role-key]" \
  -d '{"enabled": true}'
```

---

## 🎛️ Environment Variables

### Set Configuration
```bash
# Performance tuning
supabase secrets set SYNC_BATCH_SIZE=50              # Emails per sync
supabase secrets set SYNC_TIMEOUT_MS=55000           # Max sync time
supabase secrets set MAX_CONCURRENT_MAILBOXES=5      # Parallel mailboxes

# Legacy import tuning
supabase secrets set IMPORT_BATCH_SIZE=50            # Emails per batch
supabase secrets set IMPORT_TIMEOUT_MS=55000         # Max import time
```

### Default Values
- `SYNC_BATCH_SIZE`: 50
- `SYNC_TIMEOUT_MS`: 55000 (55 seconds)
- `MAX_CONCURRENT_MAILBOXES`: 5
- `IMPORT_BATCH_SIZE`: 50
- `IMPORT_TIMEOUT_MS`: 55000 (55 seconds)

---

## 🔄 Cron Job Control

### Check Status
```bash
curl https://[project-ref].supabase.co/functions/v1/toggle-cron-job \
  -H "Authorization: Bearer [service-role-key]"
```

### Enable Sync
```bash
curl -X POST https://[project-ref].supabase.co/functions/v1/toggle-cron-job \
  -H "Authorization: Bearer [service-role-key]" \
  -d '{"enabled": true}'
```

### Disable Sync
```bash
curl -X POST https://[project-ref].supabase.co/functions/v1/toggle-cron-job \
  -H "Authorization: Bearer [service-role-key]" \
  -d '{"enabled": false}'
```

---

## 📊 Monitoring

### Check Sync Status
```sql
SELECT email, last_synced_at, sync_status 
FROM mailboxes 
ORDER BY last_synced_at DESC;
```

### View Cron Runs
```sql
SELECT * FROM cron.job_run_details 
WHERE jobname = 'sync-emails-every-minute'
ORDER BY start_time DESC LIMIT 10;
```

### Email Counts
```sql
SELECT 
  m.email,
  COUNT(e.id) as emails,
  COUNT(DISTINCT e.conversation_id) as conversations
FROM mailboxes m
LEFT JOIN emails e ON e.mailbox_id = m.id
GROUP BY m.email;
```

---

## 🔧 Common Tasks

### Add New Mailbox
```sql
-- 1. Insert mailbox
INSERT INTO mailboxes (email, name, imap_host, imap_port, is_active)
VALUES ('new@company.com', 'New User', 'mail.company.com', 993, true)
RETURNING id;

-- 2. Set password (replace hyphens with underscores)
```
```bash
supabase secrets set IMAP_PASSWORD_[mailbox_id]="password"
```

### Import Historical Data
```bash
# Start import
curl -X POST https://[project-ref].supabase.co/functions/v1/import-legacy-emails \
  -H "Authorization: Bearer [service-role-key]" \
  -H "Content-Type: application/json" \
  -d '{
    "mailbox_id": "[id]",
    "folders": ["INBOX", "Sent"],
    "start_date": "2024-01-01"
  }'

# Continue with resume_token if needed
curl -X POST https://[project-ref].supabase.co/functions/v1/import-legacy-emails \
  -H "Authorization: Bearer [service-role-key]" \
  -H "Content-Type: application/json" \
  -d '{
    "mailbox_id": "[id]",
    "resume_token": "INBOX:5050:1"
  }'
```

### Manual Sync Test
```bash
curl -X POST https://[project-ref].supabase.co/functions/v1/sync-emails \
  -H "Authorization: Bearer [service-role-key]"
```

### View Logs
```bash
supabase functions logs sync-emails
supabase functions logs import-legacy-emails
supabase functions logs toggle-cron-job
```

---

## 🐛 Troubleshooting

### IMAP Connection Failed
```bash
# Check secret exists
supabase secrets list

# Verify secret name format (underscores not hyphens)
# Correct:   IMAP_PASSWORD_550e8400_e29b_41d4_a716_446655440000
# Incorrect: IMAP_PASSWORD_550e8400-e29b-41d4-a716-446655440000
```

### No Emails Syncing
```sql
-- Check last synced UID
SELECT email, last_synced_uid FROM mailboxes;

-- Reset to re-import (if needed)
UPDATE mailboxes SET last_synced_uid = '{}' WHERE id = '[mailbox-id]';
```

### Cron Not Running
```sql
-- Check if cron job exists
SELECT * FROM cron.job WHERE jobname = 'sync-emails-every-minute';

-- Check database settings
SELECT current_setting('app.settings.supabase_url', true);
SELECT current_setting('app.settings.service_role_key', true);
```

### Function Timeout
```bash
# Reduce batch sizes
supabase secrets set SYNC_BATCH_SIZE=20
supabase secrets set MAX_CONCURRENT_MAILBOXES=2

# Redeploy
supabase functions deploy sync-emails
```

---

## 📱 UI Integration Example

```typescript
// React/Next.js example
import { useState, useEffect } from 'react';

function EmailSyncSettings() {
  const [cronEnabled, setCronEnabled] = useState(false);
  const [loading, setLoading] = useState(false);

  // Load status
  useEffect(() => {
    fetch(`${process.env.SUPABASE_URL}/functions/v1/toggle-cron-job`, {
      headers: { 'Authorization': `Bearer ${process.env.SERVICE_ROLE_KEY}` }
    })
    .then(r => r.json())
    .then(data => setCronEnabled(data.enabled));
  }, []);

  // Toggle handler
  const handleToggle = async () => {
    setLoading(true);
    try {
      const response = await fetch(
        `${process.env.SUPABASE_URL}/functions/v1/toggle-cron-job`,
        {
          method: 'POST',
          headers: {
            'Authorization': `Bearer ${process.env.SERVICE_ROLE_KEY}`,
            'Content-Type': 'application/json'
          },
          body: JSON.stringify({ enabled: !cronEnabled })
        }
      );
      const result = await response.json();
      if (result.success) {
        setCronEnabled(result.status.enabled);
      }
    } finally {
      setLoading(false);
    }
  };

  return (
    <div>
      <h2>Email Sync</h2>
      <label>
        <input 
          type="checkbox" 
          checked={cronEnabled} 
          onChange={handleToggle}
          disabled={loading}
        />
        Enable automatic sync
      </label>
      <p>{cronEnabled ? 'Syncing every minute' : 'Sync disabled'}</p>
    </div>
  );
}
```

---

## 📚 Documentation

- **[README.md](supabase/README.md)** - System overview
- **[DEPLOYMENT.md](supabase/DEPLOYMENT.md)** - Deployment guide
- **[ENV_VARS.md](supabase/functions/ENV_VARS.md)** - Environment variables
- **[CHANGES_SUMMARY.md](CHANGES_SUMMARY.md)** - Recent changes
- **[DEPLOYMENT_CHECKLIST.md](DEPLOYMENT_CHECKLIST.md)** - Step-by-step checklist

---

## 🎯 Deployment Workflow

```
1. Apply Migrations
   ↓
2. Deploy Functions
   ↓
3. Configure Database Settings
   ↓
4. Add Mailboxes & Passwords
   ↓
5. Import Legacy Data
   ↓
6. Enable Cron Job
   ↓
7. Monitor Sync
```

---

## 🔐 Security Checklist

- [ ] Service role key not in git
- [ ] IMAP passwords stored as secrets
- [ ] `.env` in `.gitignore`
- [ ] Database settings configured
- [ ] Functions deployed with latest code
- [ ] Secrets list reviewed
- [ ] Access logs monitored

---

## 📞 Support

**Check logs first:**
```bash
supabase functions logs [function-name]
```

**Common solutions:**
- IMAP errors → Check secrets
- No emails → Check CC deduplication
- Timeouts → Reduce batch size
- Cron not running → Check DB settings

**See [DEPLOYMENT.md](supabase/DEPLOYMENT.md) for detailed troubleshooting.**

