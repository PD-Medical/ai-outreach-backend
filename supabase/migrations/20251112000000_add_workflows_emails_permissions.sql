-- Migration: Add individual permissions for Workflows and Emails
-- This allows admins to control access to Workflows, Campaigns, and Emails independently

-- Add new columns to role_permissions table
ALTER TABLE public.role_permissions
ADD COLUMN IF NOT EXISTS view_workflows BOOLEAN NOT NULL DEFAULT true,
ADD COLUMN IF NOT EXISTS view_emails BOOLEAN NOT NULL DEFAULT true;

-- Update existing rows to set values based on view_campaigns
-- If they had view_campaigns enabled, enable the new permissions too
-- This ensures existing data is consistent
UPDATE public.role_permissions
SET 
  view_workflows = view_campaigns,
  view_emails = view_campaigns;

-- Add comment for documentation
COMMENT ON COLUMN public.role_permissions.view_workflows IS 'Permission to view and access workflows page';
COMMENT ON COLUMN public.role_permissions.view_emails IS 'Permission to view and access emails page';

