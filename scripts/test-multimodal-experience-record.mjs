#!/usr/bin/env node
// Test suite for the AKATH multimodal experience record contract.
//
// Runs under plain `node` (no package.json, no dependencies). It exercises the
// shared validator against the JSON fixtures in
// AKATH_CORE/runtime/fixtures/{valid,invalid}/ and, first of all, asserts that
// the validator's own field/enum lists still match the schema file — so a
// schema edit that the validator does not mirror fails here.
//
//   node scripts/test-multimodal-experience-record.mjs
//
// Exit 0 = all cases pass. Exit 1 = a case failed (details on stderr).

import assert from "node:assert/strict";
import { readFileSync, readdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

import {
  validateExperienceRecord,
  assertValidatorMatchesSchema,
} from "../AKATH_CORE/runtime/experience-record-validator.mjs";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const SCHEMA_PATH = join(ROOT, "AKATH_CORE", "experience-record.schema.json");
const FIXTURES = join(ROOT, "AKATH_CORE", "runtime", "fixtures");

const readJson = (p) => JSON.parse(readFileSync(p, "utf8"));

const cases = [];
function check(name, fn) {
  try {
    fn();
    cases.push({ name, result: "pass" });
  } catch (error) {
    cases.push({ name, result: "fail", error: error.message });
  }
}

// 1. The validator and the schema must agree.
check("validator matches schema field and enum lists", () => {
  const problems = assertValidatorMatchesSchema(readJson(SCHEMA_PATH));
  assert.deepEqual(problems, [], `validator/schema drift: ${problems.join(", ")}`);
});

// 2. Every valid fixture must be accepted.
const validDir = join(FIXTURES, "valid");
for (const file of readdirSync(validDir).filter((f) => f.endsWith(".json")).sort()) {
  check(`valid fixture accepted: ${file}`, () => {
    const result = validateExperienceRecord(readJson(join(validDir, file)));
    assert.equal(result.ok, true, `unexpected errors: ${result.errors.join(", ")}`);
  });
}

// 3. Every invalid fixture must be rejected, with the expected error present.
const invalidDir = join(FIXTURES, "invalid");
const expected = readJson(join(invalidDir, "expected.json"));
for (const file of Object.keys(expected).sort()) {
  check(`invalid fixture rejected: ${file}`, () => {
    const result = validateExperienceRecord(readJson(join(invalidDir, file)));
    assert.equal(result.ok, false, "record was accepted but should have been rejected");
    assert.ok(
      result.errors.includes(expected[file]),
      `expected error "${expected[file]}", got: ${result.errors.join(", ")}`,
    );
  });
}

// 4. The specific rules the task calls out, asserted directly so a fixture
//    rename cannot silently drop coverage.
const valid = readJson(join(validDir, "akath-mm-0001.json"));

check("PASS without independent verifier evidence is rejected", () => {
  const r = structuredClone(valid);
  r.verification.evidence = [];
  const out = validateExperienceRecord(r);
  assert.ok(out.errors.includes("pass_requires_independent_verifier_evidence_and_timestamp"));
});

check("unknown verification status is rejected", () => {
  const r = structuredClone(valid);
  r.verification.status = "PROBABLY";
  assert.ok(validateExperienceRecord(r).errors.includes("verification.status"));
});

check("malformed evidence hash is rejected", () => {
  const r = structuredClone(valid);
  r.input.evidence[0].sha256 = "zzzz";
  assert.ok(validateExperienceRecord(r).errors.includes("evidence.sha256"));
});

check("unverified lesson cannot be promoted to APPROVED", () => {
  const r = structuredClone(valid);
  r.verification.status = "NOT_VERIFIED";
  r.lesson.review_state = "APPROVED";
  assert.ok(validateExperienceRecord(r).errors.includes("approved_lesson_requires_verified_pass"));
});

check("record without evidence is rejected", () => {
  const r = structuredClone(valid);
  r.input.evidence = [];
  assert.ok(validateExperienceRecord(r).errors.includes("input.evidence"));
});

check("record with unknown top-level key is rejected", () => {
  const r = structuredClone(valid);
  r.secret_token = "should-not-be-here";
  assert.ok(validateExperienceRecord(r).errors.includes("unknown_key:.secret_token"));
});

const failed = cases.filter((c) => c.result === "fail");
for (const c of cases) {
  if (c.result === "fail") console.error(`FAIL ${c.name}\n     ${c.error}`);
}

console.log(JSON.stringify({
  suite: "AKATH multimodal experience record contract",
  result: failed.length === 0 ? "PASS" : "FAIL",
  cases: cases.length,
  passed: cases.length - failed.length,
  failed: failed.length,
  checks: cases.map((c) => `${c.result === "pass" ? "ok" : "FAIL"} ${c.name}`),
}, null, 2));

process.exit(failed.length === 0 ? 0 : 1);
