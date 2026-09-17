#!/usr/bin/env node

import { executeAllowlistedPowerShell } from './allowlisted-powershell.mjs';

const raw = process.argv[2];
if (!raw) {
  console.error('PC2 specialist requires one JSON job argument');
  process.exit(2);
}

let job;
try {
  job = JSON.parse(raw);
} catch (error) {
  console.error(`invalid job JSON: ${error.message}`);
  process.exit(2);
}

const nodeId = process.env.AX_PC1_NODE_ID || 'PC2-MAIN';
const now = new Date().toISOString();
const action = job.payload?.action ?? job.action;
const ps = await executeAllowlistedPowerShell(action);
const execution = ps.exitCode === 0 ? 'POWERSHELL_EXECUTED' : 'POWERSHELL_FAILED';
let hostIdentity = null;
if (action === 'runtime_identity' && ps.exitCode === 0) {
  try { hostIdentity = JSON.parse(ps.stdout); } catch { hostIdentity = { raw: ps.stdout }; }
}

const result = {
  executor: 'PC2_POWERSHELL_SPECIALIST',
  capability: 'powershell',
  node: nodeId,
  task_id: job.task_id ?? null,
  execution,
  completed_at: now,
  stdout: ps.stdout,
  stderr: ps.stderr,
  exitCode: ps.exitCode,
  hostIdentity
};

const verified = ps.exitCode === 0 &&
  (action !== 'runtime_identity' || !!hostIdentity?.computerName) &&
  (!hostIdentity?.nodeId || hostIdentity.nodeId === nodeId);

process.stdout.write(JSON.stringify({
  ok: verified,
  result,
  evidence: {
    executor: 'PC2_POWERSHELL_SPECIALIST',
    capability: 'powershell',
    node: nodeId,
    hostIdentity,
    verification: { verified },
    execution,
    stdout: ps.stdout,
    stderr: ps.stderr,
    exitCode: ps.exitCode
  }
}));
process.exit(verified ? 0 : 1);
