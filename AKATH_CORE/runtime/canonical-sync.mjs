export function mergeCanonicalTasks(localRegistry, remoteRegistry) {
  const localTasks = Array.isArray(localRegistry?.tasks) ? localRegistry.tasks : [];
  const remoteTasks = Array.isArray(remoteRegistry?.tasks) ? remoteRegistry.tasks : [];
  const byId = new Map(localTasks.map((task) => [task.task_id, task]));
  let added = 0;
  let preserved = 0;
  let requeued = 0;
  let currentRehydrated = 0;

  const currentTaskId = remoteRegistry?.current_work?.active
    ? remoteRegistry.current_work.task_id
    : null;

  for (const remoteTask of remoteTasks) {
    if (!remoteTask?.task_id) continue;
    const localTask = byId.get(remoteTask.task_id);

    if (!localTask) {
      localTasks.push(structuredClone(remoteTask));
      byId.set(remoteTask.task_id, localTasks.at(-1));
      added += 1;
      if (remoteTask.task_id === currentTaskId && remoteTask.status === 'PENDING') currentRehydrated += 1;
      continue;
    }

    const isCanonicalCurrent = remoteTask.task_id === currentTaskId;
    const isFreshProductiveCurrent = isCanonicalCurrent
      && remoteTask.status === 'PENDING'
      && (remoteTask.type === 'PRODUCTION' || remoteTask.capability === 'ai' || remoteTask.capability === 'execution');

    const localTerminal = ['DONE', 'VERIFIED', 'COMPLETED'].includes(localTask.status);
    const localActive = ['EXECUTING'].includes(localTask.status);
    const metadataChanged = localTask.created_at !== remoteTask.created_at
      || localTask.deadline_at !== remoteTask.deadline_at
      || localTask.action !== remoteTask.action;

    if (
      (isFreshProductiveCurrent && !localTerminal && !localActive)
      || (isFreshProductiveCurrent && localTerminal && metadataChanged)
      || (remoteTask.status === 'PENDING' && localTask.status === 'FAILED')
    ) {
      Object.assign(localTask, structuredClone(remoteTask));
      requeued += 1;
      if (isFreshProductiveCurrent) currentRehydrated += 1;
    } else {
      preserved += 1;
    }
  }

  localRegistry.tasks = localTasks;
  if (remoteRegistry?.current_work) localRegistry.current_work = structuredClone(remoteRegistry.current_work);

  return { added, preserved, requeued, currentRehydrated };
}
