import { describe, expect, it } from 'vitest';
import { handleAxAdaptersRoute } from '../src/ax-adapters-route';

function makeEnv() {
  const records = new Map<string, any>();
  const sent: any[] = [];
  const stub = {
    async fetch(url: string, init?: RequestInit) {
      const path = new URL(url).pathname;
      if (path === '/put') {
        const incoming = JSON.parse(String(init?.body || 'null'));
        const existing = records.get(incoming.command.mission_id);
        if (!existing) {
          records.set(incoming.command.mission_id, incoming);
          return Response.json({ ok: true, kind: 'CREATED', mission: incoming }, { status: 201 });
        }
        if (existing.command.fingerprint === incoming.command.fingerprint) return Response.json({ ok: true, kind: 'DUPLICATE', mission: existing });
        return Response.json({ ok: false, kind: 'CONFLICT', error: 'MISSION_ID_CONFLICT', mission: existing }, { status: 409 });
      }
      if (path === '/get') {
        const mission = [...records.values()][0];
        return mission ? Response.json({ ok: true, mission }) : Response.json({ ok: false, error: 'MISSION_NOT_FOUND' }, { status: 404 });
      }
      return Response.json({ error: 'NOT_FOUND' }, { status: 404 });
    },
  } as any;
  return {
    env: {
      AX_MOBILE_INGRESS_SECRET: 'test-secret',
      AX_EXECUTION_QUEUE: { send: async (event: unknown) => sent.push(event) },
      AX_MISSION_LEDGER: { idFromName: (name: string) => name, get: () => stub },
    } as any,
    sent,
    records,
  };
}

describe('AX direct intake', () => {
  it('preserves the command exactly and sends to the execution queue once', async () => {
    const { env, sent } = makeEnv();
    const body = { mission_id: 'MISSION-CONTINUITY-1', task_id: 'TASK-CONTINUITY-1', request_id: 'REQ-CONTINUITY-1', content_type: 'text', content: 'รักษาข้อความนี้ทุกตัวอักษร: READY → RUNNING → COMPLETED', attachments: [] };
    const first = await handleAxAdaptersRoute(new Request('https://example.test/ax/direct/input', { method: 'POST', headers: { Authorization: 'Bearer test-secret' }, body: JSON.stringify(body) }), env);
    expect(first?.status).toBe(201);
    expect(sent).toHaveLength(1);
    expect(sent[0].taskId).toBe(body.task_id);
    expect(sent[0].action).toBe(body.content);

    const second = await handleAxAdaptersRoute(new Request('https://example.test/ax/direct/input', { method: 'POST', headers: { Authorization: 'Bearer test-secret' }, body: JSON.stringify(body) }), env);
    expect(second?.status).toBe(200);
    expect(sent).toHaveLength(1);
  });

  it('rejects a different command under the same mission id', async () => {
    const { env } = makeEnv();
    const first = { mission_id: 'MISSION-COLLISION-1', task_id: 'TASK-1', request_id: 'REQ-1', content_type: 'text', content: 'alpha', attachments: [] };
    const second = { ...first, request_id: 'REQ-2', content: 'beta' };
    await handleAxAdaptersRoute(new Request('https://example.test/ax/direct/input', { method: 'POST', headers: { Authorization: 'Bearer test-secret' }, body: JSON.stringify(first) }), env);
    const result = await handleAxAdaptersRoute(new Request('https://example.test/ax/direct/input', { method: 'POST', headers: { Authorization: 'Bearer test-secret' }, body: JSON.stringify(second) }), env);
    expect(result?.status).toBe(409);
  });
});
