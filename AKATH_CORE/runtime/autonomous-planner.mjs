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
    payload: { action: 'pc1_recovery_path_check', capability: 'recovery', autonomous: true, failed_task_id: failedTaskId }
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
    payload: { action: 'pc1_autonomous_execution_continuation', capability: 'execution', autonomous: true, objective: 'continue the verified execution loop without human-per-cycle intervention' }
  };
}

function buildPowerShellGateTask({ now }) {
  const created = now.toISOString();
  const deadline = new Date(now.getTime() + 10 * 60 * 1000).toISOString();
  return {
    task_id: `AKATH-PC1-POWERSHELL-CONTROL-${now.getTime()}`,
    type: 'SYSTEM',
    title: 'Verify autonomous allowlisted PowerShell control',
    capability: 'powershell',
    action: 'runtime_heartbeat',
    status: 'PENDING',
    created_at: created,
    deadline_at: deadline,
    milestones: ['PC1 claims task', 'PowerShell executes allowlisted action', 'stdout/stderr/exitCode captured', 'EVIDENCE persisted', 'VERIFY passes', 'DONE recorded'],
    completion_criteria: ['specialist returns ok=true', 'exitCode=0', 'evidence contains stdout', 'verification.verified=true', 'task status is DONE'],
    evidence: null,
    verification: null,
    completed_at: null,
    payload: { action: 'runtime_heartbeat', capability: 'powershell', autonomous: true, objective: 'prove the bot can control PowerShell without K typing each cycle' }
  };
}

export function planNextTask(registry, now = new Date()) {
  const tasks = registry?.tasks ?? [];
  if (tasks.some((task) => ['PENDING', 'EXECUTING'].includes(task.status))) return null;

  const failed = tasks.find((task) => ['FAILED', 'OVERDUE'].includes(task.status));
  if (failed) {
    const recoveryId = `AKATH-AUTONOMOUS-RECOVERY-${failed.task_id}`;
    const existingRecovery = tasks.find((task) => task.task_id === recoveryId);
    if (!existingRecovery) return tasks.push(buildRecoveryTask({ failedTaskId: failed.task_id, now })) && tasks.at(-1);
    if (existingRecovery.status !== 'DONE') return null;
    if (failed.capability === 'powershell') {
      failed.status = 'PENDING';
      failed.recovered_at = now.toISOString();
      failed.error = null;
      failed.verification = null;
      return failed;
    }
  }

  const continuationId = 'AKATH-PC1-AUTONOMOUS-CONTINUATION-001';
  const existingContinuation = tasks.find((task) => task.task_id === continuationId);
  if (!existingContinuation) return tasks.push(buildContinuationTask({ now })) && tasks.at(-1);

  const existingPowerShell = tasks.find((task) => task.capability === 'powershell');
  if (!existingPowerShell) return tasks.push(buildPowerShellGateTask({ now })) && tasks.at(-1);

  return null;
}
