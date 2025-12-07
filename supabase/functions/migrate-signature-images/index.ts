/**
 * One-time Migration: Move signature images from 'ai-outreach' bucket to 'internal' bucket
 *
 * This edge function migrates existing signature images from the 'ai-outreach' bucket
 * to the 'internal' bucket and updates the mailboxes.signature_images JSONB paths.
 *
 * Usage: Invoke once to migrate existing logos, then this function can be removed.
 */

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

const SOURCE_BUCKET = "ai-outreach";
const TARGET_BUCKET = "internal";
const SIGNATURES_FOLDER = "signatures";

if (!SUPABASE_URL || !SERVICE_ROLE_KEY) {
  throw new Error("Missing Supabase environment variables");
}

const supabaseAdmin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
  auth: {
    autoRefreshToken: false,
    persistSession: false,
  },
});

interface SignatureImage {
  cid: string;
  storage_path: string;
  filename: string;
  content_type: string;
}

interface MigrationResult {
  mailboxId: string;
  email: string;
  imagesProcessed: number;
  imagesMigrated: number;
  errors: string[];
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const results: MigrationResult[] = [];
    let totalMigrated = 0;
    let totalErrors = 0;

    // 1) Find all mailboxes with signature_images
    const { data: mailboxes, error: selectError } = await supabaseAdmin
      .from("mailboxes")
      .select("id, email, signature_images")
      .not("signature_images", "is", null)
      .neq("signature_images", "[]");

    if (selectError) {
      console.error("Failed to fetch mailboxes:", selectError);
      return new Response(
        JSON.stringify({ success: false, error: "Failed to fetch mailboxes" }),
        { status: 500, headers: { "Content-Type": "application/json", ...corsHeaders } }
      );
    }

    if (!mailboxes || mailboxes.length === 0) {
      return new Response(
        JSON.stringify({
          success: true,
          message: "No mailboxes with signature images found",
          results: [],
        }),
        { headers: { "Content-Type": "application/json", ...corsHeaders } }
      );
    }

    console.log(`Found ${mailboxes.length} mailboxes with signature images`);

    // 2) Process each mailbox
    for (const mailbox of mailboxes) {
      const result: MigrationResult = {
        mailboxId: mailbox.id,
        email: mailbox.email,
        imagesProcessed: 0,
        imagesMigrated: 0,
        errors: [],
      };

      const signatureImages = mailbox.signature_images as SignatureImage[];
      if (!signatureImages || signatureImages.length === 0) {
        results.push(result);
        continue;
      }

      const updatedImages: SignatureImage[] = [];

      for (const img of signatureImages) {
        result.imagesProcessed++;

        // Check if already in internal bucket (path starts with signatures/)
        if (img.storage_path.startsWith(`${SIGNATURES_FOLDER}/`)) {
          console.log(`Image ${img.cid} already in internal bucket, skipping`);
          updatedImages.push(img);
          continue;
        }

        try {
          // Download from source bucket (ai-outreach)
          const { data: fileData, error: downloadError } = await supabaseAdmin.storage
            .from(SOURCE_BUCKET)
            .download(img.storage_path);

          if (downloadError || !fileData) {
            result.errors.push(`Failed to download ${img.cid}: ${downloadError?.message || "No data"}`);
            console.error(`Failed to download ${img.storage_path}:`, downloadError);
            // Keep original path if download fails
            updatedImages.push(img);
            continue;
          }

          // Generate new path in internal bucket
          const extension = img.filename.split(".").pop() || "png";
          const newStoragePath = `${SIGNATURES_FOLDER}/${mailbox.id}/${img.cid}.${extension}`;

          // Upload to target bucket (internal)
          const { error: uploadError } = await supabaseAdmin.storage
            .from(TARGET_BUCKET)
            .upload(newStoragePath, fileData, {
              contentType: img.content_type,
              upsert: true, // Overwrite if exists
            });

          if (uploadError) {
            result.errors.push(`Failed to upload ${img.cid}: ${uploadError.message}`);
            console.error(`Failed to upload to ${newStoragePath}:`, uploadError);
            // Keep original path if upload fails
            updatedImages.push(img);
            continue;
          }

          // Update image metadata with new path
          updatedImages.push({
            cid: img.cid,
            storage_path: newStoragePath,
            filename: img.filename,
            content_type: img.content_type,
          });

          result.imagesMigrated++;
          totalMigrated++;
          console.log(`Migrated ${img.cid}: ${img.storage_path} -> ${newStoragePath}`);

          // Optionally delete from source bucket (commented out for safety)
          // await supabaseAdmin.storage.from(SOURCE_BUCKET).remove([img.storage_path]);

        } catch (err) {
          const errorMsg = err instanceof Error ? err.message : "Unknown error";
          result.errors.push(`Error processing ${img.cid}: ${errorMsg}`);
          console.error(`Error processing ${img.cid}:`, err);
          updatedImages.push(img); // Keep original on error
        }
      }

      // 3) Update mailbox with new signature_images paths
      if (result.imagesMigrated > 0) {
        const { error: updateError } = await supabaseAdmin
          .from("mailboxes")
          .update({ signature_images: updatedImages })
          .eq("id", mailbox.id);

        if (updateError) {
          result.errors.push(`Failed to update mailbox: ${updateError.message}`);
          console.error(`Failed to update mailbox ${mailbox.id}:`, updateError);
          totalErrors++;
        }
      }

      if (result.errors.length > 0) {
        totalErrors += result.errors.length;
      }

      results.push(result);
    }

    return new Response(
      JSON.stringify({
        success: true,
        message: `Migration complete: ${totalMigrated} images migrated, ${totalErrors} errors`,
        totalMailboxes: mailboxes.length,
        totalMigrated,
        totalErrors,
        results,
      }),
      { headers: { "Content-Type": "application/json", ...corsHeaders } }
    );

  } catch (err) {
    console.error("Migration error:", err);
    return new Response(
      JSON.stringify({
        success: false,
        error: err instanceof Error ? err.message : "Unknown error",
      }),
      { status: 500, headers: { "Content-Type": "application/json", ...corsHeaders } }
    );
  }
});
