import { DriveAdapter } from './drive-adapter';
import { GeminiRouter, type GeminiAccount } from './gemini-router';
import { AxMissionLedger, commandFingerprint, type MissionCommand, type MissionRecord } from './ax-mission-ledger';
import { axDirectConsolePage } from './ax-direct-console';
import { directSessionTokenAccepted } from './direct-auth';

export type AxAdaptersEnv = {
  AX_MOBILE_INGRESS_SECRET?: string;
  AX_EXECUTION_QUEUE?: Queue<unknown>;
  AX_MISSION_LEDGER?: DurableObjectNamespace;
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

const DIRECT_CONTENT_TYPES = new Set(['text', 'file', 'image', 'event', 'command']);

function json(body: unknown, status = 200): Response {
  return Response.json(body, {
    status,
    headers: {
      'Cache-Control': 'no-store',
      'Content-Type': 'application/json; charset=utf-8',
    },
  });
}

function bearer(request: Request): string {
  return (request.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '').trim();
}

function constantTimeEqual(left: string, right: string): boolean {
  const a = new TextEncoder().encode(left);
  const b = new TextEncoder().encode(right);
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i += 1) diff |= a[i] ^ b[i];
  return diff === 0;
}

async function authorized(request: Request, env: AxAdaptersEnv): Promise<boolean> {
  const received = bearer(request);
  const secret = env.AX_MOBILE_INGRESS_SECRET || '';
  if (secret && received && received.length <= 512 && constantTimeEqual(received, secret)) return true;
  return Boolean(secret && received && await directSessionTokenAccepted.verify(received, secret));
}

function geminiAccounts(env: AxAdaptersEnv): GeminiAccount[] {
  return [env.GEMINI_ACCOUNT_1, env.GEMINI_ACCOUNT_2, env.GEMINI_ACCOUNT_3]
    .map((apiKey, index) => apiKey ? { id: `G${index + 1}`, apiKey } : null)
    .filter((account): account is GeminiAccount => Boolean(account));
}

function directLedgerStub(env: AxAdaptersEnv, missionId: string): DurableObjectStub | null {
  if (!env.AX_MISSION_LEDGER) return null;
  return env.AX_MISSION_LEDGER.get(env.AX_MISSION_LEDGER.idFromName(`mission:${missionId}`));
}

async function directAttachment(request: Request, env: AxAdaptersEnv): Promise<Response> {
  if (!await authorized(request, env)) return json({ error: 'AUTH_REQUIRED' }, 401);
  if (!env.AX_MISSION_LEDGER) return json({ error: 'DIRECT_AX_LEDGER_UNAVAILABLE' }, 503);

  const missionId = (request.headers.get('X-AX-Mission-Id') || '').trim();
  const attachmentId = (request.headers.get('X-AX-Attachment-Id') || '').trim();
  const name = (request.headers.get('X-AX-Attachment-Name') || '').trim();
  const mediaType = (request.headers.get('Content-Type') || 'application/octet-stream').trim().split(';', 1)[0] || 'application/octet-stream';
  if (!missionId || !attachmentId || !name) return json({ error: 'ATTACHMENT_SCHEMA_INVALID' }, 422);
  if (missionId.length > 128 || attachmentId.length > 128 || name.length > 512) return json({ error: 'ATTACHMENT_METADATA_TOO_LARGE' }, 413);

  const stub = directLedgerStub(env, missionId);
  if (!stub) return json({ error: 'DIRECT_AX_LEDGER_UNAVAILABLE' }, 503);
  const target = new URL('https://mission.local/attachment');
  target.searchParams.set('mission_id', missionId);
  target.searchParams.set('attachment_id', attachmentId);
  target.searchParams.set('name', name);
  target.searchParams.set('media_type', mediaType);

  const response = await stub.fetch(target.toString(), {
    method: 'POST',
    headers: { 'content-type': mediaType },
    body: request.body,
  });
  const body = await response.json().catch(() => ({ error: 'ATTACHMENT_RESPONSE_INVALID' }));
  return json(body, response.status);
}

