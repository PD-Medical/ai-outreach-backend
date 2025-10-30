/**
 * Workflow-related TypeScript types
 */

export interface WorkflowMetadata {
  id: string
  name: string
  description: string
  version: string
  steps: WorkflowStep[]
}

export interface WorkflowStep {
  id: string
  name: string
  type: "agent" | "tool" | "decision" | "parallel"
  config: Record<string, any>
  nextSteps?: string[]
}

export interface WorkflowExecutionState {
  workflowId: string
  currentStep: string
  status: WorkflowStatus
  data: Record<string, any>
  history: WorkflowStepExecution[]
}

export enum WorkflowStatus {
  PENDING = "pending",
  RUNNING = "running",
  COMPLETED = "completed",
  FAILED = "failed",
  PAUSED = "paused",
}

export interface WorkflowStepExecution {
  stepId: string
  startTime: Date
  endTime?: Date
  status: WorkflowStatus
  input: any
  output?: any
  error?: string
}

export interface WorkflowExecutionResult {
  workflowId: string
  status: WorkflowStatus
  output: any
  error?: string
  metadata: {
    startTime: Date
    endTime: Date
    totalSteps: number
    completedSteps: number
  }
}

