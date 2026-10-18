#!/usr/bin/env node
// Mint a GitHub App installation access token from the persisted app key.
//
// Usage:
//   node scripts/gh-app-token.mjs            # print token
//   node scripts/gh-app-token.mjs --export   # print `export GITHUB_TOKEN=...`
//
// Key lookup order:
//   1. $AERIS_GH_APP_KEY / $AERIS_GH_APP_CONFIG
//   2. ~/.config/aeris/gh-app.pem + gh-app.json
import { createSign } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';

const HOME = homedir();
const KEY_PATH = process.env.AERIS_GH_APP_KEY || join(HOME, '.config/aeris/gh-app.pem');
const CFG_PATH = process.env.AERIS_GH_APP_CONFIG || join(HOME, '.config/aeris/gh-app.json');

const b64url = (buf) =>
  Buffer.from(buf).toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');

function appJwt(clientId, pem) {
  const now = Math.floor(Date.now() / 1000);
  const header = b64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const payload = b64url(JSON.stringify({ iat: now - 60, exp: now + 540, iss: clientId }));
  const signingInput = `${header}.${payload}`;
  const sig = createSign('RSA-SHA256').update(signingInput).sign(pem);
  return `${signingInput}.${b64url(sig)}`;
}

async function api(url, token, method = 'GET') {
  const res = await fetch(url, {
    method,
    headers: {
      Authorization: `Bearer ${token}`,
      Accept: 'application/vnd.github+json',
      'X-GitHub-Api-Version': '2022-11-28',
    },
  });
  const text = await res.text();
  if (!res.ok) throw new Error(`${method} ${url} -> ${res.status} ${text.slice(0, 300)}`);
  return text ? JSON.parse(text) : {};
}

const cfg = JSON.parse(readFileSync(CFG_PATH, 'utf8'));
const pem = readFileSync(KEY_PATH, 'utf8');
const jwt = appJwt(cfg.client_id, pem);

let installationId = cfg.installation_id;
if (!installationId) {
  const installs = await api('https://api.github.com/app/installations', jwt);
  const match = installs.find((i) => (i.account || {}).login === cfg.owner) || installs[0];
  if (!match) throw new Error('App is not installed on any account');
  installationId = match.id;
}

const result = await api(
  `https://api.github.com/app/installations/${installationId}/access_tokens`,
  jwt,
  'POST',
);

if (process.argv.includes('--export')) {
  console.log(`export GITHUB_TOKEN=${result.token}`);
  console.error(`# expires ${result.expires_at}`);
} else {
  console.log(result.token);
  console.error(`# expires ${result.expires_at} permissions=${JSON.stringify(result.permissions)}`);
}
