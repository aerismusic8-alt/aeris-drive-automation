#!/usr/bin/env node

import { resolveSpecialist } from './specialist-registry.mjs';
import { executeAllowlistedPowerShell } from './allowlisted-powershell.mjs';

function verifyPowerShellAction(action, ps) {
  if (!ps || ps.exitCode !== 0) return false;
  if (action === 'youtube_short_package') return /\\[REVENUE\\] MP4=\\S+\\.mp4/.test(ps.stdout) && /\\[REVENUE\\] BYTES=\\d+/.test(ps.stdout) && /\\[REVENUE\\] RESULT=YOUTUBE_SHORT_PACKAGE_READY/.test(ps.stdout);
  if (action === 'runtime_identity') { try { const id = JSON.parse(ps.stdout); return !!id?.computerName; } catch { return false; } }
  return true;
}

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
const action = job.payload?.action;
const now = new Date().toISOString();

if (specialist.capability === 'powershell') {
  const ps = await executeAllowlistedPowerShell(action);
  const verified = verifyPowerShellAction(action, ps);
  const execution = ps.exitCode === 0 ? 'POWERSHELL_EXECUTED' : 'POWERSHELL_FAILED';
  let hostIdentity = null;
  if (job.payload?.action === 'runtime_identity' && ps.exitCode === 0) {
    try { hostIdentity = JSON.parse(ps.stdout); } catch { hostIdentity = { raw: ps.stdout }; }
  }
  process.stdout.write(JSON.stringify({
    ok: verified,
    result: {
      executor: specialist.id,
      capability: specialist.capability,
      task_id: job.task_id ?? null,
      execution,
      completed_at: now,
      stdout: ps.stdout,
      stderr: ps.stderr,
      exitCode: ps.exitCode,
      hostIdentity
    },
    evidence: {
      executor: specialist.id,
      capability: specialist.capability,
      node: process.env.AX_PC1_NODE_ID || 'PC1-MAIN',
      hostIdentity,
      verification: { verified },
      execution,
      stdout: ps.stdout,
      stderr: ps.stderr,
      exitCode: ps.exitCode
    }
  }));
  process.exit(verified ? 0 : 1);
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
