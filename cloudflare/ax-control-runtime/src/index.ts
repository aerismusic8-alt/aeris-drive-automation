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
  source_channel: 'MOBILE' | 'PC' | 'WEB';
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
  requestId?: string;
  taskId?: string;
  evidence?: Record<string, unknown> | null;
  writeBackVerified?: boolean;
  status?: string;
  [key: string]: unknown;
};

type AxWebResult = {
  request_id: string;
  task_id: string;
  received_at: string;
  source: 'LOCAL_CONTROL_HUB';
  result: AxExecutionResult | Record<string, unknown>;
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
const WEB_SESSION_TTL_MS = 30 * 60 * 1000;
const ALLOWED_CONTENT_TYPES = new Set(['text', 'file', 'image', 'event', 'command']);
const NL = String.fromCharCode(10);

function json(body: unknown, status = 200): Response {
  return Response.json(body, {
    status,
    headers: {
      'Cache-Control': 'no-store',
      'Content-Type': 'application/json; charset=utf-8',
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET,POST,OPTIONS',
      'Access-Control-Allow-Headers': 'Authorization, Content-Type',
    },
  });
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

function base64UrlEncode(bytes: Uint8Array): string {
  let binary = '';
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '');
}

async function signWebSession(issuedAt: number, nonce: string, secret: string): Promise<string> {
  const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const signature = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(`${issuedAt}.${nonce}`));
  return base64UrlEncode(new Uint8Array(signature));
}

async function createWebSession(secret: string): Promise<string> {
  const issuedAt = Date.now();
  const nonce = crypto.randomUUID();
  const signature = await signWebSession(issuedAt, nonce, secret);
  return `${issuedAt}.${nonce}.${signature}`;
}

async function webSessionAccepted(token: string, secret: string | undefined): Promise<boolean> {
  if (!token || !secret) return false;
  const parts = token.split('.');
  if (parts.length !== 3) return false;
  const issuedAt = Number(parts[0]);
  if (!Number.isFinite(issuedAt) || issuedAt <= 0 || Date.now() - issuedAt > WEB_SESSION_TTL_MS || Date.now() < issuedAt - 60_000) return false;
  const expected = await signWebSession(issuedAt, parts[1], secret);
  return constantTimeEqual(parts[2], expected);
}

async function requireWebSession(request: Request, env: Env): Promise<Response | null> {
  if (await webSessionAccepted(bearerSecret(request), env.AX_MOBILE_INGRESS_SECRET)) return null;
  return json({ error: 'AUTH_REQUIRED' }, 401);
}

function makeRequestId(): string { return crypto.randomUUID(); }
function makeTaskId(): string { return `TASK-${crypto.randomUUID().slice(0, 8)}`; }

function hasRawBinary(attachments: unknown): boolean {
  if (!Array.isArray(attachments)) return true;
  return attachments.some((item) => !item || typeof item !== 'object' || 'bytes' in item || 'data' in item);
}

function normalizeGatewayBody(body: Record<string, unknown>, sourceChannel: AxGatewayInput['source_channel']): AxGatewayInput | Response {
  const contentType = String(body.contentType ?? body.content_type ?? 'text');
  if (!ALLOWED_CONTENT_TYPES.has(contentType)) return json({ error: 'INVALID_CONTENT_TYPE' }, 422);
  const content = body.content === undefined || body.content === null ? null : String(body.content);
  if (content !== null && new TextEncoder().encode(content).byteLength > MAX_PAYLOAD_BYTES) return json({ error: 'REQUEST_TOO_LARGE' }, 413);
  const attachments = body.attachments ?? [];
  if (hasRawBinary(attachments)) return json({ error: 'RAW_BINARY_NOT_ALLOWED' }, 422);
  return {
    request_id: String(body.requestId ?? body.request_id ?? makeRequestId()),
    task_id: String(body.taskId ?? body.task_id ?? makeTaskId()),
    status: 'RECEIVED',
    source_channel: sourceChannel,
    content_type: contentType as AxGatewayInput['content_type'],
    content,
    evidence_status: 'PENDING',
    verification_status: 'PENDING',
    attachments: attachments as Array<Record<string, unknown>>,
    source_of_truth: 'A_MASTER_BRAIN',
    transport_store: INBOX_NAME,
    received_at: new Date().toISOString(),
  };
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

    if (path === '/result-put' && payload && typeof payload === 'object') {
      const resultRecord = (payload as { record?: AxWebResult }).record;
      if (!resultRecord?.request_id || !resultRecord?.task_id || !resultRecord.result) return json({ error: 'RESULT_SCHEMA_INVALID' }, 422);
      await this.state.storage.put(`result:${resultRecord.request_id}`, resultRecord);
      return json({ ok: true, requestId: resultRecord.request_id, taskId: resultRecord.task_id }, 201);
    }

    if (path.startsWith('/result-get/') && request.method === 'GET') {
      const requestId = decodeURIComponent(path.slice('/result-get/'.length));
      if (!requestId) return json({ error: 'REQUEST_ID_REQUIRED' }, 422);
      const result = await this.state.storage.get<AxWebResult>(`result:${requestId}`);
      if (!result) return json({ error: 'RESULT_UNAVAILABLE', requestId }, 404);
      return json({ ok: true, result });
    }

    return json({ error: 'NOT_FOUND' }, 404);
  }
}

