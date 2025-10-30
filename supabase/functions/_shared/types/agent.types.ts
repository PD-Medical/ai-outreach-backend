/**
 * Agent-related TypeScript types
 */

export interface AgentMetadata {
  id: string
  name: string
  type: AgentType
  version: string
  description: string
  capabilities: string[]
}

export enum AgentType {
  GENERAL = "general",
  EMAIL = "email",
  RESEARCH = "research",
  SCHEDULING = "scheduling",
  DATA_ANALYST = "data_analyst",
}

export interface AgentExecutionContext {
  userId?: string
  sessionId?: string
  timestamp: Date
  metadata?: Record<string, any>
}

export interface AgentExecutionResult {
  success: boolean
  output: any
  error?: string
  metadata: {
    executionTime: number
    tokensUsed?: number
    toolsUsed: string[]
  }
}

