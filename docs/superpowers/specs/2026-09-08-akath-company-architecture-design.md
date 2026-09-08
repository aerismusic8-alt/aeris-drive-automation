# AKATH Company Architecture Design

**Date:** 2026-09-08  
**Status:** K APPROVED DESIGN / SPECIFICATION FOR REVIEW  
**Authority:** K Final Authority  
**Executive:** AX  
**Company:** AKATH  
**Repository:** `aerismusic8-alt/aeris-drive-automation`

## 1. Purpose

จัดโครงสร้าง repository และ operating model ของ AKATH ให้เป็นระบบเดียว โดยไม่รื้อของที่ทำงานอยู่แล้ว และไม่สร้าง competing source of truth.

เป้าหมายคือให้คนหรือ AI ที่เข้ามาใหม่สามารถ reconstruct ได้ทันทีว่า:

`บริษัทคืออะไร → ใครมีอำนาจ → ตอนนี้สถานะอะไร → กำลังทำอะไร → ใคร execute → ผลคืออะไร → หลักฐานอยู่ที่ไหน → ขั้นต่อไปคืออะไร`

การเปลี่ยนแปลงทั้งหมดต้องรักษา GPT-independent runtime continuation และกติกา PCSEV ที่มีอยู่แล้ว.

## 2. Canonical Authority Model

โครงสร้างอำนาจและข้อมูลจะเป็น:

```text
K — Final Authority
        │
        ▼
AKATH — Company / Operating Identity
        │
        ▼
AX — Executive Management & Orchestration
        │
        ├── A MASTER BRAIN — durable knowledge / experience / lessons
        │
        ├── Master Task Registry — canonical current task catalog
        │
        ├── Runtime / Workforce — execution resources
        │
        └── Evidence / Verification — proof of execution and completion
```

กฎสำคัญ:

- A MASTER BRAIN = durable knowledge and accumulated experience; ไม่ใช่ current operational state.
- Master Task Registry = authoritative task catalog เพียงแห่งเดียว.
- Runtime ledgers, dashboards, chats, execution registries และ model memory เป็น projections/persistence/supporting state และห้ามสร้าง task identity แข่งขัน.
- `task_id` เดียวต้องหมายถึง task เดียวตลอด lifecycle.
- `current_work` เป็น pointer ไปยัง task เดิม ไม่ใช่ task record ใหม่.
- `APPROVED` ไม่เท่ากับ `EXECUTING`.
- `HEARTBEAT` ไม่เท่ากับ task execution.
- `EXECUTING` ไม่เท่ากับ `COMPLETED`.
- `COMPLETED` ต้องมี verification.
- ห้ามสร้าง timestamp ที่ไม่มีหลักฐาน.

## 3. Five Core Layers

### 3.1 Company Layer

รับผิดชอบ identity, mission, business direction, revenue priorities และ executive authority ของ AKATH.

Canonical identity ต้องสอดคล้องกับ `AX_MASTER_STATE.json` และ README ปัจจุบัน ซึ่งกำหนด AKATH เป็น Autonomous AI Company.

AERIS MUSIC ซึ่งยังปรากฏใน repository metadata/legacy naming ให้ถือเป็น legacy/product/business naming จนกว่าจะมี K decision แยกต่างหาก; design นี้ไม่เปลี่ยน brand identity โดยอัตโนมัติ.

### 3.2 Brain Layer

A MASTER BRAIN เก็บ:

- durable knowledge
- accumulated experience
- lessons learned
- historical decisions and rationale
- architecture knowledge
- recovery/continuity knowledge
- verified evidence references
- verified outcomes/failures

Current verified AKATH/AX state outranks historical brain knowledge for present operational truth.

### 3.3 Management Layer

AX เป็น executive management/orchestration layer และต้องอ่าน canonical state ก่อนรายงานหรือเปลี่ยน operational context.

ประกอบด้วย:

