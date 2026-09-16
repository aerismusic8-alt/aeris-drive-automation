import { appendFile, readFile, mkdir } from 'node:fs/promises';
import { dirname } from 'node:path';

export async function appendEvidence(path, record) {
  await mkdir(dirname(path), {recursive:true});
  await appendFile(path, `${JSON.stringify({...record,timestamp:record.timestamp ?? new Date().toISOString()})}\n`, 'utf8');
}

export async function readJobEvidence(path, jobId) {
  try { return (await readFile(path,'utf8')).split('\n').filter(Boolean).map(JSON.parse).filter((r)=>r.jobId===jobId); }
  catch (error) { if (error.code === 'ENOENT') return []; throw error; }
}
