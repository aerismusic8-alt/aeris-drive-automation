import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

const source = fs.readFileSync("AERIS_Delegation_Scope_Compat.gs", "utf8");

test("delegation scope compatibility shim is present", () => {
  assert.match(source, /var AERIS_TRIGGER_SCOPE_SNAPSHOT_\s*=\s*null/);
  assert.match(source, /function getAERISDelegationTriggerScopeSnapshot_\(\)/);
  assert.match(source, /var data = new Proxy\(\{\}, \{/);
  assert.match(source, /var index = new Proxy\(\{\}, \{/);
  assert.match(source, /getAERISDelegationSheet\(\)/);
  assert.match(source, /property === "length"/);
  assert.match(source, /statusIndex: index\["status"\]/);
});

test("shim exposes the exact legacy names required by the failing trigger", () => {
  const requiredNames = ["data", "index", "getAERISDelegationTriggerScopeSnapshot_"];
  for (const name of requiredNames) {
    assert.match(source, new RegExp(`\\b${name}\\b`));
  }
});
