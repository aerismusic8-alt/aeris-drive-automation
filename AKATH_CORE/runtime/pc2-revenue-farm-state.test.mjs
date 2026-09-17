import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

const bot = fs.readFileSync(path.join(process.cwd(), 'AKATH_CORE/runtime/pc2-revenue-farm-bot.ps1'), 'utf8');

assert.match(bot, /\$StatePath\s*=\s*Join-Path\s+\$RuntimeDir\s+'revenue-farm-state\.json'/);
assert.match(bot, /Set-Content\s+-Path\s+\$StatePath\s+-Encoding\s+UTF8/);
assert.doesNotMatch(bot, /\$State\s*=\s*Join-Path\s+\$RuntimeDir\s+'revenue-farm-state\.json'/);

console.log('PASS PC2 revenue farm state path regression guard');
