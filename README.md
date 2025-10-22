# AI Outreach Backend

Backend API for PD Medical AI Automation Project

## Tech Stack

- Deno + TypeScript
- Supabase (Database + Auth + Edge Functions)
- Supabase CLI for deployment

## Quick Start

### 1. Install Supabase CLI

**macOS/Linux:**
```bash
brew install supabase/tap/supabase
```

**Windows:**
```bash
scoop bucket add supabase https://github.com/supabase/scoop-bucket.git
scoop install supabase
```

Or use npm:
```bash
npm install -g supabase
```

### 2. Login to Supabase
```bash
supabase login
```

### 3. Link Your Project
```bash
supabase link --project-ref your-project-ref
```

Get your project ref from [Supabase Dashboard](https://supabase.com/dashboard) → Project Settings

### 4. Setup Environment Variables

Create `.env` file in `supabase/` directory:
```env
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_ANON_KEY=your-anon-key
SUPABASE_SERVICE_ROLE_KEY=your-service-role-key
```

Get credentials from Dashboard → Settings → API

### 5. Start Local Development
```bash
npm run supabase:start
```

This starts:
- Local Supabase (Database, Auth, Storage)
- Studio UI at `http://localhost:54323`
- API at `http://localhost:54321`

### 6. Serve Functions Locally
```bash
npm run functions:serve
```

Test endpoints:
- Health: `http://localhost:54321/functions/v1/health`
- Test DB: `http://localhost:54321/functions/v1/test-db`

## Project Structure

```
ai-outreach-backend/
├── supabase/
│   ├── functions/
│   │   ├── health/           # Health check endpoint
│   │   ├── test-db/          # Test database connection
│   │   └── _shared/          # Shared utilities (CORS, response)
│   └── config.toml           # Supabase configuration
├── src/
│   └── types/                # Shared TypeScript types
└── package.json
```

## Creating New Functions

### 1. Create a new function:
```bash
supabase functions new my-function
```

### 2. Edit the function in `supabase/functions/my-function/index.ts`

### 3. Test locally:
```bash
supabase functions serve my-function
```

### 4. Deploy:
```bash
supabase functions deploy my-function
```

## Available Scripts

```bash
npm run supabase:start      # Start local Supabase
npm run supabase:stop       # Stop local Supabase
npm run supabase:status     # Check status
npm run functions:serve     # Serve all functions locally
npm run functions:deploy    # Deploy all functions
npm run db:reset           # Reset local database
npm run db:push            # Push schema to remote
```

## Deployment

### Deploy Single Function
```bash
supabase functions deploy function-name
```

### Deploy All Functions
```bash
npm run functions:deploy
```

### Set Environment Variables (Remote)
```bash
supabase secrets set MY_SECRET=value
```

## Accessing Functions

### Local Development
```
http://localhost:54321/functions/v1/function-name
```

### Production
```
https://your-project.supabase.co/functions/v1/function-name
```

## Database Setup

### Create Tables via Supabase Studio
1. Open `http://localhost:54323` (local) or your project dashboard
2. Go to Table Editor
3. Create your tables

### Or use SQL migrations:
```bash
supabase migration new create_tables
```

Edit the migration file, then:
```bash
supabase db reset  # Apply locally
supabase db push   # Push to remote
```

## Authentication

Supabase Edge Functions automatically receive the user's JWT. Access it via:

```typescript
const authHeader = req.headers.get("Authorization");
const token = authHeader?.replace("Bearer ", "");
```

## Next Steps

1. Create your database schema in Supabase
2. Add authentication endpoints
3. Build AI automation functions
4. Create outreach campaign endpoints
5. Integrate AI services (OpenAI, etc.)
6. Connect with frontend

## Useful Links

- [Supabase Docs](https://supabase.com/docs)
- [Edge Functions Guide](https://supabase.com/docs/guides/functions)
- [Deno Docs](https://deno.land/manual)

## License

MIT
