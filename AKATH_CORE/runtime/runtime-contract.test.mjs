import test from 'node:test';
import assert from 'node:assert/strict';
import { validateRuntimeState, validateEvidence } from './runtime-contract.mjs';

test('runtime state requires runtimeStatus, nodeId and lastHeartbeatAt', () => {
  assert.equal(validateRuntimeState({}).valid, false);
  assert.equal(validateRuntimeState({runtimeStatus:'ONLINE',nodeId:'PC1-MAIN',lastHeartbeatAt:'2026-09-16T00:00:00Z'}).valid, true);
});

test('evidence requires jobId, event and verification', () => {
  assert.equal(validateEvidence({jobId:'j1',event:'RESULT'}).valid, false);
  assert.equal(validateEvidence({jobId:'j1',event:'RESULT',verification:{verified:true}}).valid, true);
});
