import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';

const execFileAsync = promisify(execFile);
const CANONICAL = 'AKATH_CORE/CANONICAL_TASK_REGISTRY.json';

export async function writeBackCanonical({ repoRoot, job, evidence, verification, now = new Date() }) {
  if (!job?.task_id) throw new Error('CANONICAL_WRITEBACK_MISSING_TASK_ID');
  const show = await execFileAsync('git', ['show', 'origin/main:' + CANONICAL], { cwd: repoRoot });
  const registry = JSON.parse(show.stdout);
  const task = Array.isArray(registry.tasks) ? registry.tasks.find((item) => item?.task_id === job.task_id) : null;
  if (!task) throw new Error('CANONICAL_WRITEBACK_TASK_NOT_FOUND:' + job.task_id);
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
