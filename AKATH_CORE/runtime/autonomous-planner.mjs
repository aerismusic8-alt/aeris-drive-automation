import { planRecoveryRetry } from './recovery-planner.mjs';
import { transitionJob } from './task-store.mjs';

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

function markExpiredCurrentWorkOverdue(registry, now) {
  const currentTaskId = registry?.current_work?.active ? registry.current_work.task_id : null;
  if (!currentTaskId) return null;
  const currentTask = registry.tasks.find((task) => task.task_id === currentTaskId);
  if (!currentTask || currentTask.status !== 'PENDING' || !currentTask.deadline_at) return null;
  if (new Date(currentTask.deadline_at) > now) return null;

  transitionJob(currentTask, 'OVERDUE', {
    root_cause: 'deadline_exceeded_before_claim',
    correction: 'autonomous_planner_recovery_path',
    overdue_at: now.toISOString()
  });
  return currentTask;
}

function markAllExpiredPendingOverdue(registry, now) {
  const expired = [];
  for (const task of registry?.tasks ?? []) {
    if (task.status !== 'PENDING' || !task.deadline_at) continue;
    if (new Date(task.deadline_at) <= now) {
      transitionJob(task, 'OVERDUE', {
        root_cause: 'deadline_exceeded_before_claim',
        correction: 'autonomous_planner_recovery_path',
        overdue_at: now.toISOString()
      });
      expired.push(task);
    }
  }
  return expired;
}

export function planNextTask(registry, now = new Date()) {
  const tasks = registry?.tasks ?? [];
  markExpiredCurrentWorkOverdue(registry, now);
  markAllExpiredPendingOverdue(registry, now);
  if (tasks.some((task) => ['PENDING', 'EXECUTING'].includes(task.status))) return null;

  const failed = tasks.find((task) => ['FAILED', 'OVERDUE'].includes(task.status));
  if (!failed) {
    // Persistent AX management mode: when the queue is genuinely empty,
    // keep the controller alive by scheduling a lightweight management
    // self-check. Real externally-issued work takes priority because this
    // task is created only when no PENDING/EXECUTING task exists.
    const created = now.toISOString();
    const tickId = `AKATH-AX-MANAGEMENT-TICK-${now.getTime()}`;
    const managementTick = {
      task_id: tickId,
      type: 'SYSTEM',
      title: 'AX persistent management cycle',
      capability: 'self_check',
      action: 'ax_autonomous_management_tick',
      status: 'PENDING',
      created_at: created,
      deadline_at: new Date(now.getTime() + 60 * 1000).toISOString(),
      milestones: [
        'AX controller selects next eligible workload',
        'PC1 claims management cycle',
        'SPECIALIST executes self-check',
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
      payload: {
        action: 'ax_autonomous_management_tick',
        capability: 'self_check',
        autonomous: true,
        controller: 'AX',
        purpose: 'keep autonomous management loop active while awaiting real workload'
      }
    };
    tasks.push(managementTick);
    return managementTick;
  }

  const recoveryId = `AKATH-AUTONOMOUS-RECOVERY-${failed.task_id}`;
  const existingRecovery = tasks.find((task) => task.task_id === recoveryId);
  if (!existingRecovery) {
    const recovery = buildRecoveryTask({ failedTaskId: failed.task_id, now });
    tasks.push(recovery);
    return recovery;
  }

  if (existingRecovery.status === 'DONE') {
    const retry = planRecoveryRetry(registry, existingRecovery, now);
    if (retry) {
      tasks.push(retry);
      return retry;
    }
  }

  return null;
}
