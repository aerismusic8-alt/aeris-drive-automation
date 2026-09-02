import crypto from "node:crypto";

const AUTH_ENDPOINT = "https://accounts.google.com/o/oauth2/v2/auth";
const DEFAULT_SCOPES = [
  "https://www.googleapis.com/auth/script.projects",
  "https://www.googleapis.com/auth/script.deployments",
];

export function generateState() {
  return crypto.randomBytes(32).toString("hex");
}

export function generatePkce() {
  const verifier = crypto.randomBytes(48).toString("base64url");
  const challenge = crypto.createHash("sha256").update(verifier).digest("base64url");
  return { verifier, challenge };
}

export function validateState(expected, received) {
  if (!expected || !received || expected.length !== received.length) return false;
  return crypto.timingSafeEqual(Buffer.from(expected), Buffer.from(received));
}

export function buildAuthorizationUrl({ clientId, redirectUri, state, codeChallenge, scopes = DEFAULT_SCOPES }) {
  if (!clientId || !redirectUri || !state || !codeChallenge) throw new Error("OAUTH_CONFIGURATION_REQUIRED");

  const url = new URL(AUTH_ENDPOINT);
  url.searchParams.set("client_id", clientId);
  url.searchParams.set("redirect_uri", redirectUri);
  url.searchParams.set("response_type", "code");
  url.searchParams.set("scope", scopes.join(" "));
  url.searchParams.set("access_type", "offline");
  url.searchParams.set("prompt", "consent");
  url.searchParams.set("code_challenge", codeChallenge);
  url.searchParams.set("code_challenge_method", "S256");
  url.searchParams.set("state", state);
  return url.toString();
}

export function parseCallback(input) {
  const url = new URL(input, "http://127.0.0.1");
  const state = url.searchParams.get("state");
  const error = url.searchParams.get("error");
  const code = url.searchParams.get("code");

  if (error) return { error, state };
  if (code) return { code, state };
  return { state };
}
