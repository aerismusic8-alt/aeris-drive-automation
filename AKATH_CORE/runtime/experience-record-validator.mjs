// Validator for the AKATH multimodal experience record.
//
// Contract: AKATH_CORE/experience-record.schema.json (draft 2020-12).
// The schema states the *shape*; this validator also enforces the semantic
// rules a JSON Schema cannot express on its own — above all that a PASS is
// never accepted without independent verifier evidence, and that an APPROVED
// lesson cannot rest on an unverified outcome.
//
// Dependency-free on purpose: the repository ships no package.json and its
// tests run under plain `node`, so this must not require a schema library.
// `assertValidatorMatchesSchema` re-derives the field/enum lists from the
// schema file so the two cannot silently drift.

export const SCHEMA_VERSION = "1.0";

export const MODALITIES = ["image", "video", "audio", "text", "desktop", "action_trace", "structured"];
export const VERIFICATION_STATES = ["NOT_VERIFIED", "PASS", "FAIL", "BLOCKED"];
export const REVIEW_STATES = ["CANDIDATE", "APPROVED", "REJECTED"];
export const PRIVACY_CLASSES = ["PUBLIC", "INTERNAL", "CONFIDENTIAL", "RESTRICTED"];

export const REQUIRED_FIELDS = [
  "schema_version", "experience_id", "task_id", "created_at", "input", "perception",
  "context", "plan", "actions", "outcome", "verification", "lesson", "privacy",
];

export const SHA256_RE = /^[a-fA-F0-9]{64}$/;
// The schema splits the id constraint: `pattern` is the character class only,
// and `minLength`/`maxLength` carry the length. Mirror that split exactly so
// `assertValidatorMatchesSchema` can compare both parts.
export const EXPERIENCE_ID_RE = /^[A-Za-z0-9._:-]+$/;
export const EXPERIENCE_ID_MIN = 8;
export const EXPERIENCE_ID_MAX = 160;
// ISO-8601 date-time with an explicit offset, e.g. 2026-10-25T12:00:00.000Z.
const DATE_TIME_RE = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$/;

const isPlainObject = (v) => typeof v === "object" && v !== null && !Array.isArray(v);
const isNonEmptyString = (v) => typeof v === "string" && v.length > 0;

function isDateTime(value) {
  return typeof value === "string" && DATE_TIME_RE.test(value) && !Number.isNaN(Date.parse(value));
}

function unknownKeys(obj, allowed, path, errors) {
  for (const key of Object.keys(obj)) {
    if (!allowed.includes(key)) errors.push(`unknown_key:${path}.${key}`);
  }
}

/**
 * Validate one experience record.
 * @returns {{ok: boolean, errors: string[]}}
 */
