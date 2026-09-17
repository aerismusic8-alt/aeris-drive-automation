const PLAN = Object.freeze([
  Object.freeze({
    capability: 'self_check',
    title: 'Autonomous PC1 runtime self-check',
    action: 'pc1_runtime_self_check'
  }),
  Object.freeze({
    capability: 'recovery',
    title: 'Autonomous PC1 recovery-path check',
    action: 'pc1_recovery_path_check'
  })
]);

function nextSequence(tasks, prefix) {
  let max = 0;
  for (const task of tasks) {
    const match = String(task.task_id ?? '').match(new RegExp(`^${prefix}-(\\d+)$`));
    if (match) max = Math.max(max, Number(match[1]));
  }
  return max + 1;
}

function buildTask({ taskId, capability, title, action, now, failedTaskId = null }) {
  const created = now.toISOString();
  const deadline = new Date(now.getTime() + 30 * 60 * 1000).toISOString();
  return {
    task_id: taskId,
    type: 'SYSTEM',
    title,
    status: 'PENDING',
    created_at: created,
    deadline_at: deadline,
    milestones: ['PC1 claims task', 'SPECIALIST executes task', 'EVIDENCE persisted', 'VERIFY passes', 'DONE recorded'],
    completion_criteria: ['specialist returns ok=true', 'evidence contains matching RESULT', 'verification.verified=true', 'task status is DONE'],
    evidence: null,
    verification: null,
    completed_at: null,
    payload: {
      action,
      capability,
      autonomous: true,
      ...(failedTaskId ? { failed_task_id: failedTaskId } : {})
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
      const recovery = buildTask({
        taskId: recoveryId,
        capability: 'recovery',
        title: `Recover failed task ${failed.task_id}`,
        action: 'pc1_recovery_path_check',
        now,
        failedTaskId: failed.task_id
      });
      tasks.push(recovery);
      return recovery;
    }
    if (existingRecovery.status !== 'DONE') return null;
  }

  const selfCheckPrefix = 'AKATH-AUTONOMOUS-SELF-CHECK';
  const selfCheckSequence = nextSequence(tasks, selfCheckPrefix);
  const candidate = PLAN[0];
  const task = buildTask({
    taskId: `${selfCheckPrefix}-${String(selfCheckSequence).padStart(3, '0')}`,
    capability: candidate.capability,
    title: candidate.title,
    action: candidate.action,
    now
  });
  tasks.push(task);
  return task;
}
