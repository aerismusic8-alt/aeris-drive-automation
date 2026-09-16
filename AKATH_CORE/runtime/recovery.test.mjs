import test from 'node:test';
import assert from 'node:assert/strict';
import { recoverJob } from './recovery.mjs';

test('recovery records cause and correction before requeue',()=>{
  const job={task_id:'j1',status:'EXECUTING'};
  recoverJob(job,'worker_timeout',new Date('2026-09-16T00:00:00Z'));
  assert.equal(job.status,'PENDING'); assert.equal(job.root_cause,'worker_timeout'); assert.ok(job.correction);
});
