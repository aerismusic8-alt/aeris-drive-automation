import assert from 'node:assert/strict';
import { planNextTask } from './autonomous-planner.mjs';

const registry = {
  tasks: [{ task_id: 'AKATH-EXECUTION-E2E-001', status: 'DONE' }]
};

const first = planNextTask(registry, new Date('2026-09-17T02:00:00Z'));
assert.equal(first.task_id, 'AKATH-AUTONOMOUS-SELF-CHECK-001');
assert.equal(first.status, 'PENDING');
assert.equal(first.capability, 'self_check');
assert.equal(first.action, 'pc1_runtime_self_check');
assert.equal(first.payload.capability, 'self_check');
assert.ok(first.deadline_at);
assert.equal(registry.tasks.length, 2);

const blockedWhilePending = planNextTask(registry, new Date('2026-09-17T02:00:01Z'));
assert.equal(blockedWhilePending, null);

registry.tasks[1].status = 'DONE';
const second = planNextTask(registry, new Date('2026-09-17T02:00:02Z'));
assert.equal(second.capability, 'recovery');
assert.equal(second.action, 'pc1_recovery_path_check');
assert.equal(second.task_id, 'AKATH-AUTONOMOUS-RECOVERY-CHECK-001');
assert.equal(second.status, 'PENDING');

registry.tasks[2].status = 'DONE';
const recurring = planNextTask(registry, new Date('2026-09-17T02:00:03Z'));
assert.equal(recurring.capability, 'self_check');
assert.equal(recurring.task_id, 'AKATH-AUTONOMOUS-SELF-CHECK-002');
assert.equal(recurring.status, 'PENDING');
assert.notEqual(recurring.task_id, first.task_id);

const failedRegistry = {
  tasks: [{ task_id: 'AKATH-AUTONOMOUS-SELF-CHECK-001', status: 'FAILED' }]
};
const recovery = planNextTask(failedRegistry, new Date('2026-09-17T02:01:00Z'));
assert.equal(recovery.capability, 'recovery');
assert.equal(recovery.payload.capability, 'recovery');
assert.equal(recovery.payload.failed_task_id, 'AKATH-AUTONOMOUS-SELF-CHECK-001');
assert.equal(recovery.status, 'PENDING');

recovery.status = 'DONE';
const recoveryAfterDone = planNextTask(failedRegistry, new Date('2026-09-17T02:01:01Z'));
assert.equal(recoveryAfterDone.capability, 'self_check');
assert.equal(recoveryAfterDone.task_id, 'AKATH-AUTONOMOUS-SELF-CHECK-002');
assert.equal(recoveryAfterDone.status, 'PENDING');

console.log('PASS autonomous planner');
