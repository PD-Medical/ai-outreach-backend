// Follow this setup guide to integrate the Deno language server with your editor:
// https://deno.land/manual/getting_started/setup_your_environment
// This enables autocomplete, go to definition, etc.

// Setup type definitions for built-in Supabase Runtime APIs
import "jsr:@supabase/functions-js/edge-runtime.d.ts"

import { createAgent } from "langchain"
import { weatherTool } from "../_shared/tools/weather.tool.ts"
import { createChatModel, getDefaultLLMConfig } from "../_shared/utils/llm-config.ts"
import { GENERAL_AGENT_PROMPT } from "../_shared/prompts/system-prompts.ts"
import { formatErrorResponse } from "../_shared/utils/error-handler.ts"
import { createLogger } from "../_shared/utils/logger.ts"

const logger = createLogger("GeneralAgent")

// Get LLM configuration
const llmConfig = getDefaultLLMConfig()
const model = createChatModel(llmConfig)

// Create the agent with tools
const agent = createAgent({
  model,
  tools: [weatherTool],
  // Note: LangChain's createAgent doesn't accept systemPrompt directly
  // You'll need to add it to the messages array when invoking
})

logger.info("General Agent initialized", {
  provider: llmConfig.provider,
  model: llmConfig.model,
})

Deno.serve(async (req) => {
  const startTime = Date.now()
  
  try {
    const { messages } = await req.json()

    if (!messages || !Array.isArray(messages)) {
      return new Response(
        JSON.stringify({ error: "Invalid input. Expected 'messages' array." }),
        { status: 400, headers: { "Content-Type": "application/json" } },
      )
    }

    // Add system prompt if not present
    const messagesWithSystem = messages[0]?.role === "system" 
      ? messages 
      : [{ role: "system", content: GENERAL_AGENT_PROMPT }, ...messages]

    logger.info("Agent invoked", {
      messageCount: messages.length,
    })

    // Invoke the agent
    const response = await agent.invoke({
      messages: messagesWithSystem,
    })

    const duration = Date.now() - startTime

    logger.info("Agent completed", {
      duration,
      responseMessageCount: response.messages.length,
    })

    return new Response(
      JSON.stringify({
        messages: response.messages,
        output: response.messages[response.messages.length - 1].content,
        metadata: {
          duration,
          model: llmConfig.model,
          provider: llmConfig.provider,
        },
      }),
      { headers: { "Content-Type": "application/json" } },
    )
  } catch (error) {
    const duration = Date.now() - startTime
    
    logger.error("Agent error", error as Error, {
      duration,
    })

    return new Response(
      JSON.stringify(formatErrorResponse(error as Error)),
      { status: 500, headers: { "Content-Type": "application/json" } },
    )
  }
})

/* To invoke locally:

  1. Set the OPENROUTER_API_KEY or OPENAI_API_KEY environment variable
  2. Run `supabase start` (see: https://supabase.com/docs/reference/cli/supabase-start)
  3. Make an HTTP request:

  curl -i --location --request POST 'http://127.0.0.1:54321/functions/v1/agents' \
    --header 'Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0' \
    --header 'Content-Type: application/json' \
    --data '{"messages":[{"role":"user","content":"What'\''s the weather in Tokyo?"}]}'

*/
