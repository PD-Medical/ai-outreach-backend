# Import Contacts Supervisor

Generic Supabase Edge Function that imports contacts from multiple sources (Email Server + Mailchimp) with a unified API.

## Features

- **Unified API** - Single endpoint for multiple data sources
- **Email Server Import** - IMAP connection to extract contacts
- **Mailchimp Import** - API integration with Mailchimp lists
- **Modular Architecture** - Separate modules for each source
- **Future-Ready** - Easy to add more sources (HubSpot, Salesforce, etc.)
- **Enrichment Ready** - Prepared for hybrid LLM enrichment scripts

## Usage

### Email Server Import

```bash
curl -X POST https://your-project.supabase.co/functions/v1/import-contacts-supervisor \
  -H "Authorization: Bearer YOUR_ANON_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "source": "email_server",
    "email_id": "peter@pdmedical.com.au",
    "limit": 500
  }'
```

### Mailchimp Import

```bash
curl -X POST https://your-project.supabase.co/functions/v1/import-contacts-supervisor \
  -H "Authorization: Bearer YOUR_ANON_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "source": "mailchimp",
    "mailchimp_list_id": "your-list-id",
    "limit": 10000
  }'
```

## Request Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `source` | string | Yes | `"email_server"` or `"mailchimp"` |
| `email_id` | string | No | Email address for server import (defaults to EMAIL_USER) |
| `mailchimp_list_id` | string | No | Mailchimp list ID (required for mailchimp source) |
| `limit` | number | No | Max contacts to import (email: 500, mailchimp: 10000) |

## Environment Variables

### Email Server
```env
EMAIL_USER=peter@pdmedical.com.au
EMAIL_PASSWORD=your-email-password
```

### Mailchimp
```env
MAILCHIMP_API_KEY=your-mailchimp-api-key
```

## Response Format

```json
{
  "success": true,
  "source": "email_server",
  "extracted": 159,
  "inserted": 159,
  "errors": 0,
  "message": "Successfully extracted 159 contacts from mail.pdmedical.com.au",
  "details": {
    "email_id": "peter@pdmedical.com.au",
    "limit": 500
  },
  "timestamp": "2025-10-22T14:30:00.000Z"
}
```

## Architecture

```
import-contacts-supervisor/
├── index.ts              # Main supervisor function
├── email-server.ts       # IMAP email import module
├── mailchimp.ts          # Mailchimp API import module
└── README.md            # This documentation
```

## Future Enhancements

### Planned Sources
- **HubSpot** - CRM contact import
- **Salesforce** - Lead import
- **Google Contacts** - Gmail contact sync
- **LinkedIn** - Connection import

### Enrichment Pipeline
- **Hybrid LLM** - Cost-effective contact enrichment
- **Data Validation** - Email verification, phone validation
- **Duplicate Detection** - Advanced matching algorithms
- **Lead Scoring** - AI-powered quality assessment

## Deployment

```bash
# Deploy the supervisor function
supabase functions deploy import-contacts-supervisor

# Set environment variables
supabase secrets set EMAIL_USER=peter@pdmedical.com.au
supabase secrets set EMAIL_PASSWORD=your-password
supabase secrets set MAILCHIMP_API_KEY=your-api-key
```

## Testing

### Test Email Server Import
```bash
curl -X POST https://yuiqdslwixpcudtqnrox.supabase.co/functions/v1/import-contacts-supervisor \
  -H "Authorization: Bearer YOUR_ANON_KEY" \
  -H "Content-Type: application/json" \
  -d '{"source": "email_server"}'
```

### Test Mailchimp Import
```bash
curl -X POST https://yuiqdslwixpcudtqnrox.supabase.co/functions/v1/import-contacts-supervisor \
  -H "Authorization: Bearer YOUR_ANON_KEY" \
  -H "Content-Type: application/json" \
  -d '{"source": "mailchimp", "mailchimp_list_id": "your-list-id"}'
```

## Performance

- **Email Server**: ~159 contacts in 60 seconds
- **Mailchimp**: ~1260 contacts in 15 seconds
- **Database**: Batch upsert with conflict resolution
- **Memory**: Optimized for large datasets

## Security

- **Environment Variables** - Credentials stored securely
- **CORS Protection** - Configurable origins
- **Rate Limiting** - Built-in request limits
- **Error Handling** - No sensitive data in responses

## Notes

- Contacts are **upserted** (insert new, update existing)
- **Duplicate prevention** by email address
- **Source tracking** in custom_fields
- **Quality scoring** based on data completeness
- **Ready for AI enrichment** pipeline integration
