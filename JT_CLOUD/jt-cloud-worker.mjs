import { chromium } from 'playwright';
import fs from 'node:fs/promises';

const baseUrl = process.env.JT_APP_URL || 'https://app.jumptask.io';
const storageB64 = (process.env.JT_STORAGE_STATE_B64 || '').trim();
const evidencePath = process.env.JT_EVIDENCE_PATH || 'jt-evidence.json';
const statePath = process.env.JT_STATE_PATH || 'JT_STATE/latest.json';
const runId = process.env.GITHUB_RUN_ID || `local-${Date.now()}`;

function hasAny(text, patterns) {
  return patterns.some((rx) => rx.test(text));
}

function extractCredits(text) {
  const matches = [...text.matchAll(/(?:balance|credits|earnings|my\s+earnings)[^\n]{0,80}?([0-9]+(?:[.,][0-9]+)?)/gi)];
  return matches.slice(0, 5).map((m) => m[1]);
}

function cleanText(value) {
  return String(value || '').replace(/\s+/g, ' ').trim().slice(0, 500);
}

async function writeEvidence(evidence) {
  await fs.mkdir('JT_STATE', { recursive: true });
  await fs.writeFile(evidencePath, JSON.stringify(evidence, null, 2));
  await fs.writeFile(statePath, JSON.stringify(evidence, null, 2));
}

async function main() {
  const browser = await chromium.launch({ headless: true });
  let context;
  try {
    let storageState;
    if (storageB64) {
      const decoded = Buffer.from(storageB64, 'base64').toString('utf8');
      storageState = JSON.parse(decoded);
      if (!storageState || typeof storageState !== 'object' ||
          !Array.isArray(storageState.cookies) || !Array.isArray(storageState.origins)) {
        throw new Error('Invalid Playwright storage state schema');
      }
    }

    context = await browser.newContext(storageState ? { storageState } : {});
    const page = await context.newPage();
    const startedAt = new Date().toISOString();

    const accountUrl = new URL('/my-account', baseUrl).toString();
    await page.goto(accountUrl, { waitUntil: 'domcontentloaded', timeout: 60000 });
    await page.waitForLoadState('networkidle', { timeout: 30000 }).catch(() => {});

    const accountBody = (await page.locator('body').innerText()).slice(0, 24000);
    const loginSignals = hasAny(accountBody, [/sign\s*in/i, /log\s*in/i, /create\s*(an?\s*)?account/i]);
    const accountSignals = hasAny(accountBody, [/my\s+account/i, /account\s+id/i, /my\s+earnings/i, /my\s+rewards/i]);
    const securityGate = hasAny(accountBody, [/captcha/i, /two[- ]factor|2fa/i, /security\s+(check|verification)/i, /verify\s+your\s+identity/i, /kyc/i]);
    const accountRoute = /app\.jumptask\.io\/my-account/i.test(page.url());
    const authenticated = Boolean(storageState) && accountRoute && accountSignals && !loginSignals && !securityGate;

    let offers = [];
    if (authenticated) {
      const earnUrl = new URL('/earn', baseUrl).toString();
      await page.goto(earnUrl, { waitUntil: 'domcontentloaded', timeout: 60000 });
      await page.waitForLoadState('networkidle', { timeout: 30000 }).catch(() => {});
      const earnUrlObserved = page.url();
      const candidates = await page.locator('a,button,[role="button"]').evaluateAll((els) =>
        els.map((el) => ({
          tag: el.tagName,
          text: (el.innerText || el.textContent || '').replace(/\s+/g, ' ').trim(),
          href: el instanceof HTMLAnchorElement ? el.href : ''
        }))
        .filter(x => x.text && x.text.length <= 500)
        .slice(0, 250)
      );
      const body = (await page.locator('body').innerText()).slice(0, 30000);
      const lines = body.split(/\n+/).map(x => x.replace(/\s+/g, ' ').trim()).filter(Boolean);
      const likely = candidates.filter(x =>
        /earn|reward|credit|watch|survey|game|offer|task|complete|\$[0-9]/i.test(x.text)
      ).slice(0, 80);
      offers = { earnUrlObserved, likelyControls: likely, bodyLines: lines.slice(0, 300) };
    }

    const evidence = {
      schema: 'AERIS-JT-CLOUD-BROWSER-EVIDENCE/v5',
      runId,
      startedAt,
      finishedAt: new Date().toISOString(),
      runtime: 'github-hosted-ubuntu',
      pc2Dependency: false,
      browser: 'playwright-chromium',
      accountUrl: page.url(),
      storageStateSupplied: Boolean(storageState),
      authenticated,
      authRequired: !authenticated,
      securityGate,
      accountSignals,
      accountRoute,
      visibleCreditCandidates: extractCredits(accountBody),
      offerDiscovery: offers,
      currentOffer: null,
      taskCompleted: false,
      rewardConfirmed: false,
      rewardDeltaVerified: false,
      executionMode: 'OFFER_DISCOVERY_ONLY',
      state: securityGate ? 'BLOCKED_BY_SECURITY_GATE' : authenticated ? 'OFFERS_DISCOVERED' : 'AUTH_REQUIRED_OR_NOT_VERIFIED',
      note: securityGate
        ? 'Security/identity gate detected. No task or reward action attempted.'
        : authenticated
          ? 'Authenticated cloud session verified. Earn page inspected without starting, submitting, or automating any earning task.'
          : 'Cloud worker could not verify an authenticated JumpTask session. No task or reward action was attempted.'
    };

    await writeEvidence(evidence);
    console.log(JSON.stringify(evidence));
    if (!authenticated) process.exitCode = 2;
  } finally {
    await context?.close().catch(() => {});
    await browser.close();
  }
}

main().catch(async () => {
  const evidence = {
    schema: 'AERIS-JT-CLOUD-BROWSER-EVIDENCE/v5',
    runId,
    finishedAt: new Date().toISOString(),
    runtime: 'github-hosted-ubuntu',
    pc2Dependency: false,
    state: 'FAILED',
    taskCompleted: false,
    rewardConfirmed: false,
    executionMode: 'OFFER_DISCOVERY_ONLY',
    error: 'Cloud worker failed while initializing or inspecting the authenticated session.'
  };
  await writeEvidence(evidence).catch(() => {});
  process.exit(1);
});
