import assert from 'node:assert/strict';
import { buildRecoveryRetry } from './recovery-planner-v2.mjs';

const registry = {
  tasks: [
    {
      task_id: 'AKATH-PC1-AI-PRODUCTION-001',
      capability: 'ai',
      status: 'FAILED',
      payload: { prompt: 'test prompt', capability: 'ai' }
    },
    {
      task_id: 'AKATH-AUTONOMOUS-RECOVERY-AKATH-PC1-AI-PRODUCTION-001',
      capability: 'recovery',
      status: 'DONE',
      payload: { failed_task_id: 'AKATH-PC1-AI-PRODUCTION-001' }
    }
  ]
};

const retry = buildRecoveryRetry(
  registry,
  registry.tasks[1],
  new Date('2026-09-17T05:10:00.000Z')
);

assert.ok(retry, 'recovery should produce a retry task');
assert.equal(retry.task_id, 'AKATH-PC1-AI-PRODUCTION-001-RETRY-1');
assert.equal(retry.status, 'PENDING');
assert.equal(retry.capability, 'ai');
assert.equal(retry.payload.prompt, 'test prompt');
assert.equal(retry.payload.recovery_of, 'AKATH-PC1-AI-PRODUCTION-001');
assert.equal(retry.payload.retry_attempt, 1);

console.log('PASS recovery planner real retry');
