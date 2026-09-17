import assert from 'node:assert/strict';
import { mergeCanonicalTasks } from './canonical-sync.mjs';

const local = {
  current_work: { active: true, task_id: 'AKATH-BRIDGE-001' },
  tasks: [
    { task_id: 'AKATH-DONE-001', status: 'DONE' },
    { task_id: 'AKATH-PENDING-001', status: 'PENDING' },
    { task_id: 'AKATH-AI-PRODUCTION-001', status: 'FAILED', capability: 'ai' },
    { task_id: 'AKATH-BRIDGE-002', status: 'DONE', capability: 'control' }
  ]
};

const remote = {
  current_work: { active: true, task_id: 'AKATH-BRIDGE-002' },
  tasks: [
    { task_id: 'AKATH-DONE-001', status: 'PENDING' },
    { task_id: 'AKATH-PENDING-001', status: 'PENDING' },
    { task_id: 'AKATH-AI-PRODUCTION-001', status: 'PENDING', capability: 'ai' },
    { task_id: 'AKATH-BRIDGE-002', status: 'PENDING', capability: 'control' },
    { task_id: 'AKATH-REMOTE-002', status: 'PENDING', capability: 'execution' }
  ]
};

const result = mergeCanonicalTasks(local, remote);
assert.equal(result.added, 1);
assert.equal(result.preserved, 2);
assert.equal(result.requeued, 2);
assert.equal(local.current_work.task_id, 'AKATH-BRIDGE-002');
assert.equal(local.tasks.length, 5);
assert.equal(local.tasks.find((task) => task.task_id === 'AKATH-DONE-001').status, 'DONE');
assert.equal(local.tasks.find((task) => task.task_id === 'AKATH-AI-PRODUCTION-001').status, 'PENDING');
assert.equal(local.tasks.find((task) => task.task_id === 'AKATH-BRIDGE-002').status, 'PENDING');
assert.equal(local.tasks.find((task) => task.task_id === 'AKATH-REMOTE-002').status, 'PENDING');

console.log('PASS canonical sync');
