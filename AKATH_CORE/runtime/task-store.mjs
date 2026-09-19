import { loadJson, persistJson } from './state-store.mjs';
const transitions={PENDING:new Set(['EXECUTING','OVERDUE']),EXECUTING:new Set(['COMPLETED','FAILED','OVERDUE']),COMPLETED:new Set(['VERIFIED','FAILED']),VERIFIED:new Set(['DONE','FAILED']),OVERDUE:new Set(['PENDING','FAILED']),FAILED:new Set(['PENDING']),DONE:new Set()};
export async function loadRegistry(path){return loadJson(path,{tasks:[]});}
export async function persistRegistry(path,registry){return persistJson(path,registry);}
export function claimNextEligibleJob(registry,now=new Date()){
  const pendingTasks=registry.tasks.filter(item=>item.status==='PENDING');
  const currentTaskId=registry?.current_work?.active?registry.current_work.task_id:null;
  const currentTask=currentTaskId?pendingTasks.find(item=>item.task_id===currentTaskId):null;
  const eligible=pendingTasks.filter(item=>(!item.retry_at||new Date(item.retry_at)<=now)&&(!item.deadline_at||new Date(item.deadline_at)>now));
  if(!eligible.length){
    for(const item of pendingTasks){
      if(item.deadline_at&&new Date(item.deadline_at)<=now&&!item.retry_at)transitionJob(item,'OVERDUE',{overdue_at:now.toISOString()});
    }
    return null;
  }
  const currentEligible=currentTask&&eligible.includes(currentTask)?currentTask:null;
  const priority=task=>task?.type==='PRODUCTION'||task?.capability==='ai'||task?.capability==='execution'?1:task?.capability==='recovery'?2:task?.capability==='control'?3:task?.capability==='self_check'||task?.action==='ax_autonomous_management_tick'?4:3;
  const ranked=[...eligible].sort((a,b)=>priority(a)-priority(b)||new Date(a.created_at||0)-new Date(b.created_at||0));
  const job=currentEligible&&priority(currentEligible)<=1?currentEligible:(ranked[0]??null);
  if(!job)return null;
  transitionJob(job,'EXECUTING',{started_at:now.toISOString(),attempt:(job.attempt??0)+1});
  return job;
}
export function transitionJob(job,nextStatus,metadata={}){const allowed=transitions[job.status]??new Set();if(!allowed.has(nextStatus))throw new Error(`Illegal transition ${job.status} -> ${nextStatus}`);Object.assign(job,metadata,{status:nextStatus});return job;}
