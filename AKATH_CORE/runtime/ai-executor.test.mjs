import assert from 'node:assert/strict';
import { executeAiTask } from './ai-executor.mjs';

const result = await executeAiTask({
  task_id: 'PC1-AI-TEST',
  prompt: 'Return exactly the word READY.',
  model: 'test-model'
}, {
  fetchImpl: async (url, options) => {
    assert.match(url, /test-model/);
    assert.equal(options.headers['x-goog-api-key'], 'test-key');
    const body = JSON.parse(options.body);
    assert.equal(body.contents[0].parts[0].text, 'Return exactly the word READY.');
    return {
      ok: true,
      status: 200,
      async json() {
        return { candidates: [{ content: { parts: [{ text: 'READY' }] } }] };
      }
    };
  },
  apiKey: 'test-key',
  baseUrl: 'https://example.test/v1beta'
});

assert.equal(result.text, 'READY');
assert.equal(result.model, 'test-model');
assert.equal(result.provider, 'gemini');
console.log('PASS AI executor');
