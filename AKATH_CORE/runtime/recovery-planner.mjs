function nextRetryAttempt(tasks, failedTaskId) {
  const prefix = `${failedTaskId}-RETRY-`;
  const attempts = tasks
    .filter((task) => task.task_id?.startsWith(prefix))
    .map((task) => Number(task.task_id.slice(prefix.length)))
    .filter(Number.isInteger);
  return attempts.length ? Math.max(...attempts) + 1 : 1;
}

export function planRecoveryRetry(registry, recoveryTask, now = new Date()) {
  const failedTaskId = recoveryTask?.payload?.failed_task_id;
  if (!failedTaskId) return null;

  const tasks = registry?.tasks ?? [];
  const failedTask = tasks.find((task) => task.task_id === failedTaskId);
  if (!failedTask) return null;

  const retryAttempt = nextRetryAttempt(tasks, failedTaskId);
  const retryId = `${failedTaskId}-RETRY-${retryAttempt}`;
  if (tasks.some((task) => task.task_id === retryId)) return null;

  return {
    ...failedTask,
    task_id: retryId,
    status: 'PENDING',
    created_at: now.toISOString(),
    deadline_at: new Date(now.getTime() + 30 * 60 * 1000).toISOString(),
    milestones: [
      'PC1 claims retry task',
      'SPECIALIST executes retry',
      'EVIDENCE persisted',
      'VERIFY passes',
      'DONE recorded'
    ],
    completion_criteria: [
      'specialist returns ok=true',
      'evidence contains matching RESULT',
      'verification.verified=true',
      'task status is DONE'
    ],
    evidence: null,
    verification: null,
    completed_at: null,
    result: null,
    payload: {
      ...(failedTask.payload || {}),
      recovery_of: failedTaskId,
      retry_attempt: retryAttempt,
      recovery_task_id: recoveryTask.task_id,
      recovered_at: now.toISOString()
    }
  };
}