- AX master state
- company priorities
- operating policies
- Master Task Registry
- single `current_work`
- task lifecycle/status rules
- management categories
- rehydration protocol
- continuous reflection

### 3.4 Execution Layer

รวม runtime และ execution resources ที่ AX ใช้ เช่น workers, agents, queue, dispatcher, PC1/PC2 และ GitHub Actions.

Execution layer ไม่สามารถประกาศ task identity ใหม่เองได้.

Execution claim ต้องผูกกับ canonical `task_id` และมี trusted timestamp/evidence ตาม contract.

### 3.5 Evidence Layer

เก็บ execution evidence, verification, acceptance results, recovery evidence และ audit trail.

Evidence ต้องใช้เพื่อแยก:

`configured → approved → started → executed → verified → completed/closed`

Dashboard/heartbeat/configuration ที่ไม่มี execution evidence ห้ามถูกตีความเป็น proof of autonomous operation.

## 4. Task Architecture

ใช้ `AX_MASTER_BRAIN/AX_MASTER_TASK_REGISTRY_v2.json` เป็น canonical task source.

ข้อกำหนด:

1. ทุก task มี stable `task_id` เดียว.
2. ทุก task เป็น `SYSTEM` หรือ `MISSION` เท่านั้น.
3. `SYSTEM` คือ enduring component; หลัง verified completion ต้องรักษา operational baseline ต่อเนื่อง 24/7.
4. `MISSION` คือ finite objective; เมื่อ target achieved และ verified ให้ transition เป็น `CLOSED` โดยคง outcome experience ไว้ใน A MASTER BRAIN.
5. category เป็นเพียง management label และไม่สร้าง registry ใหม่.
6. task count = `len(tasks)` ณ เวลาที่อ่าน registry.
7. ห้าม padding, invention, backfill, merge หรือดึง task จาก chat/dashboard/runtime เพื่อให้จำนวนตรงกับรายงานเก่า.
8. ทุก operational detail ต้องผูกกับ task_id เดียวกัน.
9. ต้องมี exactly one active `current_work` pointer และ pointer ต้องชี้ task ที่มีอยู่จริง.

Acceptance refinement ที่มีอยู่ใน master state ต้องถูกนำไปใช้จริง โดยเฉพาะ SYSTEM-vs-MISSION, category validation, mission target declaration และ canonical detail linkage.

## 5. Revenue and Priority Model

Company priorities ยังคงเป็น:

- P1 Revenue
- P2 Continuity
- P3 Input/Limit
- P4 Financial Control
- P5 Autonomous Execution

Revenue systems must remain guarded. Financial/live-money execution cannot bypass K authority and verification.

Current canonical `current_work` remains `AICS-LIVE-TRADING` unless a later verified K decision changes it through the canonical registry.

## 6. Repository Organization Rules

การจัด repository จะใช้ existing architecture เป็นฐาน ไม่สร้าง parallel architecture.

Logical ownership:

```text
Company / entry docs
  README.md

Company runtime
  AKATH/

AX management + knowledge
  AX_MASTER_BRAIN/

Execution/control surfaces
  AX_* runtime/control files
  .github/workflows/

Architecture decisions/specs
  docs/superpowers/specs/
  docs/superpowers/plans/

Evidence / verification
  AKATH/VERIFICATION/
  existing runtime evidence locations
```

ก่อนย้าย/rename file ใด ๆ ต้องตรวจ references และ tests ก่อน และต้องไม่ทำให้ canonical paths ที่ runtime ใช้อยู่เสียหาย.

## 7. Rehydration Contract

ทุก AX-compatible channel/runtime ต้องสามารถ reconstruct จาก canonical storage ตามลำดับ:

