/**
 * Tool-related TypeScript types
 */

export interface ToolMetadata {
  name: string
  description: string
  category: ToolCategory
  version: string
  requiredPermissions?: string[]
}

export enum ToolCategory {
  DATABASE = "database",
  EMAIL = "email",
  CALENDAR = "calendar",
  SEARCH = "search",
  ANALYSIS = "analysis",
  COMMUNICATION = "communication",
  UTILITY = "utility",
}

export interface ToolExecutionResult {
  success: boolean
  data: any
  error?: string
  executionTime: number
}

export interface ToolConfig {
  timeout?: number
  retries?: number
  cache?: boolean
}

