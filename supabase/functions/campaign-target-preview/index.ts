/**
 * Campaign Target Preview Edge Function
 *
 * Converts form filters or natural language to SQL and returns target preview.
 * This function abstracts SQL generation from the user - they never see SQL.
 *
 * Modes:
 * - form: Converts FilterConfig to SQL with proper JOINs and WHERE clauses
 * - natural_language: Calls campaign-sql-agent Lambda for AI-powered SQL generation
 *
 * Deploy: supabase functions deploy campaign-target-preview
 */

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders, handleCors } from "../_shared/cors.ts";

// Lambda Function URL for natural language SQL generation
const CAMPAIGN_SQL_AGENT_URL = Deno.env.get("CAMPAIGN_SQL_AGENT_LAMBDA_URL") ||
  "http://host.docker.internal:3001/campaign-sql-agent";

// Types
interface FilterConfig {
  // Contact filters
  leadClassification?: string[];
  engagementLevel?: string[];
  status?: string[];
  tags?: string[];
  departments?: string[];
  leadScoreRange?: { min: number | null; max: number | null };

  // Organization filters
  regions?: string[];
  states?: string[];
  hospitalCategories?: string[];
  facilityTypes?: string[];
  industries?: string[];
  bedCountRange?: { min: number | null; max: number | null };
  hasMaternity?: boolean | null;
  hasOperatingTheatre?: boolean | null;
}

interface ExclusionConfig {
  excludeUnsubscribed: boolean;
  excludeBounced: boolean;
  excludeActiveCampaigns: boolean;
  excludeContactedDays: number | null;
  excludeCampaignIds: string[];
}

interface ClarificationResponse {
  question_id: string;
  question: string;
  answer: string;
}

interface ClarificationQuestion {
  id: string;
  question: string;
  ambiguous_term: string;
  suggestions: string[];
  allows_custom: boolean;
}

interface PreviewRequest {
  mode: 'form' | 'natural_language';
  filterConfig?: FilterConfig;
  naturalLanguageQuery?: string;
  exclusionConfig: ExclusionConfig;
  // Clarification flow fields
  clarificationResponses?: ClarificationResponse[];
  clarificationRound?: number;
}

interface PreviewContact {
  id: string;
  email: string;
  first_name: string | null;
  last_name: string | null;
  organization_name: string | null;
  lead_classification: string | null;
  engagement_level: string | null;
  lead_score: number | null;
}

interface PreviewResponse {
  totalCount: number;
  contacts: PreviewContact[];
  generatedSql?: string; // Internal use only, not exposed to UI
  // Clarification flow fields
  needsClarification?: boolean;
  confidenceScore?: number;
  interpretation?: string;
  clarificationQuestions?: ClarificationQuestion[];
  maxRoundsReached?: boolean;
}

