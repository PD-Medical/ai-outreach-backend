/**
 * IMAP Client for Email Synchronization
 * 
 * Uses npm:imap package for connecting to IMAP servers and fetching emails.
 * Handles connection management, email fetching, and parsing IMAP messages.
 */

import Imap from 'npm:imap@0.8.19';
import { ImapConfig, FetchOptions, ImapMessage, ImapConnectionError } from './types.ts';

/**
 * IMAP Client class for managing email server connections
 */
export class ImapClient {
  private imap: any;
  private config: ImapConfig;
  private connected: boolean = false;

  constructor(config: ImapConfig) {
    this.config = config;
    this.imap = new Imap({
      user: config.user,
      password: config.password,
      host: config.host,
      port: config.port,
      tls: config.tls,
      tlsOptions: config.tlsOptions || { rejectUnauthorized: false },
      connTimeout: 30000,        // 30 second connection timeout
      authTimeout: 30000,         // 30 second auth timeout
      keepalive: {
        interval: 10000,          // Send keepalive every 10 seconds
        idleInterval: 300000,     // 5 minute idle interval
        forceNoop: true
      }
    });
  }

  /**
   * Connect to the IMAP server
   */
  async connect(): Promise<void> {
    return new Promise((resolve, reject) => {
      this.imap.once('ready', () => {
        this.connected = true;
        console.log('[IMAP] Connected to', this.config.host);
        resolve();
      });

      this.imap.once('error', (err: Error) => {
        console.error('[IMAP] Connection error:', err);
        this.connected = false;
        reject(new ImapConnectionError(`Failed to connect: ${err.message}`));
      });

      this.imap.once('end', () => {
        console.log('[IMAP] Connection ended');
        this.connected = false;
      });

      try {
        this.imap.connect();
      } catch (error) {
        reject(new ImapConnectionError(`Connect failed: ${error.message}`));
      }
    });
  }

  /**
   * Disconnect from the IMAP server
   */
  async disconnect(): Promise<void> {
    if (this.connected) {
      this.imap.end();
      this.connected = false;
    }
  }

  /**
   * Open a mailbox folder
   */
  private async openBox(folder: string, readOnly: boolean = true): Promise<any> {
    return new Promise((resolve, reject) => {
      this.imap.openBox(folder, readOnly, (err: Error, box: any) => {
        if (err) {
          reject(new ImapConnectionError(`Failed to open folder ${folder}: ${err.message}`));
        } else {
          resolve(box);
        }
      });
    });
  }

  /**
   * Fetch emails from a folder
   */
  async fetchEmails(options: FetchOptions): Promise<ImapMessage[]> {
    const { folder, startUid, endUid, startDate, endDate, limit = 100 } = options;

    // Open folder
    const box = await this.openBox(folder, true);

    // Build search criteria
    const searchCriteria: any[] = ['ALL'];
    
    if (startDate) {
      searchCriteria.push(['SINCE', startDate]);
    }
    
    if (endDate) {
      searchCriteria.push(['BEFORE', endDate]);
    }

    // Search for messages
    const uids = await this.searchMessages(searchCriteria);
    
    if (uids.length === 0) {
      console.log(`[IMAP] No messages found in ${folder}`);
      return [];
    }

    // Filter by UID if specified
    let filteredUids = uids;
    if (startUid !== undefined) {
      filteredUids = uids.filter(uid => uid > startUid);
    }
    if (endUid !== undefined) {
      filteredUids = filteredUids.filter(uid => uid <= endUid);
    }

    // Apply limit
    if (limit && filteredUids.length > limit) {
      filteredUids = filteredUids.slice(0, limit);
    }

    if (filteredUids.length === 0) {
      console.log(`[IMAP] No messages after filtering in ${folder}`);
      return [];
    }

    console.log(`[IMAP] Fetching ${filteredUids.length} messages from ${folder}`);

    // Fetch messages
    return await this.fetchMessagesByUid(filteredUids);
  }

  /**
   * Search for messages matching criteria
   */
  private async searchMessages(criteria: any[]): Promise<number[]> {
    return new Promise((resolve, reject) => {
      this.imap.search(criteria, (err: Error, uids: number[]) => {
        if (err) {
          reject(new ImapConnectionError(`Search failed: ${err.message}`));
        } else {
          resolve(uids || []);
        }
      });
    });
  }

