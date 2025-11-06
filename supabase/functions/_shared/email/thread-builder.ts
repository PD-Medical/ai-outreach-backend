/**
 * Email Threading Logic
 * 
 * Ported from scripts/email_threading.py (lines 87-131)
 * Creates thread_id from email headers (Message-ID, In-Reply-To, References)
 * 
 * Algorithm:
 * 1. If email has References, use the first (root) Message-ID as thread root
 * 2. If email has In-Reply-To but no References, use In-Reply-To as parent
 * 3. Otherwise, this email starts a new thread - use its Message-ID as root
 * 4. Thread ID format: "thread-{md5_hash_of_root_message_id}"
 */

import { ParsedEmail } from './types.ts';

/**
 * Clean Message-ID by removing angle brackets
 */
export function cleanMessageId(messageId: string | undefined): string {
  if (!messageId) {
    return '';
  }
  return messageId.trim().replace(/^<|>$/g, '');
}

/**
 * Generate a synthetic Message-ID for emails that don't have one
 * (typically spam or malformed emails)
 */
export function generateSyntheticMessageId(email: {
  imap_uid: number;
  imap_folder: string;
  received_at: string;
}): string {
  const uniqueStr = `${email.imap_uid}${email.imap_folder}${email.received_at}`;
  const hash = md5Hash(uniqueStr).substring(0, 16);
  return `synthetic-${hash}@local`;
}

/**
 * Parse References header into list of Message-IDs
 * References can be space or newline separated
 * Format: <message-id@domain> <another-id@domain>
 */
export function parseReferences(referencesHeader: string | undefined): string[] {
  if (!referencesHeader) {
    return [];
  }

  // Replace newlines and extra whitespace with single space
  const cleaned = referencesHeader.replace(/\s+/g, ' ').trim();

  // Extract all Message-IDs (format: <...@...>)
  const messageIdPattern = /<[^>]+>/g;
  const matches = cleaned.match(messageIdPattern) || [];

  // Clean and return (remove angle brackets)
  return matches.map(mid => mid.replace(/^<|>$/g, '')).filter(Boolean);
}

/**
 * Normalize email subject for better thread matching
 * Removes Re:, Fwd:, etc. prefixes
 */
export function normalizeSubject(subject: string | undefined): string {
  if (!subject) {
    return '';
  }

  // Remove common reply/forward prefixes (case insensitive)
  let normalized = subject.replace(/^(Re|RE|Fw|FW|Fwd|FWD):\s*/gi, '');
  
  // Collapse multiple spaces to single space
  normalized = normalized.replace(/\s+/g, ' ').trim();

  return normalized;
}

/**
 * Create a thread_id for an email
 * 
 * This is the core threading algorithm that groups related emails.
 * Returns format: "thread-{16-char-md5-hash}"
 * 
 * @param email - Parsed email data with Message-ID, References, In-Reply-To
 * @param existingThreadLookup - Optional function to lookup existing thread for a message
 * @returns thread_id string
 */
export function createThreadId(
  email: Pick<ParsedEmail, 'message_id' | 'references' | 'in_reply_to' | 'imap_uid' | 'imap_folder' | 'received_at'>,
  existingThreadLookup?: (messageId: string) => Promise<string | null>
): string {
  // Get or generate Message-ID
  let messageId = cleanMessageId(email.message_id);
  if (!messageId) {
    messageId = generateSyntheticMessageId({
      imap_uid: email.imap_uid,
      imap_folder: email.imap_folder,
      received_at: email.received_at
    });
  }

  // Parse References header to find root
  const references = parseReferences(email.references);

  let rootMessageId: string;

  if (references.length > 0) {
    // First reference is the root of the thread
    rootMessageId = references[0];
  } else if (email.in_reply_to) {
    // If no References but has In-Reply-To, use it as root
    // (The parent email should have started the thread)
    const parentId = cleanMessageId(email.in_reply_to);
    rootMessageId = parentId || messageId;
    
    // Note: In a full implementation with database access, we would:
    // 1. Check if parent exists in database
    // 2. If it does, use its thread_id
    // This is handled in the db-operations layer
  } else {
    // This is a new thread - use this message as root
    rootMessageId = messageId;
  }

  // Create thread_id from root message ID
  // Use first 16 chars of MD5 hash for shorter IDs
  const hash = md5Hash(rootMessageId).substring(0, 16);
  return `thread-${hash}`;
}

/**
 * Simple MD5 hash implementation for Deno
 * Uses the Web Crypto API available in Deno
 */
