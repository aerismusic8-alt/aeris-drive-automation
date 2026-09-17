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

function buildContinuationTask({ now }) {
  const created = now.toISOString();
  const deadline = new Date(now.getTime() + 30 * 60 * 1000).toISOString();
  return {
    task_id: 'AKATH-PC1-AUTONOMOUS-CONTINUATION-001',
    type: 'SYSTEM',
    title: 'Autonomous PC1 execution continuation',
    capability: 'execution',
    action: 'pc1_autonomous_execution_continuation',
    status: 'PENDING',
    created_at: created,
    deadline_at: deadline,
    milestones: ['PC1 claims next task', 'SPECIALIST executes task', 'EVIDENCE persisted', 'VERIFY passes', 'DONE recorded'],
    completion_criteria: ['specialist returns ok=true', 'evidence contains matching RESULT', 'verification.verified=true', 'task status is DONE'],
    evidence: null,
    verification: null,
    completed_at: null,
    payload: {
      action: 'pc1_autonomous_execution_continuation',
      capability: 'execution',
      autonomous: true,
      objective: 'continue the verified execution loop without human-per-cycle intervention'
    }
  };
}

export function planNextTask(registry, now = new Date()) {
  const tasks = registry?.tasks ?? [];
  if (tasks.some((task) => ['PENDING', 'EXECUTING'].includes(task.status))) return null;

  const failed = tasks.find((task) => ['FAILED', 'OVERDUE'].includes(task.status));
  if (failed) {
    const recoveryId = `AKATH-AUTONOMOUS-RECOVERY-${failed.task_id}`;
    const existingRecovery = tasks.find((task) => task.task_id === recoveryId);
    if (!existingRecovery) {
      const recovery = buildRecoveryTask({ failedTaskId: failed.task_id, now });
      tasks.push(recovery);
      return recovery;
    }
    if (existingRecovery.status !== 'DONE') return null;
  }

  const continuationId = 'AKATH-PC1-AUTONOMOUS-CONTINUATION-001';
  const existingContinuation = tasks.find((task) => task.task_id === continuationId);
  if (!existingContinuation) {
    const continuation = buildContinuationTask({ now });
    tasks.push(continuation);
    return continuation;
  }

  return null;
}
