import runtime from './index';

type GitHubEnv = {
  AX_GITHUB_APP_PRIVATE_KEY?: string;
  AX_GITHUB_CLIENT_ID?: string;
  AX_GITHUB_APP_ID?: string;
  AX_MOBILE_INGRESS_SECRET?: string;
  [key: string]: unknown;
};

const REPO = 'aerismusic8-alt/aeris-drive-automation';
const API = 'https://api.github.com';
const API_VERSION = '2026-03-10';

function json(body: unknown, status = 200): Response {
  return Response.json(body, {
    status,
    headers: { 'Cache-Control': 'no-store', 'Content-Type': 'application/json; charset=utf-8' },
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

function authorized(request: Request, env: GitHubEnv): boolean {
  const expected = env.AX_MOBILE_INGRESS_SECRET || '';
  const received = (request.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '').trim();
  return Boolean(expected && received && received.length <= 512 && constantTimeEqual(received, expected));
}

function base64Url(bytes: Uint8Array): string {
  let binary = '';
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '');
}

function base64UrlText(text: string): string {
  return base64Url(new TextEncoder().encode(text));
}

function pemToDer(pem: string): Uint8Array {
  const body = pem
    .replace(/-----BEGIN PRIVATE KEY-----/g, '')
    .replace(/-----END PRIVATE KEY-----/g, '')
    .replace(/\s+/g, '');
  const binary = atob(body);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i += 1) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

async function createAppJwt(env: GitHubEnv): Promise<string> {
  const privateKeyPem = env.AX_GITHUB_APP_PRIVATE_KEY || '';
  const appId = env.AX_GITHUB_APP_ID || '';
  if (!privateKeyPem || !appId) throw new Error('GITHUB_APP_CREDENTIALS_MISSING');

  const key = await crypto.subtle.importKey(
    'pkcs8',
    pemToDer(privateKeyPem),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );

  const now = Math.floor(Date.now() / 1000);
  const header = base64UrlText(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const payload = base64UrlText(JSON.stringify({ iat: now - 60, exp: now + 540, iss: appId }));
  const signingInput = `${header}.${payload}`;
  const signature = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    key,
    new TextEncoder().encode(signingInput),
  );
  return `${signingInput}.${base64Url(new Uint8Array(signature))}`;
}

async function githubRequest(path: string, init: RequestInit = {}): Promise<Response> {
  return fetch(`${API}${path}`, {
    ...init,
    headers: {
      Accept: 'application/vnd.github+json',
      'X-GitHub-Api-Version': API_VERSION,
      'User-Agent': 'AX-Control-Runtime',
      ...(init.headers || {}),
    },
  });
}

async function getInstallationId(jwt: string): Promise<number> {
  const response = await githubRequest(`/repos/${REPO}/installation`, {
    headers: { Authorization: `Bearer ${jwt}` },
  });
  if (!response.ok) throw new Error(`GITHUB_INSTALLATION_HTTP_${response.status}`);
  const body = await response.json() as { id?: number };
  if (!body.id) throw new Error('GITHUB_INSTALLATION_ID_MISSING');
  return body.id;
}

async function createInstallationToken(jwt: string, installationId: number): Promise<{ token: string; expires_at?: string }> {
  const response = await githubRequest(`/app/installations/${installationId}/access_tokens`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${jwt}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      repositories: ['aeris-drive-automation'],
      permissions: { contents: 'read', actions: 'read', checks: 'read', metadata: 'read' },
    }),
  });
  if (!response.ok) throw new Error(`GITHUB_TOKEN_HTTP_${response.status}`);
  const body = await response.json() as { token?: string; expires_at?: string };
  if (!body.token) throw new Error('GITHUB_INSTALLATION_TOKEN_MISSING');
  return { token: body.token, expires_at: body.expires_at };
}

async function verifyRepository(token: string): Promise<{ name: string; full_name: string; private: boolean }> {
  const response = await githubRequest(`/repos/${REPO}`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  if (!response.ok) throw new Error(`GITHUB_REPOSITORY_HTTP_${response.status}`);
  const body = await response.json() as { name?: string; full_name?: string; private?: boolean };
  if (body.full_name !== REPO) throw new Error('GITHUB_REPOSITORY_MISMATCH');
  return { name: body.name || '', full_name: body.full_name || '', private: Boolean(body.private) };
}

async function verifyGitHubApp(env: GitHubEnv): Promise<Response> {
  const configured = Boolean(env.AX_GITHUB_APP_PRIVATE_KEY && env.AX_GITHUB_CLIENT_ID && env.AX_GITHUB_APP_ID);
  if (!configured) return json({ verified: false, configured: false, error: 'GITHUB_APP_CREDENTIALS_MISSING' }, 503);

  try {
    const jwt = await createAppJwt(env);
    const installationId = await getInstallationId(jwt);
    const installationToken = await createInstallationToken(jwt, installationId);
    const repository = await verifyRepository(installationToken.token);

    return json({
      verified: true,
      configured: true,
      authenticated: true,
      installationResolved: true,
      repositoryAccess: true,
      repository,
      installationIdPresent: Boolean(installationId),
      tokenExpiresAt: installationToken.expires_at || null,
      permissionsRequested: { contents: 'read', actions: 'read', checks: 'read', metadata: 'read' },
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : 'GITHUB_APP_VERIFICATION_FAILED';
    return json({ verified: false, configured: true, authenticated: false, error: message }, 502);
  }
}

async function publicStatus(env: GitHubEnv): Promise<Response> {
  const response = await verifyGitHubApp(env);
  let body: { verified?: boolean; configured?: boolean; authenticated?: boolean; repositoryAccess?: boolean } = {};
  try { body = await response.clone().json() as typeof body; } catch { /* preserve sanitized fallback */ }
  return json({
    verified: body.verified === true,
    configured: body.configured === true,
    authenticated: body.authenticated === true,
    repositoryAccess: body.repositoryAccess === true,
    status: body.verified === true ? 'VERIFIED' : 'NOT_VERIFIED',
  }, body.verified === true ? 200 : 503);
}

export default {
  async fetch(request: Request, env: GitHubEnv, ctx: ExecutionContext): Promise<Response> {
    const url = new URL(request.url);
    if (request.method === 'GET' && url.pathname === '/github/status') {
      return publicStatus(env);
    }
    if (request.method === 'GET' && url.pathname === '/github/verify') {
      if (!authorized(request, env)) return json({ error: 'AUTH_REQUIRED' }, 401);
      return verifyGitHubApp(env);
    }
    return runtime.fetch(request, env as never, ctx);
  },
  queue: runtime.queue,
};

export { AxGatewayInbox } from './index';
