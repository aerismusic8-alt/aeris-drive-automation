import assert from 'node:assert/strict';
import { planRecoveryRetry } from './recovery-planner.mjs';

const failed = {
  task_id: 'AKATH-PC1-AI-PRODUCTION-001',
  capability: 'ai',
  status: 'FAILED',
  payload: { prompt: 'test prompt', capability: 'ai' }
};
const recovery = {
  task_id: 'AKATH-AUTONOMOUS-RECOVERY-AKATH-PC1-AI-PRODUCTION-001',
  capability: 'recovery',
  status: 'DONE',
  payload: { failed_task_id: 'AKATH-PC1-AI-PRODUCTION-001' }
};

const registry = { tasks: [failed, recovery] };
const retry = planRecoveryRetry(registry, recovery, new Date('2026-09-17T05:10:00.000Z'));
assert.ok(retry, 'recovery should produce a retry task');
assert.equal(retry.task_id, 'AKATH-PC1-AI-PRODUCTION-001-RETRY-1');
assert.equal(retry.status, 'PENDING');
assert.equal(retry.capability, 'ai');
assert.equal(retry.payload.prompt, 'test prompt');
assert.equal(retry.payload.recovery_of, 'AKATH-PC1-AI-PRODUCTION-001');
assert.equal(retry.payload.retry_attempt, 1);

const exhausted = {
  tasks: [
    failed,
    recovery,
    { ...retry, task_id: 'AKATH-PC1-AI-PRODUCTION-001-RETRY-1', status: 'FAILED' },
    { ...retry, task_id: 'AKATH-PC1-AI-PRODUCTION-001-RETRY-2', status: 'FAILED' },
    { ...retry, task_id: 'AKATH-PC1-AI-PRODUCTION-001-RETRY-3', status: 'FAILED' }
  ]
};
assert.equal(planRecoveryRetry(exhausted, recovery, new Date('2026-09-17T05:11:00.000Z')), null);

console.log('PASS recovery planner real retry');