`LOAD_REHYDRATION_CONTRACT → LOAD_AKATH_AX_IDENTITY → LOAD_MASTER_STATE → LOAD_MASTER_TASK_REGISTRY → VALIDATE_TASK_IDENTITY_UNIQUENESS → VALIDATE_TASK_TYPE_AND_CATEGORY → RESOLVE_SINGLE_CURRENT_WORK → LOAD_CANONICAL_TASK_RECORD → LOAD_LATEST_EVIDENCE_AND_VERIFICATION → LOAD_A_MASTER_BRAIN_KNOWLEDGE_AND_EXPERIENCE → RECONSTRUCT_AX_CONTEXT → VERIFY_CONSISTENCY → REPORT_FACTS_WITH_TRUSTED_TIMESTAMPS → CONTINUE_ONLY_FROM_VERIFIED_STATE`

การ switch model/runtime ต้อง rehydrate และ verify ใหม่; model-local memory ไม่มีสิทธิ์ override canonical state.

## 8. PCSEV Operating Loop

ทุกงานที่ AX อ้างว่า execute ต้องรองรับ:

`Problem → Cause → Solution → Execute → Evidence → Verify`

ข้อกำหนดขั้นต่ำ:

- Execute ต้องมี evidence.
- Completion ต้องมี verification.
- Failure ต้องมี blocker/retry/fallback state.
- Recovery ต้องรักษา task_id เดิม.
- Lessons จากผลลัพธ์ที่ verified ต้องส่งกลับ A MASTER BRAIN.

## 9. Acceptance Gates

ก่อนถือว่า architecture implementation complete ต้องผ่านอย่างน้อย:

1. Runtime startup loads canonical state.
2. State writes back after valid transitions.
3. Evidence and verification link to the same task_id.
4. File ID persistence remains intact.
5. Fresh-channel reconstruction succeeds.
6. Interrupted execution resumes from canonical state.
7. Two-model/two-runtime portability succeeds.
8. Source-of-truth conflict resolution follows authority precedence.
9. Continuous reflection checks claims/evidence/uncertainty/conflicts/lessons/state.
10. Exactly one current_work remains active.
11. Task IDs are unique and reported count equals registry length.
12. No task padding/invention occurs.
13. Canonical task details remain attached to the same task_id.
14. SYSTEM and MISSION validation passes.
15. MISSION targets are explicitly declared where applicable.
16. Existing verified runtime tests remain passing.

## 10. Non-Goals

Design นี้ไม่ทำสิ่งต่อไปนี้โดยอัตโนมัติ:

- ไม่สร้างบริษัทใหม่หรือเปลี่ยน K authority.
- ไม่สร้าง second task registry.
- ไม่ย้าย live-money authority ไปให้ AX.
- ไม่ถือ dashboard/heartbeat เป็น execution proof.
- ไม่ลบ legacy files เพียงเพราะชื่อไม่ตรง architecture.
- ไม่เปลี่ยน AERIS MUSIC เป็น brand/business unit อย่างเป็นทางการโดยไม่มี K decision.
- ไม่ประกาศ 24/7 verified หากไม่มี persisted real execution evidence ตาม acceptance contract.

## 11. Implementation Sequence

หลัง K อนุมัติ specification นี้ ให้สร้าง implementation plan แยกตาม subsystem ที่สามารถทดสอบได้เป็นอิสระ โดยลำดับหลักคือ:

1. Canonical documentation / architecture map.
2. Task-model acceptance and registry validation.
3. Runtime/rehydration integration.
4. Evidence/verification linkage.
5. Dashboard/reporting projection integrity.
6. Final repository consistency and acceptance verification.

แต่ละ subsystem ต้องใช้ TDD และ verification ก่อนประกาศ complete.

## 12. Definition of Done

Architecture restructuring ถือว่าเสร็จเมื่อ repository มี single coherent model ที่ enforce ได้จริง และสามารถตอบคำถาม operational chain ได้จาก canonical storage โดยไม่พึ่ง model-local memory:

`K → AKATH → AX → Current State → Canonical Task → Execution → Evidence → Verification → Next Step`

พร้อมทั้งรักษา existing verified functionality, GPT-independent continuation และ authority boundaries เดิม.
