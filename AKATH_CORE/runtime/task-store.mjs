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
  const currentTask = currentTaskId ? pendingTasks.find((item) => item.task_id === currentTaskId) : null;
  // current_work is advisory, not an execution lock. Never let a stale
  // canonical current_work pointer block a valid recovery/management task.
  const currentEligible = currentTask && (!currentTask.deadline_at || new Date(currentTask.deadline_at) > now)
    ? currentTask
    : null;
  const eligible = pendingTasks.filter((item) => !item.deadline_at || new Date(item.deadline_at) > now);
  // Execution priority is explicit: real productive work first, recovery
  // second, autonomous management ticks last. A self-check must never starve
  // a newly-issued production task.
  const priority = (task) => {
    if (task?.type === 'PRODUCTION' || task?.capability === 'ai' || task?.capability === 'execution') return 1;
    if (task?.capability === 'recovery') return 2;
    if (task?.capability === 'control') return 3;
    if (task?.capability === 'self_check' || task?.action === 'ax_autonomous_management_tick') return 4;
    return 3;
  };
  const ranked = [...eligible].sort((a,b) => {
    const rankDelta = priority(a) - priority(b);
    if (rankDelta !== 0) return rankDelta;
    return new Date(a.created_at || 0) - new Date(b.created_at || 0);
  });
  const job = currentEligible && priority(currentEligible) <= 1
    ? currentEligible
    : (ranked[0] ?? null);
  if (!job) return null;
  transitionJob(job,'EXECUTING',{started_at:now.toISOString(),attempt:(job.attempt ?? 0)+1});
  return job;
}

export function transitionJob(job, nextStatus, metadata = {}) {
  const allowed = transitions[job.status] ?? new Set();
  if (!allowed.has(nextStatus)) throw new Error(`Illegal transition ${job.status} -> ${nextStatus}`);
  Object.assign(job, metadata, {status:nextStatus});
  return job;
}
