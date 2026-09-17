import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = dirname(fileURLToPath(import.meta.url));
const main = await readFile(resolve(root, 'main.mjs'), 'utf8');

test('main runtime persists mutable registry outside canonical registry', () => {
  assert.match(main, /resolveRuntimeRegistryPath/);
  assert.match(main, /runtimeRegistryPath/);
  assert.match(main, /persistRegistry\(runtimeRegistryPath,registry\)/);
  assert.doesNotMatch(main, /persistRegistry\(registryPath,registry\)/);
});

console.log('PASS main registry separation contract');
