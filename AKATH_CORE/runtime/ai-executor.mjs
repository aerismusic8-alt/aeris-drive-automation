const DEFAULT_BASE_URL = 'https://generativelanguage.googleapis.com/v1beta';
const DEFAULT_MODEL = 'gemini-3.6-flash';

export async function executeAiTask(job, {
  fetchImpl = globalThis.fetch,
  apiKey = process.env.GEMINI_API_KEY,
  baseUrl = process.env.AX_AI_BASE_URL || DEFAULT_BASE_URL
} = {}) {
  if (typeof fetchImpl !== 'function') throw new Error('AI executor requires fetch');
  if (!apiKey) throw new Error('GEMINI_API_KEY is required for AI capability');
  if (!job?.prompt) throw new Error('AI task prompt is required');

  const model = job.model || process.env.AX_AI_MODEL || DEFAULT_MODEL;
  const endpoint = `${baseUrl.replace(/\/$/, '')}/models/${encodeURIComponent(model)}:generateContent`;
  const response = await fetchImpl(endpoint, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'x-goog-api-key': apiKey
    },
    body: JSON.stringify({
      contents: [{ parts: [{ text: job.prompt }] }],
      ...(job.system_instruction
        ? { systemInstruction: { parts: [{ text: job.system_instruction }] } }
        : {})
    })
  });

  const payload = await response.json();
  if (!response.ok) {
    const message = payload?.error?.message || `Gemini API HTTP ${response.status}`;
    throw new Error(message);
  }

  const text = payload?.candidates?.[0]?.content?.parts
    ?.map((part) => part?.text || '')
    .join('')
    .trim();
  if (!text) throw new Error('Gemini API returned no text candidate');

  return {
    provider: 'gemini',
    model,
    text
  };
}
