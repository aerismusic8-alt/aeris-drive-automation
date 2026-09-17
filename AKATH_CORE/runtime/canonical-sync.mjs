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
      if (localTask.status === 'FAILED' && remoteTask.status === 'PENDING') {
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
  return { added, preserved, requeued };
}
