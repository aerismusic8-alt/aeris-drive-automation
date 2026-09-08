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

## Thai AX baseline-first reporting pattern

This is the default response pattern for status/update commands such as `ax อัพเดทงานในระบบปัจจุบันด้วย`.

**Mandatory rule:** AX MUST complete the baseline report from live canonical state BEFORE beginning analysis, planning, recommendations, or new task decomposition.

The baseline is a read/rehydration step, not a reasoning step. It must use the current system state and canonical registry, then expose the state in a stable Thai format. Only after the baseline is shown may AX use reasoning to decide what should happen next.

### Baseline sequence — exactly 1 to 8

| ลำดับหัวข้อสิ่งที่ AX ต้องทำแหล่งข้อมูล |
|---|---|---|
| 1 | **สถานะระบบ** | อ่านสถานะหลักของ AKATH ปัจจุบันก่อนทุกครั้ง | A MASTER BRAIN |
| 2 | **จำนวนงานทั้งหมด** | รายงานจำนวนจาก `tasks` จริงเท่านั้น ห้ามเดา/เติม | Master Task Registry |
| 3 | **งานระบบ (SYSTEM)** | แสดงงานระบบทั้งหมดที่อยู่ใน Registry พร้อมสถานะ | Master Task Registry |
| 4 | **ภารกิจ (MISSION)** | แสดงภารกิจทั้งหมด พร้อมเป้าหมายและสถานะ | Master Task Registry |
| 5 | **งานที่กำลังทำอยู่** | ชี้ `current_work.task_id` เพียงตัวเดียว | Master Task Registry |
| 6 | **หลักฐานล่าสุด** | แสดง evidence/verification ที่มีจริง | Evidence / Runtime |
| 7 | **ตัวติดขัด** | ระบุ blocker ที่ผูกกับ `task_id` | Canonical task details |
| 8 | **สถานะสรุป** | `PASS / PARTIAL / BLOCKED / QUEUED / FAILED` ตามหลักฐานจริง | AX Verification |

### Reasoning sequence — exactly 9 to 12

หลังจาก baseline ข้อ 1–8 เสร็จแล้วเท่านั้น AX จึงเริ่มใช้สมองต่อ:

| ลำดับหัวข้อสิ่งที่ AX ต้องทำแหล่งข้อมูล |
|---|---|---|
| 9 | **เข้าสู่สมอง AX** | หลัง baseline เท่านั้น จึงเริ่มวิเคราะห์และตัดสินใจ | AX Reasoning |
| 10 | **PCSEV ต่อเนื่อง** | ปัญหา → สาเหตุ → วิธีแก้ → ดำเนินการ → หลักฐาน → ตรวจสอบ | AX Execution |
| 11 | **งานถัดไป** | เลือกงานต่อจากสถานะจริง ไม่สร้าง task ใหม่ | Master Task Registry |
| 12 | **วนต่อ** | Execute → Verify → Update State → คิดงานต่อ | AKATH Runtime |

### Required Thai output layout

Every baseline report should use this order:

`## อัปเดตงานปัจจุบัน — [วันที่/เวลาอ้างอิง]`

`### 1. สถานะระบบ`

`### 2. จำนวนงานทั้งหมด`

`### 3. งานระบบ (SYSTEM)`

Each item:
`[งานระบบ] task_id — ชื่องาน`

- สถานะอนุมัติ:
- สถานะการทำงาน:
- เวลา:
- ขั้นตอนปัจจุบัน:
- ขั้นตอนถัดไป:
- Worker:
- หลักฐาน:
- การตรวจสอบ:
- ตัวติดขัด:
- Retry/Fallback:
- สถานะธุรกิจ/รายได้:

`### 4. ภารกิจ (MISSION)`

Each item:
`[ภารกิจ] task_id — ชื่องาน`

- เป้าหมาย:
- สถานะอนุมัติ:
- สถานะการทำงาน:
- เวลา:
- ขั้นตอนปัจจุบัน:
- ขั้นตอนถัดไป:
- Worker:
- หลักฐาน:
- การตรวจสอบ:
- ตัวติดขัด:
- Retry/Fallback:
- สถานะธุรกิจ/รายได้:

`### 5. งานที่กำลังทำอยู่`

Report exactly one current work pointer:
`current_work.task_id -> canonical task record`

`### 6. หลักฐานล่าสุด`

Show only evidence that actually exists and is linked to the relevant task_id. Do not convert heartbeat/dashboard/persistence into execution evidence.

`### 7. ตัวติดขัด`

Show blockers attached to the canonical task_id. Do not turn an issue, error, or observation into a new master task unless K explicitly changes the Master Registry.

`### 8. สถานะสรุป`

Use only evidence-supported values:
`PASS` / `PARTIAL` / `BLOCKED` / `QUEUED` / `FAILED`.

### Transition to AX reasoning

Only after the baseline is visible may AX continue with:

`### 9. เข้าสู่สมอง AX`

Then:
`### 10. PCSEV ต่อเนื่อง`
`### 11. งานถัดไป`
`### 12. วนต่อ`

K may ask a question about any single item after the baseline. AX should answer from the same canonical task record and should not require K to restate the task context.

## Source-of-truth boundaries

- Master Task Registry: authoritative task catalog, identity, type, category, status and canonical task details.
- Runtime `AxMissionLedger`: execution-detail persistence only; never a competing task registry.
- Evidence and verification: proof linked to the same `task_id`; never a source for inventing tasks.
- Dashboard/task views: derived projections only.
- Chat-local context and model memory: communication/context only; never task identity authority.
- Legacy duplicate task/mission registries must not be reintroduced.

Any approved change to task identity, task details, task status or current work must be persisted to A MASTER BRAIN before the next status report.
