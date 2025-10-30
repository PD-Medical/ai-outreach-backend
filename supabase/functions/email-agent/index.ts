/**
 * Email Agent
 * Specialized agent for email automation and management
 */

import "jsr:@supabase/functions-js/edge-runtime.d.ts"

import { createAgent } from "langchain"
import { sendEmailTool, draftEmailTool } from "../_shared/tools/email.tool.ts"
import { queryContactsTool } from "../_shared/tools/database.tool.ts"
import { createChatModel, getDefaultLLMConfig } from "../_shared/utils/llm-config.ts"
import { EMAIL_AGENT_PROMPT } from "../_shared/prompts/system-prompts.ts"
import { formatErrorResponse } from "../_shared/utils/error-handler.ts"
import { createLogger } from "../_shared/utils/logger.ts"

const logger = createLogger("EmailAgent")

// Get LLM configuration
const llmConfig = getDefaultLLMConfig()
const model = createChatModel(llmConfig)

// Create the email agent with email-specific tools
const agent = createAgent({
  model,
  tools: [
    sendEmailTool,
    draftEmailTool,
    queryContactsTool,
  ],
})

logger.info("Email Agent initialized", {
  provider: llmConfig.provider,
  model: llmConfig.model,
})

Deno.serve(async (req) => {
  const startTime = Date.now()
  
  try {
    const { messages, context } = await req.json()

    if (!messages || !Array.isArray(messages)) {
      return new Response(
        JSON.stringify({ error: "Invalid input. Expected 'messages' array." }),
        { status: 400, headers: { "Content-Type": "application/json" } },
      )
    }

    // Add system prompt with context
    let systemPrompt = EMAIL_AGENT_PROMPT
    if (context) {
      systemPrompt += `\n\nAdditional Context:\n${JSON.stringify(context, null, 2)}`
    }

    const messagesWithSystem = messages[0]?.role === "system" 
      ? messages 
      : [{ role: "system", content: systemPrompt }, ...messages]

    logger.info("Email agent invoked", {
      messageCount: messages.length,
      hasContext: !!context,
    })

    // Invoke the agent
    const response = await agent.invoke({
      messages: messagesWithSystem,
    })

    const duration = Date.now() - startTime

    logger.info("Email agent completed", {
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
    
    logger.error("Email agent error", error as Error, {
      duration,
    })

    return new Response(
      JSON.stringify(formatErrorResponse(error as Error)),
      { status: 500, headers: { "Content-Type": "application/json" } },
    )
  }
})

/* To invoke locally:

  curl -i --location --request POST 'http://127.0.0.1:54321/functions/v1/email-agent' \
    --header 'Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0' \
    --header 'Content-Type: application/json' \
    --data '{"messages":[{"role":"user","content":"Draft an email to john@example.com about our new product"}]}'

*/

