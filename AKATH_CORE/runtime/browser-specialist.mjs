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


async function selectNextOffer(page,job={}){
  const excluded=new Set(job.exclude_labels||[]);
  const preferred=[
    'Follow JumpTask on X!',
    'Like Simply Bitcoin tweet on X!',
    'Join Pepperstone on Telegram!',
    'Join Pepperstone Announcements on Telegram!',
    '#7230 Search, Follow & Earn!',
    'iPhone 17 Pro CPL Multigeo Incent',
    'Modern Spin Quest - Complete multiple tasks!',
    'Wood Nuts & Bolts Screw Puzzle - Complete multiple tasks!',
    'Ultima Markets CPA Multigeo Android/iOS Incent'
  ];
  for(const label of preferred){
    if(excluded.has(label)) continue;
    const found=await page.evaluate((target)=>{
      const els=[...document.querySelectorAll('*')];
      const norm=s=>(s||'').replace(/\\s+/g,' ').trim();
      const el=els.find(e=>norm(e.innerText||e.textContent)===target && (()=>{const r=e.getBoundingClientRect(),s=getComputedStyle(e);return r.width>0&&r.height>0&&s.visibility!=='hidden'&&s.display!=='none'})());
      if(!el) return false;
      const clickable=el.closest('a,button,[role="button"],[role="link"]')||el;
      clickable.scrollIntoView({block:'center',inline:'center'});
      clickable.click();
      return true;
    },label).catch(()=>false);
    if(found){
      await page.waitForTimeout(1200);
      return {selected:true,pattern:label,url:page.url(),text:(await visibleText(page)).slice(-12000)};
    }
  }
  return {selected:false};
}

async function classifyOffer(inspection){
  const t=(inspection.page_text||'').toLowerCase();
  const blockers=[
    /captcha|verify you are human|human verification/,
    /one[- ]time password|otp|verification code/,
    /credit card|payment method|deposit|pay now/,
    /government id|passport|national id/,
    /sign up|signup|register|create account/,
    /phone number|mobile number/
  ];
  const hits=blockers.filter(r=>r.test(t)).map(String);
  return {blocked:hits.length>0,blockers:hits};
}

async function workerCycle(page,job={}){
  const maxAttempts=Math.max(1,Number(job.max_offer_attempts||5));
  const tried=[];
  for(let attempt=1;attempt<=maxAttempts;attempt++){
    const inspection=await inspectOffer(page);
    const classification=await classifyOffer(inspection);
    tried.push({attempt,url:page.url(),start_task_visible:inspection.start_task_visible,classification});
    if(classification.blocked || !inspection.start_task_visible){
      const next=await selectNextOffer(page,{exclude_labels:job.exclude_labels||[]});
      if(!next.selected) return {status:'NO_VIABLE_OFFER',tried};
      continue;
    }
    const start=await findStartTask(page);
    await start.click();
    await page.waitForLoadState('domcontentloaded',{timeout:15000}).catch(()=>{});
    await page.waitForTimeout(1500);
    const afterText=(await visibleText(page)).slice(0,20000);
    const afterBlocked=/captcha|verify you are human|verification code|one[- ]time|credit card|payment method|sign up|signup|register|create account/i.test(afterText);
    if(afterBlocked){
      const next=await selectNextOffer(page,{exclude_labels:job.exclude_labels||[]});
      if(!next.selected) return {status:'STARTED_BUT_BLOCKED_NO_NEXT',tried,after_text:afterText};
      continue;
    }
    return {
      status:'STARTED_EXECUTION_REQUIRED',
      tried,
      started:true,
      after_url:page.url(),
      after_text:afterText
    };
  }
  return {status:'MAX_ATTEMPTS_REACHED',tried};
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
    const cdpUrl=job.cdp_url||process.env.AX_BROWSER_CDP_URL||(process.env.AX_PC1_NODE_ID==='PC1-MAIN'?'http://127.0.0.1:9222':null);
    if(cdpUrl){ const browser=await chromium.connectOverCDP(cdpUrl); context=browser.contexts()[0]; connected=true; }
    else context=await chromium.launchPersistentContext(profile,{
      headless:false,
      executablePath:'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe',
      args:['--no-first-run','--no-default-browser-check']
    });
    const pages=context.pages();
    const page=pages.find(p=>/jumptask/i.test(p.url()))||pages[0]||await context.newPage();
    if(!job.use_current_page || page.url()==='about:blank') await page.goto(url,{waitUntil:'domcontentloaded',timeout:30000});

    const requestedAction=job.action||'inspect_offer';
    const action=requestedAction==='start_task'?'inspect_and_start_offer':requestedAction;
    const out={
      startedAt:new Date().toISOString(),
      node:process.env.AX_PC1_NODE_ID||'PC1-MAIN',
      url:page.url(),
      title:await page.title(),
      action
    };

    if(action==='offer_worker_cycle'){ Object.assign(out,await workerCycle(page,job)); }
    else if(action==='inspect_offer'){
      Object.assign(out,await inspectOffer(page));
    }else if(action==='select_next_offer'){ Object.assign(out,await selectNextOffer(page,job)); if(!out.selected) throw new Error('NO_NEXT_OFFER_FOUND'); }
    else if(action==='inspect_and_start_offer'){
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
    if(context && job.close_after_task===true){
      if(connected){
        for(const p of context.pages()) await p.close().catch(()=>{});
      } else {
        await context.close().catch(()=>{});
      }
    } else if(context && !connected && job.keep_open!==true) await context.close();
  }
}