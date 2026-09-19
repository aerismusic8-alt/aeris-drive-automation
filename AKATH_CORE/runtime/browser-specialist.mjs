import { chromium } from 'file:///C:/AX-Runtime/BrowserExecutor/node_modules/playwright/index.mjs';
import fs from 'node:fs';
import path from 'node:path';

export async function executeBrowserTask(job) {
  const root = process.env.AX_BROWSER_ROOT || 'C:\\AX-Runtime\\BrowserExecutor';
  const profile = path.join(root, 'profile');
  const evidenceDir = path.join(root, 'evidence');
  fs.mkdirSync(profile,{recursive:true}); fs.mkdirSync(evidenceDir,{recursive:true});
  const url = job.url || 'https://jumptask.io/';
  let context;
  try {
    context = await chromium.launchPersistentContext(profile,{headless:false,executablePath:'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe',args:['--no-first-run','--no-default-browser-check']});
    const page = context.pages()[0] || await context.newPage();
    await page.goto(url,{waitUntil:'domcontentloaded',timeout:30000});
    const title = await page.title(); const finalUrl = page.url();
    const loginCount = await page.locator('text=Log in').count();
    const out = {startedAt:new Date().toISOString(),node:process.env.AX_PC1_NODE_ID||'PC2-MAIN',url:finalUrl,title,authenticated:loginCount===0,checkedAt:new Date().toISOString(),ok:true};
    const evidencePath=path.join(evidenceDir,'browser-'+(job.task_id||'task')+'.json');
    fs.writeFileSync(evidencePath,JSON.stringify(out,null,2));
    return {ok:true,result:out,evidence:{evidence_path:evidencePath,url:finalUrl,title,authenticated:out.authenticated}};
  } finally { if(context) await context.close(); }
}
