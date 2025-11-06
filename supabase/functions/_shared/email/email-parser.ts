/**
 * Email Parser
 * 
 * Parses IMAP messages into database-ready format
 * Includes CC deduplication logic to prevent duplicate imports
 */

import { ImapMessage, ParsedEmail, EmailAttachment, EmailParseError } from './types.ts';
import { parseImapHeaders, parseImapFlags, extractPlainText } from './imap-client.ts';
import { parseEmailList } from './thread-builder.ts';

/**
 * Determine email direction based on folder and from_email
 */
export function getEmailDirection(
  folder: string,
  fromEmail: string,
  mailboxEmail: string
): 'incoming' | 'outgoing' {
  const sentFolders = ['Sent', 'Sent Items', 'Sent Mail', 'Outbox', 'Sent Messages'];

  // Check folder name first (case insensitive)
  if (sentFolders.some(f => f.toLowerCase() === folder.toLowerCase())) {
    return 'outgoing';
  }

  // Check if from_email matches mailbox
  if (fromEmail.toLowerCase() === mailboxEmail.toLowerCase()) {
    return 'outgoing';
  }

  return 'incoming';
}

/**
 * CC Deduplication Logic
 * 
 * Import rules:
 * 1. Direction = outgoing (from this mailbox) - ALWAYS IMPORT
 * 2. Direction = incoming AND mailboxEmail in to_emails - IMPORT
 * 3. Direction = incoming AND mailboxEmail in cc_emails:
 *    - If To: contains ANY @pdmedical.com.au address - SKIP (avoid duplicates)
 *    - If To: contains ONLY external addresses - IMPORT (external communication)
 * 
 * This prevents duplicate imports when multiple PD Medical mailboxes are involved,
 * while ensuring external communications are captured even when CC'd
 */
export function shouldImportEmail(
  email: Pick<ParsedEmail, 'direction' | 'to_emails' | 'cc_emails'>,
  mailboxEmail: string
): boolean {
  // Always import outgoing emails (sent by this mailbox)
  if (email.direction === 'outgoing') {
    return true;
  }

  const mailboxLower = mailboxEmail.toLowerCase();
  const isInTo = email.to_emails.some(to => to.toLowerCase() === mailboxLower);
  const isInCc = email.cc_emails.some(cc => cc.toLowerCase() === mailboxLower);

  // If mailbox is in To: field, always import
  if (isInTo) {
    return true;
  }

  // If mailbox is only in CC, check if To: contains any @pdmedical.com.au addresses
  if (isInCc) {
    const hasPdMedicalInTo = email.to_emails.some(to => 
      to.toLowerCase().endsWith('@pdmedical.com.au')
    );
    
    // Only import if To: doesn't contain any @pdmedical.com.au addresses
    // (i.e., this is external communication where we're CC'd)
    return !hasPdMedicalInTo;
  }

  // Mailbox not in To or CC, don't import
  return false;
}

/**
 * Parse IMAP message into structured email data
 */
