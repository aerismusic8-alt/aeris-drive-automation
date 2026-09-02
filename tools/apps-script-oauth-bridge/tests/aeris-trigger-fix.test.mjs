import test from "node:test";
import assert from "node:assert/strict";
import { repairDelegationQueueTrigger } from "../src/aeris-trigger-fix.mjs";

const brokenSource = `function AERIS_DELEGATION_QUEUE_TRIGGER() {
  const activeStatuses = [
  "PENDING",
  "PENDING_DISPATCH",
  "DISPATCH_READY",
  "RETRY_PENDING",
  "FALLBACK_PENDING"
];
for (let r = 1; r < data.length; r++) {
  const rowStatus =
    String(data[r][index["status"]] || "");
}
}`;

function content(source = brokenSource) {
  return {
    files: [
      { name: "AERIS_Code.gs", type: "SERVER_JS", source },
      { name: "appsscript", type: "JSON", source: "{}" }
    ]
  };
}

test("repairs data/index scope by defining trigger-local data", () => {
  const result = repairDelegationQueueTrigger(content());
  const source = result.files.find((f) => f.name === "AERIS_Code.gs").source;

  assert.match(source, /const triggerData = getAERISDelegationTriggerData_\(\);/);
  assert.match(source, /const delegationData = triggerData\.delegationData;/);
  assert.match(source, /const delegationIndex = triggerData\.delegationIndex;/);
  assert.match(source, /for \(let r = 1; r < delegationData\.length; r\+\+\)/);
  assert.match(source, /String\(delegationData\[r\]\[delegationIndex\["status"\]\] \|\| ""\)/);
  assert.match(source, /function getAERISDelegationTriggerData_\(\)/);
});

test("does not alter unrelated files", () => {
  const result = repairDelegationQueueTrigger(content());
  const manifest = result.files.find((f) => f.name === "appsscript");
  assert.equal(manifest.source, "{}");
});

test("fails closed when target scope bug is absent", () => {
  assert.throws(
    () => repairDelegationQueueTrigger(content("function AERIS_DELEGATION_QUEUE_TRIGGER() { return true; }")),
    /AERIS_TRIGGER_ACTIVE_STATUS_BLOCK_NOT_FOUND/
  );
});
