import { describe, expect, it } from 'vitest';
import { generateGeminiText } from '../src/gemini-adapter';

describe('Gemini adapter', () => {
  it('sends a prompt with the configured API key and returns model text', async () => {
    const calls: Array<{ url: string; init?: RequestInit }> = [];

    const fetchMock = async (url: string | URL, init?: RequestInit): Promise<Response> => {
      calls.push({ url: String(url), init });
      return new Response(JSON.stringify({
        candidates: [{
          content: {
            parts: [{ text: 'GEMINI_OK' }],
          },
        }],
      }), {
        status: 200,
        headers: { 'content-type': 'application/json' },
      });
    };

    const result = await generateGeminiText({
      apiKey: 'test-secret-key',
      prompt: 'Reply with GEMINI_OK',
      fetchImpl: fetchMock,
    });

    expect(result).toEqual({ ok: true, text: 'GEMINI_OK' });
    expect(calls).toHaveLength(1);
    expect(calls[0].url).toContain('generativelanguage.googleapis.com');
    expect(calls[0].url).toContain('key=test-secret-key');
    expect(calls[0].init?.method).toBe('POST');
    expect(String(calls[0].init?.body)).toContain('Reply with GEMINI_OK');
  });

  it('fails closed when the API key is missing', async () => {
    const result = await generateGeminiText({
      apiKey: '',
      prompt: 'test',
      fetchImpl: async () => {
        throw new Error('fetch must not be called');
      },
    });

    expect(result).toEqual({ ok: false, error: 'GEMINI_API_KEY_MISSING' });
  });

  it('does not expose the API key in an upstream error result', async () => {
    const secret = 'test-secret-key';
    const result = await generateGeminiText({
      apiKey: secret,
      prompt: 'test',
      fetchImpl: async () => new Response('upstream failure', { status: 500 }),
    });

    expect(result.ok).toBe(false);
    expect(result).toEqual({ ok: false, error: 'GEMINI_UPSTREAM_HTTP_500' });
    expect(JSON.stringify(result)).not.toContain(secret);
  });
});
