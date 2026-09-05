import { generateGeminiText } from './gemini-adapter';

type LiveProbeEnv = {
  GEMINI_API_KEY?: string;
  AX_MOBILE_INGRESS_SECRET?: string;
  fetchImpl?: typeof fetch;
};

const LIVE_PROMPT = 'Reply with exactly GEMINI_LIVE_OK';

function constantTimeEqual(left: string, right: string): boolean {
  const leftBytes = new TextEncoder().encode(left);
  const rightBytes = new TextEncoder().encode(right);
  if (leftBytes.length !== rightBytes.length) return false;
  let diff = 0;
  for (let index = 0; index < leftBytes.length; index += 1) diff |= leftBytes[index] ^ rightBytes[index];
  return diff === 0;
}

function bearerSecret(request: Request): string {
  const auth = request.headers.get('Authorization') || '';
  return auth.startsWith('Bearer ') ? auth.slice(7).trim() : '';
}

function secretAccepted(received: string, expected: string | undefined): boolean {
  if (!received || !expected || received.length > 512) return false;
  return constantTimeEqual(received, expected);
}

function json(body: unknown, status = 200): Response {
  return Response.json(body, {
    status,
    headers: { 'Cache-Control': 'no-store' },
  });
}

export async function handleGeminiLiveProbe(request: Request, env: LiveProbeEnv): Promise<Response> {
  if (request.method !== 'POST') return json({ error: 'METHOD_NOT_ALLOWED' }, 405);
  if (!secretAccepted(bearerSecret(request), env.AX_MOBILE_INGRESS_SECRET)) {
    return json({ error: 'AUTH_REQUIRED' }, 401);
  }

  const result = await generateGeminiText({
    apiKey: env.GEMINI_API_KEY || '',
    prompt: LIVE_PROMPT,
    fetchImpl: env.fetchImpl,
  });

  if (!result.ok) {
    const status = result.error === 'GEMINI_API_KEY_MISSING' ? 503 : 502;
    return json({ error: result.error }, status);
  }

  return result.text.trim() === 'GEMINI_LIVE_OK'
    ? json({ ok: true, status: 'GEMINI_LIVE_OK' })
    : json({ error: 'GEMINI_LIVE_MARKER_MISMATCH' }, 502);
}
