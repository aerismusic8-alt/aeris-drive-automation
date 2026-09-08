# AX MASTER TASK REPORTING PROTOCOL

Effective: 2026-09-08

## Single master task rule

`AX_MASTER_BRAIN/AX_MASTER_TASK_REGISTRY_v2.json` is the only authoritative task catalog for AKATH. A task exists only when it has a canonical `task_id` in the registry's `tasks` array.

`1 task_id = 1 task = 1 canonical task record.`

All operational task details belong to that canonical task record or are linked to the same `task_id`. Runtime ledgers, execution records, evidence, verification, dashboards and chat context may reference the task but may not create a second task identity or substitute another task list.

## Exact task count

The reported task count MUST equal `len(tasks)` from the Master Task Registry at the time of the read.

AX MUST NOT:
- pad the list to reach a previously stated number;
- infer missing tasks from memory, dashboards, runtime records, execution history or chat messages;
- merge unrelated records simply to reach a target count;
- report a task as a master task unless its `task_id` exists in the current registry.

Example: if the registry has 8 canonical tasks, report 8. If it later has 7, report 7. If it has 9, report 9. The registry wins over every previous report.

## Task record integrity

Every task record requires:
- `task_id`
- `task_type` (`SYSTEM` or `MISSION`)
- `category`
- `name`
- `objective`
- `priority`
- `approval_status`
- `execution_status`
- `timestamp`
- `details`

`details` is the canonical operational envelope for current step, next step, approvals, worker, outputs, evidence, verification, blockers, retry/fallback and business/revenue state.

`MISSION` tasks must declare a target inside `details.target`.

Duplicate `task_id` values, unsupported task types/categories, or task records without required canonical fields are invalid and must fail closed.

## System versus mission lifecycle

### SYSTEM
A SYSTEM task is an enduring company component.

`BUILD -> VERIFY -> COMPLETED/OPERATIONAL -> MAINTAIN 24/7`

`COMPLETED` establishes the verified operational baseline; it does not retire the task. A fault triggers recovery and re-verification while retaining the same `task_id`.

### MISSION
A MISSION task is a finite objective with a target.

`START -> EXECUTE -> TARGET -> VERIFY -> COMPLETED -> CLOSED`

After target achievement and verification, the mission closes and retains its result, evidence and lessons under the same `task_id` as durable experience. It is not deleted merely because it is closed.

## Categories

Categories are management labels only. They make tasks easier to group and operate, but they are not a separate registry and cannot create additional tasks.

## Current work

There is exactly one active `current_work` pointer. It contains a `task_id` that MUST resolve to exactly one task record in the Master Task Registry. `current_work` is only a pointer and must not become a second copy of the task's details.

A new chat/channel/runtime must resolve:
`A MASTER BRAIN -> Master Task Registry -> current_work.task_id -> canonical task record -> latest evidence/verification`.

## Status rules

- QUEUED is not APPROVED.
- APPROVED is not EXECUTING.
- EXECUTING requires Actual Start + Trusted Timestamp + Execution Evidence.
- COMPLETED requires Verification.
- For SYSTEM, COMPLETED means verified operational baseline and continued maintenance is required.
- For MISSION, COMPLETED means the finite target was achieved and verified, after which the task may transition to CLOSED.
- HEARTBEAT, dashboard sync, persistence, and execution-registry activity do not by themselves prove business-task execution.
- If a historical timestamp is not supported by evidence, report `NOT RECORDED — ห้ามเดาเวลา`.

## Thai AX reporting pattern

AX status reports in chat should use a stable Thai structure so K can read the state immediately. The language may be Thai, but the canonical values (`task_id`, `SYSTEM/MISSION`, statuses, evidence IDs) must remain exact and machine-traceable.

### Header

`## อัปเดตงานปัจจุบัน — [วันที่/เวลาอ้างอิง]`

### 1. ภาพรวม

State one concise conclusion from the current Master Registry and latest verified evidence. Do not use heartbeat activity as a substitute for execution proof.

### 2. งานระบบ (SYSTEM)

Use this section for enduring systems only. Every item must include:

`[งานระบบ] task_id — ชื่องาน`

- สถานะอนุมัติ: `approval_status`
- สถานะการทำงาน: `execution_status`
- เวลา: `timestamp` (or `NOT RECORDED — ห้ามเดาเวลา`)
- ขั้นตอนปัจจุบัน: `details.current_step`
- ขั้นตอนถัดไป: `details.next_step`
- Worker: `details.worker`
- หลักฐาน: `details.evidence`
- การตรวจสอบ: `details.verification`
- ตัวติดขัด: `details.blockers`
- Retry/Fallback: `details.retry_fallback`
- สถานะธุรกิจ/รายได้: `details.business_revenue_state`

For SYSTEM tasks, when `COMPLETED / OPERATIONAL` is reached, explicitly state `ต้องบำรุงรักษา 24/7` rather than treating the task as retired.

### 3. ภารกิจ (MISSION)

Use this section for finite objectives only. Every item must include:

`[ภารกิจ] task_id — ชื่องาน`

- เป้าหมาย: `details.target`
- สถานะอนุมัติ: `approval_status`
- สถานะการทำงาน: `execution_status`
- เวลา: `timestamp` (or `NOT RECORDED — ห้ามเดาเวลา`)
- ขั้นตอนปัจจุบัน: `details.current_step`
- ขั้นตอนถัดไป: `details.next_step`
- Worker: `details.worker`
- หลักฐาน: `details.evidence`
- การตรวจสอบ: `details.verification`
- ตัวติดขัด: `details.blockers`
- Retry/Fallback: `details.retry_fallback`
- สถานะธุรกิจ/รายได้: `details.business_revenue_state`

For MISSION tasks, do not report `COMPLETED` or `CLOSED` until the finite target is actually achieved and verified. After closure, retain outcome, evidence and lessons under the same `task_id`.

### 4. งานที่กำลังทำอยู่

Report exactly one current work pointer:

`current_work.task_id -> canonical task record`

Do not duplicate it as a second task. State whether it is actually executing or only approved/queued.

### 5. Blocker / PCSEV

When a blocker exists, use the pattern:

`ปัญหา -> สาเหตุ -> วิธีแก้ -> ดำเนินการ -> หลักฐาน -> ตรวจสอบ`

The blocker must remain attached to the same canonical `task_id`.

### 6. ข้อสรุปการตัดสินใจ

End the operational report with one clear conclusion:

`PASS` = verified evidence supports the claimed state.
`PARTIAL` = some required evidence exists but the acceptance condition is incomplete.
`BLOCKED` = a known blocker prevents the required next step.
`QUEUED` = task exists but execution has not started.
`FAILED` = execution failed and recovery is required.

AX MUST NOT upgrade a state simply because a dashboard, heartbeat, ledger write, or chat result looks healthy.

## Source-of-truth boundaries

- Master Task Registry: authoritative task catalog, identity, type, category, status and canonical task details.
- Runtime `AxMissionLedger`: execution-detail persistence only; never a competing task registry.
- Evidence and verification: proof linked to the same `task_id`; never a source for inventing tasks.
- Dashboard/task views: derived projections only.
- Chat-local context and model memory: communication/context only; never task identity authority.
- Legacy duplicate task/mission registries must not be reintroduced.

Any approved change to task identity, task details, task status or current work must be persisted to A MASTER BRAIN before the next status report.
