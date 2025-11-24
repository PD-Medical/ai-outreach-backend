-- Add RLS policies for workflow_executions table
-- This fixes the issue where frontend cannot access workflow execution data

-- Allow read access to workflow_executions
CREATE POLICY "Allow read workflow_executions"
  ON workflow_executions
  FOR SELECT
  USING (true);

-- Allow insert access to workflow_executions
CREATE POLICY "Allow insert workflow_executions"
  ON workflow_executions
  FOR INSERT
  WITH CHECK (true);

-- Allow update access to workflow_executions
CREATE POLICY "Allow update workflow_executions"
  ON workflow_executions
  FOR UPDATE
  USING (true);

-- Allow delete access to workflow_executions (for testing/cleanup)
CREATE POLICY "Allow delete workflow_executions"
  ON workflow_executions
  FOR DELETE
  USING (true);
