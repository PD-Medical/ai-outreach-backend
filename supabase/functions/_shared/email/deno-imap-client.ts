/**
 * Deno IMAP Client Wrapper
 * 
 * Uses @workingdevshero/deno-imap - a native Deno IMAP library
 * This avoids Node.js compatibility issues with npm:imap
 */

import { ImapClient as DenoImap } from 'jsr:@workingdevshero/deno-imap@1.0.0';
import { ImapConfig, FetchOptions, ImapMessage } from './types.ts';

/**
 * Wrapper around the Deno IMAP client
 */
export class DenoImapClient {
  private client: DenoImap;
  private config: ImapConfig;
  private connected: boolean = false;
  private authenticated: boolean = false;

  constructor(config: ImapConfig) {
    this.config = config;
    
    // Prepare TLS options
    // For shared hosting with certificate name mismatches, we include the server certificate
    const tlsOptions: any = {};
    
    // Load CA certificate if provided
    if (config.tlsOptions?.ca) {
      tlsOptions.caCerts = [config.tlsOptions.ca];
    }
    
    // For shared hosting environments where cert doesn't match hostname
    // Deno now supports unsafelyDisableHostnameVerification for hostname mismatches
    // This is needed because mail.pdmedical.com.au uses a *.vodien.com certificate
    if (config.tlsOptions?.rejectUnauthorized === false && config.host === 'mail.pdmedical.com.au') {
      // Add the shared hosting certificate to trusted CAs
      const sharedHostingCert = `-----BEGIN CERTIFICATE-----
MIIHazCCBlOgAwIBAgIQM2NT51BNKCMfb9uB8e+FkTANBgkqhkiG9w0BAQsFADCB
jzELMAkGA1UEBhMCR0IxGzAZBgNVBAgTEkdyZWF0ZXIgTWFuY2hlc3RlcjEQMA4G
A1UEBxMHU2FsZm9yZDEYMBYGA1UEChMPU2VjdGlnbyBMaW1pdGVkMTcwNQYDVQQD
Ey5TZWN0aWdvIFJTQSBEb21haW4gVmFsaWRhdGlvbiBTZWN1cmUgU2VydmVyIENB
MB4XDTI0MTExNTAwMDAwMFoXDTI1MTExNTIzNTk1OVowFzEVMBMGA1UEAwwMKi52
b2RpZW4uY29tMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAtTVGwL4l
erU4NYV31OYIp56XPWNAPv9q6O+G8nxpQv9Tq9czVRnsXC6nzKFBQ/forw9NNpgs
3rQo9wvImYBvANkLUYGfZtS3imSvaTP9/oNk8AwqC0Uvroa5I+7dHi2bnWEVqkhY
9LdkbRSm2Y7ZGTMRK8oMQC15JMSu48DfvunKgrGJhDZhO8rRZAxqFuT6XaqP+zB2
09GwDTZgwU0dDa3CaCt8JoAgdkNPD+tccJh+CB41yN1Eo4TPX73K90RuVGIf7Qwz
Jm1B6yeYYseQL29h3ZtzIYoXiKVp+Wlr+0aNELjClMatNkFi61pOJfb6gN/5AHhP
gEU6XfsTKPphtwIDAQABo4IEODCCBDQwHwYDVR0jBBgwFoAUjYxexFStiuF36Zv5
mwXhuAGNYeEwHQYDVR0OBBYEFKzqChTVA6T6csL14YqKhLePspnwMA4GA1UdDwEB
/wQEAwIFoDAMBgNVHRMBAf8EAjAAMB0GA1UdJQQWMBQGCCsGAQUFBwMBBggrBgEF
BQcDAjBJBgNVHSAEQjBAMDQGCysGAQQBsjEBAgIHMCUwIwYIKwYBBQUHAgEWF2h0
dHBzOi8vc2VjdGlnby5jb20vQ1BTMAgGBmeBDAECATCBhAYIKwYBBQUHAQEEeDB2
ME8GCCsGAQUFBzAChkNodHRwOi8vY3J0LnNlY3RpZ28uY29tL1NlY3RpZ29SU0FE
b21haW5WYWxpZGF0aW9uU2VjdXJlU2VydmVyQ0EuY3J0MCMGCCsGAQUFBzABhhdo
dHRwOi8vb2NzcC5zZWN0aWdvLmNvbTCCAX8GCisGAQQB1nkCBAIEggFvBIIBawFp
AHYA3dzKNJXX4RYF55Uy+sef+D0cUN/bADoUEnYKLKy7yCoAAAGTLqhc3wAABAMA
RzBFAiEA/8DAsmqc8K0FYFNH6vNwRqCWJ+tDxLuBGa4iICFdw/ACICcqbSl13Rrc
KoSvlLYvvWu8VHviIKei+xjYPqCr9RFDAHcAzPsPaoVxCWX+lZtTzumyfCLphVwN
l422qX5UwP5MDbAAAAGTLqhcpwAABAMASDBGAiEAkpGkodAVpLxfKJf+UbBeuiY+
mEfNtvZ6vq7jzKrMb4YCIQDtpvRvEF9cIPRBkGARg9hp1OJhupj1YK2rCwgEguaD
igB2ABLxTjS9U3JMhAYZw48/ehP457Vih4icbTAFhOvlhiY6AAABky6oXIkAAAQD
AEcwRQIhANm99r5rnVOV9LTjjxPAu24lEqiCcdEwNuSihcX+pkq1AiA9CPfJgBPp
fIKdlfvEHvwsvmHgbMVpUFS4rCzR0UJhejCCAV4GA1UdEQSCAVUwggFRggwqLnZv
ZGllbi5jb22CESouYXUuc3lyYWhvc3QuY29tghMqLmhvc3RpbmdhdXMuY29tLmF1
gg4qLmhvc3Rzb2xuLmNvbYISKi5pYWQwMS5kcy5uZXR3b3JrghUqLmxpdmVob3N0
c3VwcG9ydC5jb22CEioubG9uMDEuZHMubmV0d29ya4ISKi5wZXIwMS5kcy5uZXR3
b3JrghIqLnNpbjAxLmRzLm5ldHdvcmuCEiouc2luMDIuZHMubmV0d29ya4ISKi5z
aW4wMy5kcy5uZXR3b3Jrgg4qLnNpbmdob3N0Lm5ldIISKi5zeWQwMi5kcy5uZXR3
b3JrghIqLnN5ZDA1LmRzLm5ldHdvcmuCDyoudm9kaWVuLmNvbS5hdYIPKi53ZWJo
b3N0c2cuY29tgg4qLndlYnNlcnZlci5zZ4IQKi53ZWJ2aXNpb25zLmNvbTANBgkq
hkiG9w0BAQsFAAOCAQEAQT/BaBfBbi5knYJg7nNOAX0yducDQpA0kYPMZbaKe5Pr
2BVX6ko8IDG8jNXpOhcedqMaj3uASRy4Df1trcjgK+BammzrcL/T0y55bD602OKE
wWmMlP7/TzZj3uiuBQ+1iBe52li3OcMJZ7piMSrQfuMFS/rnbhflZBHTek0muPL3
M9hg8X7hzU57mcgNKdBhIFXct1xGLa64QMOsWVkzwDtWkaJ/YPdfrb6ijO2MICHa
NTGvyCCOqRHGNBYJ2lp6F51Z2KHQ2cSN4W1dsc6YFjtaONeS8G1v7rARCg7jRKch
noJyS9zrWN5jmAkRYdle9cTrbr0lI3nEMDFRnSWZYg==
-----END CERTIFICATE-----`;
      tlsOptions.caCerts = [sharedHostingCert];

      // Disable hostname verification for this specific case
      // WARNING: This is a security risk and should only be used for known shared hosting scenarios
      tlsOptions.unsafelyDisableHostnameVerification = true;
    }
    
    this.client = new DenoImap({
      host: config.host,
      port: config.port,
      tls: config.tls !== false,
      username: config.user,
      password: config.password,
      ...(Object.keys(tlsOptions).length > 0 ? { tlsOptions } : {}),
    });
  }

