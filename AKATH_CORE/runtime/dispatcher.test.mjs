import test from 'node:test';
import assert from 'node:assert/strict';
import { dispatchToPc1 } from './dispatcher.mjs';

test('dispatcher sends the leased job to PC1 adapter',async()=>{
  const job={task_id:'j1',status:'EXECUTING'};
  const result=await dispatchToPc1(job,{execute:async(input)=>({ok:true,result:'ok',evidence:{jobId:input.task_id,event:'RESULT',verification:{verified:true}}})});
  assert.equal(result.result,'ok'); assert.equal(result.evidence.jobId,'j1');
});
