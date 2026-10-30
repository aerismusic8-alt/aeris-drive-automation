# แก้ PC1 ให้เอเจนต์สั่งงานได้ — FileWrite / PlaySound (Tier 3)

สถานะที่ตรวจมาแล้ว (2026-10-26): **PC1 ออนไลน์อยู่ แต่ตัวเสิร์ฟ MCP บนเครื่องดับ**

หลักฐาน: `https://desktop-rgk6jkb.tail8740ad.ts.net/health` ตอบ **502**
ไม่ใช่ timeout — แปลว่า `tailscaled` ทำงานอยู่และตัว `tailscale serve` ยังเปิดพอร์ตไว้
คือ **เครื่องเปิดอยู่ ต่อเน็ตได้** แต่โปรเซส `winremote-mcp` ที่ 127.0.0.1:8090 ไม่ตอบ

พอร์ต 8090 ปิด, 3389 ปิด, 22 ปิด → ไม่มีทางต่อเข้าไปตรง ๆ
runner บน PC1 ก็ตาย (งานค้างคิว 2 งาน) และโทเคน GitHub ของฝั่งนี้ไม่มีสิทธิ์ dispatch (403)
**จึงไม่มีทางที่ฝั่งเอเจนต์จะไปสตาร์ทโปรเซสบน PC1 ได้เอง** — ต้องรันที่เครื่อง

---

## ทำไม "แคปเจอร์ได้ แต่สั่งงานไม่ได้"

`winremote-mcp` แบ่งเครื่องมือเป็น 3 ชั้น และ **ชั้น 3 ปิดไว้โดยค่าเริ่มต้น**:

| ชั้น | เครื่องมือ | ค่าเริ่มต้น |
| --- | --- | --- |
| 1 (อ่านอย่างเดียว) | `Snapshot`, `GetClipboard`, `FileList`, `OCR`, `GetSystemInfo` | เปิด |
| 2 (กด/พิมพ์) | `Click`, `Type`, `Move`, `Scroll`, `Shortcut`, `FocusWindow` | เปิด |
| **3 (เขียน/รัน)** | **`Shell`, `FileRead`, `FileWrite`, `FileUpload`, `FileDownload`, `App`, `KillProcess`, `PlaySound`, `RegWrite`, `ServiceStart`** | **ปิด** |

ค่าเริ่มต้นจึงมี **30 tools** → ถ่ายรูปหน้าจอได้ แต่ `FileWrite` / `PlaySound` / `Shell` **ไม่มีอยู่จริง**
พอเรียกจะได้ error ว่าไม่มี tool นั้น ซึ่งอ่านดูเหมือน "สิทธิ์ไม่พอ" แต่จริง ๆ คือ **ยังไม่เปิดชั้น 3**

เปิดด้วยแฟล็กเดียว: `--enable-tier3` (จะได้ **45 tools**)

### ต้องเปิดบทสนทนาใหม่ด้วย

รายการ tool ถูกโหลด **ครั้งเดียวตอนบทสนทนาเริ่ม** แก้ที่เซิร์ฟเวอร์แล้ว
บทสนทนาเดิมจะยังเห็น 30 tools เหมือนเดิม — ต้อง **เปิดบทสนทนาใหม่** จึงจะเห็น 45

---

## วิธีแก้ — คำสั่งเดียวบน PC1

### ขั้นที่ 1 — เปิด PowerShell **as Administrator** ที่ PC1

Start → พิมพ์ `powershell` → คลิกขวา → **Run as administrator**

### ขั้นที่ 2 — วางคำสั่งนี้ทั้งบรรทัด แล้วกด Enter

```powershell
iwr 'https://work-1-jhakqeqvkcqlwmjh.prod-runtime.all-hands.dev/pc1_fix_remote.ps1' -OutFile "$env:TEMP\pc1_fix_remote.ps1" -UseBasicParsing; powershell -ExecutionPolicy Bypass -File "$env:TEMP\pc1_fix_remote.ps1" -Persist
```

**ไม่ต้องใส่ `-Token`** — สคริปต์จะใช้คีย์เดิมที่อยู่ในเครื่องต่อ
(`C:\AX-Runtime\winremote\winremote-auth.key`) ทำให้ค่า secret `PC1_MCP_TOKEN_2`
ใน OpenHands ยังใช้ได้เหมือนเดิม

> **ทำไมไม่ใส่ `-Token`:** token ที่วางบน command line นั้น **โปรเซสอื่นในเครื่องอ่านได้**
> (repo นี้เคยเจอปัญหานี้ จึงเก็บ token ในไฟล์แทน) ใช้ `-Token` เฉพาะเมื่อไม่มีไฟล์คีย์เดิม
> หรือต้องการตั้งคีย์ใหม่เท่านั้น:
> `-Token "<PC1_MCP_TOKEN>" -Persist`
> ถ้าตั้งใหม่ ต้องไปแก้ secret `PC1_MCP_TOKEN_2` ใน OpenHands ให้ตรงกับค่าใหม่ด้วย
> (ค่าจริงอยู่ในไฟล์ `winremote-auth.key` สคริปต์พิมพ์ให้แค่ 4 ตัวแรก)

