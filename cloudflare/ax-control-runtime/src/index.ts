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

function healthResponse(env: Env): Response {
  return json({
    service: SERVICE, status: 'ONLINE', version: 'control-runtime-1.3.1', gate: 'CONTROLLED', mode: MODE,
    liveFinancialExecution: false, financialTransactions: false, repositoryMutation: false, queue: QUEUE_NAME,
    gatewayInbox: INBOX_NAME, mobileIngress: true, pcPull: true,
    mobileIngressAuthConfigured: Boolean(env.AX_MOBILE_INGRESS_SECRET), pcPullAuthConfigured: Boolean(env.AX_PC_PULL_SECRET),
    repository: REPO,
    endpoints: ['GET /', 'GET /health', 'GET /time', 'GET /chat', 'GET /mobile', 'GET /mobile/config', 'POST /mobile/input', 'POST /pc/pull', 'POST /pc/ack', 'POST /enqueue'],
  });
}

function externalChatPage(): Response {
  const html = `<!doctype html><html lang="th"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>AX External Chat</title><style>:root{font-family:system-ui,-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;color:#18202a;background:#f5f7fa}*{box-sizing:border-box}body{margin:0}.app{max-width:920px;margin:auto;padding:16px}.panel{background:#fff;border:1px solid #d9dee7;border-radius:14px;padding:16px;margin:12px 0;box-shadow:0 2px 8px rgba(0,0,0,.04)}h1{margin:0 0 4px;font-size:1.5rem}.muted{color:#667085;font-size:.9rem}.row{display:flex;gap:8px;flex-wrap:wrap;align-items:center}input,textarea,button{font:inherit;padding:10px;border:1px solid #c9d0db;border-radius:9px}input{min-width:0}button{cursor:pointer;background:#fff}textarea{width:100%;min-height:130px;resize:vertical}.grow{flex:1}.chat{min-height:220px;max-height:55vh;overflow:auto;white-space:pre-wrap;overflow-wrap:anywhere;background:#101828;color:#f8fafc;border-radius:10px;padding:14px}.status{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:8px}.status div{padding:10px;border:1px solid #e2e8f0;border-radius:9px}@media(max-width:600px){.app{padding:10px}.status{grid-template-columns:1fr}.row>*{width:100%}button{width:auto}}</style></head><body><main class="app"><section class="panel"><h1>AX External Chat</h1><div class="muted">Public external client • A_MASTER_BRAIN remains authoritative • FREE_ONLY</div><div class="row" style="margin-top:12px"><input id="token" class="grow" type="password" placeholder="AX mobile gateway token" autocomplete="off"><button id="check">Connection test</button></div><div class="status" style="margin-top:12px"><div><b>Runtime</b><br><span id="runtime">CHECKING</span></div><div><b>Mode</b><br><span id="mode">—</span></div><div><b>Transport</b><br><span id="transport">—</span></div></div></section><section class="panel"><div id="messages" class="chat">AX External Chat ready.</div><textarea id="message" placeholder="ส่งข้อความถึง AX"></textarea><div class="row"><input id="file" type="file" multiple class="grow"><button id="send">Send</button></div><pre id="result" class="muted"></pre></section></main><script>const $=id=>document.getElementById(id);const stored=sessionStorage.getItem('ax_mobile_token')||'';$('token').value=stored;async function health(){const r=await fetch('/health');const j=await r.json();$('runtime').textContent=j.status||'UNKNOWN';$('mode').textContent=j.mode||'—';$('transport').textContent=j.gatewayInbox||'—';return j;}$('check').onclick=async()=>{try{await health();$('result').textContent='PUBLIC_CONNECTION_PASS';}catch(e){$('runtime').textContent='ERROR';$('result').textContent=String(e)}};$('send').onclick=async()=>{try{const token=$('token').value.trim();sessionStorage.setItem('ax_mobile_token',token);const files=[...$('file').files].map(file=>({attachment_id:crypto.randomUUID(),kind:file.type.startsWith('image/')?'image':'file',name:file.name,media_type:file.type||'application/octet-stream',reference:'browser:'+crypto.randomUUID()}));const body={source_channel:'MOBILE',content_type:files.length?(files.some(f=>f.kind==='image')?'image':'file'):'text',content:$('message').value,attachments:files};const r=await fetch('/mobile/input',{method:'POST',headers:{Authorization:'Bearer '+token,'Content-Type':'application/json'},body:JSON.stringify(body)});const j=await r.json();$('result').textContent=JSON.stringify(j,null,2);if(r.ok){$('messages').textContent+='\\n\\n['+j.status+'] '+j.requestId+'\\n'+(body.content||'');$('message').value='';$('file').value='';}}catch(e){$('result').textContent=String(e)}};health().catch(()=>{$('runtime').textContent='ERROR'});</script></body></html>`;
  return new Response(html, { headers: { 'content-type': 'text/html; charset=utf-8', 'cache-control': 'no-store' } });
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    if (request.method === 'GET' && url.pathname === '/') return healthResponse(env);
    if (request.method === 'GET' && url.pathname === '/health') return healthResponse(env);
    if (request.method === 'GET' && url.pathname === '/time') { const now = new Date(); return json({ source: 'AX_CLOUD_TIME_AUTHORITY', authority: 'Cloudflare Worker runtime', requestId: crypto.randomUUID(), timestampUtc: now.toISOString(), epochMs: now.getTime(), timezoneDisplay: 'Asia/Bangkok', timestampThailand: now.toLocaleString('sv-SE', { timeZone: 'Asia/Bangkok' }).replace(' ', 'T') + '+07:00', method: request.method }); }
    if (request.method === 'GET' && (url.pathname === '/chat' || url.pathname === '/mobile')) return externalChatPage();
    if (request.method === 'GET' && url.pathname === '/mobile/config') return json({ service: SERVICE, mobileIngress: true, pcPull: true, executionMode: MODE, liveFinancialExecution: false, transportStore: INBOX_NAME, endpoint: '/mobile/input', pcPullEndpoint: '/pc/pull', pcAckEndpoint: '/pc/ack', publicClient: '/chat' });
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
      return json({ error: 'EXECUTION_NOT_AVAILABLE_IN_CONTROL_RUNTIME' }, 503);
    }
    return json({ error: 'NOT_FOUND', service: SERVICE, status: 'ONLINE' }, 404);
  },
  async queue(batch: MessageBatch<AxEvent>): Promise<void> {
    for (const message of batch.messages) {
      console.log(JSON.stringify({ event: 'AX_EXECUTION_EVENT_RECEIVED', queue: batch.queue, messageId: message.id, body: message.body, receivedAt: new Date().toISOString() }));
      message.ack();
    }
  },
};
