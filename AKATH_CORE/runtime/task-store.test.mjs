import test from 'node:test';
import assert from 'node:assert/strict';
import { claimNextEligibleJob, transitionJob } from './task-store.mjs';

test('claims only an eligible pending job', () => {
  const registry={tasks:[{task_id:'j1',status:'PENDING',deadline_at:'2099-01-01T00:00:00Z'},{task_id:'j2',status:'DONE'}]};
  const job=claimNextEligibleJob(registry,new Date('2026-09-16T00:00:00Z'));
  assert.equal(job.task_id,'j1'); assert.equal(job.status,'EXECUTING');
});

test('prioritizes the active canonical task over stale pending tasks', () => {
  const registry={
    current_work:{active:true,task_id:'current'},
    tasks:[
      {task_id:'stale',status:'PENDING',deadline_at:'2026-09-17T05:30:00.000Z'},
      {task_id:'current',status:'PENDING',deadline_at:'2026-09-17T07:00:00.000Z',capability:'control'}
    ]
  };
  const job=claimNextEligibleJob(registry,new Date('2026-09-17T06:29:30.000Z'));
  assert.equal(job?.task_id,'current');
  assert.equal(job?.status,'EXECUTING');
  assert.equal(registry.tasks.find((task)=>task.task_id==='stale').status,'PENDING');
});

test('allows EXECUTING to COMPLETED but not DONE directly', () => {
  const job={task_id:'j1',status:'EXECUTING'};
  assert.equal(transitionJob(job,'COMPLETED',{}).status,'COMPLETED');
  assert.throws(()=>transitionJob(job,'DONE',{}),/Illegal transition/);
});
