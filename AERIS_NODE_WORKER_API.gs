/* AERIS NODE WORKER API v1
 * Merge into AERIS_Code.gs and route from doGet/doPost.
 * Queue source: main AERIS command queue sheet `ชีต1`.
 * Live financial execution remains disabled.
 */

const AERIS_WORKER_CLAIM_TTL_MS = 10 * 60 * 1000;

function aerisWorkerPull_(workerId) {
  if (!workerId) throw new Error('MISSING_WORKER_ID');
  const sheet = getQueueSheet();
  const data = sheet.getDataRange().getValues();
  if (data.length < 2) return {success:true,available:false,workerId:workerId};
  const headers = data[0].map(function(h){return String(h).trim();});
  const idx = {};
  headers.forEach(function(h,i){idx[h.toLowerCase()]=i;});
  const required = ['job id','command','file id','file name','destination','approved','content','status','result','error','completed at'];
  required.forEach(function(k){if(idx[k] === undefined) throw new Error('WORKER_QUEUE_COLUMN_MISSING: '+k);});
  for (let r=1;r<data.length;r++) {
    const status=String(data[r][idx['status']]||'').trim().toUpperCase();
    if(status!=='PENDING') continue;
    const job={
      row:r+1,
      jobId:String(data[r][idx['job id']]||'').trim(),
      command:String(data[r][idx['command']]||'').trim().toUpperCase(),
      fileId:String(data[r][idx['file id']]||'').trim(),
      fileName:String(data[r][idx['file name']]||'').trim(),
      destination:String(data[r][idx['destination']]||'').trim(),
      approved:data[r][idx['approved']]===true,
      content:String(data[r][idx['content']]||'')
    };
    if(!job.jobId) continue;
    return {success:true,available:true,workerId:workerId,job:job,verified:true,timestamp:new Date().toISOString()};
  }
  return {success:true,available:false,workerId:workerId,verified:true,timestamp:new Date().toISOString()};
}

function aerisWorkerClaim_(workerId,jobId,claimToken) {
  if(!workerId||!jobId||!claimToken) throw new Error('MISSING_CLAIM_FIELDS');
  const lock=LockService.getScriptLock();
  if(!lock.tryLock(5000)) return {success:false,claimed:false,reason:'QUEUE_BUSY'};
  try {
    const sheet=getQueueSheet();
    const data=sheet.getDataRange().getValues();
    const headers=data[0].map(function(h){return String(h).trim().toLowerCase();});
    const statusCol=headers.indexOf('status')+1;
    const jobCol=headers.indexOf('job id')+1;
    const resultCol=headers.indexOf('result')+1;
    if(!statusCol||!jobCol||!resultCol) throw new Error('WORKER_QUEUE_SCHEMA_INVALID');
    for(let r=1;r<data.length;r++) {
      if(String(data[r][jobCol-1]||'').trim()!==jobId) continue;
      const status=String(data[r][statusCol-1]||'').trim().toUpperCase();
      if(status!=='PENDING') return {success:false,claimed:false,reason:'JOB_NOT_PENDING',status:status,jobId:jobId};
      const claim={workerId:workerId,claimToken:claimToken,claimedAt:new Date().toISOString(),liveFinancialExecution:false};
      sheet.getRange(r+1,statusCol).setValue('PROCESSING');
      sheet.getRange(r+1,resultCol).setValue(JSON.stringify({workerClaim:claim}));
      SpreadsheetApp.flush();
      const verify=String(sheet.getRange(r+1,statusCol).getValue()).trim().toUpperCase();
      if(verify!=='PROCESSING') throw new Error('WORKER_CLAIM_VERIFICATION_FAILED');
      return {success:true,claimed:true,workerId:workerId,jobId:jobId,claimToken:claimToken,verified:true,timestamp:new Date().toISOString()};
    }
    return {success:false,claimed:false,reason:'JOB_NOT_FOUND',jobId:jobId};
  } finally { lock.releaseLock(); }
}

function aerisWorkerResult_(workerId,jobId,status,result,errorMessage,verified,executed) {
  if(!workerId||!jobId) throw new Error('MISSING_RESULT_FIELDS');
  const allowed=['COMPLETED','FAILED','BLOCKED'];
  status=String(status||'').trim().toUpperCase();
  if(allowed.indexOf(status)===-1) throw new Error('INVALID_WORKER_RESULT_STATUS');
  if(status==='COMPLETED' && (verified!==true || executed!==true)) throw new Error('COMPLETED_REQUIRES_VERIFIED_EXECUTION');
  if(executed===true && result && result.liveFinancialExecution===true) throw new Error('LIVE_FINANCIAL_EXECUTION_DISABLED');
  const lock=LockService.getScriptLock();
  if(!lock.tryLock(5000)) return {success:false,recorded:false,reason:'QUEUE_BUSY'};
  try {
    const sheet=getQueueSheet();
    const data=sheet.getDataRange().getValues();
    const headers=data[0].map(function(h){return String(h).trim().toLowerCase();});
    const jobCol=headers.indexOf('job id')+1;
    const statusCol=headers.indexOf('status')+1;
    const resultCol=headers.indexOf('result')+1;
    const errorCol=headers.indexOf('error')+1;
    const completedCol=headers.indexOf('completed at')+1;
    if(!jobCol||!statusCol||!resultCol||!errorCol||!completedCol) throw new Error('WORKER_QUEUE_SCHEMA_INVALID');
    for(let r=1;r<data.length;r++) {
      if(String(data[r][jobCol-1]||'').trim()!==jobId) continue;
      const current=String(data[r][statusCol-1]||'').trim().toUpperCase();
      if(current!=='PROCESSING') return {success:false,recorded:false,reason:'JOB_NOT_PROCESSING',status:current,jobId:jobId};
      const payload=Object.assign({},result||{}, {workerId:workerId,verified:verified===true,executed:executed===true,reportedAt:new Date().toISOString(),liveFinancialExecution:false});
      sheet.getRange(r+1,statusCol).setValue(status);
      sheet.getRange(r+1,resultCol).setValue(JSON.stringify(payload));
      sheet.getRange(r+1,errorCol).setValue(errorMessage||'');
      sheet.getRange(r+1,completedCol).setValue(new Date());
      SpreadsheetApp.flush();
      const verifyStatus=String(sheet.getRange(r+1,statusCol).getValue()).trim().toUpperCase();
      if(verifyStatus!==status) throw new Error('WORKER_RESULT_VERIFICATION_FAILED');
      return {success:true,recorded:true,jobId:jobId,status:status,verified:true,timestamp:new Date().toISOString()};
    }
    return {success:false,recorded:false,reason:'JOB_NOT_FOUND',jobId:jobId};
  } finally { lock.releaseLock(); }
}

function aerisWorkerHeartbeat_(workerId,jobId) {
  if(!workerId) throw new Error('MISSING_WORKER_ID');
  return {success:true,workerId:workerId,jobId:jobId||'',status:'ONLINE',liveFinancialExecution:false,timestamp:new Date().toISOString()};
}
