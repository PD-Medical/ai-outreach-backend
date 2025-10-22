// Email Server Import Module
// Handles IMAP connection and contact extraction from email servers

export interface Contact {
  email: string;
  first_name?: string;
  last_name?: string;
  source: string;
  quality_score: number;
  status: string;
  tags: any[];
  custom_fields: any;
}

export async function importFromEmailServer(
  emailId: string,
  limit: number = 500
): Promise<{ contacts: Contact[], message: string }> {
  
  const emailPass = Deno.env.get("EMAIL_PASSWORD") || "";
  
  if (!emailPass) {
    throw new Error("EMAIL_PASSWORD environment variable is required");
  }

  console.log(`[EMAIL] Connecting to mail.pdmedical.com.au as ${emailId}`);

  const contacts = new Map<string, Contact>();
  
  // Try multiple connection approaches
  let conn;
  
  // Approach 1: Try standard port 143 (more lenient)
  console.log("[CONNECT] Attempting port 143...");
  try {
    conn = await Deno.connect({
      hostname: "mail.pdmedical.com.au",
      port: 143,
    });
    console.log("[SUCCESS] Connected via port 143");
  } catch (error143) {
    console.log("[ERROR] Port 143 failed:", error143.message);
    
    // Approach 2: Try port 993 with TLS
    console.log("[CONNECT] Attempting port 993 (TLS)...");
    try {
      conn = await Deno.connectTls({
        hostname: "mail.pdmedical.com.au",
        port: 993,
      });
      console.log("[SUCCESS] Connected via port 993");
    } catch (error993) {
      throw new Error(`Cannot connect to email server: Port 143: ${error143.message}, Port 993: ${error993.message}`);
    }
  }
  
  const reader = conn.readable.getReader();
  const writer = conn.writable.getWriter();
  
  const encoder = new TextEncoder();
  const decoder = new TextDecoder();
  
  const sendCommand = async (command: string) => {
    const data = encoder.encode(command + '\r\n');
    await writer.write(data);
  };
  
  const readResponse = async (): Promise<string> => {
    const { value } = await reader.read();
    return decoder.decode(value);
  };
  
  try {
    // IMAP Protocol
    await readResponse(); // Greeting
    console.log("[SUCCESS] IMAP server ready");
    
    await sendCommand(`A1 LOGIN ${emailId} ${emailPass}`);
    const loginResponse = await readResponse();
    
    if (!loginResponse.includes('A1 OK')) {
      throw new Error(`Login failed: ${loginResponse}`);
    }
    console.log("[SUCCESS] Login successful");
    
    await sendCommand('A2 SELECT INBOX');
    const selectResponse = await readResponse();
    
    if (!selectResponse.includes('A2 OK')) {
      throw new Error(`Failed to select INBOX: ${selectResponse}`);
    }
    console.log("[SUCCESS] INBOX selected");
    
    // Search for ALL messages
    await sendCommand('A3 SEARCH ALL');
    const searchResponse = await readResponse();
    
    const messageIds = searchResponse.match(/\d+/g) || [];
    console.log(`[EMAIL] Found ${messageIds.length} total messages`);
    
    // Limit messages to avoid timeout (all 308 messages)
    const limitedIds = messageIds;
    console.log(`[EMAIL] Processing ${limitedIds.length} messages...`);
    
    const parseName = (fullName?: string): { first_name?: string, last_name?: string } => {
      if (!fullName) return { first_name: undefined, last_name: undefined };
      const trimmed = fullName.trim();
      if (!trimmed) return { first_name: undefined, last_name: undefined };
      
      const parts = trimmed.split(/\s+/);
      if (parts.length === 0) return { first_name: undefined, last_name: undefined };
      if (parts.length === 1) return { first_name: parts[0], last_name: undefined };
      
      return { 
        first_name: parts[0], 
        last_name: parts.slice(1).join(' ') 
      };
    };
    
    // Track time to avoid timeout
    const startTime = Date.now();
    const maxExecutionTime = 55000; // 55 seconds max (Edge Functions have 60s timeout)
    
    // Process messages
    for (let i = 0; i < limitedIds.length; i++) {
      // Timeout protection
      if (Date.now() - startTime > maxExecutionTime) {
        console.log(`[WARN] Timeout approaching, stopped at ${i} messages`);
        break;
      }
      
      const msgId = limitedIds[i];
      
      try {
        await sendCommand(`A${4+i} FETCH ${msgId} ENVELOPE`);
        const envelopeResponse = await readResponse();
        
        // Parse IMAP ENVELOPE: (("Name" NIL "mailbox" "domain"))
        // Also handle NIL mailbox: ((NIL NIL "mailbox" "domain"))
        const addressPattern1 = /\(\("([^"]*)" NIL "([^"]+)" "([^"]+)"\)\)/g;
        const addressPattern2 = /\(\(NIL NIL "([^"]+)" "([^"]+)"\)\)/g;
        
        const matches1 = [...envelopeResponse.matchAll(addressPattern1)];
        const matches2 = [...envelopeResponse.matchAll(addressPattern2)];
        
        // Process pattern 1: (("Name" NIL "mailbox" "domain"))
        for (const match of matches1) {
          const name = match[1];
          const mailbox = match[2];
          const domain = match[3];
          
          if (!mailbox || !domain) continue;
          
          const email = `${mailbox}@${domain}`.toLowerCase().trim();
          
          // Validate email format
          if (contacts.has(email) || !email.includes('@') || email.length < 5) continue;
          
          const { first_name, last_name } = parseName(name);
          contacts.set(email, {
            email,
            first_name,
            last_name,
            source: 'email_server',
            quality_score: 50,
            status: 'active',
            tags: [],
            custom_fields: {
              imported_from: 'pdmedical_email_server',
              import_date: new Date().toISOString(),
              found_in: 'envelope',
              original_name: name || null
            }
          });
        }
        
        // Process pattern 2: ((NIL NIL "mailbox" "domain"))
        for (const match of matches2) {
          const mailbox = match[1];
          const domain = match[2];
          
          if (!mailbox || !domain) continue;
          
          const email = `${mailbox}@${domain}`.toLowerCase().trim();
          
          // Validate email format
          if (contacts.has(email) || !email.includes('@') || email.length < 5) continue;
          
          contacts.set(email, {
            email,
            first_name: undefined,
            last_name: undefined,
            source: 'email_server',
            quality_score: 50,
            status: 'active',
            tags: [],
            custom_fields: {
              imported_from: 'pdmedical_email_server',
              import_date: new Date().toISOString(),
              found_in: 'envelope',
              original_name: null
            }
          });
        }
        
        if ((i + 1) % 100 === 0) {
          console.log(`[EMAIL] Processed ${i + 1}/${limitedIds.length} messages (${contacts.size} unique contacts)...`);
        }
      } catch (error) {
        // Skip failed messages silently
        continue;
      }
    }
    
    // Cleanup
    await sendCommand('A999 LOGOUT');
    await readResponse();
    conn.close();
    console.log("[SUCCESS] Disconnected from IMAP server");
    
    const contactsList = Array.from(contacts.values());
    console.log(`[SUCCESS] Extracted ${contactsList.length} unique contacts from email server`);
    
    return {
      contacts: contactsList,
      message: `Successfully extracted ${contactsList.length} contacts from mail.pdmedical.com.au`
    };
    
  } catch (error) {
    // Ensure connection is closed on error
    try {
      conn.close();
    } catch (closeError) {
      // Ignore close errors
    }
    
    console.error("[ERROR] Email server import failed:", error);
    throw error;
  }
}
