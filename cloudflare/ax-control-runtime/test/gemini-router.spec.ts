import { describe, expect, it } from 'vitest';
import { GeminiRouter } from '../src/gemini-router';

describe('GeminiRouter', () => {
  it('uses the first available account', async () => {
    const calls: string[] = [];
    const router = new GeminiRouter([
      { id: 'G1', apiKey: 'key-1' },
      { id: 'G2', apiKey: 'key-2' },
      { id: 'G3', apiKey: 'key-3' },
    ], async (account, prompt) => {
      calls.push(`${account.id}:${prompt}`);
      return { ok: true, text: 'OK' };
    });
    const result = await router.generate('test');
    expect(result).toEqual({ ok: true, text: 'OK', accountId: 'G1' });
    expect(calls).toEqual(['G1:test']);
  });

  it('fails over from a failed account to the next account', async () => {
    const calls: string[] = [];
    const router = new GeminiRouter([
      { id: 'G1', apiKey: 'key-1' },
      { id: 'G2', apiKey: 'key-2' },
      { id: 'G3', apiKey: 'key-3' },
    ], async (account) => {
      calls.push(account.id);
      return account.id === 'G1'
        ? { ok: false, error: 'GEMINI_UPSTREAM_HTTP_429' }
        : { ok: true, text: 'OK' };
    });
    const result = await router.generate('test');
    expect(result).toEqual({ ok: true, text: 'OK', accountId: 'G2' });
    expect(calls).toEqual(['G1', 'G2']);
  });

  it('does not reuse an account while it is in cooldown', async () => {
    let calls = 0;
    const router = new GeminiRouter([
      { id: 'G1', apiKey: 'key-1' },
      { id: 'G2', apiKey: 'key-2' },
    ], async (account) => {
      calls += 1;
      return account.id === 'G1'
        ? { ok: false, error: 'GEMINI_UPSTREAM_HTTP_429' }
        : { ok: true, text: 'OK' };
    }, { cooldownMs: 60_000 });
    await router.generate('first');
    const second = await router.generate('second');
    expect(second).toEqual({ ok: true, text: 'OK', accountId: 'G2' });
    expect(calls).toBe(3);
  });
});
