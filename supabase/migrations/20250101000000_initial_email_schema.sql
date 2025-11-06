-- ============================================================================
-- Email Sync System - Initial Schema Migration
-- ============================================================================
-- This migration creates all tables needed for email synchronization:
-- - mailboxes: Owner's email accounts
-- - organizations: Customer organizations (renamed from customer_organizations)
-- - contacts: Individual contacts
-- - conversations: Email threads (1-to-1 with thread_id)
-- - emails: Individual email messages
--
-- NOTE: This file is for reference only. The actual schema uses 'organizations'
-- table with additional healthcare fields. See migration 20250106000000.
--
-- IMAP passwords stored as Supabase secrets: IMAP_PASSWORD_{mailbox_id}
-- ============================================================================

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS pg_net;
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ============================================================================
-- MAILBOXES TABLE
-- ============================================================================
-- Owner's email accounts/mailboxes
CREATE TABLE IF NOT EXISTS public.mailboxes (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  email character varying NOT NULL UNIQUE,
  name character varying NOT NULL,
  type character varying CHECK (type::text = ANY (ARRAY['personal'::character varying, 'team'::character varying, 'department'::character varying]::text[])),
  
  -- IMAP Configuration
  imap_host character varying DEFAULT 'mail.pdmedical.com.au'::character varying,
  imap_port integer DEFAULT 993,
  imap_username character varying,
  -- NOTE: IMAP passwords stored as Supabase secrets: IMAP_PASSWORD_{id}
  
  -- Sync tracking
  is_active boolean DEFAULT true,
  last_synced_at timestamp with time zone,
  last_synced_uid jsonb DEFAULT '{}'::jsonb, -- {"INBOX": 1234, "Sent": 5678}
  sync_status jsonb DEFAULT '{}'::jsonb,      -- Error tracking and state
  sync_settings jsonb DEFAULT '{}'::jsonb,
  
  -- Timestamps
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  
  CONSTRAINT mailboxes_pkey PRIMARY KEY (id)
);

-- ============================================================================
-- ORGANIZATIONS TABLE (was customer_organizations)
-- ============================================================================
-- NOTE: This table is renamed to 'organizations' in migration 20250106000000
-- with additional healthcare-specific fields
CREATE TABLE IF NOT EXISTS public.customer_organizations (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  name character varying NOT NULL,
  domain character varying UNIQUE,
  phone character varying,
  address text,
  industry character varying,
  website character varying,
  status character varying DEFAULT 'active'::character varying,
  tags jsonb DEFAULT '[]'::jsonb,
  custom_fields jsonb DEFAULT '{}'::jsonb,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  
  CONSTRAINT customer_organizations_pkey PRIMARY KEY (id)
);

-- ============================================================================
-- CONTACTS TABLE
-- ============================================================================
-- Customer contacts (individuals)
CREATE TABLE IF NOT EXISTS public.contacts (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  email character varying NOT NULL UNIQUE,
  first_name character varying,
  last_name character varying,
  job_title character varying,
  phone character varying,
  customer_organization_id uuid NOT NULL,
  status character varying DEFAULT 'active'::character varying 
    CHECK (status::text = ANY (ARRAY['active'::character varying, 'inactive'::character varying, 'unsubscribed'::character varying, 'bounced'::character varying]::text[])),
  tags jsonb DEFAULT '[]'::jsonb,
  custom_fields jsonb DEFAULT '{}'::jsonb,
  last_contact_date timestamp with time zone,
  notes text,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  
  CONSTRAINT contacts_pkey PRIMARY KEY (id),
  CONSTRAINT contacts_customer_organization_id_fkey 
    FOREIGN KEY (customer_organization_id) 
    REFERENCES public.customer_organizations(id) ON DELETE CASCADE
);

