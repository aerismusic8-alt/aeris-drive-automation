import assert from 'node:assert/strict';
import { listAllowlistedActions } from './allowlisted-powershell.mjs';

assert.ok(listAllowlistedActions().includes('runtime_heartbeat'));
assert.ok(listAllowlistedActions().includes('runtime_identity'));
assert.equal(listAllowlistedActions().includes('arbitrary_command'), false);
console.log('continuous runtime contract PASS');
