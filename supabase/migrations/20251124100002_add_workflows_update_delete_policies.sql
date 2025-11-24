-- Add missing UPDATE and DELETE policies for workflows table
-- These were missing from the initial schema, causing "cannot coerce to single JSON object" errors

-- Allow anyone to update workflows (you can restrict this later if needed)
CREATE POLICY "Allow update workflows" ON "public"."workflows"
FOR UPDATE
USING (true)
WITH CHECK (true);

-- Allow anyone to delete workflows (you can restrict this later if needed)
CREATE POLICY "Allow delete workflows" ON "public"."workflows"
FOR DELETE
USING (true);

-- Add comment
COMMENT ON POLICY "Allow update workflows" ON "public"."workflows" IS 'Allow all authenticated users to update workflows. Restrict to admin if needed.';
COMMENT ON POLICY "Allow delete workflows" ON "public"."workflows" IS 'Allow all authenticated users to delete workflows. Restrict to admin if needed.';
