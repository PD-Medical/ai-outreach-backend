import { VercelRequest, VercelResponse } from '@vercel/node';
import { getSupabaseClient } from '../src/lib/supabase';
import { sendSuccess, sendError, setCorsHeaders } from '../src/utils/response';

/**
 * Test Supabase connection
 * GET /api/test-supabase
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

  try {
    const supabase = getSupabaseClient();

    // Test connection by getting Supabase service status
    const { data, error } = await supabase.from('_test').select('*').limit(1);

    if (error && error.code !== 'PGRST204' && error.code !== '42P01') {
      throw error;
    }

    return sendSuccess(res, {
      connected: true,
      timestamp: new Date().toISOString(),
      message: 'Supabase connection successful',
    });
  } catch (error: any) {
    console.error('Supabase connection error:', error);
    return sendError(
      res,
      `Supabase connection failed: ${error.message}`,
      500
    );
  }
}

