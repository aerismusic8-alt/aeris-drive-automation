#!/usr/bin/env node

import fs from 'node:fs';
import { executeAllowlistedPowerShell } from './allowlisted-powershell.mjs';
import { verifyExecutionResult } from './pc2-specialist-verifier.mjs';

const rawArg = process.argv[2];
if (!rawArg) {
  console.error('PC2 specialist requires a JSON job file argument');
  process.exit(2);
}

let raw;
try {
  raw = fs.readFileSync(rawArg, 'utf8').replace(/^\uFEFF/, '');
} catch (error) {
  console.error(`cannot read job file: ${error.message}`);
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

const ps = await executeAllowlistedPowerShell(action, {
  onStdout: (text) => {
    if (action === 'jumtask' || action === 'youtube_short_package') process.stdout.write(text);
  },
  onStderr: (text) => {
    if (action === 'jumtask' || action === 'youtube_short_package') process.stderr.write(`[${action.toUpperCase()}][PS-ERR] ${text}`);
  }
});

const execution = ps.exitCode === 0 ? 'POWERSHELL_EXECUTED' : 'POWERSHELL_FAILED';
let hostIdentity = null;
if (action === 'runtime_identity' && ps.exitCode === 0) {
  try { hostIdentity = JSON.parse(ps.stdout); } catch { hostIdentity = { raw: ps.stdout }; }
}

const verified = verifyExecutionResult(action, ps, nodeId);
const result = {
  executor: 'PC2_POWERSHELL_SPECIALIST',
  capability: action === 'youtube_short_package' ? 'revenue' : 'powershell',
  node: nodeId,
  task_id: job.task_id ?? null,
  execution,
  completed_at: now,
  stdout: ps.stdout,
  stderr: ps.stderr,
  exitCode: ps.exitCode,
  hostIdentity
};

process.stdout.write(JSON.stringify({
  ok: verified,
  result,
  evidence: {
    executor: 'PC2_POWERSHELL_SPECIALIST',
    capability: action === 'youtube_short_package' ? 'revenue' : 'powershell',
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