async function directInput(request: Request, env: AxAdaptersEnv): Promise<Response> {
  if (!await authorized(request, env)) return json({ error: 'AUTH_REQUIRED' }, 401);
  if (!env.AX_EXECUTION_QUEUE || !env.AX_MISSION_LEDGER) return json({ error: 'DIRECT_AX_STORAGE_NOT_CONFIGURED' }, 503);

  const raw = await request.text();
  if (new TextEncoder().encode(raw).byteLength > 16_000) return json({ error: 'PAYLOAD_TOO_LARGE', maxBytes: 16_000 }, 413);
  let body: Record<string, unknown> | null = null;
  try { body = JSON.parse(raw) as Record<string, unknown>; } catch { return json({ error: 'INVALID_JSON' }, 400); }

  const missionId = String(body.mission_id ?? body.missionId ?? '').trim() || `MISSION-${crypto.randomUUID()}`;
  const requestId = String(body.request_id ?? body.requestId ?? '').trim() || `REQ-${crypto.randomUUID()}`;
  const taskId = String(body.task_id ?? body.taskId ?? '').trim() || `TASK-${missionId.replace(/^MISSION-/, '').slice(0, 32)}`;
  const contentType = String(body.content_type ?? body.contentType ?? 'text');
  const content = body.content === null || body.content === undefined ? null : String(body.content);
  const attachments = Array.isArray(body.attachments) ? body.attachments as Array<Record<string, unknown>> : [];
  if (!DIRECT_CONTENT_TYPES.has(contentType)) return json({ error: 'INVALID_CONTENT_TYPE' }, 422);
  if (content === null && attachments.length === 0) return json({ error: 'CONTENT_REQUIRED' }, 422);
  if (attachments.some(item => !item || typeof item !== 'object' || 'bytes' in item || 'data' in item)) return json({ error: 'RAW_BINARY_NOT_ALLOWED' }, 422);

  const commandBase: Omit<MissionCommand, 'fingerprint' | 'created_at'> = {
    mission_id: missionId,
    task_id: taskId,
    request_id: requestId,
    content_type: contentType as MissionCommand['content_type'],
    content,
    attachments,
  };
  const fingerprint = await commandFingerprint(commandBase);
  const now = new Date().toISOString();
  const mission: MissionRecord = { command: { ...commandBase, fingerprint, created_at: now }, status: 'READY', attempts: 0, updated_at: now };
  const stub = directLedgerStub(env, missionId);
  if (!stub) return json({ error: 'DIRECT_AX_LEDGER_UNAVAILABLE' }, 503);

  const ledgerResponse = await stub.fetch('https://mission.local/put', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(mission),
  });
  const ledgerBody = await ledgerResponse.json().catch(() => ({ error: 'LEDGER_RESPONSE_INVALID' }));
  if (!ledgerResponse.ok && ledgerResponse.status !== 409) return json(ledgerBody, ledgerResponse.status);
  if (ledgerResponse.status === 409) return json({ accepted: false, queued: false, missionId, taskId, requestId, error: 'TASK_ID_CONFLICT', ledger: ledgerBody }, 409);

  const kind = (ledgerBody as { kind?: string }).kind;
  if (kind === 'CREATED') {
    await env.AX_EXECUTION_QUEUE.send({
      id: requestId,
      taskId,
      domain: 'AERIS',
      priority: Number(body.priority ?? 100),
      action: content || '',
      createdAt: now,
      source: 'AX_DIRECT_CHANNEL',
    });
    return json({ accepted: true, queued: true, duplicate: false, missionId, taskId, requestId, fingerprint, channel: 'AX_DIRECT', transport: 'AX_EXECUTION_QUEUE', ledger: 'AX_MISSION_LEDGER' }, 201);
  }

  return json({ accepted: true, queued: false, duplicate: true, missionId, taskId, requestId, fingerprint, channel: 'AX_DIRECT', transport: 'AX_EXECUTION_QUEUE', ledger: 'AX_MISSION_LEDGER' }, 200);
}

async function directMission(request: Request, env: AxAdaptersEnv, missionId: string): Promise<Response> {
  if (!await authorized(request, env)) return json({ error: 'AUTH_REQUIRED' }, 401);
  const stub = directLedgerStub(env, missionId);
  if (!stub) return json({ error: 'DIRECT_AX_LEDGER_UNAVAILABLE' }, 503);
  return stub.fetch('https://mission.local/get', { method: 'GET' });
}

export async function handleAxAdaptersRoute(
  request: Request,
  env: AxAdaptersEnv,
  dependencies: Dependencies = {},
): Promise<Response | null> {
  const url = new URL(request.url);
  if ((url.pathname === '/ax/direct' || url.pathname === '/chat') && request.method === 'GET') return axDirectConsolePage();
  if (url.pathname === '/ax/direct/attachment' && request.method === 'POST') return directAttachment(request, env);
  if (url.pathname === '/ax/direct/input' && request.method === 'POST') return directInput(request, env);
  if (url.pathname.startsWith('/ax/direct/mission/') && request.method === 'GET') {
    const missionId = decodeURIComponent(url.pathname.slice('/ax/direct/mission/'.length)).trim();
    if (!missionId) return json({ error: 'MISSION_ID_REQUIRED' }, 422);
    return directMission(request, env, missionId);
  }
  if (!url.pathname.startsWith('/ax/')) return null;
  if (!await authorized(request, env)) return json({ error: 'AUTH_REQUIRED' }, 401);

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
