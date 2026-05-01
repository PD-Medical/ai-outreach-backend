-- ============================================================================
-- email_agent_runs — audit trail for every email-agent invocation
-- ============================================================================
-- One row per agent run regardless of outcome. Created at graph start;
-- terminal state (`outcome`) and `completed_at` set at END.
--
-- Purpose: gives user transparency for non-draft outcomes (skip / reject /
-- info_insufficient) without polluting `email_drafts` (which stays
-- valid-drafts-only). Covers all three invocation paths uniformly:
--   - workflow:  triggered by workflow-executor (links to workflow_executions)
--   - manual:    "Reply with AI" from Emails page (no workflow_executions row)
--   - redraft:   user-feedback-driven revision of an existing draft
--
-- See plan: ~/.claude/plans/mossy-puzzling-church.md (Persistence section)
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.email_agent_runs (
    id                       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    invocation_context       VARCHAR(16) NOT NULL,
    workflow_execution_id    UUID REFERENCES public.workflow_executions(id) ON DELETE SET NULL,
    source_email_id          UUID REFERENCES public.emails(id) ON DELETE SET NULL,
    contact_id               UUID REFERENCES public.contacts(id) ON DELETE SET NULL,
    from_mailbox_id          UUID NOT NULL REFERENCES public.mailboxes(id) ON DELETE RESTRICT,
    outcome                  VARCHAR(24) NOT NULL,
    outcome_reasoning        TEXT,
    plan_output              JSONB,
    review_output            JSONB,
    draft_id                 UUID REFERENCES public.email_drafts(id) ON DELETE SET NULL,
    revision_count           INT NOT NULL DEFAULT 0,
    llm_conversation_history JSONB,
    gathered_context         JSONB,
    started_at               TIMESTAMPTZ NOT NULL DEFAULT now(),
    completed_at             TIMESTAMPTZ,

    CONSTRAINT email_agent_runs_invocation_context_chk
        CHECK (invocation_context IN ('workflow', 'manual', 'redraft')),
    CONSTRAINT email_agent_runs_outcome_chk
        CHECK (outcome IN ('drafted', 'skipped', 'info_insufficient', 'rejected', 'in_progress')),
    -- Terminal-state invariant: outcome='drafted' iff draft_id IS NOT NULL.
    -- in_progress is exempt — mid-graph state may briefly hold either combo.
    CONSTRAINT email_agent_runs_draft_id_outcome_chk
        CHECK (
            outcome = 'in_progress'
            OR (outcome = 'drafted') = (draft_id IS NOT NULL)
        )
);

CREATE INDEX IF NOT EXISTS idx_eagent_runs_workflow_execution
    ON public.email_agent_runs (workflow_execution_id)
    WHERE workflow_execution_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_eagent_runs_source_email
    ON public.email_agent_runs (source_email_id)
    WHERE source_email_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_eagent_runs_draft
    ON public.email_agent_runs (draft_id)
    WHERE draft_id IS NOT NULL;

-- Non-drafted outcomes are the "user transparency" surface — query often.
CREATE INDEX IF NOT EXISTS idx_eagent_runs_non_drafted_outcome
    ON public.email_agent_runs (outcome, started_at DESC)
    WHERE outcome <> 'drafted';

CREATE INDEX IF NOT EXISTS idx_eagent_runs_started_at
    ON public.email_agent_runs (started_at DESC);

-- ==========================================================================
-- RLS
-- ==========================================================================
ALTER TABLE public.email_agent_runs ENABLE ROW LEVEL SECURITY;

-- Authenticated users can read runs (UI surfaces transparency).
DROP POLICY IF EXISTS "Users can read email_agent_runs" ON public.email_agent_runs;
CREATE POLICY "Users can read email_agent_runs"
    ON public.email_agent_runs
    FOR SELECT
    USING (auth.role() = 'authenticated');

-- Service role (Lambda) full access.
DROP POLICY IF EXISTS "Service role manages email_agent_runs" ON public.email_agent_runs;
CREATE POLICY "Service role manages email_agent_runs"
    ON public.email_agent_runs
    FOR ALL
    USING (auth.role() = 'service_role');

GRANT SELECT ON public.email_agent_runs TO authenticated;
GRANT ALL ON public.email_agent_runs TO service_role;

-- ==========================================================================
-- Realtime: enable for live UI updates as runs progress
-- ==========================================================================
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables
        WHERE pubname = 'supabase_realtime' AND tablename = 'email_agent_runs'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.email_agent_runs;
    END IF;
END $$;

COMMENT ON TABLE public.email_agent_runs IS
    'Audit trail for every email-agent invocation. One row per agent run regardless of outcome (drafted / skipped / rejected / info_insufficient). Covers workflow + manual + redraft invocation paths uniformly.';
COMMENT ON COLUMN public.email_agent_runs.invocation_context IS
    'Origin of the invocation: workflow (from workflow-executor), manual (Reply with AI from Emails page), or redraft (user-feedback-driven revision).';
COMMENT ON COLUMN public.email_agent_runs.outcome IS
    'Terminal state of the agent graph. ''drafted'' implies an email_drafts row was created (see draft_id). ''in_progress'' is a transient state during execution.';
COMMENT ON COLUMN public.email_agent_runs.plan_output IS
    'JSON output from the plan node: decision, reasoning, recipients, steps, compliance_checklist, info_gaps.';
COMMENT ON COLUMN public.email_agent_runs.review_output IS
    'JSON output from the review node: verdict, issues, reasoning, step_coverage_check.';
COMMENT ON COLUMN public.email_agent_runs.gathered_context IS
    'Audit snapshot of selector projections (plan/draft/review input views) and the source data ids the agent saw — answers "what did each node see?".';
