import { DriveAdapter } from './drive-adapter';
import { GeminiRouter, type GeminiAccount } from './gemini-router';

export type AxAdaptersEnv = {
  AX_MOBILE_INGRESS_SECRET?: string;
  GEMINI_ACCOUNT_1?: string;
  GEMINI_ACCOUNT_2?: string;
  GEMINI_ACCOUNT_3?: string;
  GOOGLE_DRIVE_CREDENTIAL?: string;
};

type GeminiGenerate = ConstructorParameters<typeof GeminiRouter>[1];
type Dependencies = {
  generateGemini?: GeminiGenerate;
  driveFetch?: typeof fetch;
};

function json(body: unknown, status = 200): Response {
  return Response.json(body, {
    status,
    headers: {
      'Cache-Control': 'no-store',
      'Content-Type': 'application/json; charset=utf-8',
    },
  });
}

function constantTimeEqual(left: string, right: string): boolean {
  const a = new TextEncoder().encode(left);
  const b = new TextEncoder().encode(right);
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i += 1) diff |= a[i] ^ b[i];
  return diff === 0;
}

function authorized(request: Request, env: AxAdaptersEnv): boolean {
  const expected = env.AX_MOBILE_INGRESS_SECRET || '';
  const received = (request.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '').trim();
  return Boolean(expected && received && received.length <= 512 && constantTimeEqual(received, expected));
}

function geminiAccounts(env: AxAdaptersEnv): GeminiAccount[] {
  return [env.GEMINI_ACCOUNT_1, env.GEMINI_ACCOUNT_2, env.GEMINI_ACCOUNT_3]
    .map((apiKey, index) => apiKey ? { id: `G${index + 1}`, apiKey } : null)
    .filter((account): account is GeminiAccount => Boolean(account));
}

export async function handleAxAdaptersRoute(
  request: Request,
  env: AxAdaptersEnv,
  dependencies: Dependencies = {},
): Promise<Response | null> {
  const url = new URL(request.url);
  if (!url.pathname.startsWith('/ax/')) return null;
  if (!authorized(request, env)) return json({ error: 'AUTH_REQUIRED' }, 401);

  if (request.method === 'GET' && url.pathname === '/ax/adapters/status') {
    return json({
      gemini: { configuredAccounts: geminiAccounts(env).length },
      drive: { configured: Boolean(env.GOOGLE_DRIVE_CREDENTIAL) },
    });
  }

  if (request.method === 'POST' && url.pathname === '/ax/gemini/generate') {
    let body: { prompt?: unknown };
    try {
      body = await request.json() as { prompt?: unknown };
    } catch {
      return json({ error: 'INVALID_JSON' }, 400);
    }
    const prompt = typeof body.prompt === 'string' ? body.prompt.trim() : '';
    if (!prompt) return json({ error: 'PROMPT_REQUIRED' }, 400);
    if (prompt.length > 8_000) return json({ error: 'PROMPT_TOO_LARGE' }, 413);

    const router = new GeminiRouter(geminiAccounts(env), dependencies.generateGemini);
    const result = await router.generate(prompt);
    return json(result, result.ok ? 200 : 503);
  }

  if (request.method === 'GET' && url.pathname === '/ax/drive/list') {
    const query = (url.searchParams.get('q') || '').trim();
    if (query.length > 200) return json({ error: 'DRIVE_QUERY_TOO_LARGE' }, 413);

    const adapter = new DriveAdapter(
      env.GOOGLE_DRIVE_CREDENTIAL || '',
      dependencies.driveFetch || fetch,
    );
    const result = await adapter.list(query);
    return json(result, result.ok ? 200 : 503);
  }

  return json({ error: 'NOT_FOUND' }, 404);
}
