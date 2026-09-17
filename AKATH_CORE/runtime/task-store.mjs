import { loadJson, persistJson } from './state-store.mjs';

const transitions = {
  PENDING: new Set(['EXECUTING','OVERDUE']), EXECUTING: new Set(['COMPLETED','FAILED','OVERDUE']),
  COMPLETED: new Set(['VERIFIED','FAILED']), VERIFIED: new Set(['DONE','FAILED']),
  OVERDUE: new Set(['PENDING','FAILED']), FAILED: new Set(['PENDING']), DONE: new Set()
};

export async function loadRegistry(path) { return loadJson(path,{tasks:[]}); }
export async function persistRegistry(path, registry) { return persistJson(path,registry); }

export function claimNextEligibleJob(registry, now = new Date()) {
  const pendingTasks = registry.tasks.filter((item) => item.status === 'PENDING');
  const currentTaskId = registry?.current_work?.active ? registry.current_work.task_id : null;
  const job = (currentTaskId ? pendingTasks.find((item) => item.task_id === currentTaskId) : null) ?? pendingTasks[0] ?? null;
  if (!job) return null;
  if (job.deadline_at && new Date(job.deadline_at) <= now) {
    transitionJob(job,'OVERDUE',{root_cause:'deadline_exceeded',correction:'deadline review required',overdue_at:now.toISOString()});
    return null;
  }
  transitionJob(job,'EXECUTING',{started_at:now.toISOString(),attempt:(job.attempt ?? 0)+1});
  return job;
}

export function transitionJob(job, nextStatus, metadata = {}) {
  const allowed = transitions[job.status] ?? new Set();
  if (!allowed.has(nextStatus)) throw new Error(`Illegal transition ${job.status} -> ${nextStatus}`);
  Object.assign(job, metadata, {status:nextStatus});
  return job;
}
