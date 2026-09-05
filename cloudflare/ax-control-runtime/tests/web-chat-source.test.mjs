import fs from 'node:fs';

const source = fs.readFileSync(new URL('../src/index.ts', import.meta.url), 'utf8');
const githubSource = fs.readFileSync(new URL('../src/github-app-entry.ts', import.meta.url), 'utf8');
const xmSource = fs.readFileSync(new URL('../src/xm-bridge.ts', import.meta.url), 'utf8');
const wrangler = fs.readFileSync(new URL('../wrangler.jsonc', import.meta.url), 'utf8');

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

assert(!/\$('messages')\.textContent\+='[\r\n]/.test(source), 'web chat contains a literal newline inside a JavaScript string');
assert(source.includes('id="loginStatus"'), 'web chat must expose a visible login status element');
assert(source.includes("$('loginStatus').textContent=e.message"), 'web chat login errors must be visible in loginStatus');
assert(source.includes("status.textContent='Connecting…'"), 'web chat login must show connecting state');

const webChatStart = source.indexOf('function webChatPage(): Response {');
const webChatEnd = source.indexOf('\n}\n\nexport default', webChatStart);
assert(webChatStart >= 0 && webChatEnd > webChatStart, 'webChatPage source block must be present');
const webChatSource = source.slice(webChatStart, webChatEnd);
assert(webChatSource.includes('<script>const NL=String.fromCharCode(10);const $=id=>document.getElementById(id);'), 'web chat browser script must declare NL in its own scope');
assert(/\$\('message'\)\.addEventListener\('keydown',/.test(webChatSource), 'web chat message box must have a keydown handler');
assert(/e\.key==='Enter'/.test(webChatSource), 'web chat keydown handler must detect Enter');

const sendHandlerStart = webChatSource.indexOf("$('send').onclick=async()=>{");
assert(sendHandlerStart >= 0, 'web chat send handler must be present');
const sendHandler = webChatSource.slice(sendHandlerStart, webChatSource.indexOf("$('message').addEventListener", sendHandlerStart));
const acceptedMarker = "const r=await submit(message);";
const clearMarker = "$('message').value='';$('file').value=''";
const acceptedIndex = sendHandler.indexOf(acceptedMarker);
const clearIndex = sendHandler.indexOf(clearMarker);
const pollIndex = sendHandler.indexOf("const result=await poll(r.requestId);");
assert(acceptedIndex >= 0, 'web chat send handler must await gateway acceptance');
assert(clearIndex > acceptedIndex && clearIndex < pollIndex, 'web chat composer must clear immediately after gateway acceptance and before polling');

assert(webChatSource.includes('<label id="filePicker" class="filePicker">'), 'web chat file picker must use a full-area clickable label');
assert(webChatSource.includes('<span id="fileLabel">Choose File</span>'), 'web chat file picker must expose a visible Choose File label');
assert(webChatSource.includes('<input id="file" type="file" multiple>'), 'web chat file input must remain available inside the full-area picker');
assert(webChatSource.includes('.filePicker{'), 'web chat file picker must define full-area label styling');
assert(webChatSource.includes("$('file').addEventListener('change'"), 'web chat file picker must react to file selection');

// GitHub App authentication contract.
assert(githubSource.includes('AX_GITHUB_APP_PRIVATE_KEY'), 'GitHub App private-key secret binding is missing');
assert(githubSource.includes('AX_GITHUB_CLIENT_ID'), 'GitHub App client-id secret binding is missing');
assert(githubSource.includes('AX_GITHUB_APP_ID'), 'GitHub App app-id secret binding is missing');
assert(githubSource.includes('crypto.subtle.importKey'), 'GitHub App JWT signing must use Web Crypto');
assert(githubSource.includes('RSASSA-PKCS1-v1_5'), 'GitHub App JWT must use RS256-compatible RSA signing');
assert(githubSource.includes('-----BEGIN RSA PRIVATE KEY-----'), 'GitHub App PEM parser must accept GitHub PKCS#1 RSA private keys');
assert(githubSource.includes('wrapPkcs1AsPkcs8'), 'GitHub App PKCS#1 key must be converted to PKCS#8 for Web Crypto import');
assert(githubSource.includes('iss: clientId'), 'GitHub App JWT issuer must use the configured Client ID');
assert(githubSource.includes('/repos/${REPO}/installation'), 'GitHub App must resolve the repository installation');
assert(githubSource.includes('/app/installations/${installationId}/access_tokens'), 'GitHub App must mint an installation access token');
assert(githubSource.includes("url.pathname === '/github/verify'"), 'GitHub App verification route is missing');
assert(githubSource.includes("url.pathname === '/github/status'"), 'GitHub App sanitized status route is missing');
assert(githubSource.includes("status: body.verified === true ? 'VERIFIED' : 'NOT_VERIFIED'"), 'GitHub App status route must expose only sanitized verification state');
assert(!githubSource.slice(githubSource.indexOf('async function publicStatus')).includes('tokenExpiresAt'), 'public GitHub status must not expose token expiry');
assert(!githubSource.slice(githubSource.indexOf('async function publicStatus')).includes('installationIdPresent'), 'public GitHub status must not expose installation identifiers');
assert(githubSource.includes("repositories: ['aeris-drive-automation']"), 'installation token must be repository-scoped');
assert(githubSource.includes("permissions: { contents: 'read', actions: 'read', checks: 'read', metadata: 'read' }"), 'installation token must request read-only verification permissions');

// XM execution bridge transport.
assert(githubSource.includes("import { AxXmExecutionQueue"), 'XM execution queue import is missing');
assert(githubSource.includes('AX_XM_NODE_SECRET'), 'XM node secret binding is missing');
assert(githubSource.includes("'/xm/node/pull'"), 'XM node pull route is missing');
assert(githubSource.includes("'/xm/node/result'"), 'XM node result route is missing');
assert(githubSource.includes("'/xm/control/enqueue'"), 'XM control enqueue route is missing');
assert(githubSource.includes("'/xm/status'"), 'XM status route is missing');
assert(githubSource.includes("export { AxXmExecutionQueue } from './xm-bridge';"), 'XM Durable Object export is missing');
assert(xmSource.includes("const SCOPE = 'XM_MICRO_K_DESIGNATED_ACCOUNT';"), 'XM account scope must be fixed');
assert(xmSource.includes('idempotency_key'), 'XM transport must carry idempotency keys');
assert(xmSource.includes('UNKNOWN_REQUIRES_RECONCILIATION'), 'XM transport must support ambiguous-result reconciliation state');
assert(xmSource.includes("DEPOSIT','WITHDRAW','CHANGE_ACCOUNT_SETTINGS','EXPORT_CREDENTIALS"), 'XM bridge must define blocked financial/account operations');
assert(xmSource.includes("live_execution_enabled: false"), 'XM status must remain live-disabled');
assert(wrangler.includes('"name": "AX_XM_EXECUTION_QUEUE"'), 'Wrangler XM queue binding is missing');
assert(wrangler.includes('"class_name": "AxXmExecutionQueue"'), 'Wrangler XM Durable Object class is missing');
assert(wrangler.includes('"tag": "v2-xm-execution-bridge"'), 'XM Durable Object migration is missing');

console.log('AX web chat, GitHub App, and XM bridge source regression checks passed.');
