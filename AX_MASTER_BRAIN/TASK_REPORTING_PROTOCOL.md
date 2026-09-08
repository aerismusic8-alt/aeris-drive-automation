# AX MASTER TASK REPORTING PROTOCOL

Effective: 2026-09-08

Every request for AX task status must resolve the complete current master task registry before reporting. `AX_MASTER_BRAIN/AX_MASTER_TASK_REGISTRY_v2.json` is the authoritative task list and contains exactly one active `current_work` record.

Required fields for every task: Approval Status, Execution Status, Timestamp.
Required fields for `current_work`: `task_id`, `name`, `priority`, `approval_status`, `execution_status`, `current_step`, `next_step`, `updated_at`, and evidence references where available.

Rules:
- QUEUED is not APPROVED.
- APPROVED is not EXECUTING.
- EXECUTING requires Actual Start + Trusted Timestamp + Execution Evidence.
- COMPLETED requires Verification.
- HEARTBEAT, dashboard sync, persistence, and execution-registry activity do not by themselves prove business-task execution.
- If a historical timestamp is not supported by evidence, report `NOT RECORDED — ห้ามเดาเวลา`.
- The master task registry is authoritative for the task list and current-work identity.
- Only one `current_work.active=true` is allowed.
- `current_work.task_id` must reference an existing task in the master registry.
- Dashboard/task views are derived projections and cannot create, rename, activate, or supersede current work.
- Chat-local context, model memory, or generated summaries cannot mutate task identity or state.
- A new chat/channel/runtime must resolve current work from A MASTER BRAIN -> Master Task Registry -> latest evidence/verification, then continue from that same task ID.
- Runtime mission details may be stored in the existing `AxMissionLedger`, but it is execution-detail persistence, not a second master task registry.
- Legacy duplicate task/mission registries must not be reintroduced.
- Any approved change must be persisted to AX MASTER BRAIN before the next status report.
