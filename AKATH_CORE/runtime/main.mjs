import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { loadRegistry, persistRegistry } from './task-store.mjs';
import { appendEvidence } from './evidence-store.mjs';
import { loadJson, persistJson } from './state-store.mjs';
import { createLocalPc1Adapter, dispatchToPc1 } from './dispatcher.mjs';
import { runOnce, startSupervisor } from './ax-runtime.mjs';

const root=dirname(fileURLToPath(import.meta.url));
const registryPath=resolve(root,'../CANONICAL_TASK_REGISTRY.json');
const statePath=resolve(root,'runtime-state.json');
const evidencePath=resolve(root,'evidence.jsonl');
const state=await loadJson(statePath,{schemaVersion:'1.0',runtimeStatus:'STARTING',nodeId:process.env.AX_PC1_NODE_ID||'PC1-MAIN',lastHeartbeatAt:null,activeJob:null,lastVerifiedJob:null,recovery:{}});
const adapter=createLocalPc1Adapter();

async function cycle(){
  const registry=await loadRegistry(registryPath);
  const result=await runOnce({registry,state,dispatch:(job)=>dispatchToPc1(job,adapter),appendEvidence:(record)=>appendEvidence(evidencePath,record)});
  await persistRegistry(registryPath,registry);
  await persistJson(statePath,state);
  if(result.status==='DONE') console.log(`[AX_RUNTIME] DONE ${result.job.task_id}`);
  else if(result.status==='FAILED') console.error(`[AX_RUNTIME] FAILED ${result.job?.task_id}: ${result.error||JSON.stringify(result.verification)}`);
}

console.log(`[AX_RUNTIME] ONLINE node=${state.nodeId}`);
startSupervisor({cycle,intervalMs:Number(process.env.AX_RUNTIME_INTERVAL_MS||5000)});
