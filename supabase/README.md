# Email Sync System

Automated email synchronization system for Supabase with IMAP integration, email threading, and conversation management.

## Overview

This system automatically syncs emails from IMAP servers into a Supabase database, organizing them into threaded conversations with full contact and organization management.

### Key Features

- ✅ **Automated Sync**: pg_cron triggers email sync every minute
- ✅ **Email Threading**: Groups related emails using Message-ID, References, and In-Reply-To headers
- ✅ **CC Deduplication**: Only imports emails where mailbox is primary recipient (not just CC'd)
- ✅ **Contact Management**: Auto-creates contacts and organizations from email addresses
- ✅ **Conversation Tracking**: Tracks email counts, last email, and response requirements
- ✅ **Legacy Import**: Batch import historical emails with resume capability
- ✅ **Multiple Mailboxes**: Supports syncing multiple IMAP accounts
- ✅ **IMAP Flags**: Preserves read, flagged, answered, draft, and deleted states

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                       Supabase Database                      │
├─────────────────────────────────────────────────────────────┤
│  Tables:                                                     │
│  • mailboxes (email accounts)                               │
│  • organizations (companies)                        │
│  • contacts (individuals)                                    │
│  • conversations (email threads)                             │
│  • emails (individual messages)                              │
└─────────────────────────────────────────────────────────────┘
                              ▲
                              │
┌─────────────────────────────┼─────────────────────────────┐
│                      pg_cron (every 1 min)                  │
│                             │                               │
│  SELECT net.http_post(                                      │
│    url := 'https://[project].supabase.co/functions/v1/     │
│             sync-emails',                                   │
│    ...                                                      │
│  )                                                          │
└─────────────────────────────┼─────────────────────────────┘
                              ▼
┌─────────────────────────────────────────────────────────────┐
│              Edge Function: sync-emails                      │
├─────────────────────────────────────────────────────────────┤
│  1. Fetch all active mailboxes                              │
│  2. For each mailbox:                                       │
│     - Connect to IMAP server                                │
│     - Fetch new emails (INBOX, Sent)                        │
│     - Parse and apply CC deduplication                      │
│     - Create thread IDs                                     │
│     - Import emails (create contacts/orgs/conversations)    │
│     - Update sync status                                    │
└─────────────────────────────────────────────────────────────┘
                              ▲
                              │
┌─────────────────────────────┼─────────────────────────────┐
│         Shared Email Utilities (_shared/email/)             │
├─────────────────────────────────────────────────────────────┤
│  • types.ts - TypeScript interfaces                         │
│  • imap-client.ts - IMAP connection & fetching              │
│  • thread-builder.ts - Thread ID creation                   │
│  • email-parser.ts - Email parsing & CC deduplication       │
│  • db-operations.ts - Database CRUD operations              │
└─────────────────────────────────────────────────────────────┘
                              ▲
                              │
┌─────────────────────────────┼─────────────────────────────┐
│         IMAP Servers (e.g., mail.pdmedical.com.au)         │
└─────────────────────────────────────────────────────────────┘
```

## File Structure

```
supabase/
├── migrations/
│   ├── 20250101000000_initial_email_schema.sql    # Database schema
│   └── 20250101000001_setup_email_sync_cron.sql   # pg_cron setup
│
├── functions/
│   ├── _shared/
│   │   └── email/
│   │       ├── types.ts              # TypeScript types
│   │       ├── imap-client.ts        # IMAP connection
│   │       ├── thread-builder.ts     # Email threading
│   │       ├── email-parser.ts       # Email parsing
│   │       └── db-operations.ts      # Database ops
│   │
│   ├── sync-emails/
│   │   └── index.ts                  # Incremental sync (cron)
│   │
│   └── import-legacy-emails/
│       └── index.ts                  # Legacy batch import
│
├── DEPLOYMENT.md                     # Deployment guide
└── README.md                         # This file
```

## Quick Start

### 1. Deploy Database

```bash
# Apply migrations
supabase db push
```

### 2. Configure pg_cron

In Supabase SQL Editor:

```sql
ALTER DATABASE postgres SET app.settings.supabase_url = 'https://[project-ref].supabase.co';
ALTER DATABASE postgres SET app.settings.service_role_key = '[service-role-key]';
```

### 3. Add Mailbox

```sql
INSERT INTO mailboxes (email, name, type, imap_host, imap_port, imap_username, is_active)
VALUES ('john@example.com', 'John Smith', 'personal', 'mail.example.com', 993, 'john@example.com', true)
RETURNING id;
```

### 4. Set IMAP Password

```bash
# Replace hyphens with underscores in mailbox UUID
supabase secrets set IMAP_PASSWORD_[mailbox_id_with_underscores]="your-password"
```

### 5. Deploy Functions

```bash
supabase functions deploy sync-emails
supabase functions deploy import-legacy-emails
```

### 6. Test

```bash
# Manual sync test
curl -X POST https://[project-ref].supabase.co/functions/v1/sync-emails \
  -H "Authorization: Bearer [service-role-key]" \
  -d '{}'
```

## Email Threading Algorithm

The system creates thread IDs using this algorithm:

1. **Parse References Header**: Extract all Message-IDs from the `References` header
2. **Find Root**: Use the first Message-ID in References as the thread root
3. **Fallback to In-Reply-To**: If no References, use `In-Reply-To` as parent
4. **New Thread**: If neither exist, this email starts a new thread
5. **Generate Thread ID**: Hash the root Message-ID to create `thread-{hash}`

**Example:**
```
Email 1: <msg-001@example.com>
  → Thread ID: thread-a1b2c3d4e5f6g7h8

Email 2: In-Reply-To: <msg-001@example.com>
         References: <msg-001@example.com>
  → Thread ID: thread-a1b2c3d4e5f6g7h8 (same thread)

Email 3: In-Reply-To: <msg-002@example.com>
         References: <msg-001@example.com> <msg-002@example.com>
  → Thread ID: thread-a1b2c3d4e5f6g7h8 (same thread, root is msg-001)
```

## CC Deduplication

To prevent duplicate imports when multiple mailboxes are CC'd:

**Import email if:**
- Direction = `outgoing` (sent by this mailbox) ✅
- Direction = `incoming` AND mailbox in `to_emails` ✅

**Skip email if:**
- Mailbox only in `cc_emails` ❌

**Example:**
```
Email: 
  From: customer@example.com
  To: sales@company.com
  Cc: support@company.com, john@company.com

Result:
  ✅ Imported to sales@company.com (in To field)
  ❌ Skipped for support@company.com (only CC'd)
  ❌ Skipped for john@company.com (only CC'd)
```

## Monitoring

### Check Sync Status

```sql
SELECT email, last_synced_at, sync_status 
FROM mailboxes 
ORDER BY last_synced_at DESC;
```

### View Cron Job Runs

```sql
SELECT * FROM cron.job_run_details 
WHERE jobname = 'sync-emails-every-minute'
ORDER BY start_time DESC LIMIT 10;
```

### Email Import Stats

```sql
SELECT 
  m.email,
  COUNT(e.id) as email_count,
  COUNT(DISTINCT e.conversation_id) as conversations,
  MAX(e.received_at) as latest_email
FROM mailboxes m
LEFT JOIN emails e ON e.mailbox_id = m.id
GROUP BY m.email;
```

## API Endpoints

### Sync Emails (Automated)

Triggered by pg_cron every minute.

**Manual trigger:**
```bash
POST /functions/v1/sync-emails
Authorization: Bearer [service-role-key]
```

**Response:**
```json
{
  "success": true,
  "stats": {
    "mailboxes_synced": 2,
    "successful_syncs": 2,
    "total_emails_imported": 15,
    "duration_ms": 8234
  }
}
```

### Import Legacy Emails (Manual)

Import historical emails with batch processing.

**Request:**
```bash
POST /functions/v1/import-legacy-emails
Authorization: Bearer [service-role-key]
Content-Type: application/json

{
  "mailbox_id": "550e8400-e29b-41d4-a716-446655440000",
  "folders": ["INBOX", "Sent"],
  "start_date": "2024-01-01",
  "end_date": "2025-01-01",
  "resume_token": "INBOX:5000:3" // optional
}
```

**Response:**
```json
{
  "completed": false,
  "processed": 50,
  "total_imported": 48,
  "resume_token": "INBOX:5050:4",
  "next_folder": "INBOX"
}
```

Continue calling with `resume_token` until `completed: true`.

## Database Schema

### Core Tables

- **mailboxes**: Owner's email accounts for synchronization
- **organizations**: Customer companies (auto-created from email domains)
- **contacts**: Individual contacts (auto-created from email addresses)
- **conversations**: Email threads (1-to-1 with thread_id)
- **emails**: Individual email messages

### Relationships

```
mailboxes (1) ──> (∞) emails
contacts (1) ──> (∞) emails
organizations (1) ──> (∞) contacts
organizations (1) ──> (∞) emails
conversations (1) ──> (∞) emails
```

## Security

- **IMAP Passwords**: Stored as Supabase secrets (never in database)
- **Service Role Key**: Used for cron job authentication
- **Secrets Format**: `IMAP_PASSWORD_{mailbox_id_with_underscores}`

## Performance

- **Parallel Processing**: Syncs up to 5 mailboxes concurrently
- **Batch Size**: 50 emails per batch (configurable)
- **Indexes**: Optimized for common queries (by mailbox, conversation, date)
- **Deduplication**: Checks by message_id and IMAP UID before insert

## Troubleshooting

See [DEPLOYMENT.md](./DEPLOYMENT.md) for detailed troubleshooting guide.

**Common issues:**
- IMAP connection failed → Check secret name format (underscores, not hyphens)
- No emails imported → Check CC deduplication logic
- Cron not running → Verify pg_cron database settings
- Function timeout → Reduce batch size or concurrent mailboxes

## Documentation

- [DEPLOYMENT.md](./DEPLOYMENT.md) - Complete deployment guide
- [scripts/FINAL_SCHEMA_GUIDE.md](../scripts/FINAL_SCHEMA_GUIDE.md) - Schema design guide
- [scripts/THREADING_EXPLAINED.md](../scripts/THREADING_EXPLAINED.md) - Threading algorithm
- [scripts/email_threading.py](../scripts/email_threading.py) - Python reference implementation

## Support

For issues or questions:
1. Check Edge Function logs in Supabase Dashboard
2. Review cron job execution history
3. Test IMAP connection manually
4. Check [DEPLOYMENT.md](./DEPLOYMENT.md) troubleshooting section

## License

Proprietary - PD Medical


