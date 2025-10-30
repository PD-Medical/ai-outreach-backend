/**
 * Error Handling Utilities
 * Centralized error handling for agents and workflows
 */

export class AgentError extends Error {
  constructor(
    message: string,
    public code: string,
    public statusCode: number = 500,
    public details?: any
  ) {
    super(message)
    this.name = "AgentError"
  }
}

export class ToolError extends Error {
  constructor(
    message: string,
    public toolName: string,
    public details?: any
  ) {
    super(message)
    this.name = "ToolError"
  }
}

export class WorkflowError extends Error {
  constructor(
    message: string,
    public workflowId: string,
    public stepId?: string,
    public details?: any
  ) {
    super(message)
    this.name = "WorkflowError"
  }
}

/**
 * Format error for API response
 */
export function formatErrorResponse(error: Error) {
  if (error instanceof AgentError) {
    return {
      error: error.message,
      code: error.code,
      details: error.details,
    }
  }

  if (error instanceof ToolError) {
    return {
      error: error.message,
      tool: error.toolName,
      details: error.details,
    }
  }

  if (error instanceof WorkflowError) {
    return {
      error: error.message,
      workflowId: error.workflowId,
      stepId: error.stepId,
      details: error.details,
    }
  }

  // Generic error
  return {
    error: error.message || "An unexpected error occurred",
    type: error.name,
  }
}

/**
 * Handle errors in agent execution
 */
export async function withErrorHandling<T>(
  fn: () => Promise<T>,
  context: string
): Promise<T> {
  try {
    return await fn()
  } catch (error) {
    console.error(`Error in ${context}:`, error)
    throw error
  }
}

/**
 * Retry logic for tool execution
 */
export async function withRetry<T>(
  fn: () => Promise<T>,
  maxRetries: number = 3,
  delayMs: number = 1000
): Promise<T> {
  let lastError: Error

  for (let attempt = 1; attempt <= maxRetries; attempt++) {
    try {
      return await fn()
    } catch (error) {
      lastError = error as Error
      console.warn(`Attempt ${attempt} failed:`, error)

      if (attempt < maxRetries) {
        await new Promise(resolve => setTimeout(resolve, delayMs * attempt))
      }
    }
  }

  throw lastError!
}

