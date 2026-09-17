import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = dirname(fileURLToPath(import.meta.url));
const script = await readFile(resolve(root, 'run-ax-runtime-with-user-env.ps1'), 'utf8');

assert.match(script, /GetEnvironmentVariable\('GEMINI_API_KEY','User'\)/);
assert.match(script, /\$env:GEMINI_API_KEY/);
assert.match(script, /main\.mjs/);
assert.doesNotMatch(script, /GEMINI_API_KEY\s*=\s*['\"][^'\"]+/);

console.log('PASS autostart environment bootstrap contract');
