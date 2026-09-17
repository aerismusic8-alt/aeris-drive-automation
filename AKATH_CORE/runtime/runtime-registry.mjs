import { resolve } from 'node:path';

export function resolveRuntimeRegistryPath(runtimeRoot) {
  return resolve(runtimeRoot, 'runtime-registry.json');
}