serve(async (req) => {
  // Handle CORS preflight
  const corsResponse = handleCors(req);
  if (corsResponse) return corsResponse;

  // Only allow POST requests
  if (req.method !== "POST") {
    return new Response(
      JSON.stringify({ success: false, error: "Method not allowed" }),
      {
        status: 405,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  }

  try {
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""
    );

    // Parse request body
    const body: PreviewRequest = await req.json();
    const {
      mode,
      filterConfig,
      naturalLanguageQuery,
      exclusionConfig,
      clarificationResponses,
      clarificationRound
    } = body;

    console.log(`[CampaignTargetPreview] Mode: ${mode}, Round: ${clarificationRound || 0}`);

    // Validate request
    if (!mode) {
      return new Response(
        JSON.stringify({ success: false, error: "mode is required" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    if (mode === 'form' && !filterConfig) {
      return new Response(
        JSON.stringify({ success: false, error: "filterConfig is required for form mode" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    if (mode === 'natural_language' && !naturalLanguageQuery) {
      return new Response(
        JSON.stringify({ success: false, error: "naturalLanguageQuery is required for natural_language mode" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    let sql: string;
    let aiExplanation: string | undefined;
    let needsClarification = false;
    let confidenceScore: number | undefined;
    let interpretation: string | undefined;
    let clarificationQuestions: ClarificationQuestion[] | undefined;
    let maxRoundsReached = false;

    if (mode === 'form') {
      // Build SQL from form filters - no clarification needed
      sql = buildSqlFromFilters(filterConfig!, exclusionConfig);
      console.log(`[CampaignTargetPreview] Generated SQL from form: ${sql.substring(0, 200)}...`);
    } else {
      // Call Lambda for natural language SQL generation with clarification support
      console.log(`[CampaignTargetPreview] Calling SQL agent for: ${naturalLanguageQuery}`);
      if (clarificationResponses?.length) {
        console.log(`[CampaignTargetPreview] With ${clarificationResponses.length} clarification responses`);
      }

      const lambdaResponse = await fetch(CAMPAIGN_SQL_AGENT_URL, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          user_query: naturalLanguageQuery,
          preview: false, // We'll do our own preview
          exclusion_context: buildExclusionContext(exclusionConfig),
          clarification_responses: clarificationResponses || [],
          clarification_round: clarificationRound || 0,
        }),
      });

      if (!lambdaResponse.ok) {
        const errorText = await lambdaResponse.text();
        console.error(`[CampaignTargetPreview] Lambda error: ${errorText}`);
        throw new Error(`AI query generation failed: ${errorText}`);
      }

      const lambdaData = await lambdaResponse.json();
      const lambdaBody = typeof lambdaData.body === "string"
        ? JSON.parse(lambdaData.body)
        : lambdaData.body || lambdaData;

      if (lambdaBody.error) {
        throw new Error(lambdaBody.error);
      }

      sql = lambdaBody.sql;
      aiExplanation = lambdaBody.explanation;
      needsClarification = lambdaBody.needs_clarification || false;
      confidenceScore = lambdaBody.confidence_score;
      interpretation = lambdaBody.interpretation;
      maxRoundsReached = lambdaBody.max_rounds_reached || false;

      // Convert clarification questions from snake_case to camelCase
      if (lambdaBody.clarification_questions?.length) {
        clarificationQuestions = lambdaBody.clarification_questions.map((q: any) => ({
          id: q.id,
          question: q.question,
          ambiguousTerm: q.ambiguous_term,
          suggestions: q.suggestions || [],
          allowsCustom: q.allows_custom !== false, // Default to true
        }));
      }

      // Apply exclusion filters to the AI-generated SQL
      sql = applyExclusionsToSql(sql, exclusionConfig);

      console.log(`[CampaignTargetPreview] AI generated SQL: ${sql.substring(0, 200)}...`);
      console.log(`[CampaignTargetPreview] Confidence: ${confidenceScore}, Needs clarification: ${needsClarification}`);
    }

    // If clarification is needed, return early without executing SQL
    if (needsClarification && clarificationQuestions?.length) {
      console.log(`[CampaignTargetPreview] Returning clarification questions (${clarificationQuestions.length})`);

      const response: PreviewResponse = {
        totalCount: 0,
        contacts: [],
        needsClarification: true,
        confidenceScore,
        interpretation,
        clarificationQuestions,
        generatedSql: sql, // Include best-effort SQL for reference
      };

      return new Response(
        JSON.stringify({
          success: true,
          data: response,
          ...(aiExplanation && { aiExplanation }),
        }),
        {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    // Execute preview using RPC function
    const { data: previewData, error: previewError } = await supabase
      .rpc('exec_campaign_preview_sql', {
        query: sql,
        preview_limit: 100
      });

    if (previewError) {
      console.error(`[CampaignTargetPreview] Preview error:`, previewError);
      throw new Error(`Failed to preview targets: ${previewError.message}`);
    }

    const result = previewData?.[0] || { total_count: 0, preview_results: [] };

    // Format response
    const response: PreviewResponse = {
      totalCount: result.total_count || 0,
      contacts: (result.preview_results || []).map((row: any) => ({
        id: row.contact_id || row.id,
        email: row.email,
        first_name: row.first_name,
        last_name: row.last_name,
        organization_name: row.organization_name,
        lead_classification: row.lead_classification,
        engagement_level: row.engagement_level,
        lead_score: row.lead_score,
      })),
      generatedSql: sql,
      // Include clarification metadata even when proceeding
      needsClarification: false,
      confidenceScore,
      interpretation,
      maxRoundsReached,
    };

    console.log(`[CampaignTargetPreview] Found ${response.totalCount} contacts`);

    return new Response(
      JSON.stringify({
        success: true,
        data: response,
        ...(aiExplanation && { aiExplanation }),
      }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );

  } catch (error) {
    console.error("[CampaignTargetPreview] Error:", error);

    return new Response(
      JSON.stringify({
        success: false,
        error: error instanceof Error ? error.message : "Unknown error",
      }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  }
});

/**
 * Build SQL query from form-based filter configuration
 */
function buildSqlFromFilters(filters: FilterConfig, exclusions: ExclusionConfig): string {
  const selectClause = `
    SELECT
      c.id AS contact_id,
      c.email,
      c.first_name,
      c.last_name,
      c.lead_classification,
      c.engagement_level,
      c.lead_score,
      o.name AS organization_name
  `;

  const fromClause = `
    FROM contacts c
    LEFT JOIN organizations o ON c.organization_id = o.id
  `;

  const conditions: string[] = [];

  // Always filter for active status (unless explicitly including inactive)
  if (!filters.status?.length || !filters.status.includes('inactive')) {
    conditions.push("c.status = 'active'");
  }

  // Apply exclusions
  if (exclusions.excludeUnsubscribed) {
    conditions.push("c.status != 'unsubscribed'");
  }
  if (exclusions.excludeBounced) {
    conditions.push("c.status != 'bounced'");
  }

  // Contact filters
  if (filters.leadClassification?.length) {
    const values = filters.leadClassification.map(v => `'${escapeString(v)}'`).join(', ');
    conditions.push(`c.lead_classification IN (${values})`);
  }

  if (filters.engagementLevel?.length) {
    const values = filters.engagementLevel.map(v => `'${escapeString(v)}'`).join(', ');
    conditions.push(`c.engagement_level IN (${values})`);
  }

  if (filters.status?.length) {
    const values = filters.status.map(v => `'${escapeString(v)}'`).join(', ');
    conditions.push(`c.status IN (${values})`);
  }

  if (filters.departments?.length) {
    const values = filters.departments.map(v => `'${escapeString(v)}'`).join(', ');
    conditions.push(`c.department IN (${values})`);
  }

  if (filters.tags?.length) {
    // JSONB contains check for tags array
    const tagConditions = filters.tags.map(tag =>
      `c.tags @> '["${escapeString(tag)}"]'::jsonb`
    ).join(' OR ');
    conditions.push(`(${tagConditions})`);
  }

  if (filters.leadScoreRange?.min !== null && filters.leadScoreRange?.min !== undefined) {
    conditions.push(`c.lead_score >= ${parseInt(String(filters.leadScoreRange.min))}`);
  }

  if (filters.leadScoreRange?.max !== null && filters.leadScoreRange?.max !== undefined) {
    conditions.push(`c.lead_score <= ${parseInt(String(filters.leadScoreRange.max))}`);
  }

  // Organization filters
  if (filters.regions?.length) {
    const values = filters.regions.map(v => `'${escapeString(v)}'`).join(', ');
    conditions.push(`o.region IN (${values})`);
  }

  if (filters.states?.length) {
    const values = filters.states.map(v => `'${escapeString(v)}'`).join(', ');
    conditions.push(`o.state IN (${values})`);
  }

  if (filters.hospitalCategories?.length) {
    const values = filters.hospitalCategories.map(v => `'${escapeString(v)}'`).join(', ');
    conditions.push(`o.hospital_category IN (${values})`);
  }

  if (filters.facilityTypes?.length) {
    const values = filters.facilityTypes.map(v => `'${escapeString(v)}'`).join(', ');
    conditions.push(`o.facility_type IN (${values})`);
  }

  if (filters.industries?.length) {
    const values = filters.industries.map(v => `'${escapeString(v)}'`).join(', ');
    conditions.push(`o.industry IN (${values})`);
  }

  if (filters.bedCountRange?.min !== null && filters.bedCountRange?.min !== undefined) {
    conditions.push(`o.bed_count >= ${parseInt(String(filters.bedCountRange.min))}`);
  }

  if (filters.bedCountRange?.max !== null && filters.bedCountRange?.max !== undefined) {
    conditions.push(`o.bed_count <= ${parseInt(String(filters.bedCountRange.max))}`);
  }

  if (filters.hasMaternity === true) {
    conditions.push("o.has_maternity = true");
  } else if (filters.hasMaternity === false) {
    conditions.push("o.has_maternity = false");
  }

  if (filters.hasOperatingTheatre === true) {
    conditions.push("o.has_operating_theatre = true");
  } else if (filters.hasOperatingTheatre === false) {
    conditions.push("o.has_operating_theatre = false");
  }

  // Exclusion: contacts already in active campaigns
  if (exclusions.excludeActiveCampaigns) {
    conditions.push(`
      NOT EXISTS (
        SELECT 1 FROM campaign_enrollments ce
        JOIN campaign_sequences cs ON ce.campaign_sequence_id = cs.id
        WHERE ce.contact_id = c.id
          AND ce.status IN ('enrolled', 'active')
          AND cs.status IN ('scheduled', 'running')
      )
    `);
  }

  // Exclusion: specific campaign IDs
  if (exclusions.excludeCampaignIds?.length) {
    const ids = exclusions.excludeCampaignIds.map(id => `'${escapeString(id)}'`).join(', ');
    conditions.push(`
      NOT EXISTS (
        SELECT 1 FROM campaign_enrollments ce
        WHERE ce.contact_id = c.id
          AND ce.campaign_sequence_id IN (${ids})
      )
    `);
  }

  // Exclusion: contacts reached in last N days
  if (exclusions.excludeContactedDays && exclusions.excludeContactedDays > 0) {
    conditions.push(`
      NOT EXISTS (
        SELECT 1 FROM emails e
        WHERE e.contact_id = c.id
          AND e.direction = 'outgoing'
          AND e.sent_at > NOW() - INTERVAL '${exclusions.excludeContactedDays} days'
      )
    `);
  }

  // Build WHERE clause
  const whereClause = conditions.length > 0
    ? `WHERE ${conditions.join('\n    AND ')}`
    : '';

  // Build final SQL
  const sql = `${selectClause}${fromClause}${whereClause}
    ORDER BY c.lead_score DESC, c.updated_at DESC`;

  return sql.trim();
}

/**
 * Build exclusion context string for AI agent
 */
function buildExclusionContext(exclusions: ExclusionConfig): string {
  const rules: string[] = [];

  if (exclusions.excludeUnsubscribed) {
    rules.push("Exclude contacts with status 'unsubscribed'");
  }
  if (exclusions.excludeBounced) {
    rules.push("Exclude contacts with status 'bounced'");
  }
  if (exclusions.excludeActiveCampaigns) {
    rules.push("Exclude contacts already enrolled in active campaigns");
  }
  if (exclusions.excludeContactedDays) {
    rules.push(`Exclude contacts who received an outgoing email in the last ${exclusions.excludeContactedDays} days`);
  }

  return rules.length > 0
    ? `Additional requirements: ${rules.join('. ')}.`
    : '';
}

/**
 * Apply exclusion rules to AI-generated SQL
 *
 * The AI should already handle basic exclusions based on exclusion_context,
 * but we add any missing ones here as a safety net.
 *
 * Note: AI-generated SQL uses 'c' as the contacts table alias.
 */
function applyExclusionsToSql(sql: string, exclusions: ExclusionConfig): string {
  let modifiedSql = sql;
  const sqlLower = sql.toLowerCase();

  // Collect additional conditions that need to be added
  const additionalConditions: string[] = [];

  // Check for missing status exclusions
  if (exclusions.excludeUnsubscribed && !sqlLower.includes("unsubscribed")) {
    additionalConditions.push("c.status != 'unsubscribed'");
  }
  if (exclusions.excludeBounced && !sqlLower.includes("bounced")) {
    additionalConditions.push("c.status != 'bounced'");
  }

  // Check for missing campaign enrollment exclusions
  if (exclusions.excludeActiveCampaigns && !sqlLower.includes("campaign_enrollments")) {
    additionalConditions.push(`
      NOT EXISTS (
        SELECT 1 FROM campaign_enrollments ce
        JOIN campaign_sequences cs ON ce.campaign_sequence_id = cs.id
        WHERE ce.contact_id = c.id
          AND ce.status IN ('enrolled', 'active')
          AND cs.status IN ('scheduled', 'running')
      )
    `.trim());
  }

  // Check for missing contacted days exclusion
  if (exclusions.excludeContactedDays && exclusions.excludeContactedDays > 0 && !sqlLower.includes("emails")) {
    additionalConditions.push(`
      NOT EXISTS (
        SELECT 1 FROM emails e
        WHERE e.contact_id = c.id
          AND e.direction = 'outgoing'
          AND e.sent_at > NOW() - INTERVAL '${exclusions.excludeContactedDays} days'
      )
    `.trim());
  }

  // If no additional conditions needed, return original SQL
  if (additionalConditions.length === 0) {
    return modifiedSql;
  }

  // Add conditions to the WHERE clause
  if (sqlLower.includes('where')) {
    // Find WHERE keyword and insert conditions after the existing WHERE clause
    // We need to be careful to add them at the right place (before ORDER BY, LIMIT, etc.)
    const orderByMatch = sqlLower.match(/\border\s+by\b/);
    const limitMatch = sqlLower.match(/\blimit\b/);
    const groupByMatch = sqlLower.match(/\bgroup\s+by\b/);

    // Find the earliest terminator
    let insertPosition = sql.length;
    if (orderByMatch && orderByMatch.index !== undefined) {
      insertPosition = Math.min(insertPosition, orderByMatch.index);
    }
    if (limitMatch && limitMatch.index !== undefined) {
      insertPosition = Math.min(insertPosition, limitMatch.index);
    }
    if (groupByMatch && groupByMatch.index !== undefined) {
      insertPosition = Math.min(insertPosition, groupByMatch.index);
    }

    const beforeTerminator = sql.substring(0, insertPosition).trim();
    const afterTerminator = sql.substring(insertPosition);

    modifiedSql = `${beforeTerminator} AND ${additionalConditions.join(' AND ')} ${afterTerminator}`;
  } else {
    // No WHERE clause exists - need to add one
    // Find where to insert (before ORDER BY, LIMIT, etc.)
    const orderByMatch = sqlLower.match(/\border\s+by\b/);
    const limitMatch = sqlLower.match(/\blimit\b/);

    let insertPosition = sql.length;
    if (orderByMatch && orderByMatch.index !== undefined) {
      insertPosition = Math.min(insertPosition, orderByMatch.index);
    }
    if (limitMatch && limitMatch.index !== undefined) {
      insertPosition = Math.min(insertPosition, limitMatch.index);
    }

    const beforeTerminator = sql.substring(0, insertPosition).trim();
    const afterTerminator = sql.substring(insertPosition);

    modifiedSql = `${beforeTerminator} WHERE ${additionalConditions.join(' AND ')} ${afterTerminator}`;
  }

  return modifiedSql.trim();
}

/**
 * Escape string for SQL to prevent injection
 */
function escapeString(str: string): string {
  return str.replace(/'/g, "''").replace(/\\/g, "\\\\");
}
