import { describe, expect, it } from 'vitest';
import { handleGeminiLiveProbe } from '../src/gemini-live-probe';

describe('Gemini live probe', () => {
  it('returns a sanitized success marker for an authenticated request', async () => {
    const response = await handleGeminiLiveProbe(
      new Request('https://worker.test/gemini/test', {
        method: 'POST',
        headers: { Authorization: 'Bearer internal-test-secret' },
      }),
      {
        GEMINI_API_KEY: 'test-gemini-key',
        AX_MOBILE_INGRESS_SECRET: 'internal-test-secret',
        fetchImpl: async () => new Response(JSON.stringify({
          candidates: [{ content: { parts: [{ text: 'GEMINI_LIVE_OK' }] } }],
        }), { status: 200 }),
      },
    );

    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ ok: true, status: 'GEMINI_LIVE_OK' });
  });

  it('rejects unauthenticated requests without calling Gemini', async () => {
    let calls = 0;
    const response = await handleGeminiLiveProbe(
      new Request('https://worker.test/gemini/test', { method: 'POST' }),
      {
        GEMINI_API_KEY: 'test-gemini-key',
        AX_MOBILE_INGRESS_SECRET: 'internal-test-secret',
        fetchImpl: async () => { calls += 1; return new Response('{}', { status: 200 }); },
      },
    );

    expect(response.status).toBe(401);
    expect(await response.json()).toEqual({ error: 'AUTH_REQUIRED' });
    expect(calls).toBe(0);
  });

  it('fails closed when the Gemini key is missing', async () => {
    const response = await handleGeminiLiveProbe(
      new Request('https://worker.test/gemini/test', {
        method: 'POST',
        headers: { Authorization: 'Bearer internal-test-secret' },
      }),
      {
        GEMINI_API_KEY: '',
        AX_MOBILE_INGRESS_SECRET: 'internal-test-secret',
        fetchImpl: async () => new Response('{}', { status: 200 }),
      },
    );

    expect(response.status).toBe(503);
    expect(await response.json()).toEqual({ error: 'GEMINI_API_KEY_MISSING' });
  });
});
