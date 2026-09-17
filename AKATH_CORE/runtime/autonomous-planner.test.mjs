import assert from 'node:assert/strict';
import { planNextTask } from './autonomous-planner.mjs';

const registry = {
  tasks: [{
    task_id: 'AKATH-REAL-001',
    status: 'PENDING',
    type: 'WORK',
    capability: 'execution',
    action: 'pc1_execution'
  }]
};

const realPending = planNextTask(registry, new Date('2026-09-17T02:00:00Z'));
assert.equal(realPending, null);
assert.equal(registry.tasks.length, 1);
assert.equal(registry.tasks[0].task_id, 'AKATH-REAL-001');

const doneOnlyRegistry = {
  tasks: [{ task_id: 'AKATH-REAL-001', status: 'DONE', type: 'WORK' }]
};
const noSyntheticExecution = planNextTask(doneOnlyRegistry, new Date('2026-09-17T02:00:01Z'));
assert.equal(noSyntheticExecution, null);
assert.equal(doneOnlyRegistry.tasks.length, 1);

const failedRegistry = {
  tasks: [{ task_id: 'AKATH-REAL-001', status: 'FAILED', type: 'WORK' }]
};
const recovery = planNextTask(failedRegistry, new Date('2026-09-17T02:01:00Z'));
assert.equal(recovery.capability, 'recovery');
assert.equal(recovery.action, 'pc1_recovery_path_check');
assert.equal(recovery.payload.capability, 'recovery');
assert.equal(recovery.payload.failed_task_id, 'AKATH-REAL-001');
assert.equal(recovery.status, 'PENDING');

recovery.status = 'DONE';
const recoveryAfterDone = planNextTask(failedRegistry, new Date('2026-09-17T02:01:01Z'));
assert.ok(recoveryAfterDone);
assert.equal(recoveryAfterDone.task_id, 'AKATH-REAL-001-RETRY-1');
assert.equal(recoveryAfterDone.status, 'PENDING');
assert.equal(recoveryAfterDone.payload.recovery_of, 'AKATH-REAL-001');
assert.equal(failedRegistry.tasks.length, 3);

const retryRegistry = {
  tasks: [
    {
      task_id: 'AI-1',
      capability: 'ai',
      status: 'FAILED',
      payload: { prompt: 'retry me', capability: 'ai' }
    },
    {
      task_id: 'AKATH-AUTONOMOUS-RECOVERY-AI-1',
      capability: 'recovery',
      status: 'DONE',
      payload: { failed_task_id: 'AI-1' }
    }
  ]
};
const retry = planNextTask(retryRegistry, new Date('2026-09-17T02:02:00Z'));
assert.ok(retry);
assert.equal(retry.task_id, 'AI-1-RETRY-1');
assert.equal(retry.status, 'PENDING');
assert.equal(retry.capability, 'ai');
assert.equal(retry.payload.recovery_of, 'AI-1');

console.log('PASS autonomous planner');