-- ============================================================================
-- CONVERSATIONS TABLE
-- ============================================================================
-- Email conversations (threads) - 1-to-1 mapping with thread_id
CREATE TABLE IF NOT EXISTS public.conversations (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  thread_id character varying NOT NULL UNIQUE, -- Enforces 1 thread = 1 conversation
  subject character varying,
  mailbox_id uuid NOT NULL,
  customer_organization_id uuid,
  primary_contact_id uuid,
  
  -- Statistics
  email_count integer DEFAULT 0,
  
  first_email_at timestamp with time zone,
  last_email_at timestamp with time zone,
  last_email_direction character varying 
    CHECK (last_email_direction::text = ANY (ARRAY['incoming'::character varying, 'outgoing'::character varying]::text[])),
  
  status character varying DEFAULT 'active'::character varying
    CHECK (status::text = ANY (ARRAY['active'::character varying, 'closed'::character varying, 'archived'::character varying]::text[])),
  
  requires_response boolean DEFAULT false,
  tags jsonb DEFAULT '[]'::jsonb,
  
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  
  CONSTRAINT conversations_pkey PRIMARY KEY (id),
  CONSTRAINT conversations_thread_id_unique UNIQUE (thread_id),
  CONSTRAINT conversations_mailbox_id_fkey 
    FOREIGN KEY (mailbox_id) 
    REFERENCES public.mailboxes(id) ON DELETE CASCADE,
  CONSTRAINT conversations_customer_organization_id_fkey 
    FOREIGN KEY (customer_organization_id) 
    REFERENCES public.customer_organizations(id) ON DELETE SET NULL,
  CONSTRAINT conversations_primary_contact_id_fkey 
    FOREIGN KEY (primary_contact_id) 
    REFERENCES public.contacts(id) ON DELETE SET NULL
);

-- ============================================================================
-- EMAILS TABLE
-- ============================================================================
-- Individual email messages
CREATE TABLE IF NOT EXISTS public.emails (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  message_id character varying NOT NULL UNIQUE,
  thread_id character varying NOT NULL,
  conversation_id uuid, -- Nullable for import flexibility
  in_reply_to character varying,
  email_references text,
  
  -- Email metadata
  subject character varying,
  from_email character varying NOT NULL,
  from_name character varying,
  to_emails text[] NOT NULL,
  cc_emails text[],
  bcc_emails text[],
  
  -- Email content
  body_html text,
  body_plain text,
  
  -- Relationships
  mailbox_id uuid NOT NULL,
  contact_id uuid,
  customer_organization_id uuid,
  
  -- Direction
  direction character varying NOT NULL
    CHECK (direction::text = ANY (ARRAY['incoming'::character varying, 'outgoing'::character varying]::text[])),
  
  -- IMAP-specific flags (directly from IMAP server)
  is_seen boolean DEFAULT false,        -- IMAP \Seen flag (read/unread)
  is_flagged boolean DEFAULT false,     -- IMAP \Flagged flag (starred)
  is_answered boolean DEFAULT false,    -- IMAP \Answered flag (replied to)
  is_draft boolean DEFAULT false,       -- IMAP \Draft flag
  is_deleted boolean DEFAULT false,     -- IMAP \Deleted flag
  
  -- IMAP folder location
  imap_folder character varying NOT NULL, -- e.g., 'INBOX', 'Sent', 'Drafts', 'Trash'
  imap_uid integer,                       -- IMAP UID (unique within folder)
  
  -- Additional data
  headers jsonb DEFAULT '{}'::jsonb,
  attachments jsonb DEFAULT '[]'::jsonb,
  
  -- Timestamps
  sent_at timestamp with time zone,
  received_at timestamp with time zone NOT NULL,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  
  CONSTRAINT emails_pkey PRIMARY KEY (id),
  CONSTRAINT emails_unique_message_id UNIQUE (message_id),
  
  -- Composite unique constraint for IMAP sync (prevents duplicates)
  CONSTRAINT emails_unique_imap UNIQUE (mailbox_id, imap_folder, imap_uid),
  
  CONSTRAINT emails_mailbox_id_fkey 
    FOREIGN KEY (mailbox_id) 
    REFERENCES public.mailboxes(id) ON DELETE CASCADE,
  CONSTRAINT emails_conversation_id_fkey 
    FOREIGN KEY (conversation_id) 
    REFERENCES public.conversations(id) ON DELETE CASCADE,
  CONSTRAINT emails_contact_id_fkey 
    FOREIGN KEY (contact_id) 
    REFERENCES public.contacts(id) ON DELETE SET NULL,
  CONSTRAINT emails_customer_organization_id_fkey 
    FOREIGN KEY (customer_organization_id) 
    REFERENCES public.customer_organizations(id) ON DELETE SET NULL
);