export async function md5HashAsync(text: string): Promise<string> {
  const encoder = new TextEncoder();
  const data = encoder.encode(text);
  
  // Use SHA-256 since MD5 is not available in Web Crypto API
  // This is fine for our use case (generating thread IDs)
  const hashBuffer = await crypto.subtle.digest('SHA-256', data);
  const hashArray = Array.from(new Uint8Array(hashBuffer));
  const hashHex = hashArray.map(b => b.toString(16).padStart(2, '0')).join('');
  
  return hashHex;
}

/**
 * Synchronous MD5-like hash for compatibility
 * Uses a simple hash algorithm since Web Crypto is async
 */
export function md5Hash(text: string): string {
  // Simple hash function (FNV-1a style)
  let hash = 2166136261;
  for (let i = 0; i < text.length; i++) {
    hash ^= text.charCodeAt(i);
    hash += (hash << 1) + (hash << 4) + (hash << 7) + (hash << 8) + (hash << 24);
  }
  
  // Convert to hex string
  const hashHex = (hash >>> 0).toString(16).padStart(8, '0');
  
  // Pad to 32 characters (MD5 length) by repeating
  return (hashHex + hashHex + hashHex + hashHex).substring(0, 32);
}

/**
 * Create thread_id with async hash (for better hash quality)
 */
export async function createThreadIdAsync(
  email: Pick<ParsedEmail, 'message_id' | 'references' | 'in_reply_to' | 'imap_uid' | 'imap_folder' | 'received_at'>
): Promise<string> {
  let messageId = cleanMessageId(email.message_id);
  if (!messageId) {
    messageId = generateSyntheticMessageId({
      imap_uid: email.imap_uid,
      imap_folder: email.imap_folder,
      received_at: email.received_at
    });
  }

  const references = parseReferences(email.references);

  let rootMessageId: string;

  if (references.length > 0) {
    rootMessageId = references[0];
  } else if (email.in_reply_to) {
    const parentId = cleanMessageId(email.in_reply_to);
    rootMessageId = parentId || messageId;
  } else {
    rootMessageId = messageId;
  }

  const hash = await md5HashAsync(rootMessageId);
  return `thread-${hash.substring(0, 16)}`;
}

/**
 * Extract email address from various formats:
 * - "Name <email@domain.com>"
 * - "email@domain.com"
 * - "<email@domain.com>"
 * - Handles malformed headers with extra quotes/parentheses
 */
export function extractEmailAddress(emailStr: string): { email: string; name?: string } {
  if (!emailStr) {
    return { email: '', name: undefined };
  }

  // Clean up the string - remove extra quotes, parentheses, and whitespace
  let cleaned = emailStr.trim();
  
  // Extract email using a more robust regex that finds email patterns
  const emailPattern = /([a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,})/;
  const emailMatch = cleaned.match(emailPattern);
  
  if (!emailMatch) {
    // No valid email found
    return { email: '', name: undefined };
  }
  
  const email = emailMatch[1].toLowerCase();
  
  // Try to extract name from angle bracket format: Name <email@domain.com>
  const angleMatch = cleaned.match(/^["']?([^"'<]+?)["']?\s*<[^>]+>$/);
  if (angleMatch) {
    const name = angleMatch[1].trim();
    // Clean up name - remove extra quotes and parentheses
    const cleanName = name.replace(/["'()]/g, '').trim();
    return {
      email,
      name: cleanName || undefined
    };
  }

  // No name found, just return email
  return {
    email,
    name: undefined
  };
}

/**
 * Parse comma-separated email addresses
 * Handles formats like:
 * - "email1@domain.com, Name <email2@domain.com>, email3@domain.com"
 */
export function parseEmailList(emailList: string | string[]): Array<{ email: string; name?: string }> {
  if (Array.isArray(emailList)) {
    return emailList.flatMap(e => parseEmailList(e));
  }

  if (!emailList) {
    return [];
  }

  // Split by comma (but not inside angle brackets)
  const emails: string[] = [];
  let current = '';
  let inBrackets = false;

  for (let i = 0; i < emailList.length; i++) {
    const char = emailList[i];
    
    if (char === '<') {
      inBrackets = true;
      current += char;
    } else if (char === '>') {
      inBrackets = false;
      current += char;
    } else if (char === ',' && !inBrackets) {
      if (current.trim()) {
        emails.push(current.trim());
      }
      current = '';
    } else {
      current += char;
    }
  }

  if (current.trim()) {
    emails.push(current.trim());
  }

  return emails.map(extractEmailAddress);
}


