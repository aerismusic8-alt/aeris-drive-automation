export function planNextRevenueJob(registry, now = new Date()) {
  const tasks = registry?.tasks ?? [];
  if (tasks.some((task) => ['PENDING', 'EXECUTING'].includes(task.status))) return null;

  const sequence = tasks.filter((task) => task.capability === 'revenue').length + 1;
  const created = now.toISOString();
  const deadline = new Date(now.getTime() + 30 * 60 * 1000).toISOString();

  return {
    task_id: `PC2-REV-YT-SHORT-${sequence}-${now.getTime()}`,
    type: 'REVENUE',
    title: 'AERIS YouTube Short production package',
    capability: 'revenue',
    action: 'youtube_short_package',
    status: 'PENDING',
    created_at: created,
    deadline_at: deadline,
    milestones: [
      'PC2 claims revenue job',
      'PowerShell prepares upload package',
      'Evidence persisted',
      'Verification passes',
      'DONE recorded'
    ],
    completion_criteria: [
      'specialist returns ok=true',
      'exitCode=0',
      'package manifest exists',
      'verification.verified=true'
    ],
    evidence: null,
    verification: null,
    completed_at: null,
    payload: {
      action: 'youtube_short_package',
      capability: 'revenue',
      channel: 'AERISMusicTH',
      autonomous: true,
      source: 'AERIS_REVENUE_INPUT',
      output: 'AERIS_REVENUE_OUTPUT'
    }
  };
}
