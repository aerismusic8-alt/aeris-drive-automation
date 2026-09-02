import http from "node:http";
import crypto from "node:crypto";
import fs from "node:fs/promises";
import { spawn } from "node:child_process";
import { buildAuthorizationUrl, generateState, parseCallback, validateState } from "./oauth.mjs";

const HOST = "127.0.0.1";
const PORT = Number(process.env.AERIS_OAUTH_PORT || 8765);
const CLIENT_ID = process.env.GOOGLE_OAUTH_CLIENT_ID;
const CLIENT_SECRET = process.env.GOOGLE_OAUTH_CLIENT_SECRET;
const TOKEN_FILE = process.env.AERIS_OAUTH_TOKEN_FILE || `${process.env.USERPROFILE || process.env.HOME}/.aeris/apps-script-oauth.json`;

function redirectUri() {
  return `http://${HOST}:${PORT}/oauth/callback`;
}

async function persistToken(token) {
  await fs.mkdir(new URL(".", `file://${TOKEN_FILE}`).pathname, { recursive: true }).catch(() => {});
  const dir = TOKEN_FILE.slice(0, TOKEN_FILE.lastIndexOf("/") > 0 ? TOKEN_FILE.lastIndexOf("/") : TOKEN_FILE.lastIndexOf("\\"));
  if (dir) await fs.mkdir(dir, { recursive: true, mode: 0o700 });
  await fs.writeFile(TOKEN_FILE, JSON.stringify(token, null, 2), { encoding: "utf8", mode: 0o600 });
}

async function exchangeCode(code) {
  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      code,
      client_id: CLIENT_ID,
      client_secret: CLIENT_SECRET,
      redirect_uri: redirectUri(),
      grant_type: "authorization_code",
    }),
  });
  const body = await response.json();
  if (!response.ok) throw new Error(`GOOGLE_TOKEN_EXCHANGE_${response.status}`);
  return body;
}

function openBrowser(url) {
  if (process.platform === "win32") spawn("cmd", ["/c", "start", "", url], { detached: true, stdio: "ignore" }).unref();
  else if (process.platform === "darwin") spawn("open", [url], { detached: true, stdio: "ignore" }).unref();
  else spawn("xdg-open", [url], { detached: true, stdio: "ignore" }).unref();
}

export function startOAuthServer() {
  if (!CLIENT_ID || !CLIENT_SECRET) throw new Error("GOOGLE_OAUTH_CLIENT_CONFIGURATION_REQUIRED");
  const state = generateState();
  const authUrl = buildAuthorizationUrl({ clientId: CLIENT_ID, redirectUri: redirectUri(), state });

  return new Promise((resolve, reject) => {
    const server = http.createServer(async (req, res) => {
      try {
        const url = new URL(req.url, `http://${HOST}:${PORT}`);
        if (url.pathname !== "/oauth/callback") {
          res.writeHead(302, { Location: authUrl });
          res.end();
          return;
        }
        const callback = parseCallback(url.search);
        if (!validateState(state, callback.state)) throw new Error("OAUTH_STATE_MISMATCH");
        if (callback.error) throw new Error(`GOOGLE_OAUTH_${callback.error}`);
        if (!callback.code) throw new Error("GOOGLE_AUTHORIZATION_CODE_MISSING");

        const token = await exchangeCode(callback.code);
        await persistToken({ ...token, storedAt: new Date().toISOString() });
        res.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
        res.end("<h1>AERIS authorization complete</h1><p>You may close this window.</p>");
        server.close();
        resolve(token);
      } catch (error) {
        res.writeHead(400, { "Content-Type": "text/plain; charset=utf-8" });
        res.end("Authorization failed. Check the bridge logs for the error code.");
        server.close();
        reject(error);
      }
    });
    server.once("error", reject);
    server.listen(PORT, HOST, () => openBrowser(authUrl));
  });
}

if (import.meta.url === `file://${process.argv[1]}`) {
  startOAuthServer().then(() => process.exit(0)).catch((error) => {
    console.error(error.message);
    process.exit(1);
  });
}
