# AX Time, Workload & Capacity Control Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** ทำให้ AX มีโครงสร้างถาวรสำหรับวัดเวลา ประสิทธิภาพ Workload (ปริมาณงาน), Capacity (ความสามารถรองรับงาน), Bottleneck (คอขวด) และ Forecast (การคาดการณ์) พร้อมภาษาไทยกำกับ

**Architecture:** ใช้ Task/Mission ID เดิมตลอดวงจรงาน แยก Target Time ออกจาก Actual Time และแยก Batch Timing ออกจาก Task Timing. เพิ่มข้อมูล workload/capacity เป็นชั้นวัดผลเหนือคิวงาน และให้รายงานผู้บริหารสรุปเป็นภาษาไทยโดยมีศัพท์เทคนิคอังกฤษกำกับเมื่อจำเป็น

**Tech Stack:** GitHub repository, JSON registry/configuration, existing AX Mission/Task components, existing dashboard/reporting paths

**Spec:** `docs/superpowers/specs/2026-09-02-ax-time-workload-capacity-design.md`

## Global Constraints

- ภาษาไทยเป็นภาษาหลักในการสื่อสารกับ K; ศัพท์เทคนิคอังกฤษต้องมีคำไทยกำกับ
- Target Time และ Actual Time ต้องแยกจากกัน
- Batch Start ห้ามถูกนับเป็น Task Start โดยไม่มีหลักฐานการเริ่มงานจริง
- ห้ามรายงานเวลาจริงจากการประมาณการ
- งานต้องคงอยู่ใน Persistent Queue และใช้ Task/Mission ID เดิมตลอด lifecycle
- Capacity ต้องคำนวณจากข้อมูลจริง ไม่กำหนดจากการเดา
- หากกฎถูกละเมิดต้องเข้าสู่ PCSEV และบันทึกประสบการณ์ป้องกันการเกิดซ้ำ

---

### Task 1: ลงทะเบียนกฎโครงสร้าง AX

**Files:**
- Create: `docs/superpowers/specs/2026-09-02-ax-time-workload-capacity-design.md`
- Create: `docs/superpowers/plans/2026-09-02-ax-time-workload-capacity.md`

- [x] บันทึกกฎโครงสร้างและภาษาไทยเป็นหลัก
- [x] บันทึกหลักฐาน commit

### Task 2: ขยาย Task Registry ให้รองรับการวัดเวลาและโหลด

**Files:**
- Modify: `AX_TASK_REGISTRY.json`

**Interfaces:**
- เพิ่ม schema metadata สำหรับ Target/Actual, workload, capacity และ bottleneck โดยไม่ลบ task เดิม

- [ ] อ่าน registry ปัจจุบันและรักษานโยบายเดิม
- [ ] เพิ่ม policy สำหรับ time/workload/capacity tracking
- [ ] เพิ่ม recovered tasks โดยคงสถานะที่ยังไม่ verified ตามหลักฐานจริง
- [ ] ตรวจสอบ JSON และความถูกต้องเชิงโครงสร้าง

### Task 3: เชื่อมการรายงานภาษาไทยและตัวชี้วัด

**Files:**
- ตรวจสอบ/แก้ไฟล์ dashboard/reporting ที่มีอยู่ตามจุดเชื่อมจริง

- [ ] ระบุจุดสร้าง executive status
- [ ] เพิ่ม Technical Metric + คำไทยกำกับ
- [ ] เพิ่ม Target vs Actual, queue, utilization, headroom, bottleneck และ forecast
- [ ] ทดสอบข้อมูลตัวอย่างโดยไม่อ้างว่าเป็นข้อมูลจริง

### Task 4: ตรวจสอบการทำงานจริงและหลักฐาน

- [ ] ตรวจสอบว่า Task Start/End มีหลักฐานจริง
- [ ] ตรวจสอบ pause/resume และ elapsed time
- [ ] ตรวจสอบ queue/workload/capacity calculations
- [ ] ตรวจสอบรายงานภาษาไทย
- [ ] บันทึกผล PASS/FAIL พร้อมหลักฐาน

### Task 5: ปิดวงจร PCSEV สำหรับการละเมิดกฎ

- [ ] กำหนด event ที่ถือเป็น violation
- [ ] บันทึก Problem/Cause/Solution/Execute/Verify
- [ ] บันทึก experience/rule เพื่อป้องกันซ้ำ
- [ ] ทดสอบว่าการละเมิดครั้งถัดไปสามารถตรวจจับได้
