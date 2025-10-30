# Agentic AI Architecture Overview

## 🏛️ High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         HTTP Requests                            │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                    SUPABASE EDGE FUNCTIONS                       │
│                                                                  │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐         │
│  │   Agents     │  │   Workflows  │  │   Other      │         │
│  │  Endpoints   │  │  Endpoints   │  │  Functions   │         │
│  └──────┬───────┘  └──────┬───────┘  └──────────────┘         │
│         │                  │                                     │
│         └──────────┬───────┘                                     │
│                    ▼                                             │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │              _shared/ (Core Components)                  │   │
│  │                                                           │   │
│  │  ┌─────────┐  ┌─────────┐  ┌──────────┐  ┌─────────┐  │   │
│  │  │  Tools  │  │ Agents  │  │Workflows │  │ Prompts │  │   │
│  │  └─────────┘  └─────────┘  └──────────┘  └─────────┘  │   │
│  │                                                           │   │
│  │  ┌─────────┐  ┌─────────┐                               │   │
│  │  │  Types  │  │  Utils  │                               │   │
│  │  └─────────┘  └─────────┘                               │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                    EXTERNAL SERVICES                             │
│                                                                  │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐         │
│  │ LLM Provider │  │   Supabase   │  │  Email APIs  │         │
│  │ (OpenRouter/ │  │   Database   │  │  (SendGrid/  │         │
│  │   OpenAI)    │  │              │  │   Resend)    │         │
│  └──────────────┘  └──────────────┘  └──────────────┘         │
└─────────────────────────────────────────────────────────────────┘
```

## 🔄 Request Flow

### Simple Agent Request

```
User Request
    │
    ▼
Agent Endpoint (e.g., /agents)
    │
    ├─→ Load Tools from _shared/tools/
    ├─→ Load Prompts from _shared/prompts/
    ├─→ Configure LLM from _shared/utils/llm-config
    │
    ▼
Create Agent (LangChain)
    │
    ▼
Agent Invokes Tools as Needed
    │
    ├─→ Tool 1: Query Database
    ├─→ Tool 2: Send Email
    └─→ Tool 3: External API
    │
    ▼
Return Response to User
```

### Complex Workflow Request

```
User Request
    │
    ▼
Workflow Endpoint (e.g., /workflows/email-campaign)
    │
    ▼
LangGraph Workflow
    │
    ├─→ Step 1: Fetch Contacts (Database Tool)
    │       │
    │       ▼
    ├─→ Step 2: Generate Emails (Email Agent)
    │       │
    │       ▼
    ├─→ Step 3: Send Emails (Email Tool)
    │       │
    │       ▼
    └─→ Step 4: Track Results (Database Tool)
    │
    ▼
Return Workflow Results to User
```

## 🧩 Component Relationships

### Tools → Agents → Workflows

```
┌─────────────────────────────────────────────────────────────┐
│                          WORKFLOWS                           │
│  (Complex multi-step processes using LangGraph)             │
│                                                              │
│  Example: Email Campaign Workflow                           │
│  ┌────────┐    ┌────────┐    ┌────────┐    ┌────────┐    │
│  │ Fetch  │───▶│Generate│───▶│  Send  │───▶│ Track  │    │
│  │Contacts│    │ Emails │    │ Emails │    │Results │    │
│  └────────┘    └────────┘    └────────┘    └────────┘    │
│       │             │              │             │         │
└───────┼─────────────┼──────────────┼─────────────┼─────────┘
        │             │              │             │
        ▼             ▼              ▼             ▼
┌─────────────────────────────────────────────────────────────┐
│                           AGENTS                             │
│  (Orchestrate tools to accomplish specific tasks)           │
│                                                              │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐  │
│  │ General  │  │  Email   │  │ Research │  │Scheduling│  │
│  │  Agent   │  │  Agent   │  │  Agent   │  │  Agent   │  │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘  │
└───────┼─────────────┼──────────────┼─────────────┼─────────┘
        │             │              │             │
        └─────────────┴──────────────┴─────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────┐
│                           TOOLS                              │
│  (Atomic, reusable functions)                               │
│                                                              │
│  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐      │
│  │ Weather │  │Database │  │  Email  │  │ Search  │      │
│  │  Tool   │  │  Tool   │  │  Tool   │  │  Tool   │      │
│  └─────────┘  └─────────┘  └─────────┘  └─────────┘      │
└─────────────────────────────────────────────────────────────┘
```

## 📊 Data Flow

### Agent Execution with Tools

```
1. Request arrives at agent endpoint
   ↓
2. Agent receives user message
   ↓
3. LLM analyzes message and decides which tools to use
   ↓
4. Agent calls Tool 1 (e.g., query_contacts)
   ↓
5. Tool 1 returns data
   ↓
6. LLM processes tool result
   ↓
7. LLM decides to call Tool 2 (e.g., draft_email)
   ↓
8. Tool 2 returns draft
   ↓
9. LLM formats final response
   ↓
