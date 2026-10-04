import fs from 'node:fs/promises';

const source = await fs.readFile('JT_CLOUD/jt-cloud-worker.mjs', 'utf8');
const workflow = await fs.readFile('.github/workflows/jt-cloud-browser-worker.yml', 'utf8');

const forbidden = [
  /DESKTOP-M9M4818/i,
  /192\.168\./i,
  /(?:^|[^0-9])127\.0\.0\.1(?:[^0-9]|$)/,
  /(?:^|[^a-z0-9])localhost(?:[^a-z0-9]|$)/i,
  /C:\\\\AX-Runtime/i,
  /Desktop Commander/i,
  /PowerShell/i,
  /Windows Scheduler/i,
  /local Chrome/i,
  /cdp.*pc2|pc2.*cdp/i
];

for (const rx of forbidden) {
  if (rx.test(source) || rx.test(workflow)) {
    throw new Error('PC2/local dependency detected: ' + rx);
  }
}

for (const required of [
  "runtime: 'github-hosted-ubuntu'",
  'pc2Dependency: false',
  "executionMode: 'INSPECTION_ONLY'",
  'rewardConfirmed: false',
  'rewardDeltaVerified: false',
  'JT_STORAGE_STATE_B64',
  "new URL('/my-account', baseUrl)",
  'Array.isArray(storageState.cookies)',
  'Array.isArray(storageState.origins)',
  'accountRoute',
  'accountSignals',
  'securityGate'
]) {
  if (!source.includes(required) && !workflow.includes(required)) {
    throw new Error('Missing invariant: ' + required);
  }
}

if (!workflow.includes('runs-on: ubuntu-latest')) {
  throw new Error('Cloud runner invariant missing');
}
if (!workflow.includes('actions/upload-artifact@v5')) {
  throw new Error('Evidence upload invariant missing');
}
if (/console\.log\(JSON\.stringify\(body/i.test(source)) {
  throw new Error('Page body logging would risk session-data exposure');
}

console.log('JT cloud architecture self-test: PASS');
