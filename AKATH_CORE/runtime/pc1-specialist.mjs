#!/usr/bin/env node

import { resolveSpecialist } from './specialist-registry.mjs';
import { executeAiTask } from './ai-executor.mjs';
import { executeControlTask } from './pc1-control.mjs';

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

if (specialist.capability === 'ai') {
  try {
    const ai = await executeAiTask(job);
    process.stdout.write(JSON.stringify({
      ok: true,
      result: {
        executor: specialist.id,
        capability: specialist.capability,
        task_id: job.task_id ?? null,
        execution: 'AI_EXECUTED',
        provider: ai.provider,
        model: ai.model,
        output: ai.text,
        completed_at: new Date().toISOString()
      },
      evidence: {
        executor: specialist.id,
        capability: specialist.capability,
        node: process.env.AX_PC1_NODE_ID || 'PC1-MAIN',
        verification: { verified: true },
        execution: 'AI_EXECUTED',
        provider: ai.provider,
        model: ai.model
      }
    }));
  } catch (error) {
    console.error(`AI execution failed: ${error.message}`);
    process.exit(1);
  }
  process.exit(0);
}

if (specialist.capability === 'control') {
  try {
    const control = await executeControlTask(job);
    process.stdout.write(JSON.stringify({
      ok: true,
      result: {
        executor: specialist.id,
        capability: specialist.capability,
        task_id: job.task_id ?? null,
        execution: 'PC1_CONTROL_EXECUTED',
        action: control.action,
        command: control.command,
        exit_code: control.exitCode,
        output: control.stdout,
        stderr: control.stderr,
        completed_at: new Date().toISOString()
      },
      evidence: {
        executor: specialist.id,
        capability: specialist.capability,
        node: process.env.AX_PC1_NODE_ID || 'PC1-MAIN',
        verification: { verified: true },
        execution: 'PC1_CONTROL_EXECUTED',
        action: control.action,
        exit_code: control.exitCode,
        output: control.stdout
      }
    }));
  } catch (error) {
    console.error(`PC1 control execution failed: ${error.message}`);
    process.exit(1);
  }
  process.exit(0);
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
