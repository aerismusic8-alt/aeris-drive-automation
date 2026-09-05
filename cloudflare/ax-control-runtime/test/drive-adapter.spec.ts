import { describe, expect, it } from 'vitest';
import { DriveAdapter } from '../src/drive-adapter';

describe('DriveAdapter', () => {
  it('lists files using the configured credential without exposing it', async () => {
    const calls: Array<{ url: string; headers?: HeadersInit }> = [];
    const adapter = new DriveAdapter('drive-secret', async (url, init) => {
      calls.push({ url: String(url), headers: init?.headers });
      return new Response(JSON.stringify({ files: [{ id: 'f1', name: 'state.json' }] }), {
        status: 200,
        headers: { 'content-type': 'application/json' },
      });
    });

    const result = await adapter.list('state');

    expect(result).toEqual({ ok: true, files: [{ id: 'f1', name: 'state.json' }] });
    expect(calls).toHaveLength(1);
    expect(calls[0].url).toContain('www.googleapis.com/drive/v3/files');
    expect(JSON.stringify(result)).not.toContain('drive-secret');
  });

  it('fails closed when the Drive credential is missing', async () => {
    const result = await new DriveAdapter('', async () => {
      throw new Error('fetch must not be called');
    }).list('state');
    expect(result).toEqual({ ok: false, error: 'GOOGLE_DRIVE_CREDENTIAL_MISSING' });
  });

  it('maps upstream failures to sanitized errors', async () => {
    const result = await new DriveAdapter('drive-secret', async () =>
      new Response('failure', { status: 403 }),
    ).list('state');
    expect(result).toEqual({ ok: false, error: 'GOOGLE_DRIVE_HTTP_403' });
    expect(JSON.stringify(result)).not.toContain('drive-secret');
  });
});
