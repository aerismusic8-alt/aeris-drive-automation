import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { promises as fs } from 'node:fs';

const ROOT=dirname(fileURLToPath(import.meta.url));
const REGISTRY_PATH=resolve(ROOT,'node-registry.json');

const DEFAULT_NODES={
  "PC1-MAIN":{nodeId:"PC1-MAIN",role:"PRIMARY",transport:"local",status:"UNKNOWN",capabilities:["execution","ai","control","browser"]},
  "PC2-NIGHT":{nodeId:"PC2-NIGHT",role:"SECONDARY",transport:"http",status:"UNKNOWN",capabilities:["execution","ai","control","browser"]}
};

export async function loadNodeRegistry(){
  try { const raw=await fs.readFile(REGISTRY_PATH,'utf8'); return JSON.parse(raw.replace(/^\uFEFF/,'')); }
  catch { const data={schemaVersion:"1.0",updatedAt:new Date().toISOString(),nodes:DEFAULT_NODES}; await persistNodeRegistry(data); return data; }
}

export async function persistNodeRegistry(registry){
  registry.updatedAt=new Date().toISOString();
  const tmp=REGISTRY_PATH+'.tmp';
  await fs.writeFile(tmp,JSON.stringify(registry,null,2),'utf8');
  await fs.rename(tmp,REGISTRY_PATH);
}

export async function heartbeatNode(nodeId,patch={}){
  const registry=await loadNodeRegistry();
  const node=registry.nodes[nodeId] || {nodeId};
  Object.assign(node,{nodeId,lastHeartbeatAt:new Date().toISOString()},patch);
  if (!patch.status) node.status="ONLINE";
  registry.nodes[nodeId]=node;
  await persistNodeRegistry(registry);
  return node;
}

export function chooseNode(registry,{capability='execution',preferred}={}){
  const candidates=Object.values(registry.nodes||{}).filter(n=>
    (n.status==='ONLINE'||n.transport==='local') &&
    (!Array.isArray(n.capabilities)||n.capabilities.includes(capability))
  );
  if(preferred && candidates.some(n=>n.nodeId===preferred)) return candidates.find(n=>n.nodeId===preferred);
  return candidates.find(n=>n.nodeId==='PC1-MAIN') || candidates[0] || null;
}

export function nodeForTask(job,registry){
  const preferred=job?.target_node || process.env.AX_PREFERRED_NODE || null;
  const requested=job?.capability||'execution';
  // Recovery is a control-plane concern, but it still requires an execution arm.
  // Route recovery work through nodes that advertise execution capability.
  const capability=requested==='recovery' ? 'execution' : requested;
  return chooseNode(registry,{capability,preferred});
}

export { REGISTRY_PATH };
