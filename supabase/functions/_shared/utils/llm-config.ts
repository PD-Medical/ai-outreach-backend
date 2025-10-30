/**
 * LLM Configuration Utilities
 * Helpers for configuring and managing LLM instances
 */

import { ChatOpenAI } from "@langchain/openai"

export interface LLMConfig {
  provider: "openai" | "openrouter" | "anthropic"
  model: string
  temperature?: number
  maxTokens?: number
  topP?: number
  frequencyPenalty?: number
  presencePenalty?: number
}

/**
 * Get LLM configuration from environment
 */
export function getDefaultLLMConfig(): LLMConfig {
  const openRouterKey = Deno.env.get("OPENROUTER_API_KEY")
  const openAIKey = Deno.env.get("OPENAI_API_KEY")

  if (openRouterKey) {
    return {
      provider: "openrouter",
      model: Deno.env.get("OPENROUTER_MODEL") || "x-ai/grok-4-fast",
      temperature: 0.7,
    }
  }

  if (openAIKey) {
    return {
      provider: "openai",
      model: Deno.env.get("OPENAI_MODEL") || "gpt-4-turbo-preview",
      temperature: 0.7,
    }
  }

  throw new Error("No LLM provider API key found in environment")
}

/**
 * Create ChatOpenAI instance from config
 */
export function createChatModel(config: LLMConfig) {
  const apiKey = config.provider === "openrouter" 
    ? Deno.env.get("OPENROUTER_API_KEY")
    : Deno.env.get("OPENAI_API_KEY")

  if (!apiKey) {
    throw new Error(`API key not found for provider: ${config.provider}`)
  }

  const baseConfig = {
    model: config.model,
    temperature: config.temperature ?? 0.7,
    maxTokens: config.maxTokens,
    topP: config.topP,
    frequencyPenalty: config.frequencyPenalty,
    presencePenalty: config.presencePenalty,
  }

  if (config.provider === "openrouter") {
    return new ChatOpenAI({
      ...baseConfig,
      configuration: {
        baseURL: "https://openrouter.ai/api/v1",
        apiKey,
      },
    })
  }

  return new ChatOpenAI({
    ...baseConfig,
    apiKey,
  })
}

/**
 * Model presets for common use cases
 */
export const MODEL_PRESETS = {
  fast: {
    provider: "openrouter" as const,
    model: "x-ai/grok-4-fast",
    temperature: 0.7,
  },
  balanced: {
    provider: "openai" as const,
    model: "gpt-4-turbo-preview",
    temperature: 0.7,
  },
  creative: {
    provider: "openai" as const,
    model: "gpt-4-turbo-preview",
    temperature: 0.9,
  },
  precise: {
    provider: "openai" as const,
    model: "gpt-4-turbo-preview",
    temperature: 0.3,
  },
}

