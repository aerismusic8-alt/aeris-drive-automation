import runtime from './index';
import { AxXmExecutionQueue, auth as xmAuth, json as xmJson, xmQueueStub } from './xm-bridge';

type GitHubEnv = {
  AX_GITHUB_APP_PRIVATE_KEY?: string;
  AX_GITHUB_CLIENT_ID?: string;
  AX_GITHUB_APP_ID?: string;
  AX_MOBILE_INGRESS_SECRET?: string;
  AX_XM_NODE_SECRET?: string;
  AX_XM_EXECUTION_QUEUE: DurableObjectNamespace;
  [key: string]: unknown;
};

const REPO = 'aerismusic8-alt/aeris-drive-automation';
const API = 'https://api.github.com';
const API_VERSION = '2026-03-10';

function json(body: unknown, status = 200): Response {
  return Response.json(body, { status, headers: { 'Cache-Control': 'no-store', 'Content-Type': 'application/json; charset=utf-8' } });
}
function constantTimeEqual(left: string, right: string): boolean {
  const a = new TextEncoder().encode(left), b = new TextEncoder().encode(right);
  if (a.length !== b.length) return false;
  let diff = 0; for (let i = 0; i < a.length; i += 1) diff |= a[i] ^ b[i]; return diff === 0;
}
function authorized(request: Request, env: GitHubEnv): boolean {
  const expected = env.AX_MOBILE_INGRESS_SECRET || '';
  const received = (request.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '').trim();
  return Boolean(expected && received && received.length <= 512 && constantTimeEqual(received, expected));
}
function base64Url(bytes: Uint8Array): string {
  let binary = ''; for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '');
}
function base64UrlText(text: string): string { return base64Url(new TextEncoder().encode(text)); }
function normalizePemSecret(pem: string): string {
  let normalized = pem.trim();
  if ((normalized.startsWith('"') && normalized.endsWith('"')) || (normalized.startsWith("'") && normalized.endsWith("'"))) {
    try {
      if (normalized.startsWith('"')) normalized = JSON.parse(normalized) as string;
      else normalized = normalized.slice(1, -1);
    } catch { /* keep raw value */ }
  }
  return normalized.replace(/\\r/g, '\r').replace(/\\n/g, '\n').replace(/\r/g, '').trim();
}
function pemToDer(pem: string): { der: Uint8Array; format: 'pkcs1' | 'pkcs8' } {
  const normalized = normalizePemSecret(pem);
  const isPkcs1 = normalized.includes('-----BEGIN RSA PRIVATE KEY-----');
  const isPkcs8 = normalized.includes('-----BEGIN PRIVATE KEY-----');
  if (!isPkcs1 && !isPkcs8) throw new Error('GITHUB_PRIVATE_KEY_PEM_FORMAT_UNSUPPORTED');
  const body = normalized.replace(/-----BEGIN RSA PRIVATE KEY-----/g, '').replace(/-----END RSA PRIVATE KEY-----/g, '').replace(/-----BEGIN PRIVATE KEY-----/g, '').replace(/-----END PRIVATE KEY-----/g, '').replace(/\s+/g, '');
  const binary = atob(body); const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i += 1) bytes[i] = binary.charCodeAt(i);
  return { der: bytes, format: isPkcs1 ? 'pkcs1' : 'pkcs8' };
}
function derLength(length: number): Uint8Array {
  if (length < 128) return new Uint8Array([length]);
  const bytes: number[] = []; let value = length;
  while (value > 0) { bytes.unshift(value & 0xff); value >>>= 8; }
  return new Uint8Array([0x80 | bytes.length, ...bytes]);
}
function concatBytes(...parts: Uint8Array[]): Uint8Array {
  const total = parts.reduce((n, part) => n + part.length, 0); const out = new Uint8Array(total); let offset = 0;
  for (const part of parts) { out.set(part, offset); offset += part.length; } return out;
}
function wrapPkcs1AsPkcs8(pkcs1: Uint8Array): Uint8Array {
  const version = new Uint8Array([0x02, 0x01, 0x00]);
  const algorithm = new Uint8Array([0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01, 0x05, 0x00]);
  const privateKey = concatBytes(new Uint8Array([0x04]), derLength(pkcs1.length), pkcs1);
  const body = concatBytes(version, algorithm, privateKey);
  return concatBytes(new Uint8Array([0x30]), derLength(body.length), body);
}
async function createAppJwt(env: GitHubEnv): Promise<string> {
  const privateKeyPem = env.AX_GITHUB_APP_PRIVATE_KEY || '', clientId = env.AX_GITHUB_CLIENT_ID || '';
  if (!privateKeyPem || !clientId) throw new Error('GITHUB_APP_CREDENTIALS_MISSING');
  const parsed = pemToDer(privateKeyPem); const keyDer = parsed.format === 'pkcs1' ? wrapPkcs1AsPkcs8(parsed.der) : parsed.der;
  const key = await crypto.subtle.importKey('pkcs8', keyDer, { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign']);
  const now = Math.floor(Date.now() / 1000);
  const header = base64UrlText(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const payload = base64UrlText(JSON.stringify({ iat: now - 60, exp: now + 540, iss: clientId }));
  const signingInput = `${header}.${payload}`;
  const signature = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, new TextEncoder().encode(signingInput));
  return `${signingInput}.${base64Url(new Uint8Array(signature))}`;
}
async function githubRequest(path: string, init: RequestInit = {}): Promise<Response> {
  return fetch(`${API}${path}`, { ...init, headers: { Accept: 'application/vnd.github+json', 'X-GitHub-Api-Version': API_VERSION, 'User-Agent': 'AX-Control-Runtime', ...(init.headers || {}) } });
}
async function getInstallationId(jwt: string): Promise<number> {
  const response = await githubRequest(`/repos/${REPO}/installation`, { headers: { Authorization: `Bearer ${jwt}` } });
  if (!response.ok) throw new Error(`GITHUB_INSTALLATION_HTTP_${response.status}`);
  const body = await response.json() as { id?: number }; if (!body.id) throw new Error('GITHUB_INSTALLATION_ID_MISSING'); return body.id;
}
async function createInstallationToken(jwt: string, installationId: number): Promise<{ token: string; expires_at?: string }> {
  const response = await githubRequest(`/app/installations/${installationId}/access_tokens`, { method: 'POST', headers: { Authorization: `Bearer ${jwt}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ repositories: ['aeris-drive-automation'], permissions: { contents: 'read', actions: 'read', checks: 'read', metadata: 'read' } }) });
  if (!response.ok) throw new Error(`GITHUB_TOKEN_HTTP_${response.status}`);
  const body = await response.json() as { token?: string; expires_at?: string }; if (!body.token) throw new Error('GITHUB_INSTALLATION_TOKEN_MISSING'); return { token: body.token, expires_at: body.expires_at };
}
async function verifyRepository(token: string): Promise<{ name: string; full_name: string; private: boolean }> {
  const response = await githubRequest(`/repos/${REPO}`, { headers: { Authorization: `Bearer ${token}` } });
  if (!response.ok) throw new Error(`GITHUB_REPOSITORY_HTTP_${response.status}`);
  const body = await response.json() as { name?: string; full_name?: string; private?: boolean }; if (body.full_name !== REPO) throw new Error('GITHUB_REPOSITORY_MISMATCH'); return { name: body.name || '', full_name: body.full_name || '', private: Boolean(body.private) };
}
async function verifyGitHubApp(env: GitHubEnv): Promise<Response> {
  const configured = Boolean(env.AX_GITHUB_APP_PRIVATE_KEY && env.AX_GITHUB_CLIENT_ID && env.AX_GITHUB_APP_ID);
  if (!configured) return json({ verified: false, configured: false, error: 'GITHUB_APP_CREDENTIALS_MISSING' }, 503);
  try {
    const jwt = await createAppJwt(env); const installationId = await getInstallationId(jwt); const installationToken = await createInstallationToken(jwt, installationId); const repository = await verifyRepository(installationToken.token);
    return json({ verified: true, configured: true, authenticated: true, installationResolved: true, repositoryAccess: true, repository, installationIdPresent: Boolean(installationId), tokenExpiresAt: installationToken.expires_at || null, permissionsRequested: { contents: 'read', actions: 'read', checks: 'read', metadata: 'read' } });
  } catch (error) {
    const message = error instanceof Error ? error.message : 'GITHUB_APP_VERIFICATION_FAILED';
    return json({ verified: false, configured: true, authenticated: false, repositoryAccess: false, status: 'NOT_VERIFIED', error: message }, 502);
  }
}
async function publicStatus(env: GitHubEnv): Promise<Response> {
  const response = await verifyGitHubApp(env); let body: Record<string, unknown> = {};
  try { body = await response.clone().json() as Record<string, unknown>; } catch { /* sanitized fallback */ }
  return json({ verified: body.verified === true, configured: body.configured === true, authenticated: body.authenticated === true, repositoryAccess: body.repositoryAccess === true, status: body.verified === true ? 'VERIFIED' : 'NOT_VERIFIED', error: typeof body.error === 'string' ? body.error : undefined }, body.verified === true ? 200 : 503);
}

async function xmRoute(request: Request, env: GitHubEnv): Promise<Response | null> {
  const url = new URL(request.url);
  if (!url.pathname.startsWith('/xm/')) return null;
  const nodeAuthorized = xmAuth(request, env.AX_XM_NODE_SECRET);
  const controlAuthorized = authorized(request, env);
  const stub = xmQueueStub(env);

  if (request.method === 'GET' && url.pathname === '/xm/status') {
    return xmJson({ ok: true, service: 'AX XM EXECUTION BRIDGE', mode: 'READ_ONLY_PENDING_HANDSHAKE', live_execution_enabled: false, kill_switch: true, account_scope: 'XM_MICRO_K_DESIGNATED_ACCOUNT', node_auth_configured: Boolean(env.AX_XM_NODE_SECRET) });
  }
  if (request.method === 'POST' && url.pathname === '/xm/node/pull') {
    if (!nodeAuthorized) return xmJson({ error: 'AUTH_REQUIRED' }, 401);
    return stub.fetch('https://xm.local/pull', { method: 'POST', headers: { 'content-type': 'application/json' }, body: '{}' });
  }
  if (request.method === 'POST' && url.pathname === '/xm/node/result') {
    if (!nodeAuthorized) return xmJson({ error: 'AUTH_REQUIRED' }, 401);
    return stub.fetch('https://xm.local/result', { method: 'POST', headers: { 'content-type': 'application/json' }, body: await request.text() });
  }
  if (request.method === 'GET' && url.pathname.startsWith('/xm/node/result/')) {
    if (!nodeAuthorized) return xmJson({ error: 'AUTH_REQUIRED' }, 401);
    return stub.fetch(`https://xm.local/result/${encodeURIComponent(url.pathname.slice('/xm/node/result/'.length))}`, { method: 'GET' });
  }
  if (request.method === 'POST' && url.pathname === '/xm/control/enqueue') {
    if (!controlAuthorized) return xmJson({ error: 'AUTH_REQUIRED' }, 401);
    const body = await request.text();
    return stub.fetch('https://xm.local/enqueue', { method: 'POST', headers: { 'content-type': 'application/json' }, body });
  }
  return xmJson({ error: 'NOT_FOUND' }, 404);
}

export default {
  async fetch(request: Request, env: GitHubEnv, ctx: ExecutionContext): Promise<Response> {
    const xm = await xmRoute(request, env);
    if (xm) return xm;
    const url = new URL(request.url);
    if (request.method === 'GET' && url.pathname === '/github/status') return publicStatus(env);
    if (request.method === 'GET' && url.pathname === '/github/verify') {
      if (!authorized(request, env)) return json({ error: 'AUTH_REQUIRED' }, 401);
      return verifyGitHubApp(env);
    }
    return runtime.fetch(request, env as never, ctx);
  },
  queue: runtime.queue,
};

export { AxGatewayInbox } from './index';
export { AxXmExecutionQueue } from './xm-bridge';