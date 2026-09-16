import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';

const execFileAsync = promisify(execFile);
const script = fileURLToPath(new URL('./pc1-specialist.mjs', import.meta.url));

async function run(job) {
  const { stdout } = await execFileAsync(process.execPath, [script, JSON.stringify(job)]);
  return JSON.parse(stdout);
}

const execution = await run({ task_id: 'PC1-SPECIALIST-TEST', capability: 'execution' });
assert.equal(execution.ok, true);
assert.equal(execution.result.task_id, 'PC1-SPECIALIST-TEST');
assert.equal(execution.result.executor, 'PC1_MAIN_SPECIALIST');
assert.equal(execution.evidence.verification.verified, true);

const selfCheck = await run({ task_id: 'PC1-SELF-CHECK-TEST', capability: 'self_check' });
assert.equal(selfCheck.ok, true);
assert.equal(selfCheck.result.executor, 'PC1_SELF_CHECK_SPECIALIST');
assert.equal(selfCheck.result.execution, 'SELF_CHECK');
assert.equal(selfCheck.evidence.verification.verified, true);

const recovery = await run({ task_id: 'PC1-RECOVERY-TEST', capability: 'recovery' });
assert.equal(recovery.ok, true);
assert.equal(recovery.result.executor, 'PC1_RECOVERY_SPECIALIST');
assert.equal(recovery.result.execution, 'RECOVERY_READY');
assert.equal(recovery.evidence.verification.verified, true);

console.log('PASS PC1 specialist set');
