-- ============================================================================
-- Migration: Enable RLS for Workflows and Workflow Executions
-- ============================================================================
-- Description: Enables Row Level Security and creates policies for workflows and workflow_executions tables
-- Date: 2025-01-17
-- ============================================================================

-- ============================================================================
-- 1. ENABLE ROW LEVEL SECURITY
-- ============================================================================

ALTER TABLE public.workflows ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.workflow_executions ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- 2. WORKFLOWS POLICIES
-- ============================================================================

-- Policy: Allow authenticated users to view all workflows
CREATE POLICY "workflows_select_all"
  ON public.workflows
  FOR SELECT
  TO authenticated
  USING (true);

-- Policy: Allow authenticated users to insert workflows
CREATE POLICY "workflows_insert_all"
  ON public.workflows
  FOR INSERT
  TO authenticated
  WITH CHECK (true);

-- Policy: Allow authenticated users to update workflows
CREATE POLICY "workflows_update_all"
  ON public.workflows
  FOR UPDATE
  TO authenticated
  USING (true)
  WITH CHECK (true);

-- Policy: Allow authenticated users to delete workflows (soft delete via is_active)
CREATE POLICY "workflows_delete_all"
  ON public.workflows
  FOR DELETE
  TO authenticated
  USING (true);

-- ============================================================================
-- 3. WORKFLOW_EXECUTIONS POLICIES
-- ============================================================================

-- Policy: Allow authenticated users to view all workflow executions
CREATE POLICY "workflow_executions_select_all"
  ON public.workflow_executions
  FOR SELECT
  TO authenticated
  USING (true);

-- Policy: Allow authenticated users to insert workflow executions
-- (Typically done by backend Lambda functions, but allowing authenticated users too)
CREATE POLICY "workflow_executions_insert_all"
  ON public.workflow_executions
  FOR INSERT
  TO authenticated
  WITH CHECK (true);

-- Policy: Allow authenticated users to update workflow executions
-- (For updating status, approval actions, etc.)
CREATE POLICY "workflow_executions_update_all"
  ON public.workflow_executions
  FOR UPDATE
  TO authenticated
  USING (true)
  WITH CHECK (true);

-- Policy: Allow authenticated users to delete workflow executions
CREATE POLICY "workflow_executions_delete_all"
  ON public.workflow_executions
  FOR DELETE
  TO authenticated
  USING (true);

-- ============================================================================
-- NOTES
-- ============================================================================
-- These policies allow all authenticated users full access to workflows and executions.
-- If you need more restrictive policies (e.g., organization-based access), you can:
-- 1. Add organization_id columns to workflows table
-- 2. Modify policies to check organization membership
-- 3. Use service_role key for backend Lambda functions instead of authenticated users
--
-- Example of organization-based policy (if you add organization_id):
-- CREATE POLICY "workflows_select_org"
--   ON public.workflows
--   FOR SELECT
--   TO authenticated
--   USING (
--     organization_id IN (
--       SELECT organization_id FROM organization_members
--       WHERE user_id = auth.uid()
--     )
--   );
-- ============================================================================

