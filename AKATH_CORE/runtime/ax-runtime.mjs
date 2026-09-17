import { claimNextEligibleJob, transitionJob } from './task-store.mjs';
import { verifyJobResult } from './verifier.mjs';
import { appendEvidence as appendEvidenceFile } from './evidence-store.mjs';

export async function runOnce({registry,state,now=new Date(),dispatch,appendEvidence=appendEvidenceFile}) {
  state.runtimeStatus='ONLINE'; state.lastHeartbeatAt=now.toISOString();
  const job=claimNextEligibleJob(registry,now);
  if(!job) return {status:'IDLE'};
  state.activeJob=job.task_id;
  try {
    const outcome=await dispatch(job);
    if(!outcome?.ok) throw new Error(outcome?.error || 'PC1 execution failed');
    job.result=outcome.result;
    const evidence={...(outcome.evidence||{}),jobId:job.task_id,result:outcome.result,event:'RESULT',timestamp:now.toISOString()};

    await appendEvidence(evidence);
    transitionJob(job,'COMPLETED',{completed_at:now.toISOString()});

    const verification=verifyJobResult(job,evidence);
    if(!verification.verified) {
      transitionJob(job,'FAILED',{verification,failed_at:now.toISOString()});
      state.activeJob=null;
      return {status:'FAILED',job,verification};
    }
    transitionJob(job,'VERIFIED',{verification,verified_at:now.toISOString()});
    transitionJob(job,'DONE',{completed_at:now.toISOString()});
    state.lastVerifiedJob=job.task_id; state.activeJob=null;
    return {status:'DONE',job,verification};
  } catch (error) {
    if(['EXECUTING','COMPLETED'].includes(job.status)) {
      transitionJob(job,'FAILED',{error:error.message,failed_at:now.toISOString()});
    }
    state.activeJob=null; return {status:'FAILED',job,error:error.message};
  }
}

export function startSupervisor({cycle,intervalMs=5000,signal=process}) {
  let stopped=false;
  const tick=async()=>{ if(stopped)return; try { await cycle(); } catch (error) { console.error(`[AX_RUNTIME] ${error.stack||error}`); } if(!stopped)setTimeout(tick,intervalMs); };
  const stop=()=>{stopped=true;}; signal.on?.('SIGINT',stop); signal.on?.('SIGTERM',stop); tick();
  return {stop};
}