  /**
   * Fetch messages by their UIDs
   */
  private async fetchMessagesByUid(uids: number[]): Promise<ImapMessage[]> {
    const messages: ImapMessage[] = [];

    return new Promise((resolve, reject) => {
      const fetch = this.imap.fetch(uids, {
        bodies: ['HEADER.FIELDS (FROM TO CC BCC SUBJECT DATE MESSAGE-ID IN-REPLY-TO REFERENCES)', 'TEXT'],
        struct: true
      });

      fetch.on('message', (msg: any, seqno: number) => {
        const message: Partial<ImapMessage> = {
          attributes: {} as any,
          headers: new Map(),
          body: ''
        };

        msg.on('body', (stream: any, info: any) => {
          let buffer = '';
          
          stream.on('data', (chunk: any) => {
            buffer += chunk.toString('utf8');
          });

          stream.once('end', () => {
            if (info.which.includes('HEADER')) {
              // Parse headers
              const headerLines = buffer.split('\r\n');
              let currentHeader = '';
              let currentValue = '';

              for (const line of headerLines) {
                if (line.match(/^[\w-]+:/)) {
                  // New header
                  if (currentHeader) {
                    const existing = message.headers!.get(currentHeader.toLowerCase()) || [];
                    existing.push(currentValue.trim());
                    message.headers!.set(currentHeader.toLowerCase(), existing);
                  }
                  const match = line.match(/^([\w-]+):\s*(.*)$/);
                  if (match) {
                    currentHeader = match[1];
                    currentValue = match[2];
                  }
                } else if (line.startsWith(' ') || line.startsWith('\t')) {
                  // Continuation of previous header
                  currentValue += ' ' + line.trim();
                }
              }

              // Don't forget the last header
              if (currentHeader) {
                const existing = message.headers!.get(currentHeader.toLowerCase()) || [];
                existing.push(currentValue.trim());
                message.headers!.set(currentHeader.toLowerCase(), existing);
              }
            } else {
              // Body
              message.body = buffer;
            }
          });
        });

        msg.once('attributes', (attrs: any) => {
          message.attributes = attrs;
        });

        msg.once('end', () => {
          messages.push(message as ImapMessage);
        });
      });

      fetch.once('error', (err: Error) => {
        reject(new ImapConnectionError(`Fetch failed: ${err.message}`));
      });

      fetch.once('end', () => {
        console.log(`[IMAP] Fetched ${messages.length} messages`);
        resolve(messages);
      });
    });
  }

  /**
   * Get list of available folders
   */
  async listFolders(): Promise<string[]> {
    return new Promise((resolve, reject) => {
      this.imap.getBoxes((err: Error, boxes: any) => {
        if (err) {
          reject(new ImapConnectionError(`Failed to list folders: ${err.message}`));
        } else {
          const folderNames = this.extractFolderNames(boxes);
          resolve(folderNames);
        }
      });
    });
  }

  /**
   * Extract folder names from IMAP boxes structure
   */
  private extractFolderNames(boxes: any, prefix: string = ''): string[] {
    const names: string[] = [];

    for (const [name, box] of Object.entries(boxes)) {
      const fullName = prefix ? `${prefix}/${name}` : name;
      names.push(fullName);

      if (box && typeof box === 'object' && box.children) {
        names.push(...this.extractFolderNames(box.children, fullName));
      }
    }

    return names;
  }

  /**
   * Get the highest UID in a folder
   */
  async getHighestUid(folder: string): Promise<number> {
    const box = await this.openBox(folder, true);
    return box.uidnext - 1; // uidnext is the next UID that will be assigned
  }

  /**
   * Check if connected
   */
  isConnected(): boolean {
    return this.connected;
  }
}

/**
 * Helper function to create IMAP client and execute operation
 * Automatically handles connection and disconnection
 */
export async function withImapClient<T>(
  config: ImapConfig,
  operation: (client: ImapClient) => Promise<T>
): Promise<T> {
  const client = new ImapClient(config);
  
  try {
    await client.connect();
    const result = await operation(client);
    return result;
  } finally {
    await client.disconnect();
  }
}

/**
 * Parse IMAP message headers into structured format
 */
export function parseImapHeaders(headers: Map<string, string[]>): Record<string, string | string[]> {
  const result: Record<string, string | string[]> = {};

  for (const [key, values] of headers.entries()) {
    if (values.length === 1) {
      result[key] = values[0];
    } else {
      result[key] = values;
    }
  }

  return result;
}

/**
 * Extract plain text from email body
 */
export function extractPlainText(body: string | Buffer): string {
  const text = typeof body === 'string' ? body : body.toString('utf8');
  
  // Remove quoted-printable encoding
  let decoded = text.replace(/=\r?\n/g, ''); // Remove soft line breaks
  decoded = decoded.replace(/=([0-9A-F]{2})/gi, (_, hex) => {
    return String.fromCharCode(parseInt(hex, 16));
  });

  return decoded;
}

/**
 * Parse IMAP flags into boolean fields
 */
export function parseImapFlags(flags: string[]): {
  is_seen: boolean;
  is_flagged: boolean;
  is_answered: boolean;
  is_draft: boolean;
  is_deleted: boolean;
} {
  return {
    is_seen: flags.includes('\\Seen'),
    is_flagged: flags.includes('\\Flagged'),
    is_answered: flags.includes('\\Answered'),
    is_draft: flags.includes('\\Draft'),
    is_deleted: flags.includes('\\Deleted')
  };
}


