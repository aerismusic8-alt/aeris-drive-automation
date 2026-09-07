export type MissionStatus = 'READY' | 'QUEUED' | 'RUNNING' | 'RECOVERING' | 'COMPLETED' | 'FAILED';

export type MissionCommand = {
  mission_id: string;
  task_id: string;
  request_id: string;
  content_type: 'text' | 'file' | 'image' | 'event' | 'command';
  content: string | null;
  attachments: Array<Record<string, unknown>>;
  fingerprint: string;
  created_at: string;
};

export type MissionRecord = {
  command: MissionCommand;
  status: MissionStatus;
  attempts: number;
  executor?: string;
  run_id?: string;
  evidence?: Record<string, unknown> | null;
  updated_at: string;
};

export type MissionPutResult =
  | { kind: 'CREATED'; mission: MissionRecord }
  | { kind: 'DUPLICATE'; mission: MissionRecord }
  | { kind: 'CONFLICT'; mission: MissionRecord };

const RECORD_KEY = 'record';

function json(body: unknown, status = 200): Response {
  return Response.json(body, { status, headers: { 'Cache-Control': 'no-store', 'Content-Type': 'application/json; charset=utf-8' } });
}

export async function commandFingerprint(input: Omit<MissionCommand, 'fingerprint' | 'created_at'>): Promise<string> {
  const canonical = JSON.stringify({
    mission_id: input.mission_id,
    task_id: input.task_id,
    request_id: input.request_id,
    content_type: input.content_type,
    content: input.content,
    attachments: input.attachments,
  });
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(canonical));
  return Array.from(new Uint8Array(digest)).map(byte => byte.toString(16).padStart(2, '0')).join('');
}

export class AxMissionLedger {
  constructor(private readonly state: DurableObjectState) {}

  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);
    const method = request.method;
    const record = await this.state.storage.get<MissionRecord>(RECORD_KEY);

    if (method === 'GET' && url.pathname === '/get') {
      return record ? json({ ok: true, mission: record }) : json({ ok: false, error: 'MISSION_NOT_FOUND' }, 404);
    }

    if (method === 'POST' && url.pathname === '/put') {
      const incoming = await request.json().catch(() => null) as MissionRecord | null;
      if (!incoming?.command?.mission_id || !incoming.command.task_id || !incoming.command.request_id || !incoming.command.fingerprint) {
        return json({ ok: false, error: 'MISSION_SCHEMA_INVALID' }, 422);
      }
      if (!record) {
        await this.state.storage.put(RECORD_KEY, incoming);
        return json({ ok: true, kind: 'CREATED', mission: incoming }, 201);
      }
      if (record.command.fingerprint === incoming.command.fingerprint) {
        return json({ ok: true, kind: 'DUPLICATE', mission: record }, 200);
      }
      return json({ ok: false, kind: 'CONFLICT', mission: record, error: 'MISSION_ID_CONFLICT' }, 409);
    }

    if (method === 'POST' && url.pathname === '/status') {
      if (!record) return json({ ok: false, error: 'MISSION_NOT_FOUND' }, 404);
      const body = await request.json().catch(() => null) as Partial<MissionRecord> | null;
      const nextStatus = body?.status as MissionStatus | undefined;
      const allowed: MissionStatus[] = ['READY', 'QUEUED', 'RUNNING', 'RECOVERING', 'COMPLETED', 'FAILED'];
      if (!nextStatus || !allowed.includes(nextStatus)) return json({ ok: false, error: 'MISSION_STATUS_INVALID' }, 422);
      const updated: MissionRecord = {
        ...record,
        status: nextStatus,
        attempts: Math.max(record.attempts, Number(body?.attempts ?? record.attempts)),
        executor: typeof body?.executor === 'string' ? body.executor : record.executor,
        run_id: typeof body?.run_id === 'string' ? body.run_id : record.run_id,
        evidence: body && 'evidence' in body ? body.evidence ?? null : record.evidence,
        updated_at: new Date().toISOString(),
      };
      await this.state.storage.put(RECORD_KEY, updated);
      return json({ ok: true, mission: updated });
    }

    return json({ ok: false, error: 'NOT_FOUND' }, 404);
  }
}
