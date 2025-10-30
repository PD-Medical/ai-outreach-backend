/**
 * Agent Type Definitions
 * Common types used across all agents
 */

export interface Message {
  role: "system" | "user" | "assistant" | "tool"
  content: string
  name?: string
}

export interface AgentRequest {
  messages: Message[]
  context?: Record<string, any>
  config?: {
    temperature?: number
    maxTokens?: number
  }
}

export interface AgentResponse {
  messages: Message[]
  output: string
  metadata?: {
    tokensUsed?: number
    toolCalls?: string[]
    duration?: number
  }
}

export interface ToolCall {
  id: string
  name: string
  arguments: Record<string, any>
  result?: any
}

export interface AgentState {
  messages: Message[]
  toolCalls: ToolCall[]
  context: Record<string, any>
}

