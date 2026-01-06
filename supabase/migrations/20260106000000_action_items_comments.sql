-- Migration: Add comments JSONB column to action_items
-- Purpose: Allow users to add notes/comments to action items for tracking purposes

-- Add comments column to action_items
ALTER TABLE action_items
ADD COLUMN IF NOT EXISTS comments JSONB DEFAULT '[]'::jsonb;

-- Add comment for documentation
COMMENT ON COLUMN action_items.comments IS 'Array of comment objects: [{id, text, created_at, created_by}]';
