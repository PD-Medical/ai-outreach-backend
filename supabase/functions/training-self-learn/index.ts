/**
 * Training Self-Learn Edge Function
 *
 * Processes training feedback with per-item LLM calls (each with full
 * conversation context), then consolidates into instruction updates.
 * No agent/Lambda needed — just structured LLM calls via OpenRouter.
 *
 * POST { training_session_id: string }
 */

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";
import { requireAuth } from "../_shared/auth.ts";

// ─── Types ───────────────────────────────────────────────────────────────────

interface FeedbackItem {
  id: string;
  decision: string;
  feedback: string | null;
  edited_subject: string | null;
  edited_body: string | null;
  email_drafts: {
    id: string;
    subject: string;
    body_plain: string | null;
    body_html: string | null;
    generation_confidence: number | null;
    source_email_id: string | null;
    conversation_id: string | null;
  };
}

interface ThreadEmail {
  from_email: string;
  from_name: string | null;
  subject: string | null;
  body_plain: string | null;
  direction: string;
  received_at: string;
}

interface PerFeedbackResult {
  feedback_valid: boolean;
  validation_reason: string;
  revised_confidence: number;
  confidence_reasoning: string;
  key_reflection: string;
}

interface ConsolidationResult {
  refined_instructions: string;
  instructions_diff: string;
}

// ─── LLM Call ────────────────────────────────────────────────────────────────

async function callLLM(
  model: string,
  apiKey: string,
  systemPrompt: string,
  userPrompt: string,
): Promise<Record<string, unknown>> {
  const resp = await fetch("https://openrouter.ai/api/v1/chat/completions", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model,
      temperature: 0.2,
      response_format: { type: "json_object" },
      messages: [
        { role: "system", content: systemPrompt },
        { role: "user", content: userPrompt },
      ],
    }),
  });

  if (!resp.ok) {
    const errText = await resp.text();
    throw new Error(`LLM call failed (${resp.status}): ${errText}`);
  }

  const data = await resp.json();
  const content = data.choices?.[0]?.message?.content;
  if (!content) throw new Error("Empty LLM response");
  return JSON.parse(content);
}

// ─── Prompts ─────────────────────────────────────────────────────────────────

const PER_FEEDBACK_SYSTEM = `You are an AI training analyst. You evaluate human feedback on AI-generated email drafts to improve future drafting. Always respond with valid JSON.`;

function buildPerFeedbackPrompt(
  feedback: FeedbackItem,
  thread: ThreadEmail[],
): string {
  const draft = feedback.email_drafts;

  let threadSection = "No conversation history available.";
  if (thread.length > 0) {
    threadSection = thread
      .map(
        (e) =>
          `[${e.direction === "incoming" ? "INBOUND" : "OUTBOUND"}] From: ${e.from_name || e.from_email}\nSubject: ${e.subject || "(no subject)"}\n${(e.body_plain || "").slice(0, 1000)}`,
      )
      .join("\n---\n");
  }

  let humanDecisionSection = `Action: ${feedback.decision}`;
  if (feedback.feedback) {
    humanDecisionSection += `\nFeedback: ${feedback.feedback}`;
  }
  if (feedback.edited_subject) {
    humanDecisionSection += `\nEdited Subject: ${feedback.edited_subject}`;
  }
  if (feedback.edited_body) {
    humanDecisionSection += `\nEdited Body:\n${feedback.edited_body.slice(0, 1500)}`;
  }

  return `## Conversation Thread (oldest first)
${threadSection}

## AI-Generated Draft
Subject: ${draft.subject}
Body:
${(draft.body_plain || "").slice(0, 2000)}
Original AI Confidence: ${draft.generation_confidence ?? "unknown"}

## Human Decision
${humanDecisionSection}

Evaluate:
1. Is this feedback valid and actionable for improving future drafts?
2. Given the conversation context and the human's decision, what should the revised confidence be? (0.00 = terrible draft, 1.00 = perfect draft that needed no changes)
3. What is the key reflection — what should the AI learn from this specific feedback?

Return JSON:
{
  "feedback_valid": boolean,
  "validation_reason": "why valid or invalid",
  "revised_confidence": number between 0.00 and 1.00,
  "confidence_reasoning": "why this confidence score",
  "key_reflection": "the specific lesson: what to do differently, what pattern to remember, what tone/content/structure adjustment is needed"
}`;
}

const CONSOLIDATION_SYSTEM = `You are refining email drafting instructions based on validated human feedback. Be conservative — only add rules backed by multiple signals. Build upon existing instructions. Always respond with valid JSON.`;

