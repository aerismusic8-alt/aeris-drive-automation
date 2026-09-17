import test from 'node:test';
import assert from 'node:assert/strict';
import { runOnce } from './ax-runtime.mjs';

test('one runtime cycle reaches DONE only after verification',async()=>{
  const registry={tasks:[{task_id:'j1',status:'PENDING',deadline_at:'2099-01-01T00:00:00Z',completion_criteria:['result']}]};
  const state={runtimeStatus:'ONLINE',nodeId:'PC1-MAIN'}; const evidence=[];
  const result=await runOnce({registry,state,now:new Date('2026-09-16T00:00:00Z'),dispatch:async()=>({ok:true,result:'ok',evidence:{jobId:'j1',event:'RESULT',verification:{verified:true}}}),appendEvidence:async(r)=>evidence.push(r)});
  assert.equal(result.status,'DONE'); assert.equal(registry.tasks[0].status,'DONE'); assert.equal(evidence.length,1); assert.equal(state.lastVerifiedJob,'j1');
});

test('overdue job is not silently completed',async()=>{
  const registry={tasks:[{task_id:'j2',status:'PENDING',deadline_at:'2020-01-01T00:00:00Z'}]};
  await runOnce({registry,state:{runtimeStatus:'ONLINE',nodeId:'PC1-MAIN'},now:new Date('2026-09-16T00:00:00Z'),dispatch:async()=>{throw new Error('must not dispatch');},appendEvidence:async()=>{}});
  assert.equal(registry.tasks[0].status,'OVERDUE');
});

test('evidence persistence failure cannot leave a job COMPLETED',async()=>{
  const registry={tasks:[{task_id:'j3',status:'PENDING',deadline_at:'2099-01-01T00:00:00Z'}]};
  const state={runtimeStatus:'ONLINE',nodeId:'PC1-MAIN'};
  const result=await runOnce({registry,state,now:new Date('2026-09-16T00:00:00Z'),dispatch:async()=>({ok:true,result:'ok',evidence:{jobId:'j3',event:'RESULT',verification:{verified:true}}}),appendEvidence:async()=>{throw new Error('disk unavailable');}});
  assert.equal(result.status,'FAILED');
  assert.equal(registry.tasks[0].status,'FAILED');
});
