/**
 * Email Sync System - TypeScript Type Definitions
 * 
 * These types match the database schema and provide type safety
 * for email synchronization operations.
 */

// ============================================================================
// DATABASE ENTITY TYPES
// ============================================================================

export interface Mailbox {
  id: string;
  email: string;
  name: string;
  type?: 'personal' | 'team' | 'department';
  imap_host: string;
  imap_port: number;
  imap_username?: string;
  is_active: boolean;
  last_synced_at?: string;
  last_synced_uid: Record<string, number>; // { "INBOX": 1234, "Sent": 5678 }
  sync_status: SyncStatus;
  sync_settings: Record<string, any>;
  created_at: string;
  updated_at: string;
}

export interface OrganizationType {
  id: string;
  name: string;
  description?: string;
  is_active: boolean;
  created_at: string;
  updated_at: string;
}

export interface Organization {
  id: string;
  name: string;
  domain: string; // Required field
  phone?: string;
  address?: string;
  industry?: string;
  website?: string;
  status: string;
  tags: string[];
  custom_fields: Record<string, any>;
  
  // Organization type
  organization_type_id?: string;
  
  // Healthcare-specific fields
  region?: string;
  hospital_category?: string;
  city?: string;
  state?: string;
  key_hospital?: string;
  street_address?: string;
  suburb?: string;
  facility_type?: string;
  bed_count?: number;
  top_150_ranking?: number;
  general_info?: string;
  products_sold?: string[];
  has_maternity?: boolean;
  has_operating_theatre?: boolean;
  
  created_at: string;
  updated_at: string;
}

export interface Contact {
  id: string;
  email: string;
  first_name?: string;
  last_name?: string;
  job_title?: string;
  phone?: string;
  organization_id: string;
  status: 'active' | 'inactive' | 'unsubscribed' | 'bounced';
  tags: string[];
  custom_fields: Record<string, any>;
  last_contact_date?: string;
  notes?: string;
  created_at: string;
  updated_at: string;
}

export interface Conversation {
  id: string;
  thread_id: string;
  subject?: string;
  mailbox_id: string;
  organization_id?: string;
  primary_contact_id?: string;
  email_count: number;
  first_email_at?: string;
  last_email_at?: string;
  last_email_direction?: 'incoming' | 'outgoing';
  status: 'active' | 'closed' | 'archived';
  requires_response: boolean;
  tags: string[];
  created_at: string;
  updated_at: string;
}

export interface Email {
  id: string;
  message_id: string;
  thread_id: string;
  conversation_id?: string;
  in_reply_to?: string;
  email_references?: string;
  
  // Email metadata
  subject?: string;
  from_email: string;
  from_name?: string;
  to_emails: string[];
  cc_emails: string[];
  bcc_emails: string[];
  
  // Email content
  body_html?: string;
  body_plain?: string;
  
  // Relationships
  mailbox_id: string;
  contact_id?: string;
  organization_id?: string;
  
  // Direction
  direction: 'incoming' | 'outgoing';
  
  // IMAP flags
  is_seen: boolean;
  is_flagged: boolean;
  is_answered: boolean;
  is_draft: boolean;
  is_deleted: boolean;
  
  // IMAP metadata
  imap_folder: string;
  imap_uid?: number;
  
  // Additional data
  headers: Record<string, string | string[]>;
  attachments: EmailAttachment[];
  
  // Timestamps
  sent_at?: string;
  received_at: string;
  created_at: string;
  updated_at: string;
}

// ============================================================================
// HELPER TYPES
// ============================================================================

export interface EmailAttachment {
  filename: string;
  content_type: string;
  size: number;
}

export interface SyncStatus {
  last_sync_success?: boolean;
  last_sync_error?: string;
  last_sync_timestamp?: string;
  legacy_import?: {
    folder: string;
    last_uid: number;
    total_processed: number;
    in_progress: boolean;
  };
}

export interface ParsedEmail {
  message_id: string;
  thread_id: string;
  references?: string;
  in_reply_to?: string;
  subject?: string;
  from_email: string;
  from_name?: string;
  to_emails: string[];
  cc_emails: string[];
  body_html?: string;
  body_plain?: string;
  direction: 'incoming' | 'outgoing';
  is_seen: boolean;
  is_flagged: boolean;
  is_answered: boolean;
  is_draft: boolean;
  is_deleted: boolean;
  imap_folder: string;
  imap_uid: number;
  headers: Record<string, string | string[]>;
  attachments: EmailAttachment[];
  sent_at?: string;
  received_at: string;
}

export interface ImapMessage {
  attributes: {
    uid: number;
    flags: string[];
    size?: number; // Message size in bytes
    date: Date;
    struct?: any[];
    envelope?: {
      date: Date;
      subject: string;
      from: Array<{ mailbox: string; host: string; name?: string }>;
      sender?: Array<{ mailbox: string; host: string; name?: string }>;
      replyTo?: Array<{ mailbox: string; host: string; name?: string }>;
      to?: Array<{ mailbox: string; host: string; name?: string }>;
      cc?: Array<{ mailbox: string; host: string; name?: string }>;
      bcc?: Array<{ mailbox: string; host: string; name?: string }>;
      inReplyTo?: string;
      messageId?: string;
    };
  };
  headers: Map<string, string[]>;
  body: Buffer | string;
  isParsed?: boolean; // Track if body was parsed or stored raw (for large emails)
}

// ============================================================================
// SYNC OPERATION TYPES
// ============================================================================

export interface SyncResult {
  success: boolean;
  mailbox_id: string;
  mailbox_email: string;
  folders_synced: string[];
  emails_imported: number;
  errors: string[];
  sync_duration_ms: number;
}

export interface BatchImportRequest {
  mailbox_id: string;
  folders?: string[];
  start_date?: string;
  end_date?: string;
  resume_token?: string;
}

export interface BatchImportResponse {
  completed: boolean;
  processed: number;
  total_imported: number;
  resume_token?: string;
  next_folder?: string;
  errors: string[];
}

export interface ImportStats {
  total_emails_fetched: number;
  emails_imported: number;
  emails_skipped: number;
  contacts_created: number;
  organizations_created: number;
  conversations_created: number;
  errors: number;
}

// ============================================================================
// IMAP CONNECTION TYPES
// ============================================================================

export interface ImapConfig {
  host: string;
  port: number;
  user: string;
  password: string;
  tls: boolean;
  tlsOptions?: {
    rejectUnauthorized?: boolean;
  };
}

export interface FetchOptions {
  folder: string;
  startUid?: number;
  endUid?: number;
  startDate?: Date;
  endDate?: Date;
  limit?: number;
}

// ============================================================================
// ERROR TYPES
// ============================================================================

export class EmailSyncError extends Error {
  constructor(
    message: string,
    public code: string,
    public mailboxId?: string,
    public folder?: string
  ) {
    super(message);
    this.name = 'EmailSyncError';
  }
}

export class ImapConnectionError extends EmailSyncError {
  constructor(message: string, mailboxId?: string) {
    super(message, 'IMAP_CONNECTION_ERROR', mailboxId);
    this.name = 'ImapConnectionError';
  }
}

export class EmailParseError extends EmailSyncError {
  constructor(message: string, mailboxId?: string) {
    super(message, 'EMAIL_PARSE_ERROR', mailboxId);
    this.name = 'EmailParseError';
  }
}

export class DatabaseError extends EmailSyncError {
  constructor(message: string, mailboxId?: string) {
    super(message, 'DATABASE_ERROR', mailboxId);
    this.name = 'DatabaseError';
  }
}


