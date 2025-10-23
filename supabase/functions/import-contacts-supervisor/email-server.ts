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
  emailIds: string[],
  limit: number = 500
): Promise<{ contacts: Contact[], message: string }> {
  
  const emailPass = Deno.env.get("EMAIL_PASSWORD") || "";
  
  if (!emailPass) {
    throw new Error("EMAIL_PASSWORD environment variable is required");
  }

  console.log(`[EMAIL] Processing ${emailIds.length} email accounts: ${emailIds.join(', ')}`);

  const allContacts = new Map<string, Contact>();
  const globalStartTime = Date.now();
  const globalMaxTime = 50000; // 50 seconds total for all accounts (reduced due to dual folder processing)
  
  // Process each email account
  for (const emailId of emailIds) {
    // Global timeout check
    if (Date.now() - globalStartTime > globalMaxTime) {
      console.log(`[WARN] Global timeout reached, stopping at account: ${emailId}`);
      break;
    }
    console.log(`[EMAIL] Processing account: ${emailId}`);
    
    try {
      const accountContacts = await processEmailAccount(emailId, emailPass, limit);
      
      // Merge contacts from this account
      for (const contact of accountContacts) {
        allContacts.set(contact.email, contact);
      }
      
      if (accountContacts.length === 0) {
        console.log(`[WARN] ${emailId}: 0 contacts extracted - may need investigation`);
      } else {
        console.log(`[SUCCESS] ${emailId}: ${accountContacts.length} contacts`);
      }
      
    } catch (error) {
      console.error(`[ERROR] ${emailId} failed:`, error.message);
      // Continue with other accounts
    }
  }
  
  const contactsList = Array.from(allContacts.values());
  console.log(`[SUCCESS] Total unique contacts from all accounts: ${contactsList.length}`);
  
  return {
    contacts: contactsList,
    message: `Successfully extracted ${contactsList.length} contacts from ${emailIds.length} accounts`
  };
}

async function processEmailAccount(
  emailId: string,
  emailPass: string,
  limit: number
): Promise<Contact[]> {
  
  console.log(`[EMAIL] Connecting to mail.pdmedical.com.au as ${emailId}`);

  const contacts = new Map<string, Contact>();
  
  // Process INBOX only (SENT folder doesn't exist on this server)
  const folders = ['INBOX'];
  
  for (const folder of folders) {
    try {
      console.log(`[EMAIL] Processing folder: ${folder}`);
      const folderContacts = await processFolder(emailId, emailPass, folder, limit);
      
      // Merge contacts from this folder
      for (const contact of folderContacts) {
        contacts.set(contact.email, contact);
      }
      
      console.log(`[SUCCESS] ${folder}: ${folderContacts.length} contacts`);
    } catch (error) {
      console.log(`[WARN] ${folder} folder failed:`, error.message);
      // Continue with other folders
    }
  }
  
  const contactsList = Array.from(contacts.values());
  console.log(`[SUCCESS] Extracted ${contactsList.length} unique contacts from ${emailId}`);
  
  return contactsList;
}

async function processFolder(
  emailId: string,
  emailPass: string,
  folder: string,
  limit: number
): Promise<Contact[]> {
  
  console.log(`[EMAIL] Processing ${folder} folder for ${emailId}`);

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
    
    await sendCommand(`A2 SELECT ${folder}`);
    const selectResponse = await readResponse();
    
    if (!selectResponse.includes('A2 OK')) {
      throw new Error(`Failed to select ${folder}: ${selectResponse}`);
    }
    console.log(`[SUCCESS] ${folder} selected`);
    
    // Search for ALL messages
    await sendCommand('A3 SEARCH ALL');
    const searchResponse = await readResponse();
    
    const messageIds = searchResponse.match(/\d+/g) || [];
    console.log(`[EMAIL] Found ${messageIds.length} total messages`);
    
    // Limit messages to avoid timeout (max 500 messages per account for single-account processing)
    const limitedIds = messageIds.slice(0, 500);
    console.log(`[EMAIL] Processing ${limitedIds.length} messages (single-account mode)...`);
    
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
    
    // Track time to avoid timeout - increased for single-account processing
    const startTime = Date.now();
    const maxExecutionTime = 45000; // 45 seconds max per account (single-account mode)
    
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
    console.log(`[SUCCESS] Extracted ${contactsList.length} unique contacts from ${folder}`);
    
    return contactsList;
    
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
