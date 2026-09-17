import assert from 'node:assert/strict';
import { mergeCanonicalTasks } from './canonical-sync.mjs';

const local = {
  tasks: [
    { task_id: 'AKATH-DONE-001', status: 'DONE' },
    { task_id: 'AKATH-PENDING-001', status: 'PENDING' }
  ]
};

const remote = {
  tasks: [
    { task_id: 'AKATH-DONE-001', status: 'PENDING' },
    { task_id: 'AKATH-PENDING-001', status: 'PENDING' },
    { task_id: 'AKATH-REMOTE-002', status: 'PENDING', capability: 'execution' }
  ]
};

const result = mergeCanonicalTasks(local, remote);
assert.equal(result.added, 1);
assert.equal(result.preserved, 2);
assert.equal(local.tasks.length, 3);
assert.equal(local.tasks.find((task) => task.task_id === 'AKATH-DONE-001').status, 'DONE');
assert.equal(local.tasks.find((task) => task.task_id === 'AKATH-REMOTE-002').status, 'PENDING');

console.log('PASS canonical sync');
