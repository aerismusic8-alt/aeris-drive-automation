import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';

const execFileAsync = promisify(execFile);
const CANONICAL = 'AKATH_CORE/CANONICAL_TASK_REGISTRY.json';

export async function reconcileCanonicalTerminalTasks({ repoRoot, registry, now = new Date() }) {
  const show = await execFileAsync('git', ['show', 'origin/main:' + CANONICAL], { cwd: repoRoot });
  const remote = JSON.parse(show.stdout.replace(/^\uFEFF/,''));
  let changed = false;
  for (const remoteTask of (remote.tasks || [])) {
    const localTask = (registry.tasks || []).find((item) => item?.task_id === remoteTask?.task_id);
    if (!localTask) continue;
    const localTerminal = ['DONE','VERIFIED','COMPLETED'].includes(localTask.status);
    const remotePending = remoteTask.status === 'PENDING';
    const locallyVerified = localTask.verification?.verified === true;
    if (!remotePending || !localTerminal || !locallyVerified || !localTask.result) continue;
    Object.assign(remoteTask, {
      status: 'DONE',
      result: localTask.result,
      verification: localTask.verification,
      evidence: localTask.evidence ?? null,
      completed_at: localTask.completed_at ?? localTask.verified_at ?? now.toISOString(),
      verified_at: localTask.verified_at ?? now.toISOString()
    });
    if (remote.current_work?.active && remote.current_work.task_id === remoteTask.task_id) {
      remote.current_work = {active:false,task_id:remoteTask.task_id,completed_at:remoteTask.completed_at};
    }
    changed = true;
  }
  if (!changed) return {changed:false};
  await execFileAsync('git',['checkout','--',CANONICAL],{cwd:repoRoot});
  await writeFile(resolve(repoRoot,CANONICAL),JSON.stringify(remote,null,2)+'\n','utf8');
  try {
    await execFileAsync('git',['add','--',CANONICAL],{cwd:repoRoot});
    await execFileAsync('git',['-c','user.name=AX Runtime','-c','user.email=ax-runtime@aeris.local','commit','-m','AX reconcile canonical terminal tasks'],{cwd:repoRoot});
    await execFileAsync('git',['push','origin','HEAD:main'],{cwd:repoRoot});
  } finally {
    await execFileAsync('git',['checkout','--',CANONICAL],{cwd:repoRoot}).catch(()=>{});
  }
  return {changed:true};
}

export async function writeBackCanonical({ repoRoot, job, evidence, verification, now = new Date() }) {
  if (!job?.task_id) throw new Error('CANONICAL_WRITEBACK_MISSING_TASK_ID');
  const show = await execFileAsync('git', ['show', 'origin/main:' + CANONICAL], { cwd: repoRoot });
  const registry = JSON.parse(show.stdout.replace(/^\uFEFF/,''));
  const task = Array.isArray(registry.tasks) ? registry.tasks.find((item) => item?.task_id === job.task_id) : null;
  if (!task) return {taskId:job.task_id,status:'DONE',canonical:false,writeBack:'LOCAL_SYSTEM_TASK',completedAt:now.toISOString()};
  const iso = now.toISOString();
  Object.assign(task, { status:'DONE', result:job.result ?? null, verification:verification ?? null, evidence:evidence ? {event:evidence.event ?? 'RESULT',jobId:job.task_id,timestamp:evidence.timestamp ?? iso} : null, completed_at:iso, verified_at:iso });
  if (registry.current_work?.active && registry.current_work.task_id === job.task_id) registry.current_work={active:false,task_id:job.task_id,completed_at:iso};
  await execFileAsync('git', ['checkout','--',CANONICAL], {cwd:repoRoot});
  await writeFile(resolve(repoRoot,CANONICAL), JSON.stringify(registry,null,2)+'\n','utf8');
  try {
    await execFileAsync('git',['add','--',CANONICAL],{cwd:repoRoot});
    await execFileAsync('git',['-c','user.name=AX Runtime','-c','user.email=ax-runtime@aeris.local','commit','-m','AX canonical write-back: '+job.task_id],{cwd:repoRoot});
    await execFileAsync('git',['push','origin','HEAD:main'],{cwd:repoRoot});
  } finally {
    await execFileAsync('git',['checkout','--',CANONICAL],{cwd:repoRoot}).catch(()=>{});
  }
  return {taskId:job.task_id,status:'DONE',canonical:true,completedAt:iso};
}
