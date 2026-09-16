import { transitionJob } from './task-store.mjs';

export function recoverJob(job, reason, now = new Date()) {
  const correction = 'requeue after root-cause record';
  transitionJob(job,'OVERDUE',{root_cause:reason,correction,overdue_at:now.toISOString()});
  transitionJob(job,'PENDING',{recovery_at:now.toISOString()});
  return job;
}
