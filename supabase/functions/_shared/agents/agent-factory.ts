/**
 * Agent Factory
 * Factory pattern for creating different types of agents
 */

import type { LLMProvider, AgentConfig } from "./base-agent.ts"

/**
 * Get LLM provider configuration from environment
 */
export function getLLMProvider(): LLMProvider {
  // Check for OpenRouter first
  const openRouterKey = Deno.env.get("OPENROUTER_API_KEY")
  if (openRouterKey) {
    return {
      name: "openrouter",
      apiKey: openRouterKey,
      baseURL: "https://openrouter.ai/api/v1",
    }
  }

  // Fallback to OpenAI
  const openAIKey = Deno.env.get("OPENAI_API_KEY")
  if (openAIKey) {
    return {
      name: "openai",
      apiKey: openAIKey,
    }
  }

  throw new Error("No LLM provider API key found in environment variables")
}

/**
 * Create agent configuration with defaults
 */
export function createAgentConfig(overrides: Partial<AgentConfig> = {}): AgentConfig {
  return {
    model: overrides.model,
    temperature: overrides.temperature ?? 0.7,
    maxTokens: overrides.maxTokens,
    systemPrompt: overrides.systemPrompt,
    tools: overrides.tools || [],
  }
}

