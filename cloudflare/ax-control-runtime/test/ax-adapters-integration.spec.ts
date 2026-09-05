import { describe, expect, it, vi } from 'vitest';
import { GeminiRouter } from '../src/gemini-router';
import { DriveAdapter } from '../src/drive-adapter';

type IntegrationEnv = {
  GEMINI_ACCOUNT_1?: string;
  GEMINI_ACCOUNT_2?: string;
  GEMINI_ACCOUNT_3?: string;
  GOOGLE_DRIVE_CREDENTIAL?: string;
};

function buildRouterFromEnv(env: IntegrationEnv, generate: ConstructorParameters<typeof GeminiRouter>[1]) {
  return new GeminiRouter(
    [env.GEMINI_ACCOUNT_1, env.GEMINI_ACCOUNT_2, env.GEMINI_ACCOUNT_3]
      .map((apiKey, index) => apiKey ? { id: `G${index + 1}`, apiKey } : null)
      .filter((account): account is { id: string; apiKey: string } => Boolean(account)),
    generate,
  );
}

describe('AX adapter integration', () => {
  it('builds Triple Gemini Router from secret bindings without exposing secrets', async () => {
    const env: IntegrationEnv = {
      GEMINI_ACCOUNT_1: 'secret-g1',
      GEMINI_ACCOUNT_2: 'secret-g2',
      GEMINI_ACCOUNT_3: 'secret-g3',
    };
    const seen: string[] = [];
    const generate = vi.fn(async (account: { id: string; apiKey: string }, prompt: string) => {
      seen.push(account.apiKey);
      return { ok: true as const, text: `reply:${prompt}` };
    });

    const router = buildRouterFromEnv(env, generate);
    const result = await router.generate('hello');

    expect(result).toEqual({ ok: true, text: 'reply:hello', accountId: 'G1' });
    expect(seen).toEqual(['secret-g1']);
    expect(JSON.stringify(result)).not.toContain('secret-g1');
    expect(JSON.stringify(result)).not.toContain('secret-g2');
    expect(JSON.stringify(result)).not.toContain('secret-g3');
  });

  it('fails over through configured Gemini accounts', async () => {
    const env: IntegrationEnv = {
      GEMINI_ACCOUNT_1: 'secret-g1',
      GEMINI_ACCOUNT_2: 'secret-g2',
      GEMINI_ACCOUNT_3: 'secret-g3',
    };
    const attempts: string[] = [];
    const generate = vi.fn(async (account: { id: string; apiKey: string }) => {
      attempts.push(account.id);
      if (account.id !== 'G3') return { ok: false as const, error: 'GEMINI_UPSTREAM_HTTP_503' };
      return { ok: true as const, text: 'ok' };
    });

    const router = buildRouterFromEnv(env, generate);
    expect(await router.generate('work')).toEqual({ ok: true, text: 'ok', accountId: 'G3' });
    expect(attempts).toEqual(['G1', 'G2', 'G3']);
  });

  it('builds Drive Adapter from credential binding and keeps credential out of results', async () => {
    const env: IntegrationEnv = { GOOGLE_DRIVE_CREDENTIAL: 'drive-secret' };
    const fetchImpl = vi.fn(async (_url: string, init?: RequestInit) => {
      expect(init?.headers).toEqual({ Authorization: 'Bearer drive-secret' });
      return new Response(JSON.stringify({ files: [{ id: 'f1', name: 'AKATH' }] }), { status: 200 });
    });

    const adapter = new DriveAdapter(env.GOOGLE_DRIVE_CREDENTIAL || '', fetchImpl);
    const result = await adapter.list();

    expect(result).toEqual({ ok: true, files: [{ id: 'f1', name: 'AKATH' }] });
    expect(JSON.stringify(result)).not.toContain('drive-secret');
  });

  it('fails closed when Drive credential is absent', async () => {
    const adapter = new DriveAdapter('');
    await expect(adapter.list()).resolves.toEqual({ ok: false, error: 'GOOGLE_DRIVE_CREDENTIAL_MISSING' });
  });
});