async function gatewayInboxCall(env: Env, operation: 'put' | 'pull' | 'ack' | 'result-put' | 'result-get/', payload?: unknown, requestId?: string): Promise<Response> {
  const stub = env.AX_GATEWAY_INBOX.get(env.AX_GATEWAY_INBOX.idFromName('AERIS-K-GATEWAY'));
  const path = operation === 'result-get/' ? `${operation}${encodeURIComponent(requestId || '')}` : operation;
  return stub.fetch(`https://gateway.local/${path}`, {
    method: operation === 'result-get/' ? 'GET' : 'POST',
    headers: { 'content-type': 'application/json' },
    body: operation === 'result-get/' ? undefined : JSON.stringify(payload || {}),
  });
}

async function verifyGitHubToken(token: string): Promise<boolean> {
  try {
    const response = await fetch(`https://api.github.com/repos/${REPO}`, {
      method: 'GET',
      headers: {
        Accept: 'application/vnd.github+json',
        Authorization: `Bearer ${token}`,
        'X-GitHub-Api-Version': '2026-03-10',
        'User-Agent': 'AX-Control-Runtime',
      },
    });
    return response.ok;
  } catch {
    return false;
  }
}

function healthResponse(env: Env): Response {
  return json({
    service: SERVICE,
    status: 'ONLINE',
    version: 'control-runtime-1.5.0',
    gate: 'CONTROLLED',
    mode: MODE,
    liveFinancialExecution: false,
    financialTransactions: false,
    repositoryMutation: false,
    queue: QUEUE_NAME,
    gatewayInbox: INBOX_NAME,
    mobileIngress: true,
    pcPull: true,
    webChat: true,
    mobileIngressAuthConfigured: Boolean(env.AX_MOBILE_INGRESS_SECRET),
    pcPullAuthConfigured: Boolean(env.AX_PC_PULL_SECRET),
    webChatAuthConfigured: Boolean(env.AX_MOBILE_INGRESS_SECRET),
    repository: REPO,
    cloudTimeAuthority: {
      enabled: true,
      endpoint: '/time',
      source: 'Cloudflare Worker runtime',
      storageTimezone: 'UTC',
      displayTimezone: 'Asia/Bangkok',
    },
    endpoints: ['GET /', 'GET /health', 'GET /time', 'GET /mobile', 'GET /mobile/config', 'POST /mobile/input', 'GET /chat', 'POST /web/session', 'GET /web/context', 'POST /web/input', 'GET /web/result/{request_id}', 'POST /pc/pull', 'POST /pc/result', 'POST /pc/ack', 'POST /enqueue'],
  });
}

