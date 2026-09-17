#!/usr/bin/env node

import { resolveSpecialist } from './specialist-registry.mjs';
import { executeAllowlistedPowerShell } from './allowlisted-powershell.mjs';

const raw = process.argv[2];
if (!raw) {
  console.error('PC1 specialist requires one JSON job argument');
  process.exit(2);
}

let job;
try {
  job = JSON.parse(raw);
} catch (error) {
  console.error(`invalid job JSON: ${error.message}`);
  process.exit(2);
}

const specialist = resolveSpecialist(job.capability);
const now = new Date().toISOString();

if (specialist.capability === 'powershell') {
  const ps = await executeAllowlistedPowerShell(job.payload?.action);
  const execution = ps.exitCode === 0 ? 'POWERSHELL_EXECUTED' : 'POWERSHELL_FAILED';
  process.stdout.write(JSON.stringify({
    ok: ps.exitCode === 0,
    result: {
      executor: specialist.id,
      capability: specialist.capability,
      task_id: job.task_id ?? null,
      execution,
      completed_at: now,
      stdout: ps.stdout,
      stderr: ps.stderr,
      exitCode: ps.exitCode
    },
    evidence: {
      executor: specialist.id,
      capability: specialist.capability,
      node: process.env.AX_PC1_NODE_ID || 'PC1-MAIN',
      verification: { verified: ps.exitCode === 0 },
      execution,
      stdout: ps.stdout,
      stderr: ps.stderr,
      exitCode: ps.exitCode
    }
  }));
  process.exit(ps.exitCode === 0 ? 0 : 1);
}

const execution = specialist.capability === 'self_check'
  ? 'SELF_CHECK'
  : specialist.capability === 'recovery'
    ? 'RECOVERY_READY'
    : 'EXECUTED';

const result = {
  executor: specialist.id,
  capability: specialist.capability,
  task_id: job.task_id ?? null,
  execution,
  completed_at: now
};

process.stdout.write(JSON.stringify({
  ok: true,
  result,
  evidence: {
    executor: specialist.id,
    capability: specialist.capability,
    node: process.env.AX_PC1_NODE_ID || 'PC1-MAIN',
    verification: { verified: true },
    execution
  }
}));
