#!/usr/bin/env node
import assert from "node:assert/strict";

const SHA = "a".repeat(64);
const valid = () => ({
  schema_version: "1.0",
  experience_id: "exp:test-0001",
  task_id: "AKATH-MULTIMODAL-LEARNING-001",
  created_at: "2026-10-25T12:00:00.000Z",
  input: {
    modalities: ["image", "audio"],
    evidence: [{ sha256: SHA, uri: "evidence://fixture/sample", source: "test-fixture", redacted: true }]
  },
  perception: [{ modality: "image", tool: "fixture-parser", version: "1.0", summary: "sample", confidence: 0.99, evidence_sha256: SHA }],
  context: { situation: "fixture", hypothesis: "test validation" },
  plan: ["validate record"],
  actions: [{ action: "validate", result: "success", evidence_sha256: SHA, idempotency_key: "test-0001" }],
  outcome: { expected_postconditions: ["schema accepted"], observed: "schema accepted" },
  verification: { status: "PASS", verifier: "independent-fixture-check", evidence: ["test://validation"], reasons: [], verified_at: "2026-10-25T12:00:01.000Z" },
  lesson: { candidate: "schema validation is repeatable", confidence: 1, review_state: "CANDIDATE", applicability: ["schema test"], contradictions: [] },
  privacy: { classification: "INTERNAL", redaction_complete: true, retention_policy: "test fixture only" }
});

function validate(record) {
  const errors = [];
  const required = ["schema_version", "experience_id", "task_id", "created_at", "input", "perception", "context", "plan", "actions", "outcome", "verification", "lesson", "privacy"];
  for (const key of required) if (!(key in record)) errors.push("missing:" + key);
  if (record.schema_version !== "1.0") errors.push("schema_version");
  if (typeof record.experience_id !== "string" || !/^[A-Za-z0-9._:-]{8,160}$/.test(record.experience_id)) errors.push("experience_id");
  if (!record.input || !Array.isArray(record.input.modalities) || record.input.modalities.length === 0) errors.push("input.modalities");
  if (record.input && (!Array.isArray(record.input.evidence) || record.input.evidence.length === 0)) errors.push("input.evidence");
  for (const ev of record.input?.evidence ?? []) {
    if (!/^[a-fA-F0-9]{64}$/.test(ev.sha256 ?? "")) errors.push("evidence.sha256");
    if (typeof ev.uri !== "string" || !ev.uri) errors.push("evidence.uri");
    if (typeof ev.source !== "string" || !ev.source) errors.push("evidence.source");
  }
  for (const p of record.perception ?? []) {
    if (typeof p.tool !== "string" || !p.tool || typeof p.version !== "string" || !p.version) errors.push("perception.provenance");
    if (typeof p.confidence !== "number" || p.confidence < 0 || p.confidence > 1) errors.push("perception.confidence");
  }
  const allowed = ["NOT_VERIFIED", "PASS", "FAIL", "BLOCKED"];
  if (!record.verification || !allowed.includes(record.verification.status)) errors.push("verification.status");
  if (record.verification?.status === "PASS") {
    if (!record.verification.verifier || !Array.isArray(record.verification.evidence) || record.verification.evidence.length === 0 || !record.verification.verified_at) {
      errors.push("pass_requires_independent_verifier_evidence_and_timestamp");
    }
  }
  if (!record.lesson || !["CANDIDATE", "APPROVED", "REJECTED"].includes(record.lesson.review_state)) errors.push("lesson.review_state");
  if (record.lesson?.review_state === "APPROVED" && record.verification?.status !== "PASS") errors.push("approved_lesson_requires_verified_pass");
  if (!record.privacy || !["PUBLIC", "INTERNAL", "CONFIDENTIAL", "RESTRICTED"].includes(record.privacy.classification)) errors.push("privacy.classification");
  if (record.privacy?.redaction_complete !== true) errors.push("privacy_redaction_incomplete");
  return { ok: errors.length === 0, errors };
}

const good = validate(valid());
assert.equal(good.ok, true, JSON.stringify(good));

const noEvidence = valid();
noEvidence.input.evidence[0].sha256 = "not-a-hash";
assert.equal(validate(noEvidence).ok, false, "reject malformed evidence hash");

const falsePass = valid();
falsePass.verification.evidence = [];
assert.ok(validate(falsePass).errors.includes("pass_requires_independent_verifier_evidence_and_timestamp"), "PASS must require verifier evidence");

const unverifiedApproved = valid();
unverifiedApproved.verification.status = "NOT_VERIFIED";
unverifiedApproved.lesson.review_state = "APPROVED";
assert.ok(validate(unverifiedApproved).errors.includes("approved_lesson_requires_verified_pass"), "unverified lesson must not be promoted");

const unredacted = valid();
unredacted.privacy.redaction_complete = false;
assert.ok(validate(unredacted).errors.includes("privacy_redaction_incomplete"), "reject unredacted record");

console.log(JSON.stringify({
  suite: "AKATH multimodal experience record contract",
  result: "PASS",
  cases: 5,
  checks: ["valid record accepted", "bad evidence hash rejected", "PASS without evidence rejected", "unverified lesson promotion rejected", "unredacted record rejected"]
}, null, 2));
