import { readFile, rename, writeFile, mkdir } from 'node:fs/promises';
import { dirname } from 'node:path';

export async function loadJson(path, fallback) {
  try {
    const text = await readFile(path,'utf8');
    return JSON.parse(text.replace(/^\uFEFF/, ''));
  }
  catch (error) { if(error.code==='ENOENT') return structuredClone(fallback); throw error; }
}

export async function persistJson(path, value) {
  await mkdir(dirname(path),{recursive:true});
  const tmp=`${path}.tmp-${process.pid}`;
  await writeFile(tmp,`${JSON.stringify(value,null,2)}\n`,'utf8');
  await rename(tmp,path);
}
