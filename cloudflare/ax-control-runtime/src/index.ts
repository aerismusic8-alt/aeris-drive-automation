type AxEvent = {
  id: string;
  taskId: string;
  domain: string;
  priority: number;
  action: string;
  createdAt: string;
  source: string;
};

type AxGatewayInput = {
  request_id: string;
  task_id: string;
  status: 'RECEIVED';
  source_channel: 'MOBILE' | 'PC';
  content_type: 'text' | 'file' | 'image' | 'event' | 'command';
  content: string | null;
  evidence_status: 'PENDING';
  verification_status: 'PENDING';
  attachments: Array<Record<string, unknown>>;
  source_of_truth: 'A_MASTER_BRAIN';
  transport_store: 'AX_GATEWAY_INBOX';
  received_at: string;
};

type AxExecutionResult = {
  accepted?: boolean;
  executed?: boolean;
  verified?: boolean;
  taskId?: string;
  evidence?: Record<string, unknown> | null;
  writeBackVerified?: boolean;
  status?: string;
  [key: string]: unknown;
};

type Env = {
  AX_EXECUTION_QUEUE: Queue<AxEvent>;
  AX_GATEWAY_INBOX: DurableObjectNamespace;
  AX_MOBILE_INGRESS_SECRET?: string;
  AX_PC_PULL_SECRET?: string;
};

const SERVICE = 'AX CONTROL RUNTIME';
const MODE = 'FREE_ONLY';
const QUEUE_NAME = 'ax-execution-events';
const INBOX_NAME = 'AX_GATEWAY_INBOX';
const REPO = 'aerismusic8-alt/aeris-drive-automation';
const MAX_PAYLOAD_BYTES = 16_000;
const LEASE_MS = 60_000;
const ALLOWED_CONTENT_TYPES = new Set(['text', 'file', 'image', 'event', 'command']);

function json(body: unknown, status = 200): Response {
  return Response.json(body, { status, headers: { 'Cache-Control': 'no-store', 'Content-Type': 'application/json; charset=utf-8' } });
}

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
  return Boolean(received && expected && received.length <= 512 && constantTimeEqual(received, expected));
}

function readJsonObject(text: string): Record<string, unknown> | null {
  try {
    const parsed = JSON.parse(text);
    return parsed && typeof parsed === 'object' && !Array.isArray(parsed) ? parsed as Record<string, unknown> : null;
  } catch {
    return null;
  }
}

function makeRequestId(): string { return crypto.randomUUID(); }
function makeTaskId(): string { return `TASK-${crypto.randomUUID().slice(0, 8)}`; }

function hasRawBinary(attachments: unknown): boolean {
  if (!Array.isArray(attachments)) return true;
  return attachments.some((item) => !item || typeof item !== 'object' || 'bytes' in item || 'data' in item);
}

export class AxGatewayInbox {
  constructor(private readonly state: DurableObjectState) {}

  async fetch(request: Request): Promise<Response> {
    const path = new URL(request.url).pathname;
    const payload = request.method === 'POST' ? await request.json().catch(() => null) : null;
    const current = (await this.state.storage.get<AxGatewayInput[]>('items')) || [];

    if (path === '/put' && payload && typeof payload === 'object') {
      const record = (payload as { record?: AxGatewayInput }).record;
      if (!record?.request_id) return json({ error: 'INPUT_SCHEMA_INVALID' }, 422);
      const existing = current.find((item) => item.request_id === record.request_id);
      if (existing) {
        const same = JSON.stringify(existing) === JSON.stringify(record);
        return json(same ? { ok: true, requestId: record.request_id } : { error: 'REQUEST_ID_CONFLICT' }, same ? 200 : 409);
      }
      current.push(record);
      await this.state.storage.put('items', current);
      return json({ ok: true, requestId: record.request_id }, 201);
    }

    if (path === '/pull' && request.method === 'POST') {
      const now = Date.now();
      const index = current.findIndex((item) => {
        const meta = item as AxGatewayInput & { _status?: string; _leaseUntil?: number };
        return meta._status !== 'ACKED' && (!meta._leaseUntil || meta._leaseUntil <= now);
      });
      if (index < 0) return json({ ok: true, item: null });
      const item = current[index] as AxGatewayInput & { _status?: string; _leaseUntil?: number };
      item._status = 'CLAIMED';
      item._leaseUntil = now + LEASE_MS;
      current[index] = item;
      await this.state.storage.put('items', current);
      return json({ ok: true, item });
    }

    if (path === '/ack' && payload && typeof payload === 'object') {
      const requestId = String((payload as { request_id?: unknown }).request_id || '');
      const index = current.findIndex((item) => item.request_id === requestId);
      if (index < 0) return json({ error: 'INPUT_UNAVAILABLE', requestId }, 404);
      const item = current[index] as AxGatewayInput & { _status?: string; _leaseUntil?: number };
      item._status = 'ACKED';
      delete item._leaseUntil;
      current[index] = item;
      await this.state.storage.put('items', current);
      return json({ ok: true, requestId });
    }

    return json({ error: 'NOT_FOUND' }, 404);
  }
}

