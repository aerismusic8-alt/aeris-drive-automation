import test from 'node:test';
import assert from 'node:assert/strict';
import { normalizeCodeStream } from './dashboard-data.mjs';

test('normalizes a live code stream and preserves verified execution metadata', () => {
  const result = normalizeCodeStream({
    schema: 'AX_CODE_STREAM_V1',
    status: 'WRITING',
    agent: 'OPENAI',
    taskId: 'TASK-001',
    file: 'dashboard/index.html',
    startedAt: '2026-09-07T14:00:00Z',
    updatedAt: '2026-09-07T14:00:02Z',
    lines: [
      { seq: 1, kind: 'stdout', text: 'creating dashboard component' },
      { seq: 2, kind: 'code', text: 'const refresh = () => load();' }
    ]
  });

  assert.equal(result.schema, 'AX_CODE_STREAM_V1');
  assert.equal(result.status, 'WRITING');
  assert.equal(result.agent, 'OPENAI');
  assert.equal(result.taskId, 'TASK-001');
  assert.equal(result.file, 'dashboard/index.html');
  assert.equal(result.lines.length, 2);
  assert.equal(result.lines[1].kind, 'code');
  assert.equal(result.lines[1].text, 'const refresh = () => load();');
});

test('fails closed when the stream is not verified', () => {
  assert.throws(() => normalizeCodeStream({ status: 'WRITING', lines: [] }), /AX_CODE_STREAM_V1/);
});
