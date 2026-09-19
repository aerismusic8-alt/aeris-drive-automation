import { claimNextEligibleJob, transitionJob } from './task-store.mjs';
import { verifyJobResult } from './verifier.mjs';
import { appendEvidence as appendEvidenceFile } from './evidence-store.mjs';
import { writeBackCanonical as defaultWriteBackCanonical } from './canonical-writeback.mjs';

function isRecoverable(error){const m=String(error?.message||error||'').toLowerCase();return Boolean(error?.recoverable)||/quota|rate.?limit|too many requests|resource exhausted|429|temporarily unavailable|timeout|timed out|econnrefused|fetch failed|ollama.*(unavailable|refused)/.test(m);}
function retryDelayMs(attempt){return Math.min(300000,15000*Math.max(1,2**Math.min(Math.max(attempt-1,0),4)));}

export async function runOnce({registry,state,now=new Date(),dispatch,appendEvidence=appendEvidenceFile,writeBackCanonical=defaultWriteBackCanonical,repoRoot,onEvent=()=>{}}){
  state.runtimeStatus='ONLINE';state.lastHeartbeatAt=now.toISOString();onEvent('HEARTBEAT',{detail:state.nodeId});
  const job=claimNextEligibleJob(registry,now);
  if(!job){onEvent('QUEUE',{detail:'WAITING'});return{status:'IDLE'};}
  state.activeJob=job.task_id;onEvent('CLAIM',{taskId:job.task_id,detail:job.capability||'unknown'});
  try{
    onEvent('DISPATCH',{taskId:job.task_id,detail:'PC1_MAIN_SPECIALIST'});
    const outcome=await dispatch(job);
    if(!outcome?.ok)throw new Error(outcome?.error||'PC1 execution failed');
    onEvent('EXECUTE',{taskId:job.task_id,detail:outcome.result?.execution||job.capability||'execution'});
    job.result=outcome.result;
    const evidence={...(outcome.evidence||{}),jobId:job.task_id,result:outcome.result,event:'RESULT',timestamp:now.toISOString()};
    await appendEvidence(evidence);onEvent('EVIDENCE',{taskId:job.task_id,detail:'RESULT SAVED'});
    transitionJob(job,'COMPLETED',{completed_at:now.toISOString()});
    const verification=verifyJobResult(job,evidence);onEvent('VERIFY',{taskId:job.task_id,detail:verification.verified?'PASS':'FAIL'});
    if(!verification.verified){transitionJob(job,'FAILED',{verification,failed_at:now.toISOString()});state.activeJob=null;return{status:'FAILED',job,verification};}
    transitionJob(job,'VERIFIED',{verification,verified_at:now.toISOString()});transitionJob(job,'DONE',{completed_at:now.toISOString()});
    if(repoRoot){await writeBackCanonical({repoRoot,job,evidence,verification,now});onEvent('WRITE_BACK',{taskId:job.task_id,detail:'CANONICAL DONE'});}
    state.lastVerifiedJob=job.task_id;state.activeJob=null;onEvent('DONE',{taskId:job.task_id,detail:'VERIFIED'});
    return{status:'DONE',job,verification};
  }catch(error){
    const recoverable=isRecoverable(error);
    if(['EXECUTING','COMPLETED'].includes(job.status))transitionJob(job,'FAILED',{error:error.message,failed_at:now.toISOString()});
    if(recoverable&&(job.attempt??0)<8){const retryAt=new Date(now.getTime()+retryDelayMs(job.attempt??1)).toISOString();transitionJob(job,'PENDING',{retry_at:retryAt,deadline_at:null,last_error:error.message,recoverable:true});onEvent('RETRY_SCHEDULED',{taskId:job.task_id,detail:retryAt});}
    else onEvent('ERROR',{taskId:job.task_id,detail:error.message});
    state.activeJob=null;onEvent('ERROR',{taskId:job.task_id,detail:recoverable?'RECOVERABLE':'FATAL'});return{status:'FAILED',job,error:error.message,recoverable};
  }
}
export function startSupervisor({cycle,intervalMs=5000,signal=process,onTick=()=>{}}){
  let stopped=false;
  const tick=async()=>{if(stopped)return;try{await cycle();}catch(error){onTick('ERROR',{detail:error.stack||String(error)});console.error(`[AX_RUNTIME] ${error.stack||error}`);}if(!stopped){onTick('NEXT_JOB',{detail:`in=${intervalMs}ms`});setTimeout(tick,intervalMs);}};
  const stop=()=>{stopped=true;onTick('STOP',{detail:'signal'});};signal.on?.('SIGINT',stop);signal.on?.('SIGTERM',stop);tick();return{stop};
}
