# Agentic AI Architecture

This directory contains a scalable, production-ready architecture for building agentic AI systems using Supabase Edge Functions, LangChain, and LangGraph.

## 📁 Project Structure

```
/supabase/functions/
├── deno.json                           # Global Deno configuration
├── import_map.json                     # Shared dependencies (LangChain, OpenAI, Zod, LangGraph)
│
├── _shared/                            # Shared utilities & core components
│   ├── cors.ts                         # CORS handling
│   ├── response.ts                     # Response utilities
│   │
│   ├── tools/                          # Reusable tools for all agents
│   │   ├── index.ts                    # Tool exports
│   │   ├── weather.tool.ts             # Weather API tool
│   │   ├── database.tool.ts            # Supabase DB operations
│   │   └── email.tool.ts               # Email operations
│   │
│   ├── agents/                         # Base agent classes & configs
│   │   ├── base-agent.ts               # Abstract base agent class
│   │   ├── agent-factory.ts            # Factory for creating agents
│   │   └── agent-types.ts              # Agent type definitions
│   │
│   ├── workflows/                      # LangGraph workflow definitions
│   │   ├── index.ts                    # Workflow exports
│   │   └── email-workflow.ts           # Email automation workflow
│   │
│   ├── prompts/                        # Reusable prompt templates
│   │   ├── system-prompts.ts           # System prompts for different agents
│   │   └── task-prompts.ts             # Task-specific prompts
│   │
│   ├── types/                          # Shared TypeScript types
│   │   ├── agent.types.ts              # Agent-related types
│   │   ├── tool.types.ts               # Tool-related types
│   │   └── workflow.types.ts           # Workflow-related types
│   │
│   └── utils/                          # Utility functions
│       ├── llm-config.ts               # LLM configuration helpers
│       ├── error-handler.ts            # Error handling utilities
│       └── logger.ts                   # Logging utilities
│
├── agents/                             # Agent endpoints (one per agent type)
│   └── index.ts                        # General purpose agent
│
├── email-agent/                        # Email automation agent
│   └── index.ts
│
├── workflows/                          # LangGraph workflow endpoints
│   └── email-campaign/                 # Email campaign workflow
│       └── index.ts
│
├── health/                             # Health check endpoint
│   └── index.ts
│
├── import-contacts-supervisor/         # Contact import function
│   ├── email-server.ts
│   ├── index.ts
│   ├── mailchimp.ts
│   └── README.md
│
└── test-db/                            # Test endpoint
    └── index.ts
```

## 🎯 Core Concepts

### 1. **Tools** (`_shared/tools/`)

Tools are reusable, atomic functions that agents can use to perform specific tasks.

**Characteristics:**
- Pure functions with clear inputs/outputs
- No agent logic - just functionality
- Can be used by any agent
- Schema-validated using Zod

**Example:**
```typescript
import { weatherTool } from "../_shared/tools/weather.tool.ts"

// Use in any agent
const agent = createAgent({
  model,
  tools: [weatherTool],
})
```

**Available Tools:**
- `weatherTool` - Get weather information
- `queryContactsTool` - Query contacts from database
- `updateContactTool` - Update contact information
- `sendEmailTool` - Send emails
- `draftEmailTool` - Generate email drafts

### 2. **Agents** (`agents/`, `email-agent/`, etc.)

Agents are specialized AI assistants that orchestrate tools to accomplish tasks.

**Characteristics:**
- Each agent has a specific purpose
- Uses a curated set of tools
- Has a specialized system prompt
- Exposed as HTTP endpoints

**Example Agent Types:**
- **General Agent** - Multi-purpose assistant
- **Email Agent** - Email automation and management
- **Research Agent** - Information gathering and analysis
- **Scheduling Agent** - Calendar and appointment management
- **Data Analyst Agent** - Database queries and insights

**Creating a New Agent:**
```typescript
import { createAgent } from "langchain"
import { createChatModel, getDefaultLLMConfig } from "../_shared/utils/llm-config.ts"
import { EMAIL_AGENT_PROMPT } from "../_shared/prompts/system-prompts.ts"
import { sendEmailTool, draftEmailTool } from "../_shared/tools/email.tool.ts"

const llmConfig = getDefaultLLMConfig()
const model = createChatModel(llmConfig)

const agent = createAgent({
  model,
  tools: [sendEmailTool, draftEmailTool],
})
```

### 3. **Workflows** (`_shared/workflows/`, `workflows/`)

Workflows are complex, multi-step processes that coordinate multiple agents and tools using LangGraph.

**Characteristics:**
- Orchestrate multiple agents/tools
- Handle complex state management
- Support branching and conditional logic
- Can run steps in parallel

**Example Workflow:**
```typescript
// Email Campaign Workflow
// 1. Fetch contacts from database
// 2. Generate personalized email content for each
// 3. Send emails in batches
// 4. Track responses and update database
```

**When to Use Workflows:**
- Multi-step processes with dependencies
- Need for state management across steps
- Complex branching logic
- Parallel execution requirements

### 4. **Prompts** (`_shared/prompts/`)

Centralized prompt templates for consistency and easy updates.

**Types:**
- **System Prompts** - Define agent personality and capabilities
- **Task Prompts** - Templates for specific tasks with placeholders

**Example:**
```typescript
import { EMAIL_AGENT_PROMPT } from "../_shared/prompts/system-prompts.ts"
import { EMAIL_PERSONALIZATION_PROMPT } from "../_shared/prompts/task-prompts.ts"
```

### 5. **Types** (`_shared/types/`)

Shared TypeScript types for type safety across the codebase.

