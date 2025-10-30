/**
 * Logging Utilities
 * Structured logging for agents and workflows
 */

export enum LogLevel {
  DEBUG = "DEBUG",
  INFO = "INFO",
  WARN = "WARN",
  ERROR = "ERROR",
}

export interface LogEntry {
  level: LogLevel
  message: string
  timestamp: string
  context?: string
  metadata?: Record<string, any>
}

/**
 * Logger class for structured logging
 */
export class Logger {
  constructor(private context: string) {}

  private log(level: LogLevel, message: string, metadata?: Record<string, any>) {
    const entry: LogEntry = {
      level,
      message,
      timestamp: new Date().toISOString(),
      context: this.context,
      metadata,
    }

    // In production, you might want to send logs to a service
    // For now, we'll use console
    const logFn = level === LogLevel.ERROR ? console.error :
                  level === LogLevel.WARN ? console.warn :
                  console.log

    logFn(JSON.stringify(entry))
  }

  debug(message: string, metadata?: Record<string, any>) {
    this.log(LogLevel.DEBUG, message, metadata)
  }

  info(message: string, metadata?: Record<string, any>) {
    this.log(LogLevel.INFO, message, metadata)
  }

  warn(message: string, metadata?: Record<string, any>) {
    this.log(LogLevel.WARN, message, metadata)
  }

  error(message: string, error?: Error, metadata?: Record<string, any>) {
    this.log(LogLevel.ERROR, message, {
      ...metadata,
      error: error ? {
        name: error.name,
        message: error.message,
        stack: error.stack,
      } : undefined,
    })
  }
}

/**
 * Create logger instance
 */
export function createLogger(context: string): Logger {
  return new Logger(context)
}

/**
 * Log agent execution
 */
export function logAgentExecution(
  agentName: string,
  input: any,
  output: any,
  duration: number
) {
  const logger = createLogger("AgentExecution")
  logger.info(`Agent executed: ${agentName}`, {
    agentName,
    duration,
    inputSize: JSON.stringify(input).length,
    outputSize: JSON.stringify(output).length,
  })
}

/**
 * Log tool execution
 */
export function logToolExecution(
  toolName: string,
  input: any,
  output: any,
  duration: number
) {
  const logger = createLogger("ToolExecution")
  logger.info(`Tool executed: ${toolName}`, {
    toolName,
    duration,
    inputSize: JSON.stringify(input).length,
    outputSize: JSON.stringify(output).length,
  })
}

