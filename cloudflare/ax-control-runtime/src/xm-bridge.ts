export type XmCommand = {
  request_id: string;
  idempotency_key: string;
  operation: string;
  timestamp: string;
  account_scope: string;
  symbol?: string;
  side?: string;
  volume?: number;
  stop_loss?: number;
  take_profit?: number;
  strategy_id?: string;
  risk_snapshot?: Record<string, unknown>;
};

export type XmResult = {
  request_id: string;
  idempotency_key: string;
  state: 'REQUESTED' | 'VALIDATED' | 'SENT' | 'BROKER_ACK' | 'VERIFIED' | 'REJECTED' | 'FAILED' | 'UNKNOWN_REQUIRES_RECONCILIATION';
  broker?: Record<string, unknown>;
  evidence?: Record<string, unknown>;
  error?: string;
  received_at: string;
};

export type XmHeartbeat = {
  account_scope: string;
  login?: number;
  currency?: string;
  balance?: number;
  equity?: number;
  terminal_connected?: boolean;
  trade_allowed?: boolean;
  expert_allowed?: boolean;
  received_at: string;
};

const ALLOWED = new Set(['GET_ACCOUNT_STATE','GET_POSITIONS','GET_SYMBOL_STATE','SUBMIT_ORDER','MODIFY_POSITION','CLOSE_POSITION']);
const BLOCKED = new Set(['DEPOSIT','WITHDRAW','CHANGE_ACCOUNT_SETTINGS','EXPORT_CREDENTIALS']);
const SCOPE = 'XM_MICRO_K_DESIGNATED_ACCOUNT';
const TERMINAL = new Set(['VERIFIED','REJECTED','FAILED','UNKNOWN_REQUIRES_RECONCILIATION']);

function json(body: unknown, status = 200): Response {
  return Response.json(body, { status, headers: { 'Cache-Control': 'no-store', 'Content-Type': 'application/json; charset=utf-8' } });
}
function auth(request: Request, expected?: string): boolean {
  const received = (request.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '').trim();
  if (!expected || !received || received.length > 512) return false;
  const a = new TextEncoder().encode(received), b = new TextEncoder().encode(expected);
  if (a.length !== b.length) return false;
  let diff = 0; for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i];
  return diff === 0;
}
function validCommand(value: unknown): value is XmCommand {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return false;
  const v = value as Record<string, unknown>;
  return typeof v.request_id === 'string' && v.request_id.length > 0 &&
    typeof v.idempotency_key === 'string' && v.idempotency_key.length > 0 &&
    typeof v.operation === 'string' && ALLOWED.has(v.operation) && !BLOCKED.has(v.operation) &&
    v.account_scope === SCOPE && typeof v.timestamp === 'string';
}

export class AxXmExecutionQueue {
  constructor(private readonly state: DurableObjectState) {}

