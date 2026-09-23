import { chromium } from 'file:///C:/AX-Runtime/BrowserExecutor/node_modules/playwright/index.mjs';
import fs from 'node:fs';
import path from 'node:path';
import { loadAccountProfile } from './account-profile.mjs';

async function visibleText(page){ return await page.locator('body').innerText({timeout:10000}).catch(()=> ''); }
async function fillIfPresent(page, labels, value){
  if(value===undefined || value===null || value==='') return false;
  for(const label of labels){
    const loc=page.getByLabel(label,{exact:false}).first();
    if(await loc.count() && await loc.isVisible().catch(()=>false)){ await loc.fill(String(value)); return true; }
  }
  return false;
}
export async function executeBrowserTask(job) {
  const root=process.env.AX_BROWSER_ROOT||'C:\\AX-Runtime\\BrowserExecutor';
  const profile=path.join(root,'profile'), evidenceDir=path.join(root,'evidence');
  fs.mkdirSync(profile,{recursive:true}); fs.mkdirSync(evidenceDir,{recursive:true});
  const url=job.url||'https://jumptask.io/'; let context;
  try{
    context=await chromium.launchPersistentContext(profile,{headless:false,executablePath:'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe',args:['--no-first-run','--no-default-browser-check']});
    const page=context.pages()[0]||await context.newPage();
    await page.goto(url,{waitUntil:'domcontentloaded',timeout:30000});
    const action=job.action||'inspect_offer';
    const out={startedAt:new Date().toISOString(),node:process.env.AX_PC1_NODE_ID||'PC1-MAIN',url:page.url(),title:await page.title(),action};
    if(action==='inspect_offer'){
      out.page_text=(await visibleText(page)).slice(0,30000);
      out.buttons=await page.locator('button').allTextContents().catch(()=>[]);
      out.links=await page.locator('a').allTextContents().catch(()=>[]);
    }else if(action==='signup_account'){
      const account=loadAccountProfile();
      out.profile_loaded=true;
      out.fields={
        email:await fillIfPresent(page,['Email','E-mail','Email address'],account.email),
        username:await fillIfPresent(page,['Username','User name'],account.username),
        display_name:await fillIfPresent(page,['Display name','Name'],account.display_name),
        full_name:await fillIfPresent(page,['Full name','Legal name'],account.full_name),
        password:await fillIfPresent(page,['Password'],account.password),
        confirm_password:await fillIfPresent(page,['Confirm password','Repeat password','Password confirmation'],account.password)
      };
      out.page_text_after_fill=(await visibleText(page)).slice(0,20000);
      out.submit_available=await page.getByRole('button',{name:/sign up|register|create account/i}).count().catch(()=>0)>0;
      if(job.submit===true){
        const submit=page.getByRole('button',{name:/sign up|register|create account/i}).first();
        if(await submit.count()===0) throw new Error('SIGNUP_SUBMIT_CONTROL_NOT_FOUND');
        await submit.click();
        await page.waitForLoadState('domcontentloaded',{timeout:15000}).catch(()=>{});
        out.after_url=page.url();
        out.page_text_after_submit=(await visibleText(page)).slice(0,20000);
        out.submitted=true;
        out.human_verification_required=/captcha|verify you are human|one[- ]time|verification code/i.test(out.page_text_after_submit);
      }else out.human_action_required=true;
    }else throw new Error('UNSUPPORTED_BROWSER_ACTION:'+action);
    out.checkedAt=new Date().toISOString(); out.ok=true;
    const evidencePath=path.join(evidenceDir,'browser-'+(job.task_id||'task')+'.json');
    fs.writeFileSync(evidencePath,JSON.stringify(out,null,2));
    return {ok:true,result:out,evidence:{evidence_path:evidencePath,url:out.after_url||out.url,title:out.title,action}};
  }finally{ if(context) await context.close(); }
}