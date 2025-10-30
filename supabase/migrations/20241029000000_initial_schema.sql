-- Initial schema migration
-- This migration creates the core tables for the AI Outreach application

-- Create organizations table
CREATE TABLE IF NOT EXISTS public.organizations (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  email character varying NOT NULL,
  name character varying NOT NULL,
  type character varying,
  imap_host character varying DEFAULT 'mail.pdmedical.com.au'::character varying,
  imap_port integer DEFAULT 993,
  is_active boolean DEFAULT true,
  last_synced_at timestamp with time zone,
  settings jsonb DEFAULT '{}'::jsonb,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  CONSTRAINT organizations_pkey PRIMARY KEY (id),
  CONSTRAINT organizations_email_key UNIQUE (email),
  CONSTRAINT organizations_type_check CHECK (type::text = ANY (ARRAY[
    'personal'::character varying,
    'team'::character varying,
    'department'::character varying
  ]::text[]))
);

-- Create contacts table
CREATE TABLE IF NOT EXISTS public.contacts (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  email character varying NOT NULL,
  first_name character varying,
  last_name character varying,
  company character varying,
  job_title character varying,
  phone character varying,
  category character varying,
  source character varying,
  quality_score integer DEFAULT 0,
  status character varying DEFAULT 'active'::character varying,
  tags jsonb DEFAULT '[]'::jsonb,
  custom_fields jsonb DEFAULT '{}'::jsonb,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  created_by uuid,
  updated_by uuid,
  organization_id uuid,
  CONSTRAINT contacts_pkey PRIMARY KEY (id),
  CONSTRAINT contacts_email_key UNIQUE (email),
  CONSTRAINT contacts_quality_score_check CHECK (quality_score >= 0 AND quality_score <= 100),
  CONSTRAINT contacts_status_check CHECK (status::text = ANY (ARRAY[
    'active'::character varying,
    'inactive'::character varying,
    'unsubscribed'::character varying
  ]::text[])),
  CONSTRAINT contacts_source_check CHECK (source::text = ANY (ARRAY[
    'mailchimp'::character varying,
    'asvial'::character varying,
    'outlook'::character varying,
    'manual'::character varying,
    'email_server'::character varying,
    'crazy_domain'::character varying
  ]::text[])),
  CONSTRAINT contacts_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id),
  CONSTRAINT contacts_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES auth.users(id),
  CONSTRAINT contacts_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id)
);

-- Create emails table
CREATE TABLE IF NOT EXISTS public.emails (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  subject character varying,
  body text,
  body_plain text,
  body_html text,
  message_id character varying,
  thread_id character varying,
  in_reply_to character varying,
  email_references text,
  from_email character varying NOT NULL,
  from_name character varying,
  to_emails text[],
  cc_emails text[],
  bcc_emails text[],
  organization_id uuid,
  contact_id uuid,
  direction character varying,
  is_read boolean DEFAULT false,
  is_important boolean DEFAULT false,
  is_archived boolean DEFAULT false,
  headers jsonb DEFAULT '{}'::jsonb,
  sent_at timestamp with time zone,
  received_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  CONSTRAINT emails_pkey PRIMARY KEY (id),
  CONSTRAINT emails_message_id_key UNIQUE (message_id),
  CONSTRAINT emails_direction_check CHECK (direction::text = ANY (ARRAY[
    'incoming'::character varying,
    'outgoing'::character varying
  ]::text[])),
  CONSTRAINT emails_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id),
  CONSTRAINT emails_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES public.contacts(id)
);

-- Create indexes for better query performance
CREATE INDEX IF NOT EXISTS idx_contacts_email ON public.contacts(email);
CREATE INDEX IF NOT EXISTS idx_contacts_organization_id ON public.contacts(organization_id);
CREATE INDEX IF NOT EXISTS idx_contacts_created_at ON public.contacts(created_at);
CREATE INDEX IF NOT EXISTS idx_contacts_source ON public.contacts(source);
CREATE INDEX IF NOT EXISTS idx_contacts_status ON public.contacts(status);

CREATE INDEX IF NOT EXISTS idx_emails_message_id ON public.emails(message_id);
CREATE INDEX IF NOT EXISTS idx_emails_thread_id ON public.emails(thread_id);
CREATE INDEX IF NOT EXISTS idx_emails_from_email ON public.emails(from_email);
CREATE INDEX IF NOT EXISTS idx_emails_organization_id ON public.emails(organization_id);
CREATE INDEX IF NOT EXISTS idx_emails_contact_id ON public.emails(contact_id);
CREATE INDEX IF NOT EXISTS idx_emails_created_at ON public.emails(created_at);
CREATE INDEX IF NOT EXISTS idx_emails_direction ON public.emails(direction);

CREATE INDEX IF NOT EXISTS idx_organizations_email ON public.organizations(email);
CREATE INDEX IF NOT EXISTS idx_organizations_is_active ON public.organizations(is_active);

-- Enable Row Level Security (RLS)
ALTER TABLE public.organizations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.contacts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.emails ENABLE ROW LEVEL SECURITY;

-- Create updated_at trigger function
CREATE OR REPLACE FUNCTION public.handle_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create triggers for updated_at
CREATE TRIGGER set_updated_at
  BEFORE UPDATE ON public.organizations
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_updated_at();

CREATE TRIGGER set_updated_at
  BEFORE UPDATE ON public.contacts
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_updated_at();

CREATE TRIGGER set_updated_at
  BEFORE UPDATE ON public.emails
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_updated_at();

-- Grant permissions
GRANT USAGE ON SCHEMA public TO anon, authenticated;
GRANT ALL ON public.organizations TO authenticated;
GRANT ALL ON public.contacts TO authenticated;
GRANT ALL ON public.emails TO authenticated;
