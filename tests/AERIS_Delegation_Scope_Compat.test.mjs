import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";

const source = fs.readFileSync("AERIS_Delegation_Scope_Compat.gs", "utf8");

test("delegation scope compatibility shim is present", () => {
  const requiredFragments = [
    "var AERIS_TRIGGER_SCOPE_SNAPSHOT_ = null;",
    "function getAERISDelegationTriggerScopeSnapshot_()",
    "var data = new Proxy({},",
    "var index = new Proxy({},",
    "getAERISDelegationSheet()",
    "property === \"length\"",
    "statusIndex: index[\"status\"]"
  ];

  for (const fragment of requiredFragments) {
    assert.ok(source.includes(fragment), `missing required fragment: ${fragment}`);
  }
});

test("shim preserves the exact legacy names used by the failing trigger", () => {
  for (const name of ["data", "index"]) {
    assert.ok(source.includes(`var ${name} = new Proxy`), `missing legacy global: ${name}`);
  }
});
