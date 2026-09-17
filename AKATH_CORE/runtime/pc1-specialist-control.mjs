import { executeAllowlistedPowerShell } from './allowlisted-powershell.mjs';

const raw = process.argv[2];
if (!raw) process.exit(2);
const job = JSON.parse(raw);
const ps = await executeAllowlistedPowerShell(job.payload?.action ?? job.action);
const execution = ps.exitCode === 0 ? 'PC1_CONTROL_EXECUTED' : 'PC1_CONTROL_FAILED';
let hostIdentity = null;
if ((job.payload?.action ?? job.action) === 'runtime_identity' && ps.exitCode === 0) {
  try { hostIdentity = JSON.parse(ps.stdout); } catch { hostIdentity = { raw: ps.stdout }; }
}
const result = {
  executor: 'PC1_CONTROL_SPECIALIST', capability: 'control', task_id: job.task_id ?? null,
  execution, exit_code: ps.exitCode, output: ps.stdout, stdout: ps.stdout, stderr: ps.stderr,
  hostIdentity, completed_at: new Date().toISOString()
};
process.stdout.write(JSON.stringify({
  ok: ps.exitCode === 0,
  result,
  evidence: {
    executor: 'PC1_CONTROL_SPECIALIST', capability: 'control', node: process.env.AX_PC1_NODE_ID || 'PC1-MAIN',
    hostIdentity, result,
    verification: { verified: ps.exitCode === 0 && ((job.payload?.action ?? job.action) !== 'runtime_identity' || !!hostIdentity?.computerName) }, execution, action: ps.action,
    output: ps.stdout, stdout: ps.stdout, stderr: ps.stderr, exit_code: ps.exitCode
  }
}));
process.exit(ps.exitCode === 0 ? 0 : 1);
