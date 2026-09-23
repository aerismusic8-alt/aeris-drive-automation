# AX CONTROL HARDENING + CONTINUOUS EXPERIENCE LOOP

## Purpose
AX Control is a continuously supervised execution system, not a chat-only command path. The Control layer must remain observable, recoverable, independently operated per PC, and continuously improved from verified experience.

## Control health cadence
1. 5-second runtime heartbeat — proves the local observer/runtime loop is alive. It does not prove task execution.
2. 30-second control liveness check — confirms the Control daemon, desktop observer and browser/control bridge remain responsive.
3. 60-second integrity check — checks state freshness, evidence writer health, verifier health, browser/session connectivity and recovery flags.
4. 15-minute deep AX Control Check — performs a broader audit of PC state, active task, current UI/application state, evidence/verification freshness, blockers, recovery status and learning feedback. This is the canonical deep-check interval; ChatGPT Automation is a supervisory layer and is not required to provide the 15-minute cadence.
A meaningful action must trigger immediate post-action observe → evidence → verify rather than waiting for the next scheduled check.

## Strengthened control loop
OBSERVE → LOAD CANONICAL STATE → THINK/PLAN WITH A MASTER BRAIN → DISPATCH → EXECUTE → OBSERVE → COLLECT EVIDENCE → VERIFY → LEARN → WRITE BACK → RECOVER/CONTINUE
No Control command is dispatched solely because a task exists or a UI element is visible.

## A MASTER BRAIN learning gate
Every verified execution cycle should produce a structured learning event containing, where applicable:
- objective/task identity
- node identity
- observed precondition
- action/method used
- expected result
- actual result
- evidence reference
- verification result
- failure/root-cause classification
- reusable lesson
- recovery method
- confidence/evidence quality
- whether the lesson is safe to reuse
Only evidence-backed lessons may be promoted to durable verified knowledge. Credentials, secrets and unnecessary personal data must never be written to the brain.

## Experience accumulation
Successful and failed Control cycles are both useful experience:
- successful method → reusable method candidate
- failed method → failure pattern + root cause + avoid/recovery rule
- repeated failure → capability/blocker pattern
- recovery success → recovery recipe
- verified environment change → updated capability baseline
Experience must be reused by the THINK_BEFORE_ACT gate before the next comparable action.

## Recovery ladder
When Control becomes unhealthy:
DETECT → FREEZE NEW ACTIONS → CAPTURE STATE → CLASSIFY → RESTART COMPONENT → RECONNECT → REVERIFY → RESUME SAME TASK ID
Do not create a duplicate task merely because a worker/control component restarted.

## Independence
PC1 CONTROL and PC2 CONTROL maintain separate local execution and recovery. Shared A MASTER BRAIN provides knowledge and lessons; it does not make one node dependent on the other.

## Evidence standard
HEARTBEAT != EXECUTION
CONTROL_ALIVE != LOGIN
LOGIN != TASK_SUCCESS
TASK_STARTED != REWARD
REPORTED_SUCCESS != VERIFIED_SUCCESS
A reward is counted only after node-specific evidence and verification.

## Current known PC2 lesson
On 2026-09-23/24, PC2 Control inspection found a zero-byte hybrid-control-loop.mjs and a JumpTask AUTH_REQUIRED state. The loop was reconstructed and its 5-second observation cycle was restored. The login state remains independently verified as AUTH_REQUIRED until an actual authenticated session is observed. This lesson must be used to prevent silent control degradation and to distinguish Control health from account authentication.

## Operational contract
The AX Control Check structure is a supervisory system function. Its local runtime implementation must operate independently of ChatGPT availability and must write verified state/evidence to canonical storage when the required persistence path is available.