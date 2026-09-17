import assert from 'node:assert/strict';
import { planNextTask } from './autonomous-planner.mjs';

const registry = { tasks: [{ task_id: 'AKATH-REAL-001', status: 'PENDING', type: 'WORK', capability: 'execution', action: 'pc1_execution' }] };
const realPending = planNextTask(registry, new Date('2026-09-17T02:00:00Z'));
assert.equal(realPending, null);
assert.equal(registry.tasks.length, 1);

const doneOnlyRegistry = { tasks: [{ task_id: 'AKATH-REAL-001', status: 'DONE', type: 'WORK' }] };
const continuation = planNextTask(doneOnlyRegistry, new Date('2026-09-17T02:00:01Z'));
assert.equal(continuation?.task_id, 'AKATH-PC1-AUTONOMOUS-CONTINUATION-001');
assert.equal(continuation?.capability, 'execution');
assert.equal(continuation?.action, 'runtime_identity');
assert.equal(continuation?.payload?.autonomous, true);

continuation.status = 'DONE';
const nextAction = planNextTask(doneOnlyRegistry, new Date('2026-09-17T02:00:02Z'));
assert.equal(nextAction?.capability, 'powershell');
assert.equal(nextAction?.action, 'runtime_process_snapshot');
assert.equal(nextAction?.payload?.action, 'runtime_process_snapshot');
assert.notEqual(nextAction?.task_id, continuation.task_id);

const failedRegistry = { tasks: [{ task_id: 'AKATH-REAL-001', status: 'FAILED', type: 'WORK' }] };
const recovery = planNextTask(failedRegistry, new Date('2026-09-17T02:01:00Z'));
assert.equal(recovery.capability, 'recovery');
assert.equal(recovery.action, 'pc1_recovery_path_check');
assert.equal(recovery.payload.failed_task_id, 'AKATH-REAL-001');

console.log('PASS autonomous planner');
