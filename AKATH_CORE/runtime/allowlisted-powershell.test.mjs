import assert from 'node:assert/strict';
import { listAllowlistedActions } from './allowlisted-powershell.mjs';

assert.deepEqual(listAllowlistedActions(), ['runtime_heartbeat', 'runtime_identity']);
assert.throws(() => listAllowlistedActions().includes('arbitrary_command') && (() => { throw new Error('bad') })());
console.log('allowlisted PowerShell contract PASS');
