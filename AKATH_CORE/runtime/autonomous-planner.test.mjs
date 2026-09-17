import assert from 'node:assert/strict';
import { planNextTask } from './autonomous-planner.mjs';

const registry = {
  tasks: [{ task_id: 'AKATH-EXECUTION-E2E-001', status: 'DONE' }]
};

const next = planNextTask(registry, new Date('2026-09-16T12:00:00Z'));
assert.equal(next.task_id, 'AKATH-AUTONOMOUS-SELF-CHECK-001');
assert.equal(next.status, 'PENDING');
assert.equal(next.payload.capability, 'self_check');
assert.ok(next.deadline_at);
assert.equal(registry.tasks.length, 2);

const second = planNextTask(registry, new Date('2026-09-16T12:01:00Z'));
assert.equal(second, null);

const failedRegistry = {
  tasks: [{ task_id: 'AKATH-AUTONOMOUS-SELF-CHECK-001', status: 'FAILED' }]
};
const recovery = planNextTask(failedRegistry, new Date('2026-09-16T12:02:00Z'));
assert.equal(recovery.payload.capability, 'recovery');
assert.equal(recovery.payload.failed_task_id, 'AKATH-AUTONOMOUS-SELF-CHECK-001');
assert.equal(recovery.status, 'PENDING');

console.log('PASS autonomous planner');
