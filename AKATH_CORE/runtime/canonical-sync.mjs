export function mergeCanonicalTasks(localRegistry, remoteRegistry) {
  const localTasks = Array.isArray(localRegistry?.tasks) ? localRegistry.tasks : [];
  const remoteTasks = Array.isArray(remoteRegistry?.tasks) ? remoteRegistry.tasks : [];
  const byId = new Map(localTasks.map((task) => [task.task_id, task]));
  let added = 0;
  let preserved = 0;
  let requeued = 0;

  for (const remoteTask of remoteTasks) {
    if (!remoteTask?.task_id) continue;
    const localTask = byId.get(remoteTask.task_id);
    if (localTask) {
      // A canonical task that already reached DONE/VERIFIED must never be
      // requeued merely because it remains current_work on the remote registry.
      // Requeue only an explicitly FAILED task that the canonical queue still
      // marks PENDING.
      if (remoteTask.status === 'PENDING' && localTask.status === 'FAILED') {
        localTask.status = 'PENDING';
        requeued += 1;
      } else {
        preserved += 1;
      }
      continue;
    }
    localTasks.push(structuredClone(remoteTask));
    byId.set(remoteTask.task_id, localTasks.at(-1));
    added += 1;
  }

  localRegistry.tasks = localTasks;
  if (remoteRegistry?.current_work) {
    localRegistry.current_work = structuredClone(remoteRegistry.current_work);
  }
  return { added, preserved, requeued };
}
