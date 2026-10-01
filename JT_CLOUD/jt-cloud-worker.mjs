import { chromium } from 'playwright';
import fs from 'node:fs/promises';

const baseUrl = process.env.JT_APP_URL || 'https://app.jumptask.io';
const storageB64 = process.env.JT_STORAGE_STATE_B64 || '';
const evidencePath = process.env.JT_EVIDENCE_PATH || 'jt-evidence.json';

async function main() {
  const browser = await chromium.launch({ headless: true });
  let context;
  try {
    context = await browser.newContext(
      storageB64
        ? { storageState: Buffer.from(storageB64, 'base64').toString('utf8') }
        : {}
    );
    const page = await context.newPage();
    const startedAt = new Date().toISOString();

    await page.goto(baseUrl, { waitUntil: 'domcontentloaded', timeout: 60000 });
    await page.waitForLoadState('networkidle', { timeout: 30000 }).catch(() => {});

    const title = await page.title();
    const url = page.url();
    const body = (await page.locator('body').innerText()).slice(0, 12000);

    const authIndicators = [
      /sign\s*in/i,
      /log\s*in/i,
      /create\s*(an?\s*)?account/i
    ];
    const authenticated = !authIndicators.some((rx) => rx.test(body));

    const evidence = {
      schema: 'AERIS-JT-CLOUD-BROWSER-EVIDENCE/v1',
      startedAt,
      finishedAt: new Date().toISOString(),
      runtime: 'github-hosted-ubuntu',
      pc2Dependency: false,
      browser: 'playwright-chromium',
      url,
      title,
      authenticated,
      state: authenticated ? 'AUTHENTICATED_READY_CANDIDATE' : 'AUTH_REQUIRED',
      rewardConfirmed: false,
      taskCompleted: false,
      note: authenticated
        ? 'Authenticated page reached; task execution is deliberately not attempted until current offer conditions and completion criteria are inspected.'
        : 'No authenticated JumpTask session was supplied to this worker.'
    };

    await fs.writeFile(evidencePath, JSON.stringify(evidence, null, 2));
    console.log(JSON.stringify(evidence));
    if (!authenticated) process.exitCode = 2;
  } finally {
    await context?.close().catch(() => {});
    await browser.close();
  }
}

main().catch(async (error) => {
  const evidence = {
    schema: 'AERIS-JT-CLOUD-BROWSER-EVIDENCE/v1',
    finishedAt: new Date().toISOString(),
    runtime: 'github-hosted-ubuntu',
    pc2Dependency: false,
    state: 'FAILED',
    rewardConfirmed: false,
    error: String(error?.message || error)
  };
  await fs.writeFile(evidencePath, JSON.stringify(evidence, null, 2)).catch(() => {});
  console.error(JSON.stringify(evidence));
  process.exit(1);
});
