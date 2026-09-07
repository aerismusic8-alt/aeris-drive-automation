# AX Mission Continuity + Direct Channel Design

## Goal
Make AX own mission continuity and completion independently of ChatGPT chat sessions, while giving K a direct external channel to AX.

## Principles
1. Chat is transport/UI only; it is never the source of truth for mission lifecycle.
2. A mission/task has an immutable identity and command fingerprint.
3. Opening a new chat must not create a duplicate mission or mutate an existing command.
4. READY/RUNNING/RECOVERING tasks are resumed; COMPLETED tasks are not recreated by chat lifecycle.
5. AX owns recovery: diagnose failure, retry, switch executor/AI, verify, and continue.
6. Completion requires evidence: COMPLETED + VERIFIED, with run identity and timestamps.
7. The direct K channel must bypass ChatGPT and the legacy Gateway Inbox for command intake.
8. Persistent state is separate from command transport so storage cannot rewrite the command.

## Target flow
K browser/phone -> AX Control Runtime direct endpoint -> immutable mission ledger -> AX execution queue/runtime -> evidence -> mission ledger.

## Acceptance criteria
- Direct channel has a stable URL independent of ChatGPT.
- Same request fingerprint is idempotent.
- New chat/session does not create a new task for an existing mission.
- AX can resume RUNNING/RECOVERING work without K sending another message.
- Every completion records task id, run id, executor, result, verification and completion time.
- A failed AI/runner is treated as a recoverable execution event, not a reason to wait for K.
