# AX Mission Continuity Protocol V2

## Authority

`AX_MASTER_BRAIN/AX_MASTER_STATE.json` is the single authoritative company state.
`AX_MASTER_BRAIN/AX_MASTER_TASK_REGISTRY_v2.json` is the single authoritative task list and contains exactly one active `current_work` record.

The existing Cloudflare Durable Object `AxMissionLedger` stores execution-detail persistence for a mission. It is not a second master task registry.

## Single-work rule

At any moment exactly one `current_work.active=true` record may exist in the Master Task Registry.

`current_work.task_id` must match an existing task ID in the master registry. The task ID is stable across chats, channels, PCs, runners, and model/runtime changes.

Do not create a new task ID merely because K opens a new chat. Resolve the existing task ID and continue it.

## Cross-chat reconstruction

The startup/recovery sequence is:

`A MASTER BRAIN → Master Task Registry → current_work → latest evidence/verification → runtime mission details → continue`

Chat history, ChatGPT memory, model-local memory, dashboards, queue projections, and generated summaries are not authoritative state.

When K asks about a task from a new chat, AX must return the same task ID, exact task name, current step, next step, approval state, execution state, and latest verified evidence available in the system.

## Approval rule

Approval belongs to the specific task/strategy activation and is persisted in the authoritative task state.

A notification or chat summary is not an approval. Silence is not an approval. A strategy activation approval does not imply approval for unrelated tasks.

## Status and evidence

`QUEUED` is not `APPROVED`.
`APPROVED` is not `EXECUTING`.
`EXECUTING` requires actual start, trusted timestamp, and evidence.
`COMPLETED` requires verification.
`HEARTBEAT`, dashboard synchronization, persistence activity, or execution-registry activity alone cannot prove business execution.

Never invent timestamps, request IDs, evidence references, or results.

## No duplicate system rule

The following are projections/details only and cannot become competing task authorities:

- dashboards and task views
- active-execution heartbeat registry
- runtime mission detail records

Legacy file-based `AX_MISSION_LEDGER` task registry and its sync workflow are retired. Do not recreate them.

## Recovery

An interruption must preserve the same task identity and continue from the last persisted verified state. A new model/runtime must rehydrate from A MASTER BRAIN and verify consistency before operating as A.

## Operational query

`task_id → name → approval → execution_status → current_step → next_step → latest_update → executor/run → evidence → verification → next approval → business/revenue state`

## Business continuity

Technical completion is not the final business state. Revenue-oriented work continues through value delivery and verified revenue outcome. Paper trading or simulated revenue does not count as realized revenue.
