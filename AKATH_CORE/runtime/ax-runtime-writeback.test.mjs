import test from 'node:test';
import assert from 'node:assert/strict';
import { runOnce } from './ax-runtime.mjs';

test('verified execution remains DONE when canonical write-back fails', async () => {
  const registry={tasks:[{task_id:'WB-FAIL-1',status:'PENDING',capability:'execution'}]};
  const state={nodeId:'TEST',runtimeStatus:'OFFLINE',activeJob:null,lastVerifiedJob:null};
  const result=await runOnce({
    registry,state,
    now:new Date('2026-09-24T00:00:00.000Z'),
    dispatch:async()=>({ok:true,result:{execution:'REAL_EXECUTION'},evidence:{verification:{verified:true}}}),
    appendEvidence:async()=>{},
    writeBackCanonical:async()=>{throw new Error('CANONICAL_SYNC_FAILED')},
    repoRoot:'/test'
  });
  assert.equal(result.status,'DONE');
  assert.equal(result.verification.verified,true);
  assert.equal(state.activeJob,null);
  assert.equal(state.lastVerifiedJob,'WB-FAIL-1');
});