function buildConsolidationPrompt(
  currentInstructions: string,
  reflections: Array<{ decision: string; key_reflection: string; confidence_reasoning: string }>,
): string {
  const reflectionLines = reflections
    .map(
      (r, i) =>
        `${i + 1}. [${r.decision}] ${r.key_reflection}\n   Confidence note: ${r.confidence_reasoning}`,
    )
    .join("\n\n");

  return `## Current Drafting Instructions
${currentInstructions || "(No instructions yet — this is the first training session)"}

## Validated Feedback Reflections (${reflections.length} items)
${reflectionLines}

Based on these reflections, update the drafting instructions. Rules:
- Be conservative — only add rules backed by multiple signals
- Build upon existing instructions, don't replace wholesale
- Focus on patterns, not one-off corrections
- Keep instructions concise and actionable

Return JSON:
{
  "refined_instructions": "the full updated instructions text",
  "instructions_diff": "a brief summary of what changed and why"
}`;
}

// ─── Handler ─────────────────────────────────────────────────────────────────

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    const auth = await requireAuth(req);
    if (auth instanceof Response) return auth;

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    );

    const { training_session_id } = await req.json();
    if (!training_session_id) {
      return new Response(
        JSON.stringify({ error: "training_session_id required" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    // Get config
    const openRouterKey = Deno.env.get("OPENROUTER_API_KEY");
    if (!openRouterKey) {
      return new Response(
        JSON.stringify({ error: "OPENROUTER_API_KEY not configured" }),
        { status: 503, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const { data: modelConfig } = await supabase
      .from("system_config")
      .select("value")
      .eq("key", "training_model")
      .single();
    // system_config stores JSONB — value comes back as a JSON type (string with quotes).
    // Strip surrounding quotes if present.
    let model = String(modelConfig?.value ?? "deepseek/deepseek-v3.2");
    if (model.startsWith('"') && model.endsWith('"')) {
      model = model.slice(1, -1);
    }
    console.log(`Using model: ${model}`);

    // Verify session
    const { data: session, error: sessErr } = await supabase
      .from("email_training_sessions")
      .select("*")
      .eq("id", training_session_id)
      .single();

    if (sessErr || !session) {
      return new Response(
        JSON.stringify({ error: "Session not found" }),
        { status: 404, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    // Mark as learning in progress
    await supabase
      .from("email_training_sessions")
      .update({ status: "learning_in_progress" })
      .eq("id", training_session_id);

    // Fetch feedback with drafts
    const { data: feedbackItems, error: fbErr } = await supabase
      .from("email_training_feedback")
      .select(`
        id, decision, feedback, edited_subject, edited_body,
        email_drafts(id, subject, body_plain, body_html, generation_confidence, source_email_id, conversation_id)
      `)
      .eq("training_session_id", training_session_id)
      .order("sequence_order", { ascending: true });

    if (fbErr || !feedbackItems?.length) {
      await supabase
        .from("email_training_sessions")
        .update({ status: "failed" })
        .eq("id", training_session_id);
      return new Response(
        JSON.stringify({ error: "No feedback found for session" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    console.log(`Processing ${feedbackItems.length} feedback items for session ${training_session_id}`);

    // ─── Phase 1: Per-feedback LLM calls (concurrent) ─────────────────

    const validReflections: Array<{ decision: string; key_reflection: string; confidence_reasoning: string }> = [];
    let totalRevisedConfidence = 0;
    let totalGenerationConfidence = 0;
    let validCount = 0;

    // Pre-fetch all conversation threads in parallel
    const threadPromises = (feedbackItems as unknown as FeedbackItem[]).map(async (item) => {
      const draft = item.email_drafts;
      if (!draft.conversation_id) return { item, thread: [] as ThreadEmail[] };
      const { data: emails } = await supabase
        .from("emails")
        .select("from_email, from_name, subject, body_plain, direction, received_at")
        .eq("conversation_id", draft.conversation_id)
        .order("received_at", { ascending: true })
        .limit(20);
      return { item, thread: (emails || []) as ThreadEmail[] };
    });
    const itemsWithThreads = await Promise.all(threadPromises);

    // Run all LLM calls concurrently
    const llmResults = await Promise.allSettled(
      itemsWithThreads.map(async ({ item, thread }) => {
        const result = (await callLLM(
          model,
          openRouterKey,
          PER_FEEDBACK_SYSTEM,
          buildPerFeedbackPrompt(item, thread),
        )) as unknown as PerFeedbackResult;
        return { item, result };
      })
    );

    // Process results and write back
    for (const settled of llmResults) {
      if (settled.status === "rejected") {
        console.error("LLM call failed:", settled.reason);
        continue;
      }
      const { item, result } = settled.value;
      const draft = item.email_drafts;

      try {
        await supabase
          .from("email_training_feedback")
          .update({
            feedback_valid: result.feedback_valid,
            feedback_validation_reason: result.validation_reason,
            revised_confidence: result.revised_confidence,
            confidence_reasoning: result.confidence_reasoning,
          })
          .eq("id", item.id);

        await supabase
          .from("email_drafts")
          .update({ revised_confidence: result.revised_confidence })
          .eq("id", draft.id);
      } catch (err) {
        console.error(`Failed to write results for ${item.id}:`, err);
      }

      totalRevisedConfidence += result.revised_confidence ?? 0;
      totalGenerationConfidence += (draft.generation_confidence ?? 0);

      if (result.feedback_valid) {
        validCount++;
        validReflections.push({
          decision: item.decision,
          key_reflection: result.key_reflection,
          confidence_reasoning: result.confidence_reasoning,
        });
      }

      console.log(`Feedback ${item.id}: valid=${result.feedback_valid}, confidence=${result.revised_confidence}`);
    }

    const avgRevisedConfidence = feedbackItems.length > 0
      ? totalRevisedConfidence / feedbackItems.length
      : null;
    const avgGenerationConfidence = feedbackItems.length > 0
      ? totalGenerationConfidence / feedbackItems.length
      : null;

    // ─── Phase 2: Consolidation ────────────────────────────────────────

    let instructionsDiff = "No valid feedback to consolidate.";
    let refinedInstructions = "";

    if (validReflections.length > 0) {
      // Get current instructions
      const { data: promptRow } = await supabase
        .from("prompts")
        .select("content")
        .eq("key", "email_training_instructions")
        .single();

      const currentInstructions = promptRow?.content || "";

      try {
        const consolidation = (await callLLM(
          model,
          openRouterKey,
          CONSOLIDATION_SYSTEM,
          buildConsolidationPrompt(currentInstructions, validReflections),
        )) as unknown as ConsolidationResult;

        refinedInstructions = consolidation.refined_instructions;
        instructionsDiff = consolidation.instructions_diff;

        // Update instructions in DB
        await supabase
          .from("prompts")
          .update({
            content: refinedInstructions,
            updated_at: new Date().toISOString(),
          })
          .eq("key", "email_training_instructions");

        console.log(`Instructions updated: ${instructionsDiff}`);
      } catch (err) {
        console.error("Consolidation LLM call failed:", err);
        instructionsDiff = `Consolidation failed: ${(err as Error).message}`;
      }
    }

    // ─── Phase 3: Update session ───────────────────────────────────────

    await supabase
      .from("email_training_sessions")
      .update({
        status: "learning_complete",
        learning_output: refinedInstructions || null,
        instructions_diff: instructionsDiff,
        feedback_validation_notes: `${validCount}/${feedbackItems.length} feedback items validated`,
        avg_revised_confidence: avgRevisedConfidence,
        avg_generation_confidence: avgGenerationConfidence,
        learning_completed_at: new Date().toISOString(),
      })
      .eq("id", training_session_id);

    // ─── Phase 4: Update rolling system confidence ─────────────────────

    let systemConfidenceScore: number | null = null;
    try {
      const { data: recentSessions } = await supabase
        .from("email_training_sessions")
        .select("avg_revised_confidence")
        .eq("status", "learning_complete")
        .not("avg_revised_confidence", "is", null)
        .order("learning_completed_at", { ascending: false })
        .limit(5);

      if (recentSessions && recentSessions.length > 0) {
        const weights = [5, 4, 3, 2, 1];
        let weightedSum = 0;
        let weightTotal = 0;
        for (let i = 0; i < recentSessions.length; i++) {
          const w = weights[i] || 1;
          weightedSum += (recentSessions[i].avg_revised_confidence as number) * w;
          weightTotal += w;
        }
        systemConfidenceScore = weightedSum / weightTotal;

        await supabase
          .from("system_config")
          .upsert(
            {
              key: "email_agent_confidence_score",
              value: JSON.stringify(Math.round(systemConfidenceScore * 100) / 100),
              description: "Rolling weighted confidence score from training sessions",
            },
            { onConflict: "key" },
          );
      }
    } catch (err) {
      console.error("Failed to update system confidence:", err);
    }

    // ─── Response ──────────────────────────────────────────────────────

    const responseBody = {
      session_id: training_session_id,
      status: "learning_complete",
      feedback_count: feedbackItems.length,
      valid_feedback_count: validCount,
      instructions_diff: instructionsDiff,
      avg_revised_confidence: avgRevisedConfidence,
      system_confidence_score: systemConfidenceScore,
    };

    console.log("Self-learning complete:", responseBody);

    return new Response(JSON.stringify(responseBody), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err) {
    console.error("Self-learning failed:", err);
    return new Response(
      JSON.stringify({ error: (err as Error).message }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }
});
