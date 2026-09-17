export const MAX_RETRY_ATTEMPTS = 3;

export function buildRecoveryRetry(registry, recoveryTask, now = new Date()) {
  const failedTaskId = recoveryTask?.payload?.failed_task_id;
  if (!failedTaskId) return null;
  const tasks = registry?.tasks ?? [];
  const failedTask = tasks.find((task) => task.task_id === failedTaskId);
  if (!failedTask) return null;
  const retries = tasks.filter((task) => task.payload?.recovery_of === failedTaskId);
  const latest = retries.at(-1);
  if (latest?.status === 'DONE') return null;
  const attempt = retries.length + 1;
  if (attempt > MAX_RETRY_ATTEMPTS) return null;
  return {
    ...failedTask,
    task_id: `${failedTaskId}-RETRY-${attempt}`,
    status: 'PENDING',
    created_at: now.toISOString(),
    deadline_at: new Date(now.getTime() + 30 * 60 * 1000).toISOString(),
    evidence: null,
    verification: null,
    completed_at: null,
    result: null,
    payload: {
      ...(failedTask.payload || {}),
      recovery_of: failedTaskId,
      retry_attempt: attempt,
      recovery_task_id: recoveryTask.task_id,
      recovered_at: now.toISOString()
    }
  };
}
