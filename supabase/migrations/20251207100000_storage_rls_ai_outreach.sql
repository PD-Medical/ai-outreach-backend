-- Migration: Add RLS policies for ai-outreach storage bucket
-- Description: Allow authenticated users to browse and read files from ai-outreach bucket

-- Policy: Allow authenticated users to read/list all files in ai-outreach bucket
CREATE POLICY "Users can read ai-outreach files"
ON storage.objects FOR SELECT
TO authenticated
USING (bucket_id = 'ai-outreach');

-- Policy: Allow authenticated users to upload files to ai-outreach bucket
CREATE POLICY "Users can upload ai-outreach files"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (bucket_id = 'ai-outreach');

-- Policy: Allow authenticated users to update files in ai-outreach bucket
CREATE POLICY "Users can update ai-outreach files"
ON storage.objects FOR UPDATE
TO authenticated
USING (bucket_id = 'ai-outreach')
WITH CHECK (bucket_id = 'ai-outreach');

-- Policy: Allow authenticated users to delete files from ai-outreach bucket
CREATE POLICY "Users can delete ai-outreach files"
ON storage.objects FOR DELETE
TO authenticated
USING (bucket_id = 'ai-outreach');