async function gatewayInboxCall(env: Env, operation: 'put' | 'pull' | 'ack', payload?: unknown): Promise<Response> {
  const stub = env.AX_GATEWAY_INBOX.get(env.AX_GATEWAY_INBOX.idFromName('AERIS-K-GATEWAY'));
  return stub.fetch(`https://gateway.local/${operation}`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(payload || {}) });
}

async function verifyGitHubToken(token: string): Promise<boolean> {
  try {
    const response = await fetch(`https://api.github.com/repos/${REPO}`, { method: 'GET', headers: { Accept: 'application/vnd.github+json', Authorization: `Bearer ${token}`, 'X-GitHub-Api-Version': '2026-03-10', 'User-Agent': 'AX-AERIS-Control-Runtime' } });
    return response.ok;
  } catch { return false; }
}

function healthResponse(env: Env): Response {
  return json({
    service: SERVICE, status: 'ONLINE', version: 'control-runtime-1.3.0', gate: 'CONTROLLED', mode: MODE,
    liveFinancialExecution: false, financialTransactions: false, repositoryMutation: false, queue: QUEUE_NAME,
    gatewayInbox: INBOX_NAME, mobileIngress: true, pcPull: true,
    mobileIngressAuthConfigured: Boolean(env.AX_MOBILE_INGRESS_SECRET), pcPullAuthConfigured: Boolean(env.AX_PC_PULL_SECRET),
    repository: REPO,
    cloudTimeAuthority: { enabled: true, endpoint: '/time', source: 'Cloudflare Worker runtime', storageTimezone: 'UTC', displayTimezone: 'Asia/Bangkok' },
    endpoints: ['GET /', 'GET /health', 'GET /time', 'GET /mobile', 'GET /mobile/config', 'POST /mobile/input', 'POST /pc/pull', 'POST /pc/ack', 'POST /enqueue'],
  });
}

