import test from 'node:test';
import assert from 'node:assert/strict';
import { verifyJobResult } from './verifier.mjs';

test('verification requires result, evidence and explicit verification',()=>{
  assert.equal(verifyJobResult({task_id:'j1'},{result:null}).verified,false);
  assert.equal(verifyJobResult({task_id:'j1',result:'ok'},{result:'ok',verification:{verified:true}}).verified,true);
});
