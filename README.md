# AI Outreach Backend

Backend API for PD Medical AI Automation Project - Consolidated architecture with supervisor pattern.

## Tech Stack

- **Runtime:** Deno + TypeScript
- **Backend:** Supabase (Database + Auth + Edge Functions)
- **Deployment:** Supabase CLI
- **Data Sources:** Email Server (IMAP) + Mailchimp API

## Quick Start

### 1. Install Supabase CLI

**Windows:**
```bash
scoop install supabase
```

**macOS/Linux:**
```bash
brew install supabase/tap/supabase
```

### 2. Setup Project

```bash
# Login to Supabase
supabase login

# Link your project
supabase link --project-ref yuiqdslwixpcudtqnrox

# Set environment variables
supabase secrets set EMAIL_USER=peter@pdmedical.com.au
supabase secrets set EMAIL_PASSWORD=your-password
supabase secrets set MAILCHIMP_API_KEY=your-api-key
```

### 3. Deploy Functions

```bash
# Deploy the supervisor function
supabase functions deploy import-contacts-supervisor

# Or deploy all functions
npm run functions:deploy
```

## Project Structure

```
ai-outreach-backend/
├── supabase/
│   ├── functions/
│   │   ├── import-contacts-supervisor/    # Main import function
│   │   │   ├── index.ts                    # Supervisor (routes requests)
│   │   │   ├── email-server.ts             # Email server import module
│   │   │   ├── mailchimp.ts                # Mailchimp import module
│   │   │   └── README.md                   # Documentation
│   │   ├── health/                         # Health check endpoint
│   │   ├── test-db/                        # Database test endpoint
│   │   └── _shared/                        # Shared utilities
│   └── config.toml                         # Supabase configuration
├── src/
│   └── types/                              # TypeScript types
└── package.json
```

## Main Function: Import Contacts Supervisor

**Single API endpoint that handles multiple data sources.**

### Email Server Import

```powershell
Invoke-RestMethod -Uri https://yuiqdslwixpcudtqnrox.supabase.co/functions/v1/import-contacts-supervisor -Method Post -Headers @{"Authorization"="Bearer YOUR_ANON_KEY";"Content-Type"="application/json"} -Body '{"source":"email_server"}'
```

**Response:**
```json
{
  "success": true,
  "source": "email_server",
  "extracted": 130,
  "inserted": 130,
  "errors": 0,
  "message": "Successfully extracted 130 contacts from mail.pdmedical.com.au"
}
```

### Mailchimp Import

```powershell
Invoke-RestMethod -Uri https://yuiqdslwixpcudtqnrox.supabase.co/functions/v1/import-contacts-supervisor -Method Post -Headers @{"Authorization"="Bearer YOUR_ANON_KEY";"Content-Type"="application/json"} -Body '{"source":"mailchimp","mailchimp_list_id":"9bec909b0d"}'
```

**Response:**
```json
{
  "success": true,
  "source": "mailchimp",
  "extracted": 1260,
  "inserted": 1260,
  "errors": 0,
  "message": "Successfully extracted 1260 contacts from Mailchimp"
}
```

## Request Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `source` | string | Yes | `"email_server"` or `"mailchimp"` |
| `email_id` | string | No | Email address (default: EMAIL_USER env var) |
| `mailchimp_list_id` | string | For mailchimp | Mailchimp audience/list ID |
| `limit` | number | No | Max contacts (email: 500, mailchimp: 10000) |

## Environment Variables

```bash
# Email Server
EMAIL_USER=peter@pdmedical.com.au
EMAIL_PASSWORD=your-email-password

# Mailchimp
MAILCHIMP_API_KEY=your-api-key-us19

# Supabase (auto-configured)
SUPABASE_URL=auto
SUPABASE_SERVICE_ROLE_KEY=auto
```

## Performance & Optimization

### Features
- **Batch database operations** - 500 contacts per batch
- **Timeout protection** - 55-second limit for email imports
- **Memory efficient** - Streams data instead of loading all at once
- **Error recovery** - Individual batch failures don't stop import
- **Optimized parsing** - Minimal regex operations
- **Connection reuse** - Reusable encoder/decoder instances
- **Smart pagination** - Mailchimp fetches 1000 per request

### Benchmarks
| Source | Contacts | Time | Performance |
|--------|----------|------|-------------|
| Email Server | 130 | ~8s | ~16 contacts/sec |
| Mailchimp | 1,260 | ~12s | ~105 contacts/sec |

## Available Scripts

```bash
npm run supabase:start      # Start local Supabase
npm run supabase:stop       # Stop local Supabase
npm run functions:serve     # Serve all functions locally
npm run functions:deploy    # Deploy all functions
```

## Database Schema

The `contacts` table stores imported contacts:

```sql
CREATE TABLE contacts (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  email TEXT UNIQUE NOT NULL,
  first_name TEXT,
  last_name TEXT,
  source TEXT NOT NULL,  -- 'email_server' or 'mailchimp'
  quality_score INTEGER DEFAULT 50,
  status TEXT DEFAULT 'active',
  tags JSONB DEFAULT '[]',
  custom_fields JSONB DEFAULT '{}',
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);
```

## View Imported Contacts

**Supabase Dashboard:**
1. Go to: https://supabase.com/dashboard/project/yuiqdslwixpcudtqnrox/editor
2. Click `contacts` table
3. Filter by `source` column

**SQL Query:**
```sql
-- Count by source
SELECT source, COUNT(*) as total
FROM contacts 
GROUP BY source;

-- View email server contacts
SELECT email, first_name, last_name, created_at
FROM contacts 
WHERE source = 'email_server'
ORDER BY created_at DESC;
```

## Architecture Benefits

### Supervisor Pattern
- **Single entry point** - One API for all data sources
- **Modular design** - Easy to add new sources (HubSpot, Salesforce, etc.)
- **Unified response** - Consistent API format
- **Shared utilities** - Database operations, error handling
- **Optimized code** - No duplication, minimal footprint

### Future Extensions
- Add HubSpot integration
- Add Salesforce integration
- Add CSV upload
- Add contact enrichment (LLM-based)
- Add deduplication logic
- Add quality scoring improvements

## Troubleshooting

### Email Server Connection Issues
If you see TLS certificate errors, the function automatically falls back to port 143. Contact your IT department if persistent.

### Mailchimp API Limits
Mailchimp allows 10 requests per second. The function respects this limit with pagination.

### Function Timeout
Edge Functions have a 10-second timeout. Email imports are limited to 500 messages to stay within this limit.

## Documentation

See `supabase/functions/import-contacts-supervisor/README.md` for detailed function documentation.

## License

MIT
