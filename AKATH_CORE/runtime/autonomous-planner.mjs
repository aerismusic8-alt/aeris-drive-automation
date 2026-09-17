const PLAN = Object.freeze([
  Object.freeze({
    task_id: 'AKATH-AUTONOMOUS-SELF-CHECK-001',
    capability: 'self_check',
    title: 'Autonomous PC1 runtime self-check',
    action: 'pc1_runtime_self_check'
  }),
  Object.freeze({
    task_id: 'AKATH-AUTONOMOUS-RECOVERY-CHECK-001',
    capability: 'recovery',
    title: 'Autonomous PC1 recovery-path check',
    action: 'pc1_recovery_path_check'
  })
]);

export function planNextTask(registry, now = new Date()) {
  const tasks = registry?.tasks ?? [];
  if (tasks.some((task) => ['PENDING', 'EXECUTING'].includes(task.status))) return null;

  const failed = tasks.find((task) => ['FAILED', 'OVERDUE'].includes(task.status));
  if (failed) {
    const recoveryId = `AKATH-AUTONOMOUS-RECOVERY-${failed.task_id}`;
    if (tasks.some((task) => task.task_id === recoveryId)) return null;
    const created = now.toISOString();
    const deadline = new Date(now.getTime() + 30 * 60 * 1000).toISOString();
    const task = {
      task_id: recoveryId,
      type: 'SYSTEM',
      title: `Recover failed task ${failed.task_id}`,
      status: 'PENDING',
      created_at: created,
      deadline_at: deadline,
      milestones: ['PC1 claims recovery', 'RECOVERY specialist executes', 'EVIDENCE persisted', 'VERIFY passes', 'DONE recorded'],
      completion_criteria: ['specialist returns ok=true', 'evidence contains matching RESULT', 'verification.verified=true', 'task status is DONE'],
      evidence: null,
      verification: null,
      completed_at: null,
      payload: { action: 'pc1_recovery_path_check', capability: 'recovery', autonomous: true, failed_task_id: failed.task_id }
    };
    tasks.push(task);
    return task;
  }

  const completed = new Set(tasks.filter((task) => task.status === 'DONE').map((task) => task.task_id));
  const next = PLAN.find((candidate) => !completed.has(candidate.task_id));
  if (!next) return null;

  const created = now.toISOString();
  const deadline = new Date(now.getTime() + 30 * 60 * 1000).toISOString();
  const task = {
    task_id: next.task_id,
    type: 'SYSTEM',
    title: next.title,
    status: 'PENDING',
    created_at: created,
    deadline_at: deadline,
    milestones: ['PC1 claims task', 'SPECIALIST executes task', 'EVIDENCE persisted', 'VERIFY passes', 'DONE recorded'],
    completion_criteria: ['specialist returns ok=true', 'evidence contains matching RESULT', 'verification.verified=true', 'task status is DONE'],
    evidence: null,
    verification: null,
    completed_at: null,
    payload: { action: next.action, capability: next.capability, autonomous: true }
  };
  tasks.push(task);
  return task;
}
