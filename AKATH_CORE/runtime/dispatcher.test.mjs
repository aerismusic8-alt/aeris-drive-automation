import test from 'node:test';
import assert from 'node:assert/strict';
import { dispatchToPc1, resolvePc1ExecutorCommand } from './dispatcher.mjs';

test('dispatcher sends the leased job to PC1 adapter',async()=>{
  const job={task_id:'j1',status:'EXECUTING'};
  const result=await dispatchToPc1(job,{execute:async(input)=>({ok:true,result:'ok',evidence:{jobId:input.task_id,event:'RESULT',verification:{verified:true}}})});
  assert.equal(result.result,'ok'); assert.equal(result.evidence.jobId,'j1');
});

test('PC1 executor binding is taken from AX_PC1_EXECUTOR_COMMAND',()=>{
  const previous = process.env.AX_PC1_EXECUTOR_COMMAND;
  try {
    process.env.AX_PC1_EXECUTOR_COMMAND = 'PC1-EXECUTOR-COMMAND';
    assert.equal(resolvePc1ExecutorCommand('PC1-MAIN'), 'PC1-EXECUTOR-COMMAND');
  } finally {
    if (previous === undefined) delete process.env.AX_PC1_EXECUTOR_COMMAND;
    else process.env.AX_PC1_EXECUTOR_COMMAND = previous;
  }
});

test('PC1 runtime fails closed when executor binding is missing',()=>{
  const previous = process.env.AX_PC1_EXECUTOR_COMMAND;
  try {
    delete process.env.AX_PC1_EXECUTOR_COMMAND;
    assert.throws(() => resolvePc1ExecutorCommand('PC1-MAIN'), /AX_PC1_EXECUTOR_COMMAND/);
  } finally {
    if (previous === undefined) delete process.env.AX_PC1_EXECUTOR_COMMAND;
    else process.env.AX_PC1_EXECUTOR_COMMAND = previous;
  }
});
