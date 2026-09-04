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

console.log('AX web chat source regression checks passed.');