  /**
   * Connect to IMAP server
   */
  async connect(): Promise<void> {
    try {
      console.log(`[IMAP] Connecting to ${this.config.host}:${this.config.port}`);
      
      await this.client.connect();
      this.connected = true;
      
      console.log('[IMAP] Connected, authenticating...');
      await this.client.authenticate();
      this.authenticated = true;
      
      console.log('[IMAP] Successfully authenticated');
    } catch (error) {
      throw new Error(`IMAP connection failed: ${error.message}`);
    }
  }

  /**
   * List all available mailboxes/folders
   */
  async listFolders(): Promise<Array<{ name: string; flags: string[] }>> {
    try {
      if (!this.authenticated) {
        throw new Error('Not authenticated');
      }

      console.log('[IMAP] Listing folders...');
      const mailboxes = await this.client.listMailboxes();
      
      // Convert to simpler format
      const folders = mailboxes.map((mb: any) => ({
        name: mb.name || mb.path || mb,
        flags: mb.flags || []
      }));
      
      console.log(`[IMAP] Found ${folders.length} folders:`, folders.map(f => f.name));
      return folders;
    } catch (error) {
      console.error('[IMAP] Failed to list folders:', error);
      throw new Error(`Failed to list folders: ${error.message}`);
    }
  }

  /**
   * Disconnect from IMAP server
   */
  async disconnect(): Promise<void> {
    if (this.connected) {
      try {
        this.client.disconnect();
      } catch (e) {
        console.error('[IMAP] Disconnect error:', e);
      }
      this.connected = false;
      this.authenticated = false;
    }
  }

