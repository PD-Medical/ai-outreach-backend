import { VercelResponse } from '@vercel/node';
import { ApiResponse } from '../types';

/**
 * Send successful response
 */
export function sendSuccess<T>(
  res: VercelResponse,
  data: T,
  message?: string,
  statusCode: number = 200
): VercelResponse {
  const response: ApiResponse<T> = {
    success: true,
    data,
    message,
  };
  return res.status(statusCode).json(response);
}

/**
 * Send error response
 */
export function sendError(
  res: VercelResponse,
  error: string,
  statusCode: number = 400
): VercelResponse {
  const response: ApiResponse = {
    success: false,
    error,
  };
  return res.status(statusCode).json(response);
}

/**
 * Handle CORS
 */
export function setCorsHeaders(res: VercelResponse): void {
  const frontendUrl = process.env.FRONTEND_URL || 'http://localhost:3000';
  res.setHeader('Access-Control-Allow-Origin', frontendUrl);
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  res.setHeader('Access-Control-Allow-Credentials', 'true');
}

