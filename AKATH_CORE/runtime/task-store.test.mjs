import test from 'node:test';
import assert from 'node:assert/strict';
import { claimNextEligibleJob, transitionJob } from './task-store.mjs';

test('claims only an eligible pending job', () => {
  const registry={tasks:[{task_id:'j1',status:'PENDING',deadline_at:'2099-01-01T00:00:00Z'},{task_id:'j2',status:'DONE'}]};
  const job=claimNextEligibleJob(registry,new Date('2026-09-16T00:00:00Z'));
  assert.equal(job.task_id,'j1'); assert.equal(job.status,'EXECUTING');
});

test('allows EXECUTING to COMPLETED but not DONE directly', () => {
  const job={task_id:'j1',status:'EXECUTING'};
  assert.equal(transitionJob(job,'COMPLETED',{}).status,'COMPLETED');
  assert.throws(()=>transitionJob(job,'DONE',{}),/Illegal transition/);
});
