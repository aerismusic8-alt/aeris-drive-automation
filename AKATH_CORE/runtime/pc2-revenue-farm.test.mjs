import assert from 'node:assert/strict';
import { planNextRevenueJob } from './pc2-revenue-planner.mjs';

const registry = { tasks: [] };
const first = planNextRevenueJob(registry, new Date('2026-09-17T03:00:00Z'));
assert.equal(first?.capability, 'revenue');
assert.equal(first?.action, 'youtube_short_package');
assert.equal(first?.payload?.channel, 'AERISMusicTH');
assert.equal(first?.payload?.autonomous, true);
assert.equal(first?.status, 'PENDING');
assert.match(first?.task_id ?? '', /^PC2-REV-YT-SHORT-1-/);

registry.tasks.push(first);
assert.equal(planNextRevenueJob(registry, new Date('2026-09-17T03:00:01Z')), null);

first.status = 'DONE';
const second = planNextRevenueJob(registry, new Date('2026-09-17T03:00:02Z'));
assert.equal(second?.capability, 'revenue');
assert.equal(second?.action, 'youtube_short_package');
assert.match(second?.task_id ?? '', /^PC2-REV-YT-SHORT-2-/);

console.log('PASS PC2 revenue farm planner contract');
