import test from 'node:test';
import assert from 'node:assert/strict';
import { appendEvidence, readJobEvidence } from './evidence-store.mjs';
import { mkdtemp, readFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

test('appends and reads job evidence',async()=>{
  const dir=await mkdtemp(join(tmpdir(),'ax-evidence-')); const path=join(dir,'evidence.jsonl');
  await appendEvidence(path,{jobId:'j1',event:'RESULT',verification:{verified:true}});
  assert.equal((await readJobEvidence(path,'j1')).length,1);
  assert.match(await readFile(path,'utf8'),/"jobId":"j1"/);
});
