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

const RECORDS_KEY = 'records';

type StoredRecords = Record<string, MissionRecord>;

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
    const records = (await this.state.storage.get<StoredRecords>(RECORDS_KEY)) || {};

    if (method === 'GET' && url.pathname === '/get') {
      const taskId = (url.searchParams.get('task_id') || '').trim();
      if (taskId) {
        const task = records[taskId];
        return task ? json({ ok: true, mission: task }) : json({ ok: false, error: 'TASK_NOT_FOUND' }, 404);
      }
      return json({ ok: true, tasks: Object.values(records).sort((a, b) => a.command.created_at.localeCompare(b.command.created_at)) });
    }

    if (method === 'POST' && url.pathname === '/put') {
      const incoming = await request.json().catch(() => null) as MissionRecord | null;
      if (!incoming?.command?.mission_id || !incoming.command.task_id || !incoming.command.request_id || !incoming.command.fingerprint) {
        return json({ ok: false, error: 'MISSION_SCHEMA_INVALID' }, 422);
      }
      const existing = records[incoming.command.task_id];
      if (!existing) {
        records[incoming.command.task_id] = incoming;
        await this.state.storage.put(RECORDS_KEY, records);
        return json({ ok: true, kind: 'CREATED', mission: incoming }, 201);
      }
      if (existing.command.fingerprint === incoming.command.fingerprint && existing.command.mission_id === incoming.command.mission_id) {
        return json({ ok: true, kind: 'DUPLICATE', mission: existing }, 200);
      }
      return json({ ok: false, kind: 'CONFLICT', mission: existing, error: 'TASK_ID_CONFLICT' }, 409);
    }

    if (method === 'POST' && url.pathname === '/status') {
      const taskId = (url.searchParams.get('task_id') || '').trim();
      if (!taskId || !records[taskId]) return json({ ok: false, error: 'TASK_NOT_FOUND' }, 404);
      const body = await request.json().catch(() => null) as Partial<MissionRecord> | null;
      const nextStatus = body?.status as MissionStatus | undefined;
      const allowed: MissionStatus[] = ['READY', 'QUEUED', 'RUNNING', 'RECOVERING', 'COMPLETED', 'FAILED'];
      if (!nextStatus || !allowed.includes(nextStatus)) return json({ ok: false, error: 'MISSION_STATUS_INVALID' }, 422);
      const record = records[taskId];
      const updated: MissionRecord = {
        ...record,
        status: nextStatus,
        attempts: Math.max(record.attempts, Number(body?.attempts ?? record.attempts)),
        executor: typeof body?.executor === 'string' ? body.executor : record.executor,
        run_id: typeof body?.run_id === 'string' ? body.run_id : record.run_id,
        evidence: body && 'evidence' in body ? body.evidence ?? null : record.evidence,
        updated_at: new Date().toISOString(),
      };
      records[taskId] = updated;
      await this.state.storage.put(RECORDS_KEY, records);
      return json({ ok: true, mission: updated });
    }

    return json({ ok: false, error: 'NOT_FOUND' }, 404);
  }
}
