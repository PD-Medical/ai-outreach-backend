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
  status: 'draft' | 'active' | 'paused' | 'completed';
  created_by: string;
  created_at: string;
  updated_at: string;
}

// Add more types as needed for your AI automation project

