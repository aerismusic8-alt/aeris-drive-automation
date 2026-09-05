export type GeminiSuccess = { ok: true; text: string };
export type GeminiFailure = { ok: false; error: string };
export type GeminiResult = GeminiSuccess | GeminiFailure;

export type GenerateGeminiTextOptions = {
  apiKey: string;
  prompt: string;
  fetchImpl?: typeof fetch;
  model?: string;
};

const DEFAULT_MODEL = 'gemini-2.5-flash';
const API_BASE = 'https://generativelanguage.googleapis.com/v1beta/models';

export async function generateGeminiText({
  apiKey,
  prompt,
  fetchImpl = fetch,
  model = DEFAULT_MODEL,
}: GenerateGeminiTextOptions): Promise<GeminiResult> {
  if (!apiKey) return { ok: false, error: 'GEMINI_API_KEY_MISSING' };

  const url = `${API_BASE}/${encodeURIComponent(model)}:generateContent?key=${encodeURIComponent(apiKey)}`;
  const body = JSON.stringify({ contents: [{ parts: [{ text: prompt }] }] });

  try {
    const response = await fetchImpl(url, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body,
    });

    if (!response.ok) return { ok: false, error: `GEMINI_UPSTREAM_HTTP_${response.status}` };

    const data = await response.json() as {
      candidates?: Array<{ content?: { parts?: Array<{ text?: unknown }> } }>;
    };
    const text = data.candidates?.[0]?.content?.parts?.find(
      part => typeof part.text === 'string' && part.text.length > 0,
    )?.text;

    return typeof text === 'string'
      ? { ok: true, text }
      : { ok: false, error: 'GEMINI_RESPONSE_TEXT_MISSING' };
  } catch {
    return { ok: false, error: 'GEMINI_NETWORK_ERROR' };
  }
}
