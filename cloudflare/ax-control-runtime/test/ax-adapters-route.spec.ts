import { describe, expect, it, vi } from 'vitest';
import { handleAxAdaptersRoute } from '../src/ax-adapters-route';

describe('AX adapters route', () => {
  const env = {
    AX_MOBILE_INGRESS_SECRET: 'control-secret',
    GEMINI_ACCOUNT_1: 'g1-secret',
    GEMINI_ACCOUNT_2: 'g2-secret',
    GEMINI_ACCOUNT_3: 'g3-secret',
    GOOGLE_DRIVE_CREDENTIAL: 'drive-secret',
  };

  it('rejects unauthenticated adapter requests', async () => {
    const response = await handleAxAdaptersRoute(
      new Request('https://ax.local/ax/adapters/status'),
      env,
    );
    expect(response?.status).toBe(401);
    await expect(response?.json()).resolves.toEqual({ error: 'AUTH_REQUIRED' });
  });

  it('returns sanitized adapter configuration status', async () => {
    const response = await handleAxAdaptersRoute(
      new Request('https://ax.local/ax/adapters/status', {
        headers: { Authorization: 'Bearer control-secret' },
      }),
      env,
    );
    expect(response?.status).toBe(200);
    const body = await response?.json();
    expect(body).toEqual({
      gemini: { configuredAccounts: 3 },
      drive: { configured: true },
    });
    const serialized = JSON.stringify(body);
    expect(serialized).not.toContain('g1-secret');
    expect(serialized).not.toContain('g2-secret');
    expect(serialized).not.toContain('g3-secret');
    expect(serialized).not.toContain('drive-secret');
    expect(serialized).not.toContain('control-secret');
  });

  it('routes Gemini generation through Triple Gemini failover', async () => {
    const attempts: string[] = [];
    const generate = vi.fn(async (account: { id: string; apiKey: string }, prompt: string) => {
      attempts.push(account.id);
      if (account.id === 'G1') return { ok: false as const, error: 'GEMINI_UPSTREAM_HTTP_503' };
      return { ok: true as const, text: `done:${prompt}` };
    });
    const response = await handleAxAdaptersRoute(
      new Request('https://ax.local/ax/gemini/generate', {
        method: 'POST',
        headers: {
          Authorization: 'Bearer control-secret',
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ prompt: 'work' }),
      }),
      env,
      { generateGemini: generate },
    );
    expect(response?.status).toBe(200);
    await expect(response?.json()).resolves.toEqual({ ok: true, text: 'done:work', accountId: 'G2' });
    expect(attempts).toEqual(['G1', 'G2']);
  });

  it('routes Drive list through the configured adapter', async () => {
    const fetchImpl = vi.fn(async (_url: string, init?: RequestInit) => {
      expect(init?.headers).toEqual({ Authorization: 'Bearer drive-secret' });
      return new Response(JSON.stringify({ files: [{ id: 'f1', name: 'AKATH' }] }), { status: 200 });
    });
    const response = await handleAxAdaptersRoute(
      new Request('https://ax.local/ax/drive/list?q=AKATH', {
        headers: { Authorization: 'Bearer control-secret' },
      }),
      env,
      { driveFetch: fetchImpl },
    );
    expect(response?.status).toBe(200);
    await expect(response?.json()).resolves.toEqual({ ok: true, files: [{ id: 'f1', name: 'AKATH' }] });
  });
});
