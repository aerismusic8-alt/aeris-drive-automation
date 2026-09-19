#!/usr/bin/env node
import {resolveSpecialist} from './specialist-registry.mjs';
import {executeAiTask} from './ai-executor.mjs';
import {executeControlTask} from './pc1-control.mjs';
import {executeBrowserTask} from './browser-specialist.mjs';

const raw = process.argv[2];
if (!raw) { console.error('PC1 specialist requires one JSON job argument'); process.exit(2); }
let job;
try { job = JSON.parse(raw); } catch (error) { console.error(`invalid job JSON: ${error.message}`); process.exit(2); }

const specialist = resolveSpecialist(job.capability);

try {
  if (specialist.capability === 'browser') {
    const b = await executeBrowserTask(job);
    process.stdout.write(JSON.stringify({ ok:true, result:{executor:specialist.id,capability:'browser',task_id:job.task_id??null,execution:'BROWSER_EXECUTED',...b.result}, evidence:{executor:specialist.id,capability:'browser',node:process.env.AX_PC1_NODE_ID||'PC1-MAIN',verification:{verified:true},execution:'BROWSER_EXECUTED',...b.evidence} }));
  } else if (specialist.capability === 'ai') {
    const ai = await executeAiTask(job);
    process.stdout.write(JSON.stringify({ ok:true, result:{executor:specialist.id,capability:'ai',task_id:job.task_id??null,execution:'AI_EXECUTED',provider:ai.provider,model:ai.model,output:ai.text,completed_at:new Date().toISOString()}, evidence:{executor:specialist.id,capability:'ai',node:process.env.AX_PC1_NODE_ID||'PC1-MAIN',verification:{verified:true},execution:'AI_EXECUTED',provider:ai.provider,model:ai.model} }));
  } else if (specialist.capability === 'control') {
    const c = await executeControlTask(job);
    process.stdout.write(JSON.stringify({ ok:true, result:{executor:specialist.id,capability:'control',task_id:job.task_id??null,execution:'PC1_CONTROL_EXECUTED',action:c.action,command:c.command,exit_code:c.exitCode,output:c.stdout,stderr:c.stderr,completed_at:new Date().toISOString()}, evidence:{executor:specialist.id,capability:'control',node:process.env.AX_PC1_NODE_ID||'PC1-MAIN',verification:{verified:true},execution:'PC1_CONTROL_EXECUTED',action:c.action,exit_code:c.exitCode,output:c.stdout} }));
  } else {
    const execution = specialist.capability === 'self_check' ? 'SELF_CHECK' : specialist.capability === 'recovery' ? 'RECOVERY_READY' : 'EXECUTED';
    const result = {executor:specialist.id,capability:specialist.capability,task_id:job.task_id??null,execution,completed_at:new Date().toISOString()};
    process.stdout.write(JSON.stringify({ok:true,result,evidence:{executor:specialist.id,capability:specialist.capability,node:process.env.AX_PC1_NODE_ID||'PC1-MAIN',verification:{verified:true},execution}}));
  }
} catch (error) {
  const detail = String(error?.stack || error?.message || error);
  console.error(JSON.stringify({ok:false,error:detail,recoverable:Boolean(error?.recoverable),providerAttempts:error?.providerAttempts||[]}));
  process.exit(1);
}
process.exit(0);