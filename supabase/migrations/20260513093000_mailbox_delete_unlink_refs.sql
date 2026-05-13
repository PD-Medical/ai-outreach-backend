-- Allow a mailbox to be deleted by unlinking its references in three tables
-- that previously blocked the delete with a foreign-key violation (Postgres
-- code 23503).
--
-- Records in those tables survive the deletion with `from_mailbox_id = NULL`,
-- preserving history. Campaigns won't run until reassigned to a mailbox;
-- drafts and agent-run logs remain visible.

-- campaign_sequences.from_mailbox_id is already nullable; just relax the FK.
ALTER TABLE public.campaign_sequences
  DROP CONSTRAINT campaign_sequences_from_mailbox_id_fkey;

ALTER TABLE public.campaign_sequences
  ADD  CONSTRAINT campaign_sequences_from_mailbox_id_fkey
    FOREIGN KEY (from_mailbox_id) REFERENCES public.mailboxes(id) ON DELETE SET NULL;

-- email_drafts.from_mailbox_id: drop NOT NULL + relax the FK.
ALTER TABLE public.email_drafts ALTER COLUMN from_mailbox_id DROP NOT NULL;

ALTER TABLE public.email_drafts
  DROP CONSTRAINT email_drafts_from_mailbox_id_fkey;

ALTER TABLE public.email_drafts
  ADD  CONSTRAINT email_drafts_from_mailbox_id_fkey
    FOREIGN KEY (from_mailbox_id) REFERENCES public.mailboxes(id) ON DELETE SET NULL;

-- email_agent_runs.from_mailbox_id: drop NOT NULL + relax the FK
-- (was previously ON DELETE RESTRICT, which also blocked deletion).
ALTER TABLE public.email_agent_runs ALTER COLUMN from_mailbox_id DROP NOT NULL;

ALTER TABLE public.email_agent_runs
  DROP CONSTRAINT email_agent_runs_from_mailbox_id_fkey;

ALTER TABLE public.email_agent_runs
  ADD  CONSTRAINT email_agent_runs_from_mailbox_id_fkey
    FOREIGN KEY (from_mailbox_id) REFERENCES public.mailboxes(id) ON DELETE SET NULL;