export function validateExperienceRecord(record) {
  const errors = [];
  if (!isPlainObject(record)) return { ok: false, errors: ["not_an_object"] };

  for (const key of REQUIRED_FIELDS) if (!(key in record)) errors.push(`missing:${key}`);
  unknownKeys(record, REQUIRED_FIELDS, "", errors);

  if (record.schema_version !== SCHEMA_VERSION) errors.push("schema_version");
  if (!isNonEmptyString(record.experience_id) || !EXPERIENCE_ID_RE.test(record.experience_id) ||
      record.experience_id.length < EXPERIENCE_ID_MIN || record.experience_id.length > EXPERIENCE_ID_MAX) {
    errors.push("experience_id");
  }
  if (!isNonEmptyString(record.task_id) || record.task_id.length < 3 || record.task_id.length > 160) {
    errors.push("task_id");
  }
  if (!isDateTime(record.created_at)) errors.push("created_at");

  // input
  const input = record.input;
  if (!isPlainObject(input)) {
    errors.push("input");
  } else {
    unknownKeys(input, ["modalities", "evidence"], "input", errors);
    if (!Array.isArray(input.modalities) || input.modalities.length === 0) {
      errors.push("input.modalities");
    } else {
      if (new Set(input.modalities).size !== input.modalities.length) errors.push("input.modalities.duplicate");
      for (const m of input.modalities) if (!MODALITIES.includes(m)) errors.push("input.modalities.unknown");
    }
    if (!Array.isArray(input.evidence) || input.evidence.length === 0) {
      errors.push("input.evidence");
    } else {
      for (const ev of input.evidence) {
        if (!isPlainObject(ev)) { errors.push("evidence"); continue; }
        unknownKeys(ev, ["sha256", "uri", "source", "captured_at", "license_or_permission", "redacted"], "evidence", errors);
        if (typeof ev.sha256 !== "string" || !SHA256_RE.test(ev.sha256)) errors.push("evidence.sha256");
        if (!isNonEmptyString(ev.uri)) errors.push("evidence.uri");
        // Provenance: without a source the evidence cannot be traced, so a
        // record with untraceable evidence must not validate.
        if (!isNonEmptyString(ev.source)) errors.push("evidence.source");
        if ("captured_at" in ev && !isDateTime(ev.captured_at)) errors.push("evidence.captured_at");
        if ("redacted" in ev && typeof ev.redacted !== "boolean") errors.push("evidence.redacted");
      }
    }
  }

  // perception
  if (!Array.isArray(record.perception)) {
    errors.push("perception");
  } else {
    for (const p of record.perception) {
      if (!isPlainObject(p)) { errors.push("perception"); continue; }
      unknownKeys(p, ["modality", "tool", "version", "summary", "confidence", "timestamp_ms", "evidence_sha256"], "perception", errors);
      if (!MODALITIES.includes(p.modality)) errors.push("perception.modality");
      // Provenance: a perception output with no tool/version cannot be audited.
      if (!isNonEmptyString(p.tool) || !isNonEmptyString(p.version)) errors.push("perception.provenance");
      if (typeof p.summary !== "string") errors.push("perception.summary");
      if (typeof p.confidence !== "number" || p.confidence < 0 || p.confidence > 1) errors.push("perception.confidence");
      if ("timestamp_ms" in p && (!Number.isInteger(p.timestamp_ms) || p.timestamp_ms < 0)) errors.push("perception.timestamp_ms");
      if ("evidence_sha256" in p && (typeof p.evidence_sha256 !== "string" || !SHA256_RE.test(p.evidence_sha256))) {
        errors.push("perception.evidence_sha256");
      }
    }
  }

  // context
  const context = record.context;
  if (!isPlainObject(context)) {
    errors.push("context");
  } else {
    unknownKeys(context, ["situation", "hypothesis", "constraints"], "context", errors);
    if (typeof context.situation !== "string") errors.push("context.situation");
    if (typeof context.hypothesis !== "string") errors.push("context.hypothesis");
  }

  if (!Array.isArray(record.plan) || record.plan.some((s) => typeof s !== "string")) errors.push("plan");

  // actions
  if (!Array.isArray(record.actions)) {
    errors.push("actions");
  } else {
    for (const a of record.actions) {
      if (!isPlainObject(a)) { errors.push("actions"); continue; }
      unknownKeys(a, ["action", "result", "evidence_sha256", "idempotency_key"], "actions", errors);
      if (typeof a.action !== "string") errors.push("actions.action");
      if (typeof a.result !== "string") errors.push("actions.result");
      if ("evidence_sha256" in a && (typeof a.evidence_sha256 !== "string" || !SHA256_RE.test(a.evidence_sha256))) {
        errors.push("actions.evidence_sha256");
      }
    }
  }

  // outcome
  const outcome = record.outcome;
  if (!isPlainObject(outcome)) {
    errors.push("outcome");
  } else {
    unknownKeys(outcome, ["expected_postconditions", "observed", "metrics"], "outcome", errors);
    if (!Array.isArray(outcome.expected_postconditions) ||
        outcome.expected_postconditions.some((s) => typeof s !== "string")) {
      errors.push("outcome.expected_postconditions");
    }
    if (typeof outcome.observed !== "string") errors.push("outcome.observed");
  }

  // verification
  const verification = record.verification;
  if (!isPlainObject(verification)) {
    errors.push("verification");
  } else {
    unknownKeys(verification, ["status", "verifier", "evidence", "reasons", "verified_at"], "verification", errors);
    if (!VERIFICATION_STATES.includes(verification.status)) errors.push("verification.status");
    if (typeof verification.verifier !== "string") errors.push("verification.verifier");
    if (!Array.isArray(verification.evidence) ||
        verification.evidence.some((s) => !isNonEmptyString(s))) {
      errors.push("verification.evidence");
    }
    if (!Array.isArray(verification.reasons) ||
        verification.reasons.some((s) => typeof s !== "string")) {
      errors.push("verification.reasons");
    }
    if ("verified_at" in verification && !isDateTime(verification.verified_at)) errors.push("verification.verified_at");
    // The central rule: missing evidence must never be converted to PASS.
    if (verification.status === "PASS") {
      const hasVerifier = isNonEmptyString(verification.verifier);
      const hasEvidence = Array.isArray(verification.evidence) && verification.evidence.length > 0;
      const hasTimestamp = isDateTime(verification.verified_at);
      if (!hasVerifier || !hasEvidence || !hasTimestamp) {
        errors.push("pass_requires_independent_verifier_evidence_and_timestamp");
      }
    }
  }

  // lesson
  const lesson = record.lesson;
  if (!isPlainObject(lesson)) {
    errors.push("lesson");
  } else {
    unknownKeys(lesson, ["candidate", "confidence", "review_state", "applicability", "contradictions"], "lesson", errors);
    if (typeof lesson.candidate !== "string") errors.push("lesson.candidate");
    if (typeof lesson.confidence !== "number" || lesson.confidence < 0 || lesson.confidence > 1) errors.push("lesson.confidence");
    if (!REVIEW_STATES.includes(lesson.review_state)) errors.push("lesson.review_state");
    if (!Array.isArray(lesson.applicability) || lesson.applicability.some((s) => typeof s !== "string")) {
      errors.push("lesson.applicability");
    }
    if ("contradictions" in lesson &&
        (!Array.isArray(lesson.contradictions) || lesson.contradictions.some((s) => typeof s !== "string"))) {
      errors.push("lesson.contradictions");
    }
    // A lesson cannot be authoritative unless its outcome was verified.
    if (lesson.review_state === "APPROVED" && verification?.status !== "PASS") {
      errors.push("approved_lesson_requires_verified_pass");
    }
  }

  // privacy
  const privacy = record.privacy;
  if (!isPlainObject(privacy)) {
    errors.push("privacy");
  } else {
    unknownKeys(privacy, ["classification", "redaction_complete", "retention_policy"], "privacy", errors);
    if (!PRIVACY_CLASSES.includes(privacy.classification)) errors.push("privacy.classification");
    if (privacy.redaction_complete !== true) errors.push("privacy_redaction_incomplete");
    if (!isNonEmptyString(privacy.retention_policy)) errors.push("privacy.retention_policy");
  }

  return { ok: errors.length === 0, errors: [...new Set(errors)] };
}

