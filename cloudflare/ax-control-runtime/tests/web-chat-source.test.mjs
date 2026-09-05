import fs from 'node:fs';

const source = fs.readFileSync(new URL('../src/index.ts', import.meta.url), 'utf8');

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

// Regression guard: browser JS strings inside webChatPage must not contain literal newlines.
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

// Regression guard: clear the composer immediately after gateway acceptance, before waiting for Local Hub.
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

// Regression guard: the entire file-picker field must be clickable, not only the native button.
assert(webChatSource.includes('<label id="filePicker" class="filePicker">'), 'web chat file picker must use a full-area clickable label');
assert(webChatSource.includes('<span id="fileLabel">Choose File</span>'), 'web chat file picker must expose a visible Choose File label');
assert(webChatSource.includes('<input id="file" type="file" multiple>'), 'web chat file input must remain available inside the full-area picker');
assert(webChatSource.includes('.filePicker{'), 'web chat file picker must define full-area label styling');
assert(webChatSource.includes("$('file').addEventListener('change'"), 'web chat file picker must react to file selection');

// GitHub App authentication contract: production code must use the three Worker secrets,
// mint an App JWT, resolve the repository installation, and mint an installation token.
assert(source.includes('AX_GITHUB_APP_PRIVATE_KEY'), 'GitHub App private-key secret binding is missing');
assert(source.includes('AX_GITHUB_CLIENT_ID'), 'GitHub App client-id secret binding is missing');
assert(source.includes('AX_GITHUB_APP_ID'), 'GitHub App app-id secret binding is missing');
assert(source.includes('crypto.subtle.importKey'), 'GitHub App JWT signing must use Web Crypto');
assert(source.includes('RSASSA-PKCS1-v1_5'), 'GitHub App JWT must use RS256-compatible RSA signing');
assert(source.includes('/repos/${REPO}/installation'), 'GitHub App must resolve the repository installation');
assert(source.includes('/app/installations/${installationId}/access_tokens'), 'GitHub App must mint an installation access token');
assert(source.includes('verifyGitHubToken'), 'GitHub repository access verification must remain present');

console.log('AX web chat and GitHub App source regression checks passed.');