10. Response returned to user
```

## 🎯 Key Design Patterns

### 1. Factory Pattern (Agent Creation)

```typescript
// _shared/agents/agent-factory.ts
export function getLLMProvider(): LLMProvider {
  // Automatically detect and configure provider
}

export function createAgentConfig(overrides): AgentConfig {
  // Create configuration with sensible defaults
}
```

### 2. Strategy Pattern (LLM Providers)

```typescript
// _shared/utils/llm-config.ts
export function createChatModel(config: LLMConfig) {
  switch (config.provider) {
    case "openrouter": return new ChatOpenAI({...})
    case "openai": return new ChatOpenAI({...})
    case "anthropic": return new ChatAnthropic({...})
  }
}
```

### 3. Decorator Pattern (Error Handling & Logging)

```typescript
// _shared/utils/error-handler.ts
export async function withErrorHandling<T>(
  fn: () => Promise<T>,
  context: string
): Promise<T> {
  try {
    return await fn()
  } catch (error) {
    logger.error(`Error in ${context}`, error)
    throw error
  }
}
```

### 4. Template Method Pattern (Base Agent)

```typescript
// _shared/agents/base-agent.ts
export abstract class BaseAgent {
  protected abstract getDefaultSystemPrompt(): string
  abstract execute(input: any): Promise<any>
  
  // Common functionality shared by all agents
  protected createLLM(provider, config) { ... }
}
```

## 🔐 Security Considerations

1. **API Keys**: Stored in environment variables, never in code
2. **Service Role Key**: Used for database operations, kept secure
3. **Input Validation**: All inputs validated with Zod schemas
4. **Error Messages**: Sanitized to avoid leaking sensitive info
5. **Rate Limiting**: Consider implementing at edge function level

## 🚀 Scalability Features

1. **Horizontal Scaling**: Edge functions auto-scale
2. **Stateless Design**: Each request is independent
3. **Shared Dependencies**: No duplication, faster cold starts
4. **Modular Architecture**: Easy to add/remove components
5. **Caching**: Can be added at tool level for expensive operations

## 📈 Performance Optimization

1. **Tool Execution**: Parallel when possible
2. **LLM Calls**: Streaming responses for better UX
3. **Database Queries**: Indexed and optimized
4. **Cold Starts**: Minimized by shared dependencies
5. **Logging**: Async, non-blocking

## 🧪 Testing Strategy

### Unit Tests
- Test individual tools in isolation
- Test utility functions
- Test type definitions

### Integration Tests
- Test agent with tools
- Test workflow steps
- Test error handling

### End-to-End Tests
- Test full request/response cycle
- Test with real LLM (or mocked)
- Test edge cases

## 📚 Extension Points

### Adding New Capabilities

1. **New Tool**: Add to `_shared/tools/`
2. **New Agent**: Create new endpoint directory
3. **New Workflow**: Add to `_shared/workflows/` and create endpoint
4. **New Prompt**: Add to `_shared/prompts/`
5. **New Type**: Add to `_shared/types/`
6. **New Utility**: Add to `_shared/utils/`

### Integration Examples

**Add Anthropic Support:**
```typescript
// _shared/utils/llm-config.ts
case "anthropic":
  return new ChatAnthropic({
    model: config.model,
    apiKey: Deno.env.get("ANTHROPIC_API_KEY"),
  })
```

**Add Vector Search Tool:**
```typescript
// _shared/tools/vector-search.tool.ts
export const vectorSearchTool = tool(
  async (input: { query: string }) => {
    const supabase = getSupabaseClient()
    const embedding = await generateEmbedding(input.query)
    const { data } = await supabase.rpc('match_documents', {
      query_embedding: embedding,
      match_threshold: 0.8,
      match_count: 5
    })
    return JSON.stringify(data)
  },
  { ... }
)
```

## 🎓 Best Practices

1. **Keep Tools Pure**: No side effects, clear inputs/outputs
2. **Agent Specialization**: Each agent has a specific purpose
3. **Prompt Engineering**: Iterate and improve prompts
4. **Error Handling**: Always handle errors gracefully
5. **Logging**: Log important events for debugging
6. **Type Safety**: Use TypeScript types everywhere
7. **Documentation**: Keep README and code comments updated
8. **Testing**: Test before deploying
9. **Monitoring**: Watch for errors and performance issues
10. **Iteration**: Continuously improve based on usage

## 🔮 Future Enhancements

- [ ] Add streaming responses for better UX
- [ ] Implement caching layer for expensive operations
- [ ] Add rate limiting per user/endpoint
- [ ] Implement conversation memory/history
- [ ] Add vector database for RAG capabilities
- [ ] Create admin dashboard for monitoring
- [ ] Add A/B testing for prompts
- [ ] Implement feedback loop for continuous improvement
- [ ] Add multi-modal support (images, audio)
- [ ] Create agent marketplace for sharing tools/agents

---

**Last Updated**: October 30, 2025
**Version**: 1.0.0