function mobilePage(): Response {
  const html = `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>AX Mobile Gateway</title><style>body{font-family:system-ui,sans-serif;max-width:680px;margin:24px auto;padding:0 16px}textarea,input,button{width:100%;box-sizing:border-box;margin:8px 0;padding:12px;font-size:16px}button{cursor:pointer}.ok{padding:10px;background:#eef7ee}.err{padding:10px;background:#fdecec}small{color:#666}a{display:inline-block;margin:8px 0}</style></head><body><h1>AX Mobile Gateway</h1><small>Transport only · A Master Brain remains the source of truth · FREE_ONLY</small><a href="/chat">Open AX Web Chat</a><input id="token" type="password" placeholder="Mobile gateway token" autocomplete="off"><input id="task" placeholder="Task ID (optional)"><textarea id="content" rows="8" placeholder="Send work to A Master Brain"></textarea><button id="send">Send</button><div id="result"></div><script>const NL=String.fromCharCode(10);const $=id=>document.getElementById(id);$('token').value=sessionStorage.getItem('ax_mobile_token')||'';$('send').onclick=async()=>{const token=$('token').value.trim();sessionStorage.setItem('ax_mobile_token',token);const body={task_id:$('task').value.trim()||undefined,source_channel:'MOBILE',content_type:'text',content:$('content').value};try{const r=await fetch('/mobile/input',{method:'POST',headers:{Authorization:'Bearer '+token,'Content-Type':'application/json'},body:JSON.stringify(body)});const j=await r.json();$('result').className=r.ok?'ok':'err';$('result').textContent=JSON.stringify(j,null,2)}catch(e){$('result').className='err';$('result').textContent=String(e)}};</script></body></html>`;
  return new Response(html, { headers: { 'content-type': 'text/html; charset=utf-8', 'cache-control': 'no-store' } });
}

