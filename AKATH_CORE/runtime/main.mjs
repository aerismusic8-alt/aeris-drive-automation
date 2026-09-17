import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { loadRegistry, persistRegistry } from './task-store.mjs';
import { appendEvidence } from './evidence-store.mjs';
import { loadJson, persistJson } from './state-store.mjs';
import { createLocalPc1Adapter, dispatchToPc1 } from './dispatcher.mjs';
import { runOnce, startSupervisor } from './ax-runtime.mjs';
import { planNextTask } from './autonomous-planner.mjs';
import { mergeCanonicalTasks } from './canonical-sync.mjs';

const execFileAsync = promisify(execFile);
const root = dirname(fileURLToPath(import.meta.url));
const registryPath = resolve(root, '../CANONICAL_TASK_REGISTRY.json');
const statePath = resolve(root, 'runtime-state.json');
const evidencePath = resolve(root, 'evidence.jsonl');
const canonicalRelativePath = 'AKATH_CORE/CANONICAL_TASK_REGISTRY.json';
const state = await loadJson(statePath, {
  schemaVersion: '1.0', runtimeStatus: 'STARTING', nodeId: process.env.AX_PC1_NODE_ID || 'PC1-MAIN',
  lastHeartbeatAt: null, activeJob: null, lastVerifiedJob: null, recovery: {}
});
const adapter = createLocalPc1Adapter();
let lastCanonicalSyncAt = 0;
const canonicalSyncIntervalMs = Number(process.env.AX_CANONICAL_SYNC_INTERVAL_MS || 15000);

async function syncCanonicalQueue(registry) {
  const now = Date.now();
  if (now - lastCanonicalSyncAt < canonicalSyncIntervalMs) return;
  lastCanonicalSyncAt = now;
  try {
    await execFileAsync('git', ['fetch', 'origin', 'main', '--quiet'], { cwd: resolve(root, '../..') });
    const { stdout } = await execFileAsync('git', ['show', `origin/main:${canonicalRelativePath}`], { cwd: resolve(root, '../..') });
    const remote = JSON.parse(stdout);
    const merged = mergeCanonicalTasks(registry, remote);
    if (merged.added > 0) console.log(`[AX_RUNTIME] CANONICAL_SYNC added=${merged.added}`);
  } catch (error) {
    console.error(`[AX_RUNTIME] CANONICAL_SYNC_FAILED ${error.message}`);
  }
}

async function cycle() {
  const registry = await loadRegistry(registryPath);
  await syncCanonicalQueue(registry);
  const planned = planNextTask(registry, new Date());
  if (planned) console.log(`[AX_RUNTIME] AUTONOMOUS_TASK ${planned.task_id}`);
  const result = await runOnce({
    registry,
    state,
    dispatch: job => dispatchToPc1(job, adapter),
    appendEvidence: record => appendEvidence(evidencePath, record)
  });
  await persistRegistry(registryPath, registry);
  await persistJson(statePath, state);
  if (result.status === 'DONE') console.log(`[AX_RUNTIME] DONE ${result.job.task_id}`);
  else if (result.status === 'FAILED') console.error(`[AX_RUNTIME] FAILED ${result.job?.task_id}: ${result.error || JSON.stringify(result.verification)}`);
  else console.log(`[AX_RUNTIME] HEARTBEAT ${state.nodeId} active=${state.activeJob || 'none'} lastVerified=${state.lastVerifiedJob || 'none'}`);
}

console.log(`[AX_RUNTIME] ONLINE node=${state.nodeId}`);
startSupervisor({ cycle, intervalMs: Number(process.env.AX_RUNTIME_INTERVAL_MS || 5000) });
