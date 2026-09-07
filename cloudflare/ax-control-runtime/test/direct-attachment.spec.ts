import { describe, expect, it, vi } from 'vitest';
import { handleAxAdaptersRoute } from '../src/ax-adapters-route';

describe('AX direct attachment route', () => {
  it('forwards an authorized attachment to the mission ledger', async () => {
    const missionStub = {
      fetch: vi.fn(async (url: string, init?: RequestInit) => {
        expect(url).toContain('/attachment?');
        expect(init?.method).toBe('POST');
        expect(init?.headers).toMatchObject({ 'content-type': 'image/jpeg' });
        return Response.json({
          ok: true,
          attachment: {
            attachment_id: 'ATT-1',
            mission_id: 'MISSION-1',
            name: 'shot.jpg',
            media_type: 'image/jpeg',
            size: 3,
            uploaded_at: '2026-09-08T00:00:00.000Z',
          },
        }, { status: 201 });
      }),
    };

    const env = {
      AX_MOBILE_INGRESS_SECRET: 'secret',
      AX_MISSION_LEDGER: {
        idFromName: vi.fn(() => 'id'),
        get: vi.fn(() => missionStub),
      },
      AX_EXECUTION_QUEUE: undefined,
    } as never;

    const request = new Request('https://ax.example/ax/direct/attachment', {
      method: 'POST',
      headers: {
        Authorization: 'Bearer secret',
        'Content-Type': 'image/jpeg',
        'X-AX-Mission-Id': 'MISSION-1',
        'X-AX-Attachment-Id': 'ATT-1',
        'X-AX-Attachment-Name': 'shot.jpg',
      },
      body: new Uint8Array([1, 2, 3]),
    });

    const response = await handleAxAdaptersRoute(request, env);
    expect(response).not.toBeNull();
    expect(response?.status).toBe(201);
    await expect(response?.json()).resolves.toMatchObject({
      ok: true,
      attachment: { attachment_id: 'ATT-1', mission_id: 'MISSION-1', name: 'shot.jpg' },
    });
    expect(missionStub.fetch).toHaveBeenCalledTimes(1);
  });
});
