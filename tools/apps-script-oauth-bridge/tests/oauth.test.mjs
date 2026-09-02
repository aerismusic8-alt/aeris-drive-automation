import test from "node:test";
import assert from "node:assert/strict";

import {
  buildAuthorizationUrl,
  generatePkce,
  generateState,
  validateState,
  parseCallback,
} from "../src/oauth.mjs";

test("authorization URL requests Apps Script project and deployment scopes", () => {
  const { challenge } = generatePkce();
  const url = buildAuthorizationUrl({
    clientId: "client-id",
    redirectUri: "http://127.0.0.1:8765/oauth/callback",
    state: "state-123",
    codeChallenge: challenge,
  });

  const parsed = new URL(url);
  assert.equal(parsed.hostname, "accounts.google.com");
  assert.equal(parsed.searchParams.get("client_id"), "client-id");
  assert.equal(parsed.searchParams.get("state"), "state-123");
  assert.match(parsed.searchParams.get("scope"), /script\.projects/);
  assert.match(parsed.searchParams.get("scope"), /script\.deployments/);
  assert.equal(parsed.searchParams.get("access_type"), "offline");
  assert.equal(parsed.searchParams.get("prompt"), "consent");
  assert.equal(parsed.searchParams.get("code_challenge"), challenge);
  assert.equal(parsed.searchParams.get("code_challenge_method"), "S256");
});

test("state validation accepts only the expected value", () => {
  assert.equal(validateState("abc", "abc"), true);
  assert.equal(validateState("abc", "wrong"), false);
});

test("generated state is non-empty and unpredictable-looking", () => {
  const a = generateState();
  const b = generateState();
  assert.equal(typeof a, "string");
  assert.ok(a.length >= 32);
  assert.notEqual(a, b);
});

test("callback parser distinguishes authorization success and provider errors", () => {
  const success = parseCallback("?code=abc&state=s1");
  assert.deepEqual(success, { code: "abc", state: "s1" });

  const failure = parseCallback("?error=access_denied&state=s1");
  assert.deepEqual(failure, { error: "access_denied", state: "s1" });
});