  /**
   * Fetch emails from a folder
   */
  async fetchEmails(options: FetchOptions): Promise<ImapMessage[]> {
    const { folder, startUid, startDate, endDate, limit = 100 } = options;

    // Select folder
    console.log(`[IMAP] Selecting folder: ${folder}`);
    const mailboxInfo = await this.client.selectMailbox(folder);
    console.log(`[IMAP] Folder ${folder} has ${mailboxInfo.exists} messages`);

    if (mailboxInfo.exists === 0) {
      console.log(`[IMAP] No messages in ${folder}`);
      return [];
    }

    // Build search criteria
    const searchCriteria: any = {};
    
    if (startUid !== undefined && startUid > 0) {
      searchCriteria.uid = `${startUid + 1}:*`;
    }
    
    if (startDate) {
      searchCriteria.since = this.formatDate(startDate);
    }
    
    if (endDate) {
      searchCriteria.before = this.formatDate(endDate);
    }

    // Search for messages
    let uids: number[];
    if (Object.keys(searchCriteria).length > 0) {
      console.log('[IMAP] Searching with criteria:', searchCriteria);
      uids = await this.client.search(searchCriteria);
    } else {
      console.log('[IMAP] Searching for all messages');
      uids = await this.client.search({ all: true });
    }

    if (uids.length === 0) {
      console.log(`[IMAP] No messages found in ${folder}`);
      return [];
    }

    console.log(`[IMAP] Found ${uids.length} messages`);

    // Apply limit
    const limitedUids = limit ? uids.slice(0, limit) : uids;
    
    console.log(`[IMAP] Fetching ${limitedUids.length} messages from ${folder}`);

    // Fetch messages
    return await this.fetchMessagesByUid(limitedUids);
  }

  /**
   * Fetch messages by UID
   */
  private async fetchMessagesByUid(uids: number[]): Promise<ImapMessage[]> {
    const messages: ImapMessage[] = [];

    // Fetch ONE message at a time to avoid CPU limits
    // Edge Functions have a 2-second CPU time hard limit
    // Size threshold for large emails (100 KB)
    const SIZE_THRESHOLD = 102400;
    const chunkSize = 1;
    
    for (let i = 0; i < uids.length; i += chunkSize) {
      const chunk = uids.slice(i, Math.min(i + chunkSize, uids.length));
      const uidRange = chunk.length === 1 ? chunk[0].toString() : `${chunk[0]}:${chunk[chunk.length - 1]}`;
      
      console.log(`[IMAP] Fetching UID ${uidRange}...`);
      
      // Fetch with full: true to get body content
      // We fetch one at a time to manage CPU limits
      const fetchedMessages = await this.client.fetch(uidRange, {
        uid: true,
        flags: true,
        envelope: true,
        bodyParts: ['HEADER', 'TEXT'],
        full: true, // Required to get body content
      });

      // Convert to our ImapMessage format
      // Check body size and decide whether to parse or store raw
      for (const msg of fetchedMessages) {
        // Check raw body size
        let bodySize = 0;
        if (msg.raw) {
          bodySize = msg.raw instanceof Uint8Array ? msg.raw.length : msg.raw.length;
        } else if (msg.parts && msg.parts['TEXT'] && msg.parts['TEXT'].data) {
          const textData = msg.parts['TEXT'].data;
          bodySize = textData instanceof Uint8Array ? textData.length : textData.length;
        }
        
        console.log(`[IMAP] UID ${msg.uid} body size: ${bodySize} bytes`);
        
        // For large emails, store raw without parsing
        // For small emails, we already have the data, just mark as parsed
        const isParsed = bodySize <= SIZE_THRESHOLD;
        if (!isParsed) {
          console.log(`[IMAP] Large email detected (${bodySize} bytes), will store raw without parsing`);
        }
        
        const converted = this.convertMessage(msg, isParsed, bodySize);
        if (converted) {
          messages.push(converted);
        }
      }
    }

    console.log(`[IMAP] Successfully fetched ${messages.length} messages`);
    return messages;
  }

