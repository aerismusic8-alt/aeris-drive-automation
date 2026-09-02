# AX MASTER TASK REPORTING PROTOCOL

Effective: 2026-09-02T16:54:00+07:00

Every request for AX task status must report the complete current master task registry, not a partial list.

Required fields for every task: Approval Status, Execution Status, and Timestamp.

Rules:
- QUEUED is not APPROVED.
- APPROVED is not EXECUTING.
- EXECUTING requires Actual Start + Trusted Timestamp + Execution Evidence.
- COMPLETED requires Verification.
- HEARTBEAT, dashboard sync, persistence, and execution-registry activity do not by themselves prove business-task execution.
- If a historical timestamp is not supported by evidence, report NOT RECORDED — ห้ามเดาเวลา.
- The master task registry is authoritative for the task list.
- Any approved change must be persisted to AX MASTER BRAIN before the next status report.
