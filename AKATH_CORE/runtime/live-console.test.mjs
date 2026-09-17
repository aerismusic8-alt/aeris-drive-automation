import assert from 'node:assert/strict';
import test from 'node:test';
import { formatLiveEvent } from './live-console.mjs';

test('formats production bot events as a visible execution loop', () => {
  const line = formatLiveEvent({
    at: '2026-09-17T10:00:00.000Z',
    event: 'EXECUTE',
    taskId: 'PRODUCT-001',
    detail: 'PC1_MAIN_SPECIALIST'
  });

  assert.equal(
    line,
    '[2026-09-17T10:00:00.000Z] EXECUTE task=PRODUCT-001 detail=PC1_MAIN_SPECIALIST'
  );
});

test('formats reconnect events so recovery is visible', () => {
  const line = formatLiveEvent({
    at: '2026-09-17T10:00:05.000Z',
    event: 'RECONNECT',
    detail: 'attempt=2'
  });

  assert.equal(line, '[2026-09-17T10:00:05.000Z] RECONNECT detail=attempt=2');
});