  /**
   * Parse raw email headers from HEADER part
   */
  private parseRawHeaders(headerText: string): Record<string, string> {
    const headers: Record<string, string> = {};
    const lines = headerText.split(/\r?\n/);
    
    let currentHeader = '';
    let currentValue = '';
    
    for (const line of lines) {
      // Check if this is a continuation line (starts with whitespace)
      if (line.match(/^\s/) && currentHeader) {
        currentValue += ' ' + line.trim();
      } else if (line.includes(':')) {
        // Save previous header if exists
        if (currentHeader) {
          headers[currentHeader] = currentValue;
        }
        
        // Parse new header
        const colonIndex = line.indexOf(':');
        currentHeader = line.substring(0, colonIndex).trim();
        currentValue = line.substring(colonIndex + 1).trim();
      }
    }
    
    // Save last header
    if (currentHeader) {
      headers[currentHeader] = currentValue;
    }
    
    return headers;
  }

  /**
   * Convert deno-imap message to our format
   */
  private convertMessage(msg: any, isParsed: boolean = true, size: number = 0): ImapMessage | null {
    try {
      const headers = new Map<string, string[]>();
      
      // Extract headers from envelope and custom headers
      if (msg.envelope) {
        if (msg.envelope.subject) {
          headers.set('subject', [msg.envelope.subject]);
        }
        if (msg.envelope.date) {
          headers.set('date', [msg.envelope.date]);
        }
        if (msg.envelope.messageId) {
          headers.set('message-id', [msg.envelope.messageId]);
        }
        if (msg.envelope.inReplyTo) {
          headers.set('in-reply-to', [msg.envelope.inReplyTo]);
        }
        
        // Store envelope addresses directly as structured data
        // This avoids string parsing issues - we'll extract emails directly from envelope
        if (msg.envelope.from && Array.isArray(msg.envelope.from)) {
          headers.set('_envelope_from', [JSON.stringify(msg.envelope.from)]);
        }
        
        if (msg.envelope.to && Array.isArray(msg.envelope.to)) {
          headers.set('_envelope_to', [JSON.stringify(msg.envelope.to)]);
        }
        
        if (msg.envelope.cc && Array.isArray(msg.envelope.cc)) {
          headers.set('_envelope_cc', [JSON.stringify(msg.envelope.cc)]);
        }
        
        if (msg.envelope.bcc && Array.isArray(msg.envelope.bcc)) {
          headers.set('_envelope_bcc', [JSON.stringify(msg.envelope.bcc)]);
        }
      }

      // Add custom headers (including raw To, From, Cc headers)
      if (msg.headers) {
        for (const [key, value] of Object.entries(msg.headers)) {
          const lowerKey = key.toLowerCase();
          if (!headers.has(lowerKey)) {
            headers.set(lowerKey, Array.isArray(value) ? value as string[] : [value as string]);
          }
        }
      }

      // Extract references
      if (msg.envelope?.references) {
        headers.set('references', Array.isArray(msg.envelope.references) 
          ? msg.envelope.references 
          : [msg.envelope.references]);
      }

      // Extract body from parts object
      // The deno-imap library returns body content in msg.parts
      let body = '';
      
      // Debug: Log what we have
      console.log('[IMAP] Message structure for UID', msg.uid, ':', {
        hasParts: !!msg.parts,
        partsType: typeof msg.parts,
        partsKeys: msg.parts ? Object.keys(msg.parts) : 'N/A',
        hasRaw: !!msg.raw,
        hasBody: !!msg.body
      });
      
      if (msg.parts && typeof msg.parts === 'object') {
        // Parse HEADER part if available
        const headerPart = msg.parts['HEADER'];
        if (headerPart && headerPart.data) {
          const headerText = headerPart.data instanceof Uint8Array 
            ? new TextDecoder().decode(headerPart.data)
            : headerPart.data;
          
          // Parse raw email headers
          const rawHeaders = this.parseRawHeaders(headerText);
          for (const [key, value] of Object.entries(rawHeaders)) {
            if (!headers.has(key.toLowerCase())) {
              headers.set(key.toLowerCase(), [value]);
            }
          }
        }
        
        // Try to get TEXT part first (full body), then fall back to numbered parts
        const textPart = msg.parts['TEXT'];
        
        if (textPart && textPart.data) {
          if (textPart.data instanceof Uint8Array) {
            body = new TextDecoder().decode(textPart.data);
          } else if (typeof textPart.data === 'string') {
            body = textPart.data;
          }
          console.log('[IMAP] Got body from TEXT part, length:', body.length);
        } else {
          // Fallback: Try numbered parts (1, 2, 1.1, 1.2)
          for (const partKey of ['1', '2', '1.1', '1.2']) {
            const part = msg.parts[partKey];
            if (part && part.data) {
              if (part.data instanceof Uint8Array) {
                body = new TextDecoder().decode(part.data);
              } else if (typeof part.data === 'string') {
                body = part.data;
              }
              console.log(`[IMAP] Got body from part ${partKey}, length:`, body.length);
              break;
            }
          }
        }
      }
      
      // Fallback: Try to extract from raw message if body is still empty
      if (!body && msg.raw) {
        const rawText = msg.raw instanceof Uint8Array 
          ? new TextDecoder().decode(msg.raw)
          : msg.raw;
        
        // Split headers and body (separated by double newline)
        const parts = rawText.split(/\r?\n\r?\n/);
        if (parts.length > 1) {
          body = parts.slice(1).join('\n\n');
          console.log('[IMAP] Extracted body from raw message, length:', body.length);
        }
      }
      
      // Try msg.body as last resort
      if (!body && msg.body) {
        if (msg.body instanceof Uint8Array) {
          body = new TextDecoder().decode(msg.body);
        } else if (typeof msg.body === 'string') {
          body = msg.body;
        }
        console.log('[IMAP] Got body from msg.body, length:', body.length);
      }
      
      if (!body) {
        console.log('[IMAP] WARNING: No body content found for UID:', msg.uid);
      }

      return {
        attributes: {
          uid: msg.uid || 0,
          flags: msg.flags || [],
          size: size,
        },
        headers,
        body,
        isParsed: isParsed,
      };
    } catch (error) {
      console.error('[IMAP] Error converting message:', error);
      return null;
    }
  }

  /**
   * Get list of folders
   */
  async listFolders(): Promise<string[]> {
    const mailboxes = await this.client.listMailboxes();
    return mailboxes.map((mb: any) => mb.name || mb);
  }

  /**
   * Get highest UID in folder
   */
  async getHighestUid(folder: string): Promise<number> {
    const mailboxInfo = await this.client.selectMailbox(folder);
    const uids = await this.client.search({ all: true });
    return uids.length > 0 ? Math.max(...uids) : 0;
  }

  /**
   * Format date for IMAP
   */
  private formatDate(date: Date): string {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    const day = date.getDate();
    const month = months[date.getMonth()];
    const year = date.getFullYear();
    return `${day}-${month}-${year}`;
  }

  /**
   * Check if connected
   */
  isConnected(): boolean {
    return this.connected && this.authenticated;
  }
}

/**
 * Helper function with auto-connect/disconnect
 */
export async function withDenoImapClient<T>(
  config: ImapConfig,
  operation: (client: DenoImapClient) => Promise<T>
): Promise<T> {
  const client = new DenoImapClient(config);
  
  try {
    await client.connect();
    const result = await operation(client);
    return result;
  } finally {
    await client.disconnect();
  }
}
