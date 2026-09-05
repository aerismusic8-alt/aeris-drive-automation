# AKATH / AX — EXPERIENCE & LESSONS LEARNED

## Purpose

This file preserves verified lessons from building and operating the AKATH autonomous AI system, especially lessons learned while using ChatGPT as the K-facing control and observation channel. It is durable system knowledge, not conversation memory.

## 1. Chat continuity is not system state

- A chat session must never be the authoritative source of AX state.
- Opening a new chat can provide incomplete context; therefore AX must recover from the persistent system of record.
- The authoritative recovery path is external and inspectable: current state, active task, blocker, evidence, decision, and next action must be persisted.
- ChatGPT is a control/observation interface, not the permanent memory or execution engine.

**Rule:** `CHAT_CONTEXT != AUTHORITATIVE_STATE`

## 2. GitHub is the evidence anchor

For the current AKATH operating model, GitHub is the primary inspectable evidence source.

- AI statements are not execution proof.
- A claimed connection is not proof of an executable connector.
- A claimed completion is not proof of a completed task.
- Source changes, diffs, tests, commits, workflow results, and durable evidence are stronger than chat claims.

**Rule:** If a capability cannot be demonstrated through durable, inspectable evidence, it remains `UNVERIFIED`.

## 3. IMPLEMENTED is not VERIFIED

A recurring failure mode is treating architecture or code presence as proof of operation.

Use distinct states:

- `DESIGNED`
- `IMPLEMENTED`
- `CONNECTED`
- `EXECUTED`
- `EVIDENCE_CAPTURED`
- `VERIFIED`

Do not collapse these states into one status.

## 4. AI executor verification contract

An AI worker becomes trusted only after an observable execution chain:

`TASK_ACCEPTED → TASK_EXECUTING → TASK_RESULT → EVIDENCE_VERIFIED → WRITE_BACK_VERIFIED → DONE`

For coding work, the minimum useful proof is:

1. real source file created or modified;
2. real diff is observable;
3. tests or validation actually run;
4. repository write-back is observable;
5. commit/evidence can be traced;
6. AX independently verifies the result.

**Rule:** Never enable an unverified AI connector merely because its model reports success.

## 5. Chat/UI design lessons worth preserving

Useful patterns observed from mature AI chat systems should be treated as design patterns for AKATH, not copied blindly:

- command → execution → result feedback;
- visible execution/status states;
- structured outputs for machine-readable state;
- tool/function invocation with explicit boundaries;
- file and image input when visual evidence materially improves work;
- clear error reporting and recovery paths;
- human approval gates for consequential actions;
- persistent task identifiers and idempotency;
- separation of control UI from execution runtime.

**Design principle:** The chat interface should make the system observable, while the runtime remains independently executable.

## 6. Failure lessons

### Lesson: a convincing AI response can still describe simulation

An AI can produce detailed plans, product ideas, or apparent progress without performing the corresponding external action.

**Countermeasure:** require external artifacts and independently inspectable evidence.

### Lesson: connection success is not executor success

OAuth/API/connector success only proves some level of connectivity. It does not prove that the agent can perform the intended operation.

**Countermeasure:** test the exact capability with a small real task.

### Lesson: heartbeat is not autonomy proof

A green heartbeat or dashboard can prove that a monitor is alive without proving that the autonomous worker completed useful work.

**Countermeasure:** define acceptance tests around actual scheduled execution and durable evidence.

### Lesson: repeated context reconstruction is a system smell

If K must repeatedly explain the latest state to AX after opening a new chat, persistence and rehydration are insufficient.

**Countermeasure:** make recovery deterministic from the external source of truth.

## 7. Experience → Lesson → Rule → Test

Every important operational experience should be converted into a reusable engineering artifact:

`EXPERIENCE → LESSON → RULE → TEST → VERIFIED CAPABILITY`

This prevents AKATH from merely remembering history; it turns experience into continuously improving system behavior.

## 8. Master Brain learning policy

A MASTER BRAIN should preserve:

- successful patterns;
- failed experiments;
- failure causes;
- recovery methods;
- verification criteria;
- interface/design patterns;
- executor capability evidence;
- decisions that materially change architecture.

Do not store unverified claims as established capability.

## 9. Current strategic principle

The long-term objective is for AX to operate independently of ChatGPT execution.

The preferred progression is:

`AX + VERIFIED CODING EXECUTOR → REAL CODING PROOF → VERIFIED DISPATCH → GPT EXECUTION PATH REMOVED → AUTONOMOUS ACCEPTANCE`

This principle remains subject to real GitHub evidence at every gate.
