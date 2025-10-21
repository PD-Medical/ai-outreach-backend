# AI Outreach Backend

Backend API for PD Medical AI Automation Project

## Tech Stack

- Node.js + TypeScript
- Supabase (Database & Auth)
- Vercel (Serverless Functions)

## Quick Start

### 1. Install Dependencies
```bash
npm install
```

### 2. Setup Environment Variables
Create `.env` file:
```env
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_ANON_KEY=your-anon-key
SUPABASE_SERVICE_ROLE_KEY=your-service-role-key
FRONTEND_URL=http://localhost:3000
```

Get credentials from [Supabase Dashboard](https://supabase.com/dashboard) → Settings → API

### 3. Run Dev Server
```bash
npm run dev
```

### 4. Test API
- Health: `http://localhost:3000/api/health`
- Supabase Test: `http://localhost:3000/api/test-supabase`

## Project Structure

```
├── api/              # API endpoints
├── src/
│   ├── lib/         # Supabase client
│   ├── types/       # TypeScript types
│   └── utils/       # Helpers
└── vercel.json      # Deployment config
```

## Deployment

```bash
vercel login
npm run deploy
```

Add environment variables in Vercel dashboard.

## License

MIT