export function parseImapMessage(
  imapMessage: ImapMessage,
  mailboxEmail: string,
  folder: string
): ParsedEmail {
  try {
    const headers = parseImapHeaders(imapMessage.headers);
    const flags = parseImapFlags(imapMessage.attributes.flags || []);

    // Extract basic fields
    const messageId = extractHeader(headers, 'message-id') || '';
    const inReplyTo = extractHeader(headers, 'in-reply-to');
    const references = extractHeader(headers, 'references');
    const subject = extractHeader(headers, 'subject');
    const dateStr = extractHeader(headers, 'date');

    // Parse addresses from raw headers using a simple RFC 5322-compatible parser
    // We use the raw headers instead of the IMAP library's envelope parser because
    // the Deno IMAP library has bugs parsing certain address formats
    const fromHeader = extractHeader(headers, 'from');
    const toHeader = extractHeader(headers, 'to');
    const ccHeader = extractHeader(headers, 'cc');
    
    // Parse addresses using a simple but robust parser
    let fromParsed = { email: '', name: undefined };
    let toEmails: string[] = [];
    let ccEmails: string[] = [];
    
    try {
      if (fromHeader) {
        const fromAddresses = parseAddressList(fromHeader);
        if (fromAddresses.length > 0) {
          fromParsed = fromAddresses[0];
        }
      }
      
      if (toHeader) {
        toEmails = parseAddressList(toHeader).map(addr => addr.email);
      }
      
      if (ccHeader) {
        ccEmails = parseAddressList(ccHeader).map(addr => addr.email);
      }
    } catch (error) {
      console.error('[Parser] Failed to parse address headers:', error);
      console.error('[Parser] fromHeader:', fromHeader);
      console.error('[Parser] toHeader:', toHeader);
      console.error('[Parser] ccHeader:', ccHeader);
      // Fall back to empty values
    }

    // Determine direction
    const direction = getEmailDirection(folder, fromParsed.email, mailboxEmail);

    // Extract body
    // For large emails (>100KB), store raw body without parsing to avoid CPU timeout
    let bodyPlain: string;
    if (imapMessage.isParsed === false) {
      // Large email: store raw body without extraction
      bodyPlain = typeof imapMessage.body === 'string' 
        ? imapMessage.body 
        : new TextDecoder().decode(imapMessage.body as Uint8Array);
      console.log(`[Parser] Storing raw body for large email (UID: ${imapMessage.attributes.uid}, size: ${imapMessage.attributes.size} bytes)`);
    } else {
      // Normal email: extract plain text
      bodyPlain = extractPlainText(imapMessage.body);
    }

    // Parse date
    let receivedAt: string;
    try {
      receivedAt = dateStr ? new Date(dateStr).toISOString() : new Date().toISOString();
    } catch {
      receivedAt = new Date().toISOString();
    }

    const parsed: ParsedEmail = {
      message_id: messageId,
      thread_id: '', // Will be set by thread-builder
      references,
      in_reply_to: inReplyTo,
      subject,
      from_email: fromParsed.email,
      from_name: fromParsed.name,
      to_emails: toEmails,
      cc_emails: ccEmails,
      body_html: undefined, // Would extract from MIME parts
      body_plain: bodyPlain,
      direction,
      is_seen: flags.is_seen,
      is_flagged: flags.is_flagged,
      is_answered: flags.is_answered,
      is_draft: flags.is_draft,
      is_deleted: flags.is_deleted,
      imap_folder: folder,
      imap_uid: imapMessage.attributes.uid,
      headers: headers as Record<string, string | string[]>,
      attachments: [], // Would extract from MIME parts
      sent_at: receivedAt,
      received_at: receivedAt
    };

    return parsed;
  } catch (error) {
    throw new EmailParseError(`Failed to parse email: ${error.message}`);
  }
}

/**
 * Parse MIME structure to extract HTML body and attachments
 * This is a simplified version - full MIME parsing would be more complex
 */
export function parseMimeStructure(struct: any[]): {
  html?: string;
  plain?: string;
  attachments: EmailAttachment[];
} {
  const result = {
    html: undefined as string | undefined,
    plain: undefined as string | undefined,
    attachments: [] as EmailAttachment[]
  };

  if (!struct || !Array.isArray(struct)) {
    return result;
  }

  function traverse(part: any, partId: string = '1') {
    if (!part) return;

    const [type, subtype, params, id, description, encoding, size] = part;

    if (Array.isArray(type)) {
      // Multipart
      const [subparts] = part.slice(-1);
      if (Array.isArray(subparts)) {
        subparts.forEach((subpart: any, idx: number) => {
          traverse(subpart, `${partId}.${idx + 1}`);
        });
      }
    } else {
      // Single part
      const contentType = `${type}/${subtype}`.toLowerCase();
      const disposition = params?.disposition?.toLowerCase();

      if (disposition === 'attachment' && params?.name) {
        result.attachments.push({
          filename: params.name,
          content_type: contentType,
          size: size || 0
        });
      } else if (contentType === 'text/html') {
        // HTML body (would need to fetch the actual content)
        result.html = ''; // Placeholder
      } else if (contentType === 'text/plain') {
        // Plain text body
        result.plain = ''; // Placeholder
      }
    }
  }

  traverse(struct);
  return result;
}

/**
 * Extract single header value (handles string or array)
 */
function extractHeader(headers: Record<string, string | string[]>, name: string): string | undefined {
  const value = headers[name.toLowerCase()];
  if (!value) return undefined;
  return Array.isArray(value) ? value[0] : value;
}

/**
 * Parse an RFC 5322 address list into structured data
 * Handles formats like:
 * - simple@email.com
 * - Name <email@example.com>
 * - "Name" <email@example.com>
 * - email1@example.com, Name <email2@example.com>
 */
