import assert from 'node:assert/strict';
import { listAllowlistedActions } from './allowlisted-powershell.mjs';

const actions = listAllowlistedActions();
assert.deepEqual(actions, [
  'runtime_heartbeat',
  'runtime_status',
  'runtime_identity',
  'runtime_process_snapshot',
  'runtime_disk_snapshot',
  'jumtask'
]);
assert.equal(actions.includes('arbitrary_command'), false);
console.log('allowlisted PowerShell contract PASS');
