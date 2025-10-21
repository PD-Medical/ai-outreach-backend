import { VercelRequest, VercelResponse } from '@vercel/node';
import { sendSuccess, setCorsHeaders } from '../src/utils/response';

/**
 * Health check endpoint
 * GET /api/health
 */
export default async function handler(
  req: VercelRequest,
  res: VercelResponse
): Promise<VercelResponse> {
  // Set CORS headers
  setCorsHeaders(res);

  // Handle OPTIONS request for CORS preflight
  if (req.method === 'OPTIONS') {
    return res.status(200).end();
  }

  // Only allow GET requests
  if (req.method !== 'GET') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  return sendSuccess(res, {
    status: 'healthy',
    timestamp: new Date().toISOString(),
    service: 'ai-outreach-backend',
  });
}

