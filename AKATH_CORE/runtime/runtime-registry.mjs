import { resolve } from 'node:path';

export function resolveRuntimeRegistryPath(runtimeRoot) {
  // Use a dedicated live registry path to avoid contention with stale/legacy registry handles.
  return resolve(runtimeRoot, 'runtime-registry-live.json');
}