**Categories:**
- `agent.types.ts` - Agent-related types
- `tool.types.ts` - Tool-related types
- `workflow.types.ts` - Workflow-related types

### 6. **Utilities** (`_shared/utils/`)

Common utilities used across agents and workflows.

**Available Utilities:**
- **LLM Config** - Configure and create LLM instances
- **Error Handler** - Centralized error handling
- **Logger** - Structured logging

## 🚀 Getting Started

### Environment Variables

Set up your environment variables:

```bash
# LLM Provider (choose one)
OPENROUTER_API_KEY=your_openrouter_key
# OR
OPENAI_API_KEY=your_openai_key

# Optional: Specify model
OPENROUTER_MODEL=x-ai/grok-4-fast
OPENAI_MODEL=gpt-4-turbo-preview

# Supabase
SUPABASE_URL=your_supabase_url
SUPABASE_SERVICE_ROLE_KEY=your_service_role_key
```

### Running Locally

1. Start Supabase:
```bash
supabase start
```

2. Serve a function:
```bash
supabase functions serve agents --no-verify-jwt
```

3. Test the agent:
```bash
curl -i --location --request POST 'http://127.0.0.1:54321/functions/v1/agents' \
  --header 'Content-Type: application/json' \
  --data '{"messages":[{"role":"user","content":"What is the weather in Tokyo?"}]}'
```

### Deploying

Deploy all functions:
```bash
supabase functions deploy
```

Deploy a specific function:
```bash
supabase functions deploy agents
```

## 📝 Creating New Components

### Adding a New Tool

1. Create a new file in `_shared/tools/`:
```typescript
// _shared/tools/search.tool.ts
import { tool } from "langchain"
import { z } from "zod"

export const searchTool = tool(
  async (input: { query: string }) => {
    // Implementation
    return "Search results..."
  },
  {
    name: "web_search",
    description: "Search the web for information",
    schema: z.object({
      query: z.string().describe("The search query"),
    }),
  }
)
```

2. Export from `_shared/tools/index.ts`:
```typescript
export * from "./search.tool.ts"
```

3. Use in any agent:
```typescript
import { searchTool } from "../_shared/tools/search.tool.ts"
```

### Adding a New Agent

1. Create a new directory: `my-agent/`
2. Create `my-agent/index.ts`:
```typescript
import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { createAgent } from "langchain"
import { createChatModel, getDefaultLLMConfig } from "../_shared/utils/llm-config.ts"
import { MY_AGENT_PROMPT } from "../_shared/prompts/system-prompts.ts"
// Import tools...

const model = createChatModel(getDefaultLLMConfig())
const agent = createAgent({ model, tools: [...] })

Deno.serve(async (req) => {
  // Handle requests...
})
```

3. Add system prompt to `_shared/prompts/system-prompts.ts`
4. Deploy: `supabase functions deploy my-agent`

### Adding a New Workflow

1. Create workflow definition in `_shared/workflows/my-workflow.ts`
2. Create endpoint in `workflows/my-workflow/index.ts`
3. Implement LangGraph state graph
4. Deploy: `supabase functions deploy workflows/my-workflow`

## 🏗️ Architecture Principles

### 1. **Separation of Concerns**
- Tools = Pure functions
- Agents = Orchestration
- Workflows = Complex processes
- Endpoints = HTTP handlers

### 2. **Reusability**
- Tools are shared across all agents
- Prompts are centralized and reusable
- Utilities are available everywhere
- Types ensure consistency

### 3. **Scalability**
- Easy to add new agents
- Easy to add new tools
- Easy to compose workflows
- No code duplication

### 4. **Type Safety**
- TypeScript throughout
- Zod schema validation
- Shared type definitions
- Compile-time checks

### 5. **Observability**
- Structured logging
- Error tracking
- Performance metrics
- Execution traces

## 🔧 Configuration

### LLM Providers

The system supports multiple LLM providers:

**OpenRouter (Default):**
```typescript
const config = {
  provider: "openrouter",
  model: "x-ai/grok-4-fast",
  temperature: 0.7,
}
```

**OpenAI:**
```typescript
const config = {
  provider: "openai",
  model: "gpt-4-turbo-preview",
  temperature: 0.7,
}
```

### Model Presets

Use predefined model configurations:

```typescript
import { MODEL_PRESETS } from "../_shared/utils/llm-config.ts"

// Fast responses
const fastModel = createChatModel(MODEL_PRESETS.fast)

// Balanced performance
const balancedModel = createChatModel(MODEL_PRESETS.balanced)

// Creative outputs
const creativeModel = createChatModel(MODEL_PRESETS.creative)

// Precise, factual responses
const preciseModel = createChatModel(MODEL_PRESETS.precise)
```

## 🧪 Testing

Test individual tools:
```typescript
import { weatherTool } from "../_shared/tools/weather.tool.ts"

const result = await weatherTool.invoke({ city: "Tokyo" })
console.log(result)
```

Test agents locally:
```bash
curl -X POST http://127.0.0.1:54321/functions/v1/agents \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"Test message"}]}'
```

## 📚 Additional Resources

- [Supabase Edge Functions Docs](https://supabase.com/docs/guides/functions)
- [LangChain Documentation](https://js.langchain.com/docs/)
- [LangGraph Documentation](https://langchain-ai.github.io/langgraphjs/)
- [Deno Documentation](https://deno.land/manual)

## 🤝 Contributing

When adding new components:

1. Follow the existing structure
2. Add proper TypeScript types
3. Include JSDoc comments
4. Add logging and error handling
5. Update this README
6. Test thoroughly before deploying

## 📄 License

[Your License Here]

