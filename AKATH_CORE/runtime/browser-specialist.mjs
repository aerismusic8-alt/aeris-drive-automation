import { chromium } from 'file:///C:/AX-Runtime/BrowserExecutor/node_modules/playwright/index.mjs';
import fs from 'node:fs';
import path from 'node:path';

async function visibleText(page){ return await page.locator('body').innerText({timeout:10000}).catch(()=> ''); }

async function findStartTask(page){
  const candidates=[
    page.getByRole('button',{name:/^start\s*task$/i}).first(),
    page.getByRole('link',{name:/^start\s*task$/i}).first(),
    page.getByText(/^start\s*task$/i).first()
  ];
  for(const loc of candidates){
    if(await loc.count() && await loc.isVisible().catch(()=>false)) return loc;
  }
  return null;
}

async function inspectOffer(page){
  const text=(await visibleText(page)).slice(0,30000);
  const start=await findStartTask(page);
  return {
    page_text:text,
    buttons:await page.locator('button').allTextContents().catch(()=>[]),
    links:await page.locator('a').allTextContents().catch(()=>[]),
    start_task_visible:Boolean(start),
    inspected_before_start:true
  };
}

export async function executeBrowserTask(job) {
  const root=process.env.AX_BROWSER_ROOT||'C:\\AX-Runtime\\BrowserExecutor';
  const profile=path.join(root,'profile'), evidenceDir=path.join(root,'evidence');
  fs.mkdirSync(profile,{recursive:true}); fs.mkdirSync(evidenceDir,{recursive:true});
  const url=job.url||'https://jumptask.io/';
  let context; let connected=false;
  try{
    const cdpUrl=job.cdp_url||process.env.AX_BROWSER_CDP_URL;
    if(cdpUrl){ const browser=await chromium.connectOverCDP(cdpUrl); context=browser.contexts()[0]; connected=true; }
    else context=await chromium.launchPersistentContext(profile,{
      headless:false,
      executablePath:'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe',
      args:['--no-first-run','--no-default-browser-check']
    });
    const pages=context.pages();
    const page=pages.find(p=>/jumptask/i.test(p.url()))||pages[0]||await context.newPage();
    if(!job.use_current_page || page.url()==='about:blank') await page.goto(url,{waitUntil:'domcontentloaded',timeout:30000});

    const action=job.action||'inspect_offer';
    const out={
      startedAt:new Date().toISOString(),
      node:process.env.AX_PC1_NODE_ID||'PC1-MAIN',
      url:page.url(),
      title:await page.title(),
      action
    };

    if(action==='inspect_offer'){
      Object.assign(out,await inspectOffer(page));
    }else if(action==='inspect_and_start_offer'){
      const inspection=await inspectOffer(page);
      Object.assign(out,inspection);
      if(!inspection.start_task_visible) throw new Error('START_TASK_NOT_FOUND_AFTER_OFFER_INSPECTION');
      const start=await findStartTask(page);
      await start.click();
      await page.waitForLoadState('domcontentloaded',{timeout:15000}).catch(()=>{});
      await page.waitForTimeout(1500);
      out.started=true;
      out.after_url=page.url();
      out.after_text=(await visibleText(page)).slice(0,20000);
      out.human_verification_required=/captcha|verify you are human|verification code|one[- ]time/i.test(out.after_text);
    }else{
      throw new Error('UNSUPPORTED_BROWSER_ACTION:'+action);
    }

    out.checkedAt=new Date().toISOString();
    out.ok=true;
    const evidencePath=path.join(evidenceDir,'browser-'+(job.task_id||'task')+'.json');
    fs.writeFileSync(evidencePath,JSON.stringify(out,null,2));
    return {ok:true,result:out,evidence:{
      evidence_path:evidencePath,
      url:out.after_url||out.url,
      title:out.title,
      action,
      inspected_before_start:out.inspected_before_start===true,
      started:out.started===true
    }};
  }finally{
    if(context && !connected && job.keep_open!==true) await context.close();
  }
}