function parseAddressList(addressString: string): Array<{ email: string; name?: string }> {
  if (!addressString || !addressString.trim()) {
    return [];
  }

  const addresses: Array<{ email: string; name?: string }> = [];
  
  // Simple regex-based parser for RFC 5322 addresses
  // Matches: "Display Name" <email@domain.com> or just email@domain.com
  const addressRegex = /(?:"([^"]+)"\s*)?<?([a-zA-Z0-9.!#$%&'*+\/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*)>?/g;
  
  let match;
  while ((match = addressRegex.exec(addressString)) !== null) {
    const name = match[1] || undefined; // Display name (optional)
    const email = match[2]; // Email address
    
    if (email) {
      addresses.push({
        email: email.toLowerCase(),
        name: name
      });
    }
  }
  
  return addresses;
}

/**
 * Sanitize email body (remove dangerous HTML, excessive whitespace, etc.)
 */
export function sanitizeEmailBody(body: string, isHtml: boolean = false): string {
  if (!body) return '';

  if (isHtml) {
    // Basic HTML sanitization (in production, use a proper library like DOMPurify)
    let sanitized = body;
    
    // Remove script tags
    sanitized = sanitized.replace(/<script\b[^<]*(?:(?!<\/script>)<[^<]*)*<\/script>/gi, '');
    
    // Remove event handlers
    sanitized = sanitized.replace(/on\w+="[^"]*"/gi, '');
    sanitized = sanitized.replace(/on\w+='[^']*'/gi, '');
    
    // Remove javascript: URLs
    sanitized = sanitized.replace(/href="javascript:[^"]*"/gi, 'href="#"');
    
    return sanitized;
  } else {
    // Plain text - just trim excessive whitespace
    return body.trim();
  }
}

/**
 * Extract email domain from email address
 */
export function extractDomain(email: string): string | null {
  const match = email.match(/@([^@]+)$/);
  return match ? match[1].toLowerCase() : null;
}

/**
 * Parse name into first and last name
 */
export function parseFullName(fullName: string | undefined): { first_name: string; last_name: string } {
  if (!fullName) {
    return { first_name: '', last_name: '' };
  }

  const parts = fullName.trim().split(/\s+/);
  
  if (parts.length === 0) {
    return { first_name: '', last_name: '' };
  } else if (parts.length === 1) {
    return { first_name: parts[0], last_name: '' };
  } else {
    // First word is first name, rest is last name
    return {
      first_name: parts[0],
      last_name: parts.slice(1).join(' ')
    };
  }
}

/**
 * Validate email address format
 */
export function isValidEmail(email: string): boolean {
  if (!email) return false;
  
  // Simple email regex (not perfect but good enough)
  const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
  return emailRegex.test(email);
}

/**
 * Clean and validate email data before import
 */
export function validateEmailData(email: ParsedEmail): { valid: boolean; errors: string[] } {
  const errors: string[] = [];

  // Required fields
  if (!email.from_email) {
    errors.push('Missing from_email');
  } else if (!isValidEmail(email.from_email)) {
    errors.push('Invalid from_email format');
  }

  if (!email.to_emails || email.to_emails.length === 0) {
    errors.push('Missing to_emails');
  } else {
    const invalidTo = email.to_emails.filter(e => !isValidEmail(e));
    if (invalidTo.length > 0) {
      errors.push(`Invalid to_emails: ${invalidTo.join(', ')}`);
    }
  }

  if (!email.imap_uid) {
    errors.push('Missing imap_uid');
  }

  if (!email.imap_folder) {
    errors.push('Missing imap_folder');
  }

  if (!email.received_at) {
    errors.push('Missing received_at');
  }

  return {
    valid: errors.length === 0,
    errors
  };
}

/**
 * Batch parse multiple IMAP messages
 */
export function parseImapMessages(
  imapMessages: ImapMessage[],
  mailboxEmail: string,
  folder: string
): ParsedEmail[] {
  const results: ParsedEmail[] = [];

  for (const imapMessage of imapMessages) {
    try {
      const parsed = parseImapMessage(imapMessage, mailboxEmail, folder);
      
      // Validate
      const validation = validateEmailData(parsed);
      if (validation.valid) {
        results.push(parsed);
      } else {
        console.warn(`[Parser] Skipping invalid email:`, validation.errors);
      }
    } catch (error) {
      console.error(`[Parser] Failed to parse email:`, error);
      // Continue with next email
    }
  }

  return results;
}


