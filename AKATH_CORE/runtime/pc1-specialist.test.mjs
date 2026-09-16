import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import assert from 'node:assert/strict';

const execFileAsync = promisify(execFile);
const script = new URL('./pc1-specialist.mjs', import.meta.url);

const { stdout } = await execFileAsync(process.execPath, [script, JSON.stringify({ task_id: 'PC1-SPECIALIST-TEST' })]);
const payload = JSON.parse(stdout);

assert.equal(payload.ok, true);
assert.equal(payload.result.task_id, 'PC1-SPECIALIST-TEST');
assert.equal(payload.result.executor, 'PC1_MAIN_SPECIALIST');
assert.equal(payload.evidence.verification.verified, true);
console.log('PASS PC1 specialist executor');
