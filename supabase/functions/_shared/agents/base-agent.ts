/**
 * Base Agent Class
 * Abstract base class for all agents
 */

import { ChatOpenAI } from "@langchain/openai"
import type { BaseChatModel } from "langchain"

export interface AgentConfig {
  model?: string
  temperature?: number
  maxTokens?: number
  systemPrompt?: string
  tools?: any[]
}

export interface LLMProvider {
  name: "openai" | "openrouter" | "anthropic"
  apiKey: string
  baseURL?: string
}

/**
 * Base Agent class that all specific agents extend
 */
export abstract class BaseAgent {
  protected llm: BaseChatModel
  protected tools: any[]
  protected systemPrompt: string

  constructor(
    provider: LLMProvider,
    config: AgentConfig = {}
  ) {
    this.tools = config.tools || []
    this.systemPrompt = config.systemPrompt || this.getDefaultSystemPrompt()
    this.llm = this.createLLM(provider, config)
  }

  /**
   * Create LLM instance based on provider
   */
  protected createLLM(provider: LLMProvider, config: AgentConfig): BaseChatModel {
    switch (provider.name) {
      case "openrouter":
        return new ChatOpenAI({
          model: config.model || "x-ai/grok-4-fast",
          temperature: config.temperature || 0.7,
          maxTokens: config.maxTokens,
          configuration: {
            baseURL: provider.baseURL || "https://openrouter.ai/api/v1",
            apiKey: provider.apiKey,
          },
        })
      
      case "openai":
        return new ChatOpenAI({
          model: config.model || "gpt-4-turbo-preview",
          temperature: config.temperature || 0.7,
          maxTokens: config.maxTokens,
          apiKey: provider.apiKey,
        })
      
      // Add more providers as needed
      default:
        throw new Error(`Unsupported LLM provider: ${provider.name}`)
    }
  }

  /**
   * Get default system prompt (override in subclasses)
   */
  protected abstract getDefaultSystemPrompt(): string

  /**
   * Execute the agent (override in subclasses)
   */
  abstract execute(input: any): Promise<any>
}

