/**
 * Shared TypeScript Types for AI Outreach Backend
 * Can be used in both Edge Functions and client code
 */

/**
 * API Response Types
 */
export interface ApiResponse<T = any> {
  success: boolean;
  data?: T;
  error?: string;
  message?: string;
}

/**
 * Database Types
 * Add your Supabase table types here
 */

// Example: User type
export interface User {
  id: string;
  email: string;
  created_at: string;
  updated_at: string;
}

// Example: Outreach Campaign type
export interface OutreachCampaign {
  id: string;
  name: string;
  status: "draft" | "active" | "paused" | "completed";
  created_by: string;
  created_at: string;
  updated_at: string;
}

// Contact type (matches database schema)
export interface Contact {
  id: string;
  email: string;
  first_name?: string;
  last_name?: string;
  source: string;
  quality_score: number;
  status: "active" | "inactive" | "bounced" | "unsubscribed";
  tags: any[];
  custom_fields: {
    imported_from?: string;
    import_date?: string;
    found_in?: "from" | "to" | "cc";
    original_name?: string;
    [key: string]: any;
  };
  created_at: string;
  updated_at: string;
}

// Add more types as needed for your AI automation project
