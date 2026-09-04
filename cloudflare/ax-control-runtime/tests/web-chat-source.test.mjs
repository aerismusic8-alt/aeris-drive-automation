import fs from 'node:fs';

const source = fs.readFileSync(new URL('../src/index.ts', import.meta.url), 'utf8');

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

// Regression guard: browser JS strings inside webChatPage must not contain literal newlines.
assert(!/\$\('messages'\)\.textContent\+='[\r\n]/.test(source), 'web chat contains a literal newline inside a JavaScript string');
assert(source.includes('id="loginStatus"'), 'web chat must expose a visible login status element');
assert(source.includes("$('loginStatus').textContent=e.message"), 'web chat login errors must be visible in loginStatus');
assert(source.includes("status.textContent='Connecting…'"), 'web chat login must show connecting state');
assert(source.includes("const NL = String.fromCharCode(10)"), 'web chat must use a safe newline constant');

console.log('AX web chat source regression checks passed.');
