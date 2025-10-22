// Mailchimp Import Module
// Handles Mailchimp API connection and contact extraction

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

export interface MailchimpConfig {
  apiKey: string;
  serverPrefix: string; // e.g., "us1", "us2", etc.
  listId: string;
}

export async function importFromMailchimp(
  supabaseClient: any,
  listId: string,
  limit: number = 10000
): Promise<{ contacts: Contact[], message: string }> {
  
  const apiKey = Deno.env.get("MAILCHIMP_API_KEY");
  if (!apiKey) {
    throw new Error("MAILCHIMP_API_KEY environment variable is required");
  }

  // Extract server prefix from API key (last part after the dash)
  const serverPrefix = apiKey.split('-').pop();
  if (!serverPrefix) {
    throw new Error("Invalid Mailchimp API key format");
  }

  const config: MailchimpConfig = {
    apiKey,
    serverPrefix,
    listId
  };

  console.log(`[MAILCHIMP] Connecting to Mailchimp server: ${config.serverPrefix}`);
  console.log(`[MAILCHIMP] Importing from list: ${config.listId}`);

  const contacts: Contact[] = [];
  const baseUrl = `https://${config.serverPrefix}.api.mailchimp.com/3.0`;
  const authHeader = `Basic ${btoa(`anystring:${config.apiKey}`)}`;
  
  try {
    let offset = 0;
    const count = 1000; // Max allowed by Mailchimp per request
    let totalMembers = 0;
    
    console.log(`[MAILCHIMP] Starting import from list ${config.listId}...`);
    
    // Fetch subscribed members only with pagination
    while (offset < limit) {
      const listUrl = `${baseUrl}/lists/${config.listId}/members?count=${count}&offset=${offset}&status=subscribed&fields=members.email_address,members.merge_fields,members.status,members.id,members.tags,members.timestamp_signup,members.last_changed,total_items`;
      
      console.log(`[MAILCHIMP] Fetching batch ${Math.floor(offset/count) + 1}: offset=${offset}...`);
      
      const response = await fetch(listUrl, {
        method: 'GET',
        headers: {
          'Authorization': authHeader,
          'Content-Type': 'application/json'
        }
      });

      if (!response.ok) {
        throw new Error(`Mailchimp API error: ${response.status} ${response.statusText}`);
      }

      const data = await response.json();
      totalMembers = data.total_items || 0;
      const members = data.members || [];
      
      if (offset === 0) {
        console.log(`[MAILCHIMP] Total subscribers in list: ${totalMembers}`);
      }
      
      if (members.length === 0) {
        break; // No more members to fetch
      }
      
      // Process members from this batch
      const batchContacts = members.map((member: any) => ({
        email: member.email_address.toLowerCase(),
        first_name: member.merge_fields?.FNAME || undefined,
        last_name: member.merge_fields?.LNAME || undefined,
        source: 'mailchimp',
        quality_score: 75,
        status: member.status === 'subscribed' ? 'active' : 'inactive',
        tags: member.tags?.map((tag: any) => tag.name) || [],
        custom_fields: {
          imported_from: 'mailchimp',
          import_date: new Date().toISOString(),
          mailchimp_id: member.id,
          mailchimp_status: member.status,
          mailchimp_list_id: config.listId,
          signup_date: member.timestamp_signup,
          last_changed: member.last_changed,
          merge_fields: member.merge_fields || {}
        }
      }));
      
      contacts.push(...batchContacts);
      offset += members.length;
      
      // Log progress every 1000 contacts
      if (contacts.length % 1000 === 0 || members.length < count) {
        console.log(`[MAILCHIMP] Progress: ${contacts.length}/${Math.min(limit, totalMembers)} contacts processed`);
      }
      
      // Break if we've fetched all available members or reached limit
      if (members.length < count || contacts.length >= limit) {
        break;
      }
    }
    
    console.log(`[SUCCESS] Extracted ${contacts.length} contacts from Mailchimp (Total in list: ${totalMembers})`);
    
  } catch (error) {
    console.error("[ERROR] Mailchimp API error:", error);
    throw error;
  }

  return {
    contacts,
    message: `Successfully extracted ${contacts.length} contacts from Mailchimp list ${config.listId}`
  };
}
