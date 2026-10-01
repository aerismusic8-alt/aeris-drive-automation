import { chromium } from 'playwright';
import fs from 'node:fs/promises';

const baseUrl = process.env.JT_APP_URL || 'https://app.jumptask.io';
const storageB64 = process.env.JT_STORAGE_STATE_B64 || '';
const evidencePath = process.env.JT_EVIDENCE_PATH || 'jt-evidence.json';

function firstMatch(text, patterns) {
  return patterns.some((rx) => rx.test(text));
}

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
    const body = (await page.locator('body').innerText()).slice(0, 16000);

    const authRequired = firstMatch(body, [
      /sign\s*in/i,
      /log\s*in/i,
      /create\s*(an?\s*)?account/i,
      /connect\s+wallet/i
    ]);

    const accountSignals = firstMatch(body, [
      /my\s+account/i,
      /account\s+id/i,
      /balance/i,
      /credits/i,
      /earn/i,
      /tasks?/i
    ]);

    const authenticated = !authRequired && accountSignals;

    const taskSignals = {
      earnVisible: /earn/i.test(body),
      taskVisible: /tasks?/i.test(body),
      rewardVisible: /reward|credits|earnings/i.test(body)
    };

    const evidence = {
      schema: 'AERIS-JT-CLOUD-BROWSER-EVIDENCE/v2',
      startedAt,
      finishedAt: new Date().toISOString(),
      runtime: 'github-hosted-ubuntu',
      pc2Dependency: false,
      browser: 'playwright-chromium',
      url,
      title,
      storageStateSupplied: Boolean(storageB64),
      authenticated,
      authRequired,
      accountSignals,
      taskSignals,
      state: authenticated
        ? 'AUTHENTICATED_READY_FOR_INSPECTION'
        : 'AUTH_REQUIRED_OR_NOT_VERIFIED',
      currentOffer: null,
      taskCompleted: false,
      rewardConfirmed: false,
      rewardDeltaVerified: false,
      note: authenticated
        ? 'Authenticated session appears usable. Current task/offer discovery is next; no task was started in this inspection.'
        : 'Cloud worker could not verify an authenticated JumpTask session. No task or reward action was attempted.'
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
    schema: 'AERIS-JT-CLOUD-BROWSER-EVIDENCE/v2',
    finishedAt: new Date().toISOString(),
    runtime: 'github-hosted-ubuntu',
    pc2Dependency: false,
    state: 'FAILED',
    taskCompleted: false,
    rewardConfirmed: false,
    error: String(error?.message || error)
  };
  await fs.writeFile(evidencePath, JSON.stringify(evidence, null, 2)).catch(() => {});
  console.error(JSON.stringify(evidence));
  process.exit(1);
});
