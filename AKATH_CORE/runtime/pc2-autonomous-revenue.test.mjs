import assert from 'node:assert/strict';
import { planNextTask } from './autonomous-planner.mjs';

const registry = { tasks: [{ task_id: 'AKATH-REAL-001', status: 'DONE', type: 'WORK' }] };

let task = planNextTask(registry, new Date('2026-09-17T04:00:00Z'));
assert.equal(task?.capability, 'execution');
task.status = 'DONE';

for (let i = 0; i < 3; i++) {
  task = planNextTask(registry, new Date(`2026-09-17T04:00:0${i + 1}Z`));
  assert.equal(task?.capability, 'powershell');
  task.status = 'DONE';
}

const revenue = planNextTask(registry, new Date('2026-09-17T04:00:04Z'));
assert.equal(revenue?.capability, 'revenue');
assert.equal(revenue?.action, 'youtube_short_package');
assert.equal(revenue?.payload?.channel, 'AERISMusicTH');
assert.equal(revenue?.payload?.autonomous, true);
assert.equal(revenue?.status, 'PENDING');

console.log('PASS PC2 autonomous revenue integration contract');
