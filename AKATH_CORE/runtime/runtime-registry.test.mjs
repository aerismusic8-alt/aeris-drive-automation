import test from 'node:test';
import assert from 'node:assert/strict';
import { resolveRuntimeRegistryPath } from './runtime-registry.mjs';

test('runtime registry is separate from canonical task registry', () => {
  const root = 'C:/repo/AKATH_CORE/runtime';
  const runtimePath = resolveRuntimeRegistryPath(root);
  assert.equal(runtimePath.replaceAll('\\', '/'), 'C:/repo/AKATH_CORE/runtime/runtime-registry.json');
  assert.notEqual(runtimePath, 'C:/repo/AKATH_CORE/CANONICAL_TASK_REGISTRY.json');
});

console.log('PASS runtime registry separation');
