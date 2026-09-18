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
import { createLiveEmitter } from './live-console.mjs';
import { resolveRuntimeRegistryPath } from './runtime-registry.mjs';

const execFileAsync = promisify(execFile);
const root=dirname(fileURLToPath(import.meta.url));
const repoRoot=resolve(root,'../..');
const runtimeRegistryPath=resolveRuntimeRegistryPath(root);
const statePath=resolve(root,'runtime-state.json');
const evidencePath=resolve(root,'evidence.jsonl');
const telemetryPath=resolve(root,'runtime-telemetry.json');
const canonicalRelativePath='AKATH_CORE/CANONICAL_TASK_REGISTRY.json';
const state=await loadJson(statePath,{schemaVersion:'1.0',runtimeStatus:'STARTING',nodeId:process.env.AX_PC1_NODE_ID||'PC1-MAIN',lastHeartbeatAt:null,activeJob:null,lastVerifiedJob:null,recovery:{}});
const adapter=createLocalPc1Adapter();
const live=createLiveEmitter();
let lastCanonicalSyncAt=0;
let lastTelemetryPushAt=0;
let telemetryPushInFlight=false;
const canonicalSyncIntervalMs=Number(process.env.AX_CANONICAL_SYNC_INTERVAL_MS||15000);
const telemetryIntervalMs=Number(process.env.AX_TELEMETRY_INTERVAL_MS||30000);

async function publishTelemetry(force=false){
  const now=Date.now();
  if(!force && now-lastTelemetryPushAt<telemetryIntervalMs) return;
  if(telemetryPushInFlight) return;
  telemetryPushInFlight=true;
  lastTelemetryPushAt=now;
  try {
    state.lastHeartbeatAt=new Date(now).toISOString();
    state.runtimeStatus='ONLINE';
    const telemetry={schemaVersion:'1.0',nodeId:state.nodeId,runtimeStatus:state.runtimeStatus,lastHeartbeatAt:state.lastHeartbeatAt,pid:process.pid,activeJob:state.activeJob||null,lastVerifiedJob:state.lastVerifiedJob||null,recovery:state.recovery||{},updatedAt:state.lastHeartbeatAt};
    await persistJson(telemetryPath,telemetry);
    live('TELEMETRY_UPDATED',{detail:state.lastHeartbeatAt});
  } catch(error) {
    console.error(`[AX_RUNTIME] TELEMETRY_PUBLISH_FAILED ${error.message}`);
  } finally {
    telemetryPushInFlight=false;
  }
}

async function syncCanonicalQueue(registry){
  const now=Date.now();
  if(now-lastCanonicalSyncAt<canonicalSyncIntervalMs) return true;
  lastCanonicalSyncAt=now;
  live('CONNECT',{detail:'CANONICAL_QUEUE'});
  try {
    try {
      await execFileAsync('git',['fetch','origin','main','--quiet'],{cwd:repoRoot});
    } catch (fetchError) {
      const message=String(fetchError?.message||fetchError);
      if (!message.includes("cannot lock ref 'refs/remotes/origin/main'")) throw fetchError;
      live('CANONICAL_FETCH_RACE',{detail:'using current origin/main'});
    }
    const {stdout:shaStdout}=await execFileAsync('git',['rev-parse','origin/main'],{cwd:repoRoot});
    const originSha=shaStdout.trim();
    const {stdout}=await execFileAsync('git',['show',`origin/main:${canonicalRelativePath}`],{cwd:repoRoot});
    const remote=JSON.parse(stdout);
    const currentTaskId=remote?.current_work?.active ? remote.current_work.task_id : 'none';
    const currentTask=Array.isArray(remote?.tasks) ? remote.tasks.find((task)=>task?.task_id===currentTaskId) : null;
    const localTask=Array.isArray(registry?.tasks) ? registry.tasks.find((task)=>task?.task_id===currentTaskId) : null;
    const localStatusBefore=localTask?.status||'missing';
    const localCreatedBefore=localTask?.created_at||'missing';
    const merged=mergeCanonicalTasks(registry,remote);
    live('CONNECTED',{detail:`sha=${originSha.slice(0,12)} current=${currentTaskId} remoteStatus=${currentTask?.status||'missing'} localStatus=${localStatusBefore} localCreated=${localCreatedBefore} remoteCreated=${currentTask?.created_at||'missing'} added=${merged.added} requeued=${merged.requeued} currentRehydrated=${merged.currentRehydrated} preserved=${merged.preserved}`});
    console.log(`[AX_RUNTIME] CANONICAL_SYNC sha=${originSha} current=${currentTaskId} remoteStatus=${currentTask?.status||'missing'} localStatus=${localStatusBefore} localCreated=${localCreatedBefore} remoteCreated=${currentTask?.created_at||'missing'} added=${merged.added} requeued=${merged.requeued} currentRehydrated=${merged.currentRehydrated} preserved=${merged.preserved}`);
    return true;
  } catch(error) {
    live('DISCONNECTED',{detail:error.message});
    live('RECONNECT',{detail:'next cycle'});
    console.error(`[AX_RUNTIME] CANONICAL_SYNC_FAILED ${error.message}`);
    return false;
  }
}

async function cycle(){
  const registry=await loadRegistry(runtimeRegistryPath);
  const connected=await syncCanonicalQueue(registry);
  if(!connected) {
    await persistJson(statePath,state);
    await publishTelemetry();
    return;
  }
  const planned=planNextTask(registry,new Date());
  if(planned) {
    live('JOB_FOUND',{taskId:planned.task_id,detail:planned.capability||'execution'});
    console.log(`[AX_RUNTIME] AUTONOMOUS_TASK ${planned.task_id}`);
  }
  const result=await runOnce({registry,state,dispatch:(job)=>dispatchToPc1(job,adapter),appendEvidence:(record)=>appendEvidence(evidencePath,record),onEvent:live});
  await persistRegistry(runtimeRegistryPath,registry);
  await persistJson(statePath,state);
  await publishTelemetry();
  if(result.status==='DONE') console.log(`[AX_RUNTIME] DONE ${result.job.task_id}`);
  else if(result.status==='FAILED') console.error(`[AX_RUNTIME] FAILED ${result.job?.task_id}: ${result.error||JSON.stringify(result.verification)}`);
}

live('BOT_ONLINE',{detail:state.nodeId});
console.log(`[AX_RUNTIME] ONLINE node=${state.nodeId}`);
state.runtimeStatus='ONLINE';
await publishTelemetry(true);
startSupervisor({cycle,intervalMs:Number(process.env.AX_RUNTIME_INTERVAL_MS||5000),onTick:live});