function webChatPage(): Response {
  const html = `<!doctype html><html lang="th"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>AX Web Chat</title><style>:root{font-family:system-ui,-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;color:#18202a;background:#f5f7fa}*{box-sizing:border-box}body{margin:0}.app{max-width:980px;margin:auto;padding:14px}.panel{background:#fff;border:1px solid #d9dee7;border-radius:14px;padding:16px;margin:12px 0;box-shadow:0 2px 8px rgba(0,0,0,.04)}h1{margin:0 0 4px;font-size:1.5rem}.muted{color:#667085;font-size:.9rem}.row{display:flex;gap:8px;flex-wrap:wrap;align-items:center}.row>*{flex:1}input,textarea,button{font:inherit;padding:11px;border:1px solid #c9d0db;border-radius:9px}textarea{width:100%;min-height:130px;resize:vertical}button{cursor:pointer;background:#fff;flex:0 0 auto}.hidden{display:none}.chat{min-height:220px;white-space:pre-wrap;overflow-wrap:anywhere;background:#101828;color:#f8fafc;border-radius:10px;padding:14px}.status{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:8px}.status div{padding:10px;border:1px solid #e2e8f0;border-radius:9px}.ok{padding:10px;background:#eef7ee;border-radius:9px}.err{padding:10px;background:#fdecec;border-radius:9px}.filePicker{position:relative;display:flex;align-items:center;justify-content:flex-start;min-height:44px;padding:11px;border:1px solid #c9d0db;border-radius:9px;background:#fff;overflow:hidden;cursor:pointer}.filePicker input{position:absolute;inset:0;width:100%;height:100%;padding:0;border:0;opacity:0;cursor:pointer}.filePicker span{pointer-events:none;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}@media(max-width:700px){.app{padding:8px}.status{grid-template-columns:1fr 1fr}.row>*{width:100%;flex-basis:100%}.status div{font-size:.9rem}}</style></head><body><main class="app"><section class="panel"><h1>AX Web Chat</h1><div class="muted">Independent external channel · A_MASTER_BRAIN remains authoritative · FREE_ONLY</div><div id="loginPanel"><input id="secret" type="password" autocomplete="off" placeholder="AX Web access secret"><button id="login">Start session</button><div id="loginStatus" class="muted" role="status" aria-live="polite"></div></div><div id="sessionPanel" class="hidden"><div class="row"><button id="refresh">Refresh</button><button id="macheck">M-A-CHECK</button><button id="logout">Logout</button></div><div class="status" style="margin-top:12px"><div><b>Session</b><br><span id="session">AUTHENTICATED</span></div><div><b>Channel</b><br><span>WEB → PC → HUB</span></div><div><b>Source</b><br><span>A_MASTER_BRAIN</span></div><div><b>Mode</b><br><span>FREE_ONLY</span></div></div><pre id="context" class="muted"></pre></div></section><section id="chatPanel" class="panel hidden"><div id="messages" class="chat">AX Web Chat ready.</div><textarea id="message" placeholder="ส่งข้อความถึง AX"></textarea><div class="row"><label id="filePicker" class="filePicker"><span id="fileLabel">Choose File</span><input id="file" type="file" multiple></label><button id="send">Send</button></div><div id="result" class="muted" role="status" aria-live="polite"></div></section></main><script>const NL=String.fromCharCode(10);const $=id=>document.getElementById(id);const key='ax_web_session';const session=()=>sessionStorage.getItem(key)||'';const setSession=v=>v?sessionStorage.setItem(key,v):sessionStorage.removeItem(key);async function api(path,opts={}){const headers={...(opts.headers||{})};if(opts.body&&!headers['Content-Type'])headers['Content-Type']='application/json';if(session())headers.Authorization='Bearer '+session();const r=await fetch(path,{...opts,headers});const j=await r.json().catch(()=>({}));if(!r.ok)throw new Error(j.error||j.error_code||'HTTP_'+r.status);return j}function logged(){ $('loginPanel').classList.add('hidden');$('sessionPanel').classList.remove('hidden');$('chatPanel').classList.remove('hidden') }async function login(){const status=$('loginStatus');status.className='muted';status.textContent='Connecting…';try{const secret=$('secret').value.trim();if(!secret)throw new Error('SECRET_REQUIRED');const r=await fetch('/web/session',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({secret})});const j=await r.json().catch(()=>({}));if(!r.ok)throw new Error(j.error||'AUTH_FAILED');if(!j.sessionToken)throw new Error('SESSION_TOKEN_MISSING');setSession(j.sessionToken);$('secret').value='';status.textContent='';logged();await refresh()}catch(e){status.className='err';$('loginStatus').textContent=e.message;status.textContent=e.message||'AUTH_FAILED';}}async function refresh(){try{$('context').textContent=JSON.stringify(await api('/web/context'),null,2)}catch(e){$('context').textContent=e.message}}async function submit(content){const files=[...$('file').files].map(f=>({attachment_id:crypto.randomUUID(),kind:f.type.startsWith('image/')?'image':'file',name:f.name,media_type:f.type||'application/octet-stream',reference:'browser:'+crypto.randomUUID()}));const body={request_id:crypto.randomUUID(),task_id:'TASK-WEB-'+crypto.randomUUID().slice(0,8),source_channel:'WEB',content_type:files.length?(files.some(x=>x.kind==='image')?'image':'file'):'text',content,attachments:files};return api('/web/input',{method:'POST',body:JSON.stringify(body)})}async function poll(requestId){for(let i=0;i<30;i++){try{const r=await api('/web/result/'+encodeURIComponent(requestId));return r.result}catch(e){if(!String(e.message).includes('RESULT_UNAVAILABLE'))throw e}await new Promise(r=>setTimeout(r,2000))}throw new Error('RESULT_TIMEOUT')}$('login').onclick=login;$('refresh').onclick=refresh;$('macheck').onclick=async()=>{try{const r=await submit('M-A-CHECK');$('messages').textContent+=NL+'[REQUESTED] '+r.requestId+NL+'M-A-CHECK';const result=await poll(r.requestId);$('messages').textContent+=NL+'[RESULT]'+NL+JSON.stringify(result.result||result,null,2)}catch(e){$('result').className='err';$('result').textContent=e.message}};$('logout').onclick=()=>{setSession('');location.reload()};$('file').addEventListener('change',()=>{const count=$('file').files.length;$('fileLabel').textContent=count?(count+' file'+(count===1?'':'s')+' selected'):'Choose File'});$('send').onclick=async()=>{try{const message=$('message').value.trim();if(!message&&!$('file').files.length)throw new Error('MESSAGE_REQUIRED');const r=await submit(message);$('messages').textContent+=NL+NL+'[RECEIVED] '+r.requestId+NL+(message||'[attachment]');$('message').value='';$('file').value='';$('fileLabel').textContent='Choose File';$('result').className='muted';$('result').textContent='Waiting for Local Hub result…';const result=await poll(r.requestId);$('messages').textContent+=NL+'[LOCAL HUB RESULT]'+NL+JSON.stringify(result.result||result,null,2);$('result').textContent='Completed'}catch(e){$('result').className='err';$('result').textContent=e.message}};$('message').addEventListener('keydown',e=>{if(e.key==='Enter'&&!e.shiftKey){e.preventDefault();$('send').click()}});if(session()){logged();refresh().catch(()=>{})}</script></body></html>`;
  return new Response(html, { headers: { 'content-type': 'text/html; charset=utf-8', 'cache-control': 'no-store' } });
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    if (request.method === 'OPTIONS') return json({ ok: true });
    if (request.method === 'GET' && url.pathname === '/') return healthResponse(env);
    if (request.method === 'GET' && url.pathname === '/health') return healthResponse(env);
    if (request.method === 'GET' && url.pathname === '/time') {
      const now = new Date();
      return json({ source: 'AX_CLOUD_TIME_AUTHORITY', authority: 'Cloudflare Worker runtime', requestId: crypto.randomUUID(), timestampUtc: now.toISOString(), epochMs: now.getTime(), timezoneDisplay: 'Asia/Bangkok', timestampThailand: now.toLocaleString('sv-SE', { timeZone: 'Asia/Bangkok' }).replace(' ', 'T') + '+07:00', method: request.method });
    }
    if (request.method === 'GET' && url.pathname === '/mobile') return mobilePage();
    if (request.method === 'GET' && url.pathname === '/mobile/config') return json({ service: SERVICE, mobileIngress: true, pcPull: true, webChat: true, executionMode: MODE, liveFinancialExecution: false, transportStore: INBOX_NAME, endpoint: '/mobile/input', webEndpoint: '/web/input', pcPullEndpoint: '/pc/pull', pcAckEndpoint: '/pc/ack' });
    if (request.method === 'GET' && url.pathname === '/chat') return webChatPage();
    if (request.method === 'POST' && url.pathname === '/web/session') {
      const body = await request.json().catch(() => null) as { secret?: unknown } | null;
      if (!secretAccepted(String(body?.secret || ''), env.AX_MOBILE_INGRESS_SECRET)) return json({ error: 'AUTH_FAILED' }, 401);
      return json({ authenticated: true, sessionToken: await createWebSession(env.AX_MOBILE_INGRESS_SECRET as string), expiresInMs: WEB_SESSION_TTL_MS, mode: MODE, liveFinancialExecution: false });
    }
    if (request.method === 'GET' && url.pathname === '/web/context') {
      const denied = await requireWebSession(request, env); if (denied) return denied;
      return json({ service: SERVICE, source_of_truth: 'A_MASTER_BRAIN', mode: MODE, liveFinancialExecution: false, transportStore: INBOX_NAME, note: 'Context/status is authoritative only when returned by Local Hub; submit M-A-CHECK or work through the bridge for authoritative task processing.' });
    }
    if (request.method === 'POST' && url.pathname === '/web/input') {
      const denied = await requireWebSession(request, env); if (denied) return denied;
      const raw = await request.text();
      if (new TextEncoder().encode(raw).byteLength > MAX_PAYLOAD_BYTES) return json({ error: 'PAYLOAD_TOO_LARGE', maxBytes: MAX_PAYLOAD_BYTES }, 413);
      const body = readJsonObject(raw); if (!body) return json({ error: 'INVALID_JSON' }, 400);
      if (String(body.sourceChannel ?? body.source_channel ?? 'WEB') !== 'WEB') return json({ error: 'SOURCE_CHANNEL_MUST_BE_WEB' }, 422);
      const record = normalizeGatewayBody(body, 'WEB'); if (record instanceof Response) return record;
      const inboxResponse = await gatewayInboxCall(env, 'put', { record }); const inboxBody = await inboxResponse.json(); if (!inboxResponse.ok) return json(inboxBody, inboxResponse.status);
      return json({ accepted: true, queued: true, requestId: record.request_id, taskId: record.task_id, sourceChannel: 'WEB', transportStore: INBOX_NAME, status: record.status, evidenceStatus: record.evidence_status, executionStatus: 'NOT_EXECUTED', liveFinancialExecution: false }, 201);
    }
    if (request.method === 'GET' && url.pathname.startsWith('/web/result/')) {
      const denied = await requireWebSession(request, env); if (denied) return denied;
      const requestId = decodeURIComponent(url.pathname.slice('/web/result/'.length)); if (!requestId) return json({ error: 'REQUEST_ID_REQUIRED' }, 422);
      const resultResponse = await gatewayInboxCall(env, 'result-get/', undefined, requestId);
      return json(await resultResponse.json(), resultResponse.status);
    }
    if (request.method === 'POST' && url.pathname === '/mobile/input') {
      if (!secretAccepted(bearerSecret(request), env.AX_MOBILE_INGRESS_SECRET)) return json({ error: 'AUTH_REQUIRED' }, 401);
      const raw = await request.text();
      if (new TextEncoder().encode(raw).byteLength > MAX_PAYLOAD_BYTES) return json({ error: 'PAYLOAD_TOO_LARGE', maxBytes: MAX_PAYLOAD_BYTES }, 413);
      const body = readJsonObject(raw); if (!body) return json({ error: 'INVALID_JSON' }, 400);
      if (String(body.sourceChannel ?? body.source_channel ?? 'MOBILE') !== 'MOBILE') return json({ error: 'SOURCE_CHANNEL_MUST_BE_MOBILE' }, 422);
      const record = normalizeGatewayBody(body, 'MOBILE'); if (record instanceof Response) return record;
      const inboxResponse = await gatewayInboxCall(env, 'put', { record }); const inboxBody = await inboxResponse.json(); if (!inboxResponse.ok) return json(inboxBody, inboxResponse.status);
      return json({ accepted: true, queued: true, requestId: record.request_id, taskId: record.task_id, sourceChannel: record.source_channel, transportStore: INBOX_NAME, status: record.status, evidenceStatus: record.evidence_status, executionStatus: 'NOT_EXECUTED', liveFinancialExecution: false }, 201);
    }
    if (request.method === 'POST' && url.pathname === '/pc/pull') {
      if (!secretAccepted(bearerSecret(request), env.AX_PC_PULL_SECRET)) return json({ error: 'AUTH_REQUIRED' }, 401);
      const inboxResponse = await gatewayInboxCall(env, 'pull'); return json(await inboxResponse.json(), inboxResponse.status);
    }
    if (request.method === 'POST' && url.pathname === '/pc/result') {
      if (!secretAccepted(bearerSecret(request), env.AX_PC_PULL_SECRET)) return json({ error: 'AUTH_REQUIRED' }, 401);
      const body = await request.json().catch(() => null) as { request_id?: string; task_id?: string; result?: AxExecutionResult | Record<string, unknown> } | null;
      const requestId = String(body?.request_id || ''); const taskId = String(body?.task_id || '');
      if (!requestId || !taskId || !body?.result) return json({ error: 'RESULT_SCHEMA_INVALID' }, 422);
      const record: AxWebResult = { request_id: requestId, task_id: taskId, received_at: new Date().toISOString(), source: 'LOCAL_CONTROL_HUB', result: body.result };
      const inboxResponse = await gatewayInboxCall(env, 'result-put', { record }); return json(await inboxResponse.json(), inboxResponse.status);
    }
    if (request.method === 'POST' && url.pathname === '/pc/ack') {
      if (!secretAccepted(bearerSecret(request), env.AX_PC_PULL_SECRET)) return json({ error: 'AUTH_REQUIRED' }, 401);
      const body = await request.json().catch(() => null) as { request_id?: string; requestId?: string } | null;
      const requestId = String(body?.request_id ?? body?.requestId ?? ''); if (!requestId) return json({ error: 'REQUEST_ID_REQUIRED' }, 422);
      const inboxResponse = await gatewayInboxCall(env, 'ack', { request_id: requestId }); return json(await inboxResponse.json(), inboxResponse.status);
    }
    if (request.method === 'POST' && url.pathname === '/enqueue') {
      const token = bearerSecret(request); if (!token) return json({ error: 'AUTH_REQUIRED' }, 401);
      const repoHeader = request.headers.get('X-AERIS-REPOSITORY') || ''; if (repoHeader !== REPO) return json({ error: 'REPOSITORY_NOT_ALLOWED', expected: REPO }, 403);
      if (!(await verifyGitHubToken(token))) return json({ error: 'GITHUB_TOKEN_REJECTED' }, 403);
      let event: AxEvent;
      try { event = JSON.parse(await request.text()) as AxEvent; } catch { return json({ error: 'INVALID_JSON' }, 400); }
      if (!event || typeof event !== 'object' || !event.id || !event.taskId || !event.domain || !event.action) return json({ error: 'EVENT_SCHEMA_INVALID', required: ['id', 'taskId', 'domain', 'action'] }, 422);
      const normalizedEvent: AxEvent = { id: String(event.id), taskId: String(event.taskId), domain: String(event.domain), priority: Number(event.priority || 0), action: String(event.action), createdAt: event.createdAt || new Date().toISOString(), source: event.source || 'AX_CONTROL_RUNTIME' };
      if (normalizedEvent.domain === 'PC') {
        const record: AxGatewayInput = {
          request_id: normalizedEvent.id,
          task_id: normalizedEvent.taskId,
          status: 'RECEIVED',
          source_channel: 'PC',
          content_type: 'command',
          content: JSON.stringify({ operation: normalizedEvent.action }),
          evidence_status: 'PENDING',
          verification_status: 'PENDING',
          attachments: [],
          source_of_truth: 'A_MASTER_BRAIN',
          transport_store: INBOX_NAME,
          received_at: normalizedEvent.createdAt,
        };
        const inboxResponse = await gatewayInboxCall(env, 'put', { record });
        const inboxBody = await inboxResponse.json();
        if (!inboxResponse.ok) return json(inboxBody, inboxResponse.status);
        return json({ accepted: true, queued: true, eventId: normalizedEvent.id, taskId: normalizedEvent.taskId, queue: INBOX_NAME, route: 'PC_PULL', executionGate: 'CONTROLLED', liveFinancialExecution: false }, 201);
      }
      await env.AX_EXECUTION_QUEUE.send(normalizedEvent);
      return json({ accepted: true, queued: true, eventId: normalizedEvent.id, taskId: normalizedEvent.taskId, queue: QUEUE_NAME, executionGate: 'CONTROLLED', liveFinancialExecution: false });
    }
    return json({ error: 'NOT_FOUND', service: SERVICE, status: 'ONLINE' }, 404);
  },
  async queue(batch: MessageBatch<AxEvent>): Promise<void> {
    for (const message of batch.messages) {
      const event = message.body;
      console.log(JSON.stringify({ event: 'AX_EXECUTION_EVENT_RECEIVED', queue: batch.queue, messageId: message.id, body: event, receivedAt: new Date().toISOString() }));
      if (event.domain !== 'AERIS') {
        console.log(JSON.stringify({ event: 'AX_EXECUTION_EVENT_DEFERRED', reason: 'DOMAIN_EXECUTOR_NOT_IMPLEMENTED', taskId: event.taskId, domain: event.domain }));
        message.ack();
        continue;
      }
      const response = await fetch('https://aeris-execution-runtime.aerismusic8.workers.dev/execute', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Accept: 'application/json', 'User-Agent': 'AX-Control-Runtime/1.5.0' },
        body: JSON.stringify({ jobId: event.id, command: event.action }),
      });
      const rawResponse = await response.text();
      let result: AxExecutionResult | null = null;
      try { result = rawResponse ? JSON.parse(rawResponse) as AxExecutionResult : null; } catch { result = null; }
      const responseTaskMatches = result?.taskId === event.taskId;
      const businessEvidenceValid = !!result?.evidence && String(result.evidence.taskId || '') === event.taskId;
      if (!response.ok || result?.accepted !== true || result?.verified !== true || result?.executed !== true || !responseTaskMatches || !businessEvidenceValid || result?.writeBackVerified !== true) throw new Error(`AERIS_EXECUTION_NOT_VERIFIED:${response.status}`);
      console.log(JSON.stringify({ event: 'AX_EXECUTION_VERIFIED', taskId: event.taskId, jobId: event.id, status: result.status || 'VERIFIED', evidenceTaskId: result.evidence?.taskId, writeBackVerified: result.writeBackVerified }));
      message.ack();
    }
  },
} satisfies ExportedHandler<Env, AxEvent>;
