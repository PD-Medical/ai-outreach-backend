// Shared response utilities for Supabase Edge Functions

import { corsHeaders } from "./cors.ts";

export interface ApiResponse<T = any> {
  success: boolean;
  data?: T;
  error?: string;
  message?: string;
}

export function sendSuccess<T>(
  data: T,
  message?: string,
  statusCode: number = 200
): Response {
  const response: ApiResponse<T> = {
    success: true,
    data,
    message,
  };

  return new Response(JSON.stringify(response), {
    status: statusCode,
    headers: {
      "Content-Type": "application/json",
      ...corsHeaders,
    },
  });
}

export function sendError(
  error: string,
  statusCode: number = 400
): Response {
  const response: ApiResponse = {
    success: false,
    error,
  };

  return new Response(JSON.stringify(response), {
    status: statusCode,
    headers: {
      "Content-Type": "application/json",
      ...corsHeaders,
    },
  });
}