  async fetch(request: Request): Promise<Response> {
    const path = new URL(request.url).pathname;
    const body = request.method === 'POST' ? await request.json().catch(() => null) : null;
    const commands = (await this.state.storage.get<XmCommand[]>('commands')) || [];

    if (path === '/enqueue' && request.method === 'POST') {
      if (!validCommand(body)) return json({ error: 'COMMAND_SCHEMA_INVALID' }, 422);
      const existingByRequest = commands.find(c => c.request_id === body.request_id);
      if (existingByRequest) {
        if (JSON.stringify(existingByRequest) !== JSON.stringify(body)) return json({ error: 'REQUEST_ID_CONFLICT' }, 409);
        return json({ ok: true, request_id: body.request_id, duplicate: true });
      }
      const existingByIdempotency = commands.find(c => c.idempotency_key === body.idempotency_key);
      if (existingByIdempotency) return json({ ok: true, request_id: existingByIdempotency.request_id, duplicate: true });
      commands.push(body);
      await this.state.storage.put('commands', commands);
      await this.state.storage.put(`state:${body.request_id}`, { state: 'REQUESTED', request_id: body.request_id });
      return json({ ok: true, request_id: body.request_id, state: 'REQUESTED' }, 201);
    }

    if (path === '/pull' && request.method === 'POST') {
      const now = Date.now();
      const leases = (await this.state.storage.get<Record<string, number>>('leases')) || {};
      const item = commands.find(c => {
        const lease = leases[c.request_id] || 0;
        return lease <= now && !TERMINAL.has(String((c as any)._terminal));
      }) as (XmCommand & { _lease_until?: number }) | undefined;
      if (!item) return json({ ok: true, item: null });
      const leased = { ...item, _lease_until: now + 60000 };
      leases[item.request_id] = now + 60000;
      await this.state.storage.put('leases', leases);
      return json({ ok: true, item: leased });
    }

    if (path === '/result' && request.method === 'POST') {
      const result = body as XmResult | null;
      if (!result || typeof result.request_id !== 'string' || typeof result.idempotency_key !== 'string' || !TERMINAL.has(String(result.state)) && !['REQUESTED','VALIDATED','SENT','BROKER_ACK'].includes(String(result.state))) return json({ error: 'RESULT_SCHEMA_INVALID' }, 422);
      const command = commands.find(c => c.request_id === result.request_id);
      if (!command) return json({ error: 'COMMAND_NOT_FOUND' }, 404);
      if (command.idempotency_key !== result.idempotency_key) return json({ error: 'IDEMPOTENCY_MISMATCH' }, 409);
      await this.state.storage.put(`result:${result.request_id}`, result);
      if (TERMINAL.has(result.state)) {
        const terminalCommands = commands.map(c => c.request_id === result.request_id ? { ...c, _terminal: result.state } : c);
        await this.state.storage.put('commands', terminalCommands);
        const leases = (await this.state.storage.get<Record<string, number>>('leases')) || {};
        delete leases[result.request_id];
        await this.state.storage.put('leases', leases);
      }
      return json({ ok: true, request_id: result.request_id, state: result.state }, 201);
    }

    if (path === '/heartbeat' && request.method === 'POST') {
      if (!body || typeof body !== 'object' || Array.isArray(body) || (body as any).account_scope !== SCOPE) return json({ error: 'HEARTBEAT_SCOPE_INVALID' }, 422);
      const heartbeat: XmHeartbeat = { ...(body as XmHeartbeat), received_at: new Date().toISOString() };
      await this.state.storage.put('heartbeat', heartbeat);
      return json({ ok: true, account_scope: SCOPE, received_at: heartbeat.received_at }, 201);
    }

    if (path.startsWith('/result/') && request.method === 'GET') {
      const requestId = decodeURIComponent(path.slice('/result/'.length));
      const result = await this.state.storage.get<XmResult>(`result:${requestId}`);
      return result ? json({ ok: true, result }) : json({ error: 'RESULT_UNAVAILABLE', request_id: requestId }, 404);
    }

    if (path === '/status' && request.method === 'GET') {
      const latest = commands.slice(-20).map(c => ({ request_id: c.request_id, operation: c.operation, account_scope: c.account_scope, terminal: (c as any)._terminal || null }));
      const heartbeat = await this.state.storage.get<XmHeartbeat>('heartbeat');
      return json({ ok: true, service: 'AX XM EXECUTION BRIDGE', mode: 'READ_ONLY_PENDING_HANDSHAKE', live_execution_enabled: false, kill_switch: true, account_scope: SCOPE, queued: commands.length, heartbeat: heartbeat ? { received_at: heartbeat.received_at, account_scope: heartbeat.account_scope, terminal_connected: heartbeat.terminal_connected === true, trade_allowed: heartbeat.trade_allowed === true, expert_allowed: heartbeat.expert_allowed === true } : null, recent: latest });
    }
    return json({ error: 'NOT_FOUND' }, 404);
  }
}

export function xmQueueStub(env: { AX_XM_EXECUTION_QUEUE: DurableObjectNamespace }): DurableObjectStub {
  return env.AX_XM_EXECUTION_QUEUE.get(env.AX_XM_EXECUTION_QUEUE.idFromName('XM-MICRO-DESIGNATED'));
}

export { ALLOWED, BLOCKED, SCOPE, auth, json };