function mobilePage(): Response {
  const html = `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>AX Mobile Gateway</title><style>body{font-family:system-ui,sans-serif;max-width:680px;margin:24px auto;padding:0 16px}textarea,input,button{width:100%;box-sizing:border-box;margin:8px 0;padding:12px;font-size:16px}button{cursor:pointer}.ok{padding:10px;background:#eef7ee}.err{padding:10px;background:#fdecec}small{color:#666}</style></head><body><h1>AX Mobile Gateway</h1><small>Transport only · A Master Brain remains the source of truth · FREE_ONLY</small><input id="token" type="password" placeholder="Mobile gateway token" autocomplete="off"><input id="task" placeholder="Task ID (optional)"><textarea id="content" rows="8" placeholder="Send work to A Master Brain"></textarea><button id="send">Send</button><div id="result"></div><script>const $=id=>document.getElementById(id);$('token').value=localStorage.getItem('ax_mobile_token')||'';$('send').onclick=async()=>{const token=$('token').value.trim();localStorage.setItem('ax_mobile_token',token);const body={task_id:$('task').value.trim()||undefined,source_channel:'MOBILE',content_type:'text',content:$('content').value};try{const r=await fetch('/mobile/input',{method:'POST',headers:{Authorization:'Bearer '+token,'Content-Type':'application/json'},body:JSON.stringify(body)});const j=await r.json();$('result').className=r.ok?'ok':'err';$('result').textContent=JSON.stringify(j,null,2);}catch(e){$('result').className='err';$('result').textContent=String(e);}}</script></body></html>`;
  return new Response(html, { headers: { 'content-type': 'text/html; charset=utf-8', 'cache-control': 'no-store' } });
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    if (request.method === 'GET' && url.pathname === '/') return healthResponse(env);
    if (request.method === 'GET' && url.pathname === '/health') return healthResponse(env);
    if (request.method === 'GET' && url.pathname === '/time') { const now = new Date(); return json({ source: 'AX_CLOUD_TIME_AUTHORITY', authority: 'Cloudflare Worker runtime', requestId: crypto.randomUUID(), timestampUtc: now.toISOString(), epochMs: now.getTime(), timezoneDisplay: 'Asia/Bangkok', timestampThailand: now.toLocaleString('sv-SE', { timeZone: 'Asia/Bangkok' }).replace(' ', 'T') + '+07:00', method: request.method }); }
    if (request.method === 'GET' && url.pathname === '/mobile') return mobilePage();
    if (request.method === 'GET' && url.pathname === '/mobile/config') return json({ service: SERVICE, mobileIngress: true, pcPull: true, executionMode: MODE, liveFinancialExecution: false, transportStore: INBOX_NAME, endpoint: '/mobile/input', pcPullEndpoint: '/pc/pull', pcAckEndpoint: '/pc/ack' });
    if (request.method === 'POST' && url.pathname === '/mobile/input') {
      if (!secretAccepted(bearerSecret(request), env.AX_MOBILE_INGRESS_SECRET)) return json({ error: 'AUTH_REQUIRED' }, 401);
      const raw = await request.text();
      if (new TextEncoder().encode(raw).byteLength > MAX_PAYLOAD_BYTES) return json({ error: 'PAYLOAD_TOO_LARGE', maxBytes: MAX_PAYLOAD_BYTES }, 413);
      const body = readJsonObject(raw);
      if (!body) return json({ error: 'INVALID_JSON' }, 400);
      if (String(body.sourceChannel ?? body.source_channel ?? 'MOBILE') !== 'MOBILE') return json({ error: 'SOURCE_CHANNEL_MUST_BE_MOBILE' }, 422);
      const contentType = String(body.contentType ?? body.content_type ?? 'text');
      if (!ALLOWED_CONTENT_TYPES.has(contentType)) return json({ error: 'INVALID_CONTENT_TYPE' }, 422);
      const content = body.content === undefined || body.content === null ? null : String(body.content);
      if (content !== null && new TextEncoder().encode(content).byteLength > MAX_PAYLOAD_BYTES) return json({ error: 'REQUEST_TOO_LARGE' }, 413);
      const attachments = body.attachments ?? [];
      if (hasRawBinary(attachments)) return json({ error: 'RAW_BINARY_NOT_ALLOWED' }, 422);
      const record: AxGatewayInput = { request_id: String(body.requestId ?? body.request_id ?? makeRequestId()), task_id: String(body.taskId ?? body.task_id ?? makeTaskId()), status: 'RECEIVED', source_channel: 'MOBILE', content_type: contentType as AxGatewayInput['content_type'], content, evidence_status: 'PENDING', verification_status: 'PENDING', attachments: attachments as Array<Record<string, unknown>>, source_of_truth: 'A_MASTER_BRAIN', transport_store: INBOX_NAME, received_at: new Date().toISOString() };
      const inboxResponse = await gatewayInboxCall(env, 'put', { record });
      const inboxBody = await inboxResponse.json();
      if (!inboxResponse.ok) return json(inboxBody, inboxResponse.status);
      return json({ accepted: true, queued: true, requestId: record.request_id, taskId: record.task_id, sourceChannel: record.source_channel, transportStore: INBOX_NAME, status: record.status, evidenceStatus: record.evidence_status, executionStatus: 'NOT_EXECUTED', liveFinancialExecution: false }, 201);
    }
    if (request.method === 'POST' && url.pathname === '/pc/pull') {
      if (!secretAccepted(bearerSecret(request), env.AX_PC_PULL_SECRET)) return json({ error: 'AUTH_REQUIRED' }, 401);
      const inboxResponse = await gatewayInboxCall(env, 'pull');
      return json(await inboxResponse.json(), inboxResponse.status);
    }
    if (request.method === 'POST' && url.pathname === '/pc/ack') {
      if (!secretAccepted(bearerSecret(request), env.AX_PC_PULL_SECRET)) return json({ error: 'AUTH_REQUIRED' }, 401);
      const body = await request.json().catch(() => null) as { request_id?: string; requestId?: string } | null;
      const requestId = String(body?.request_id ?? body?.requestId ?? '');
      if (!requestId) return json({ error: 'REQUEST_ID_REQUIRED' }, 422);
      const inboxResponse = await gatewayInboxCall(env, 'ack', { request_id: requestId });
      return json(await inboxResponse.json(), inboxResponse.status);
    }
    if (request.method === 'POST' && url.pathname === '/enqueue') {
      const token = bearerSecret(request);
      if (!token) return json({ error: 'AUTH_REQUIRED' }, 401);
      const repoHeader = request.headers.get('X-AERIS-REPOSITORY') || '';
      if (repoHeader !== REPO) return json({ error: 'REPOSITORY_NOT_ALLOWED', expected: REPO }, 403);
      if (!(await verifyGitHubToken(token))) return json({ error: 'GITHUB_TOKEN_REJECTED' }, 403);
      let event: AxEvent; try { event = JSON.parse(await request.text()) as AxEvent; } catch { return json({ error: 'INVALID_JSON' }, 400); }
      if (!event || typeof event !== 'object' || !event.id || !event.taskId || !event.domain || !event.action) return json({ error: 'EVENT_SCHEMA_INVALID', required: ['id', 'taskId', 'domain', 'action'] }, 422);
      const normalizedEvent: AxEvent = { id: String(event.id), taskId: String(event.taskId), domain: String(event.domain), priority: Number(event.priority || 0), action: String(event.action), createdAt: event.createdAt || new Date().toISOString(), source: event.source || 'AX_CONTROL_RUNTIME' };
      await env.AX_EXECUTION_QUEUE.send(normalizedEvent);
      return json({ accepted: true, queued: true, eventId: normalizedEvent.id, taskId: normalizedEvent.taskId, queue: QUEUE_NAME, executionGate: 'CONTROLLED', liveFinancialExecution: false });
    }
    return json({ error: 'NOT_FOUND', service: SERVICE, status: 'ONLINE' }, 404);
  },
  async queue(batch: MessageBatch<AxEvent>): Promise<void> {
    for (const message of batch.messages) {
      const event = message.body;
      console.log(JSON.stringify({ event: 'AX_EXECUTION_EVENT_RECEIVED', queue: batch.queue, messageId: message.id, body: event, receivedAt: new Date().toISOString() }));
      if (event.domain !== 'AERIS') { console.log(JSON.stringify({ event: 'AX_EXECUTION_EVENT_DEFERRED', reason: 'DOMAIN_EXECUTOR_NOT_IMPLEMENTED', taskId: event.taskId, domain: event.domain })); message.ack(); continue; }
      const response = await fetch('https://aeris-execution-runtime.aerismusic8.workers.dev/execute', { method: 'POST', headers: { 'Content-Type': 'application/json', Accept: 'application/json', 'User-Agent': 'AX-Control-Runtime/1.3.0' }, body: JSON.stringify({ jobId: event.id, command: event.action }) });
      const rawResponse = await response.text(); let result: AxExecutionResult | null = null; try { result = rawResponse ? JSON.parse(rawResponse) as AxExecutionResult : null; } catch { result = null; }
      const responseTaskMatches = result?.taskId === event.taskId;
      const businessEvidenceValid = !!result?.evidence && String(result.evidence.taskId || '') === event.taskId;
      if (!response.ok || result?.accepted !== true || result?.verified !== true || result?.executed !== true || !responseTaskMatches || !businessEvidenceValid || result?.writeBackVerified !== true) throw new Error(`AERIS_EXECUTION_NOT_VERIFIED:${response.status}`);
      console.log(JSON.stringify({ event: 'AX_EXECUTION_VERIFIED', taskId: event.taskId, jobId: event.id, status: result.status || 'VERIFIED', evidenceTaskId: result.evidence?.taskId, writeBackVerified: result.writeBackVerified }));
      message.ack();
    }
  },
} satisfies ExportedHandler<Env, AxEvent>;