-- ============================================================================
-- INDEXES FOR PERFORMANCE
-- ============================================================================

-- Emails indexes
CREATE INDEX IF NOT EXISTS idx_emails_conversation_id ON public.emails(conversation_id);
CREATE INDEX IF NOT EXISTS idx_emails_mailbox_id ON public.emails(mailbox_id);
CREATE INDEX IF NOT EXISTS idx_emails_thread_id ON public.emails(thread_id);
CREATE INDEX IF NOT EXISTS idx_emails_received_at ON public.emails(received_at DESC);
CREATE INDEX IF NOT EXISTS idx_emails_contact_id ON public.emails(contact_id);
CREATE INDEX IF NOT EXISTS idx_emails_customer_organization_id ON public.emails(customer_organization_id);
CREATE INDEX IF NOT EXISTS idx_emails_imap_folder ON public.emails(imap_folder);
CREATE INDEX IF NOT EXISTS idx_emails_from_email ON public.emails(from_email);
CREATE INDEX IF NOT EXISTS idx_emails_message_id ON public.emails(message_id);
CREATE INDEX IF NOT EXISTS idx_emails_direction ON public.emails(direction);

-- Conversations indexes
CREATE INDEX IF NOT EXISTS idx_conversations_mailbox_id ON public.conversations(mailbox_id);
CREATE INDEX IF NOT EXISTS idx_conversations_thread_id ON public.conversations(thread_id);
CREATE INDEX IF NOT EXISTS idx_conversations_last_email_at ON public.conversations(last_email_at DESC);
CREATE INDEX IF NOT EXISTS idx_conversations_customer_organization_id ON public.conversations(customer_organization_id);
CREATE INDEX IF NOT EXISTS idx_conversations_primary_contact_id ON public.conversations(primary_contact_id);
CREATE INDEX IF NOT EXISTS idx_conversations_status ON public.conversations(status);

-- Contacts indexes
CREATE INDEX IF NOT EXISTS idx_contacts_customer_organization_id ON public.contacts(customer_organization_id);
CREATE INDEX IF NOT EXISTS idx_contacts_email ON public.contacts(email);

-- Mailboxes indexes
CREATE INDEX IF NOT EXISTS idx_mailboxes_email ON public.mailboxes(email);
CREATE INDEX IF NOT EXISTS idx_mailboxes_is_active ON public.mailboxes(is_active);

-- Customer Organizations indexes
CREATE INDEX IF NOT EXISTS idx_customer_organizations_domain ON public.customer_organizations(domain);

-- ============================================================================
-- COMMENTS
-- ============================================================================

COMMENT ON TABLE public.mailboxes IS 'Owner email accounts for synchronization. IMAP passwords stored as Supabase secrets: IMAP_PASSWORD_{id}';
COMMENT ON TABLE public.emails IS 'Individual email messages with full IMAP metadata';
COMMENT ON TABLE public.conversations IS 'Email threads/conversations with 1-to-1 mapping to thread_id';
COMMENT ON TABLE public.contacts IS 'Individual customer contacts';
COMMENT ON TABLE public.customer_organizations IS 'Customer organizations (renamed to organizations in migration 20250106000000)';

COMMENT ON COLUMN public.mailboxes.last_synced_uid IS 'JSON object tracking last synced UID per folder: {"INBOX": 1234, "Sent": 5678}';
COMMENT ON COLUMN public.mailboxes.sync_status IS 'JSON object for error tracking and sync state';
COMMENT ON COLUMN public.emails.thread_id IS 'Thread identifier created from Message-ID chain (format: thread-{md5hash})';
COMMENT ON COLUMN public.emails.conversation_id IS 'Foreign key to conversations table, nullable for import flexibility';
COMMENT ON COLUMN public.emails.email_references IS 'Full References header for threading';


