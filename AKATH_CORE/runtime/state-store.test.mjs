import test from 'node:test';
import assert from 'node:assert/strict';
import { loadJson, persistJson } from './state-store.mjs';
import { mkdtemp, readFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

test('persists and reloads runtime state atomically',async()=>{
  const dir=await mkdtemp(join(tmpdir(),'ax-state-')); const path=join(dir,'state.json');
  await persistJson(path,{runtimeStatus:'ONLINE',nodeId:'PC1-MAIN'});
  assert.deepEqual(await loadJson(path,{}),{runtimeStatus:'ONLINE',nodeId:'PC1-MAIN'});
  assert.match(await readFile(path,'utf8'),/PC1-MAIN/);
});
