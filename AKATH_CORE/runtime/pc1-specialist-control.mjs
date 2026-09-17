import { executeAllowlistedPowerShell } from './allowlisted-powershell.mjs';

const raw = process.argv[2];
if (!raw) process.exit(2);
const job = JSON.parse(raw);
const ps = await executeAllowlistedPowerShell(job.payload?.action ?? job.action);
const execution = ps.exitCode === 0 ? 'PC1_CONTROL_EXECUTED' : 'PC1_CONTROL_FAILED';
process.stdout.write(JSON.stringify({
  ok: ps.exitCode === 0,
  result: {
    executor: 'PC1_CONTROL_SPECIALIST', capability: 'control', task_id: job.task_id ?? null,
    execution, exit_code: ps.exitCode, output: ps.stdout, stdout: ps.stdout, stderr: ps.stderr,
    completed_at: new Date().toISOString()
  },
  evidence: {
    executor: 'PC1_CONTROL_SPECIALIST', capability: 'control', node: process.env.AX_PC1_NODE_ID || 'PC1-MAIN',
    verification: { verified: ps.exitCode === 0 }, execution, action: ps.action,
    output: ps.stdout, stdout: ps.stdout, stderr: ps.stderr, exit_code: ps.exitCode
  }
}));
process.exit(ps.exitCode === 0 ? 0 : 1);
