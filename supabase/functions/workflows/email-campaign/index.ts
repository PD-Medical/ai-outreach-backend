/**
 * Email Campaign Workflow Endpoint
 * Orchestrates multi-step email campaign using LangGraph
 */

import "jsr:@supabase/functions-js/edge-runtime.d.ts"

import { EmailWorkflow } from "../../_shared/workflows/email-workflow.ts"
import { formatErrorResponse } from "../../_shared/utils/error-handler.ts"
import { createLogger } from "../../_shared/utils/logger.ts"

const logger = createLogger("EmailCampaignWorkflow")

Deno.serve(async (req) => {
  const startTime = Date.now()
  
  try {
    const { campaignId, contactIds } = await req.json()

    if (!campaignId || !contactIds || !Array.isArray(contactIds)) {
      return new Response(
        JSON.stringify({ 
          error: "Invalid input. Expected 'campaignId' (string) and 'contactIds' (array)." 
        }),
        { status: 400, headers: { "Content-Type": "application/json" } },
      )
    }

    logger.info("Email campaign workflow started", {
      campaignId,
      contactCount: contactIds.length,
    })

    // Execute workflow
    const workflow = new EmailWorkflow()
    const result = await workflow.execute({
      campaignId,
      contactIds,
    })

    const duration = Date.now() - startTime

    logger.info("Email campaign workflow completed", {
      duration,
      campaignId,
    })

    return new Response(
      JSON.stringify({
        ...result,
        metadata: {
          duration,
          campaignId,
          contactCount: contactIds.length,
        },
      }),
      { headers: { "Content-Type": "application/json" } },
    )
  } catch (error) {
    const duration = Date.now() - startTime
    
    logger.error("Email campaign workflow error", error as Error, {
      duration,
    })

    return new Response(
      JSON.stringify(formatErrorResponse(error as Error)),
      { status: 500, headers: { "Content-Type": "application/json" } },
    )
  }
})

/* To invoke locally:

  curl -i --location --request POST 'http://127.0.0.1:54321/functions/v1/workflows/email-campaign' \
    --header 'Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0' \
    --header 'Content-Type: application/json' \
    --data '{"campaignId":"camp_123","contactIds":["contact_1","contact_2","contact_3"]}'

*/

