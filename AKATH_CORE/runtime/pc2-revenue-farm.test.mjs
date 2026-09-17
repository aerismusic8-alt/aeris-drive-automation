import assert from 'node:assert/strict';
import { planNextTask } from './autonomous-planner.mjs';

const registry = { tasks: [{ task_id: 'AKATH-REAL-001', status: 'DONE', type: 'WORK' }] };
const continuation = planNextTask(registry, new Date('2026-09-17T03:00:00Z'));
assert.equal(continuation?.capability, 'execution');
continuation.status = 'DONE';

const revenueTask = planNextTask(registry, new Date('2026-09-17T03:00:01Z'));
assert.equal(revenueTask?.capability, 'revenue');
assert.equal(revenueTask?.action, 'youtube_short_package');
assert.equal(revenueTask?.payload?.channel, 'AERISMusicTH');
assert.equal(revenueTask?.payload?.autonomous, true);
assert.equal(revenueTask?.status, 'PENDING');

console.log('PASS PC2 revenue farm planner contract');
