function buildRecoveryTask({ failedTaskId, now }) {
  const created = now.toISOString();
  const deadline = new Date(now.getTime() + 30 * 60 * 1000).toISOString();
  return {
    task_id: `AKATH-AUTONOMOUS-RECOVERY-${failedTaskId}`,
    type: 'SYSTEM',
    title: `Recover failed task ${failedTaskId}`,
    capability: 'recovery',
    action: 'pc1_recovery_path_check',
    status: 'PENDING',
    created_at: created,
    deadline_at: deadline,
    milestones: ['PC1 claims task', 'SPECIALIST executes task', 'EVIDENCE persisted', 'VERIFY passes', 'DONE recorded'],
    completion_criteria: ['specialist returns ok=true', 'evidence contains matching RESULT', 'verification.verified=true', 'task status is DONE'],
    evidence: null,
    verification: null,
    completed_at: null,
    payload: {
      action: 'pc1_recovery_path_check',
      capability: 'recovery',
      autonomous: true,
      failed_task_id: failedTaskId
    }
  };
}

export function planNextTask(registry, now = new Date()) {
  const tasks = registry?.tasks ?? [];
  if (tasks.some((task) => ['PENDING', 'EXECUTING'].includes(task.status))) return null;

  const failed = tasks.find((task) => ['FAILED', 'OVERDUE'].includes(task.status));
  if (!failed) return null;

  const recoveryId = `AKATH-AUTONOMOUS-RECOVERY-${failed.task_id}`;
  const existingRecovery = tasks.find((task) => task.task_id === recoveryId);
  if (!existingRecovery) {
    const recovery = buildRecoveryTask({ failedTaskId: failed.task_id, now });
    tasks.push(recovery);
    return recovery;
  }

  if (existingRecovery.status !== 'DONE') return null;
  return null;
}