/**
 * Cross-check the hard-coded lists in this module against the schema file, so a
 * schema edit that this validator does not mirror fails the suite instead of
 * passing silently.
 * @returns {string[]} disagreements (empty means the two agree)
 */
export function assertValidatorMatchesSchema(schema) {
  const problems = [];
  const sameSet = (a, b) => a.length === b.length && [...a].sort().join("|") === [...b].sort().join("|");

  if (!sameSet(schema.required ?? [], REQUIRED_FIELDS)) problems.push("required_fields");
  if (schema.properties?.schema_version?.const !== SCHEMA_VERSION) problems.push("schema_version");
  if (!sameSet(schema.properties?.input?.properties?.modalities?.items?.enum ?? [], MODALITIES)) problems.push("modalities");
  if (!sameSet(schema.properties?.verification?.properties?.status?.enum ?? [], VERIFICATION_STATES)) problems.push("verification_states");
  if (!sameSet(schema.properties?.lesson?.properties?.review_state?.enum ?? [], REVIEW_STATES)) problems.push("review_states");
  if (!sameSet(schema.properties?.privacy?.properties?.classification?.enum ?? [], PRIVACY_CLASSES)) problems.push("privacy_classes");

  const shaPattern = schema.properties?.input?.properties?.evidence?.items?.properties?.sha256?.pattern;
  if (shaPattern && shaPattern !== SHA256_RE.source) problems.push("sha256_pattern");
  const idPattern = schema.properties?.experience_id?.pattern;
  if (idPattern && idPattern !== EXPERIENCE_ID_RE.source) problems.push("experience_id_pattern");
  if (schema.properties?.experience_id?.minLength !== EXPERIENCE_ID_MIN) problems.push("experience_id_minLength");
  if (schema.properties?.experience_id?.maxLength !== EXPERIENCE_ID_MAX) problems.push("experience_id_maxLength");

  // Every required field must also be a declared property, and vice versa for
  // the top-level object, or the schema itself is internally inconsistent.
  for (const f of REQUIRED_FIELDS) if (!(f in (schema.properties ?? {}))) problems.push(`schema_missing_property:${f}`);
  return problems;
}
