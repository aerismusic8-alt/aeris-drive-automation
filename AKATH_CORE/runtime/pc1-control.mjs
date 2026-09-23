import { spawn } from 'node:child_process';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const ALLOWED_ACTIONS=Object.freeze({
  pc1_status:Object.freeze({script:'$PSVersionTable.PSVersion.ToString()'}),
  runtime_status:Object.freeze({script:'Get-Date -Format o; Get-Process node -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Id'})
});

export function listAllowedControlActions(){ return [...Object.keys(ALLOWED_ACTIONS),'offer_inspect','offer_inspect_and_start']; }

function runProcess(command,args,timeoutMs){
  return new Promise((resolvePromise,reject)=>{
    const child=spawn(command,args,{shell:false,stdio:['ignore','pipe','pipe']});
    let stdout='',stderr='',settled=false;
    const timer=setTimeout(()=>{child.kill();if(!settled){settled=true;reject(new Error('CONTROL_PROCESS_TIMEOUT'))}},timeoutMs);
    child.stdout.on('data',d=>stdout+=d);
    child.stderr.on('data',d=>stderr+=d);
    child.on('error',e=>{if(!settled){settled=true;clearTimeout(timer);reject(e)}});
    child.on('close',code=>{
      if(settled)return;
      settled=true;clearTimeout(timer);
      if(code!==0) return reject(new Error(stderr.trim()||('PROCESS_EXIT_'+code)));
      resolvePromise({stdout:stdout.trim(),stderr:stderr.trim(),exitCode:code});
    });
  });
}

export async function executeControlTask(job,{
  spawnImpl=spawn,
  powershell=process.env.AX_POWERSHELL||'powershell.exe',
  timeoutMs=Number(process.env.AX_CONTROL_TIMEOUT_MS||30000)
}={}) {
  const action=job?.action||job?.payload?.action;

  if(action==='offer_inspect' || action==='offer_inspect_and_start'){
    const runtimeDir=dirname(fileURLToPath(import.meta.url));
    const executor=resolve(runtimeDir,'pc1-specialist.mjs');
    const browserJob={
      ...job,
      capability:'browser',
      action:action==='offer_inspect_and_start'?'inspect_and_start_offer':'inspect_offer',
      use_current_page:job.use_current_page!==false,
      keep_open:job.keep_open!==false,
      cdp_url:job.cdp_url||process.env.AX_BROWSER_CDP_URL||'http://127.0.0.1:9222'
    };
    const result=await runProcess(process.execPath,[executor,JSON.stringify(browserJob)],timeoutMs);
    let parsed;
    try{ parsed=JSON.parse(result.stdout); }catch{ throw new Error('BROWSER_CONTROL_INVALID_JSON:'+result.stdout); }
    if(!parsed.ok) throw new Error('BROWSER_CONTROL_FAILED');
    return {
      action,
      command:'PC1 browser specialist: '+browserJob.action,
      exitCode:result.exitCode,
      stdout:result.stdout,
      stderr:result.stderr,
      offer_inspected:parsed.evidence?.inspected_before_start===true || parsed.result?.inspected_before_start===true,
      started:parsed.evidence?.started===true || parsed.result?.started===true
    };
  }

  const definition=ALLOWED_ACTIONS[action];
  if(!definition) throw new Error(`Control action is not allowlisted: ${action||'missing'}`);

  return new Promise((resolvePromise,reject)=>{
    const child=spawnImpl(powershell,['-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-Command',definition.script],{shell:false,stdio:['ignore','pipe','pipe']});
    let stdout='',stderr='',settled=false;
    const finish=(fn,value)=>{if(settled)return;settled=true;clearTimeout(timer);fn(value)};
    const timer=setTimeout(()=>{child.kill();finish(reject,new Error(`PowerShell control timed out after ${timeoutMs}ms`))},timeoutMs);
    child.stdout.on('data',data=>stdout+=data);
    child.stderr.on('data',data=>stderr+=data);
    child.on('error',error=>finish(reject,error));
    child.on('close',code=>{
      if(code!==0){finish(reject,new Error(`PowerShell exited ${code}: ${stderr.trim()}`));return}
      finish(resolvePromise,{action,command:definition.script,exitCode:code,stdout:stdout.trim(),stderr:stderr.trim()});
    });
  });
}