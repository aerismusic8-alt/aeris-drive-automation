import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

export async function dispatchToPc1(job, adapter) {
  if (!adapter || typeof adapter.execute !== 'function') throw new Error('PC1 adapter is required');
  return adapter.execute(job);
}

export function resolvePc1ExecutorCommand(nodeId = process.env.AX_PC1_NODE_ID || 'PC1-MAIN', explicitCommand = process.env.AX_PC1_EXECUTOR_COMMAND) {
  const configured = String(explicitCommand || '').trim();
  if (configured) return configured;
  if (nodeId === 'PC1-MAIN') throw new Error('AX_PC1_EXECUTOR_COMMAND is required when nodeId is PC1-MAIN');
  return process.execPath;
}

export function createLocalPc1Adapter({
  command = resolvePc1ExecutorCommand(),
  executorPath = resolve(dirname(fileURLToPath(import.meta.url)), 'pc1-specialist.mjs'),
  controlExecutorPath = resolve(dirname(fileURLToPath(import.meta.url)), 'pc1-specialist-control.mjs')
} = {}) {
  if (!command) throw new Error('PC1 executor command is not configured');
  return { async execute(job) {
    const {spawn} = await import('node:child_process');
    const selectedExecutor = job?.capability === 'control' ? controlExecutorPath : executorPath;
    return new Promise((resolve,reject)=>{
      const child=spawn(command,[selectedExecutor, JSON.stringify(job)],{shell:false,stdio:['ignore','pipe','pipe']});
      let out='',err=''; child.stdout.on('data',(d)=>out+=d); child.stderr.on('data',(d)=>err+=d);
      child.on('error',reject); child.on('close',(code)=>{
        if(code!==0) return reject(new Error(`PC1 executor exited ${code}: ${err.trim()}`));
        try { resolve(JSON.parse(out)); } catch { reject(new Error(`PC1 executor returned invalid JSON: ${out}`)); }
      });
    });
  }};
}