> **ลิงก์นี้เป็นของ pod ชั่วคราว** — ใช้ได้ตราบเท่าที่บทสนทนานี้ยังไม่ปิด
> ถ้าหมดอายุแล้ว ให้ขอไฟล์ใหม่จากเอเจนต์ (ไฟล์อยู่ใน repo ที่ `ops/pc1_fix_remote.ps1`)

### ขั้นที่ 3 — รอจนจบ แล้วดูบรรทัด `RESULT`

สคริปต์จะพิมพ์ปิดท้ายแบบนี้:

```
SCRIPT_VERSION=2026-10-26.1
TOOLS=45
TIER3=on
SHELL_PROOF=<ชื่อเครื่อง PC1>
FILEWRITE_PROOF=ok
RESULT=OK
```

ถ้าเห็น `RESULT=OK` แปลว่าเสร็จ — ส่งกลับมาได้เลย

ถ้าไม่เห็น ให้คัดลอก **ทั้งหน้าจอ** ส่งมา โดยเฉพาะบรรทัดที่ขึ้นต้นด้วย
`MCP_SERVER_NOT_HEALTHY` หรือ `TIER3_STILL_DISABLED` (สคริปต์จะพิมพ์ log 30 บรรทัดท้ายให้เอง)

### ขั้นที่ 4 — เปิดบทสนทนาใหม่ใน OpenHands

สำคัญ: **บทสนทนาเดิมจะยังเห็น 30 tools** เพราะโหลดรายการ tool ตอนเริ่มเท่านั้น

---

## สคริปต์นั้นทำอะไร (เรียงตามลำดับ)

| ขั้น | ทำอะไร |
| --- | --- |
| IDENTITY | ตรวจว่าเครื่องนี้คือ `DESKTOP-RGK6JKB` จริง |
| PYTHON | หา Python + ติดตั้ง/อัปเดต `winremote-mcp` |
| AUTH_KEY | ใช้คีย์เดิม หรือคีย์ที่ส่งมา แล้วล็อกสิทธิ์ไฟล์ให้ SYSTEM+Administrators |
| **START_SCRIPT** | **เขียนคำสั่งสตาร์ทใหม่ให้มี `--enable-tier3`** ← ตัวแก้จริง |
| TASK | ลงทะเบียน scheduled task ให้รีสตาร์ทเองทุกครั้งที่ล็อกอิน |
| RUNNER | ปลุก GitHub Actions runner (งานที่ค้างคิวจะได้วิ่ง) |
| TAILSCALE | ยืนยัน `tailscale serve 8090` (ทางเข้าที่ไม่พึ่ง runner) |
| VERIFY_HEALTH | ยิง `/health` จริง |
| **VERIFY_TIER3** | **เรียก `Shell` และ `FileWrite` จริง** เพื่อพิสูจน์ว่าเปิดชั้น 3 แล้ว |
| EVIDENCE | เขียนผลลง `C:\AX-Runtime\evidence\pc1-remote-fix.json` |

รันซ้ำได้ไม่จำกัด (idempotent) — รันตอนไหนก็ได้ ผลเท่าเดิม

---

## หลังแก้เสร็จ เอเจนต์จะทำอะไรได้

```bash
python3 ops/check_pc1.py            # ตรวจว่าขับได้แล้วหรือยัง
python3 ops/pc1_live.py doctor      # ยืนยันว่ามี Shell/Click/Type
python3 ops/pc1_live.py shot out/pc1.png     # แคปจอจริง
python3 ops/pc1_live.py call Shell '{"command":"hostname"}'
```

---

## หมายเหตุด้านความปลอดภัย

- ชั้น 3 คือ **รัน PowerShell ได้ทุกคำสั่ง** เทียบเท่า remote code execution
  จึงปลอดภัยเพราะเซิร์ฟเวอร์ผูกกับ `127.0.0.1` และเข้าได้ทาง `tailscale serve` เท่านั้น
  (ไม่ใช่ Funnel) คือจำกัดอยู่ใน tailnet เดียวกัน
- คีย์ยังบังคับทุกคำขอ (`--auth-key`) คีย์เก็บในไฟล์ที่อ่านได้เฉพาะ SYSTEM
- **ห้าม** เปิด Tailscale Funnel กับพอร์ตนี้ และ **ห้าม** ผูก `0.0.0.0` โดยไม่มีคีย์
