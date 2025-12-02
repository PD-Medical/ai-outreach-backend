-- Migration: Add signature_images column and storage RLS policies
-- Description: Enable rich text signature editor with CID-embedded images

-- Add signature_images column to mailboxes table
ALTER TABLE public.mailboxes
ADD COLUMN IF NOT EXISTS signature_images jsonb DEFAULT '[]'::jsonb;

-- Comment on the column structure
COMMENT ON COLUMN public.mailboxes.signature_images IS
'Array of signature images for CID embedding. Structure: [{ cid: string, storage_path: string, filename: string, content_type: string }]';

-- Storage RLS policies for signature images
-- Note: These policies allow authenticated users to manage signature images in the internal bucket

-- Policy: Allow authenticated users to upload signature images
CREATE POLICY "Users can upload signature images"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
    bucket_id = 'internal'
    AND (storage.foldername(name))[1] = 'signatures'
);

-- Policy: Allow authenticated users to read signature images
CREATE POLICY "Users can read signature images"
ON storage.objects FOR SELECT
TO authenticated
USING (
    bucket_id = 'internal'
    AND (storage.foldername(name))[1] = 'signatures'
);

-- Policy: Allow authenticated users to update signature images
CREATE POLICY "Users can update signature images"
ON storage.objects FOR UPDATE
TO authenticated
USING (
    bucket_id = 'internal'
    AND (storage.foldername(name))[1] = 'signatures'
)
WITH CHECK (
    bucket_id = 'internal'
    AND (storage.foldername(name))[1] = 'signatures'
);

-- Policy: Allow authenticated users to delete signature images
CREATE POLICY "Users can delete signature images"
ON storage.objects FOR DELETE
TO authenticated
USING (
    bucket_id = 'internal'
    AND (storage.foldername(name))[1] = 'signatures'
);
