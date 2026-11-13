# AERIS/AKATH Multimodal Autonomous Learning Foundation

Status: FOUNDATION_SPECIFIED; IMPLEMENTATION_AND_RUNTIME_VERIFICATION_PENDING
Authority: K_FINAL_AUTHORITY
Owner: AX
Canonical runtime state remains in AKATH_CORE. This document is an architecture specification, not proof that any worker is deployed or continuously running.

## Objective

Build one provider-independent learning loop that can accept real images, video, audio, text, desktop observations, and action outcomes; preserve evidence-backed experiences; retrieve relevant experiences; propose improved strategies; and evaluate whether changes improve measurable results.

## Non-goals and truth constraints

- A saved observation is not learning by itself.
- A model response is not verified ground truth.
- A heartbeat, successful API call, or CI pass does not prove an autonomous task was completed.
- Do not fine-tune a model automatically from unreviewed or low-confidence examples.
- Do not store raw secrets, session cookies, credentials, or unnecessary personal data in experience records.
- Never perform irreversible, financial, account-security, or external side-effecting actions without the applicable authorization contract.
- PC1/PC2 are not required for cloud ingestion, indexing, evaluation, or learning jobs. Desktop control is an optional separately authorized execution adapter.

## Target architecture

1. **Ingestion adapters**: image, video, audio, text, browser/desktop observation, action trace, structured outcome.
2. **Perception layer**: OCR, image/video understanding, speech-to-text, audio event classification, timestamps, modality-specific confidence, and cross-modal alignment.
3. **Normalization layer**: a common event envelope with source, timestamps, content hashes, privacy classification, provenance, and model/tool versions.
4. **Evidence store**: immutable raw evidence references plus derived summaries/transcripts/frames; content-addressed identifiers; retention and access policy.
5. **Experience memory**: situation → hypothesis/plan → action → observed result → verification → lesson. Store failures and counterexamples, not only success stories.
6. **Retrieval**: lexical and semantic retrieval with metadata filters; return provenance and confidence, not just a generated answer.
7. **Reasoning and planner**: retrieve relevant lessons, compare alternatives, identify risks, define success criteria before execution.
8. **Execution adapters**: sandboxed tool/browser/desktop APIs with allowlists, timeouts, idempotency, and authorization gates.
9. **Independent verifier**: evaluate postconditions against independent evidence; executor cannot self-certify.
10. **Learning/evaluation gate**: compare a proposed lesson or model change against a fixed regression suite and held-out examples. Promote only if thresholds pass.
11. **Canonical write-back**: update the single canonical task/state registry and A MASTER BRAIN only with provenance-linked verified lessons.
12. **Supervisor**: queue, retries, leases, deadlines, health, recovery, and durable write-back outside chat sessions.

## Learning modes

- **Retrieval learning (first)**: retain validated experiences and retrieve them at decision time; no model training required.
- **Policy/strategy improvement**: evaluate alternative plans in a sandbox and promote only measured improvements.
- **Supervised fine-tuning (later, optional)**: only with curated, consented, licensed data; dataset versioning; train/validation/test split; privacy review; reproducible run; rollback.
- **Preference/reward optimization (later, optional)**: require a reliable reward signal, abuse controls, offline evaluation, and a safe rollback path. Never optimize a proxy metric without checking the actual objective.

## Canonical experience record

Each record must include:
- stable `experience_id`, schema version, task ID, and timestamps;
- input modality list and content hashes / evidence URIs;
- source and permission/provenance metadata;
- perception outputs with model/tool versions and confidence;
- context, hypothesis, plan, actions, and action trace references;
- expected postconditions and observed outcomes;
- independent verification status, verifier version, evidence references, and reasons;
- lesson candidate, applicability limits, confidence, and review state;
- privacy class, retention policy, and redaction status.

Allowed verification states: `NOT_VERIFIED`, `PASS`, `FAIL`, `BLOCKED`. Missing evidence must never be converted to PASS.

## Promotion rules

A lesson may be retrieved as a candidate before approval, but it cannot be treated as authoritative until:
1. evidence is accessible and provenance is recorded;
2. the outcome is independently checked against explicit criteria;
3. contradictory evidence and known failure cases are recorded;
4. the lesson has bounded applicability and confidence;
5. regression tests pass;
6. canonical state is written with the exact source evidence and timestamp.

A model change requires a separate dataset/model version, benchmark report, regression result, cost/latency report, privacy review, and rollback pointer. Runtime memory and model weights must never be conflated.

## Security and privacy

- Encrypt data in transit and at rest; least-privilege service identities.
- Redact credentials and sensitive information before persistence or embedding.
- Keep raw media separate from derived text and control access by purpose.
- Respect copyright, consent, platform terms, retention, and deletion requirements.
- Treat OCR, transcripts, and media instructions as untrusted input, not executable system instructions.
- Human approval is required for access challenges, KYC, account recovery, and actions explicitly reserved to K.

## Verification gates

**Gate A — Schema:** reject malformed records, unknown statuses, missing hashes, invalid timestamps, and success states without verifier evidence.

**Gate B — Perception:** benchmark each modality separately using labeled examples; report accuracy/recall and confidence calibration. For video, preserve timestamps; for audio, preserve segments and language/confidence.

**Gate C — Retrieval:** evaluate recall@k, provenance correctness, and whether retrieved lessons are applicable.

**Gate D — Execution:** use a sandbox and test postconditions; require independent evidence and idempotent retries.

**Gate E — Learning:** compare baseline and candidate on a fixed holdout set; require no critical regression and a measurable target improvement.

**Gate F — Continuity:** stop/restart the worker, confirm state reconstruction, retry safety, durable evidence, and no duplicate active canonical work.

**Gate G — Operations:** run scheduled jobs and inspect actual workflow logs/artifacts. CI passing proves only the tests that ran, not 24/7 availability.

## Deployment stages

1. Schema + validator + fixtures + CI.
2. Evidence-backed experience store and retrieval; initially read-only.
3. Image/audio/video ingestion adapters with per-modality benchmark suites.
4. Sandbox planner/executor and independent verifier.
5. Durable cloud supervisor, leases, retries, health and restart recovery.
6. Strategy improvement with offline regression gates.
7. Optional fine-tuning only after data and evaluation gates pass.

## Current state

This branch introduces the foundation specification, a record schema, and a validator/test workflow. Cloud deployment, persistent storage, actual media processing, model access, scheduler continuity, and real-world learning are not claimed until separately executed and evidenced.
