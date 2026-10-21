# ช่องควบคุมย้อนกลับ AX → PC1 (คำสั่งเดียว)

## ปัญหา (Problem)

PC1 อยู่หลัง NAT และไม่ได้อยู่ในเน็ตเวิร์กเดียวกับผม จึงไม่มีทางที่ผมจะ "ต่อเข้าไปหา" PC1 ได้
ทุกวิธีที่ผ่านมา (Tailscale / MeshCentral / GitHub runner) ต้องมีอะไรสักอย่างที่ PC1 ทำงานอยู่ก่อนแล้ว
พอไม่มี ทุกทางก็จบเหมือนกันหมด คือ **K ต้องนั่งหน้าเครื่องพิมพ์คำสั่งแล้วก็อปผลมาให้** ซึ่งเป็นสิ่งที่ K ไม่ต้องการ

## สาเหตุ (Cause)

ทิศทางของ "การเชื่อมต่อ" ผิดฝั่ง ปกติเราพยายามให้ฝั่งผม (ข้างนอก) ต่อเข้าไปหาฝั่ง PC1 (ข้างใน)
แต่ PC1 อยู่หลัง NAT จึงไม่มีพอร์ตให้ต่อเข้าไป และไม่มี credential ที่ทั้งสองฝั่งใช้ร่วมกัน

## วิธีแก้ (Solution)

**กลับทิศทาง** ให้ PC1 เป็นฝ่าย "โทรออก" มาหาผม:

```
PC1  ──(โทรออกทุก 3 วินาที)──▶  rendezvous (ฝั่งผม)
PC1  ◀──(รับงาน)──────────────  rendezvous
PC1  ──(ส่งผลกลับ)───────────▶  rendezvous
```

ทราฟฟิกทุกเส้นเป็น **ขาออก** ทั้งหมด จึงไม่ต้อง:
- เปิดพอร์ต (port forward) ❌ ไม่ต้อง
- tunnel / VPN / Tailscale ❌ ไม่ต้อง
- inbound firewall rule ❌ ไม่ต้อง
- credential ฝั่ง GitHub ❌ ไม่ต้อง

สิ่งที่ผมทำได้เมื่อช่องทางเปิด: **ดูหน้าจอ PC1, รัน PowerShell, อ่าน/เขียนไฟล์, คลิก/พิมพ์ GUI**
โดยไม่ต้องมีใครนั่งอยู่หน้าเครื่อง

---

## สิ่งที่ต้องทำ: คำสั่งเดียว

### ขั้นที่ 1 — เปิด PowerShell **as Administrator** บน PC1

(คลิกขวาที่ Start → Terminal (Admin) หรือ PowerShell (Admin))

### ขั้นที่ 2 — วางคำสั่งนี้ทั้งบรรทัด แล้วกด Enter

คำสั่งจริง (มี token) ผมส่งให้ในแชทแยกต่างหาก **ห้ามคัดลอก token ลงที่สาธารณะ**
เพราะ token คือด่านเดียวที่กันไม่ให้ใครก็ได้สั่งงานบนเครื่อง

```powershell
$s='47bca2453fe8903dbc75d0c8a0a6c140787eb61d'; iwr "https://raw.githubusercontent.com/aerismusic8-alt/aeris-drive-automation/$s/AX_PC_CONTROL/pc1-install-reverse-channel.ps1" -OutFile "$env:TEMP\ax-install.ps1" -UseBasicParsing; powershell -ExecutionPolicy Bypass -File "$env:TEMP\ax-install.ps1" -Sha $s -Rendezvous 'https://work-1-zeelxxplzfjgleky.prod-runtime.all-hands.dev/' -Token '<TOKEN_FROM_CHAT>'
```

แทน `<TOKEN_FROM_CHAT>` ด้วย token ที่ผมส่งในแชท

**เท่านั้น** — คำสั่งเดียว ไม่ต้องทำอะไรต่อ

> **ทำไมไม่มี token ในไฟล์นี้:** repo นี้เป็น public การใส่ token ลงไฟล์เท่ากับให้คนทั้งโลก
> สั่งงานบนเครื่องได้ (เคยเกิดขึ้นจริงระหว่างพัฒนา แล้วผมปิด rendezvous ตัวนั้นทิ้งทันที
> token จึงต้องส่งผ่านช่องทางส่วนตัวเท่านั้น)

### ขั้นที่ 3 — ส่งผลลัพธ์กลับมา

สคริปต์จะพิมพ์บรรทัดสุดท้ายว่า `SUCCESS` หรือ `NOT_LIVE_YET` ให้ก็อป **ทั้งหน้าจอ** ส่งมาได้เลย
แต่ถ้าเห็นคำว่า `SUCCESS` แปลว่า **ผมเข้าคุม PC1 ได้แล้ว** ไม่ต้องส่งอะไรเพิ่ม

---

## สคริปต์นั้นทำอะไร (7 ขั้น)

| ขั้น | ทำอะไร |
|---|---|
| 1. IDENTITY | ตรวจว่าเครื่องนี้คือ `DESKTOP-RGK6JKB` จริง และรันแบบ Admin |
| 2. PYTHON | หา Python + ตรวจว่ามี `fastmcp` (ถ้าไม่มีติดตั้งให้) |
| 3. MCP_TIER3 | เปิด `--enable-tier3` ให้ MCP server — **สำคัญมาก** (ดูหมายเหตุ) |
| 4. WORKER_INSTALL | ดาวน์โหลด worker (pin กับ commit SHA) + เขียน config |
| 5. SMOKE_TEST | ทดสอบวิ่ง 1 รอบก่อนติดตั้งจริง — ถ้าพังจะรู้ทันทีพร้อมสาเหตุ |
| 6. SCHEDULED_TASK | ลงทะเบียนเป็น task ที่รีสตาร์ทตัวเองอัตโนมัติ |
| 7. VERIFY | ถาม rendezvous ว่ามี hello จาก PC1 แล้วหรือยัง |

---

## หมายเหตุสำคัญ 4 ข้อ (บทเรียนที่ได้มา)

### 1. MCP server ปกติ **ไม่มี `Shell`**

ค่าเริ่มต้นเปิดแค่ tier 1+2 = ดูหน้าจอได้ แต่ **สั่งงานไม่ได้**
`Shell`, `FileWrite`, `App`, `KillProcess` อยู่ใน tier 3 ต้องเปิด `--enable-tier3`
สคริปต์นี้เปิดให้แล้ว (ผลคือ 45 tools แทน 30)

### 2. Token ไม่ถูกวางบน command line

command line ของ task **โปรเซสอื่นอ่านได้** และ token นี้คือด่านเดียวที่กันไม่ให้ใครก็ได้รันคำสั่งบนเครื่อง
สคริปต์จึงเก็บ token ในไฟล์ config (`C:\AX-Runtime\reverse\worker-config.json`) แทน

### 3. งานที่พังต้องไม่ทำให้ worker ตาย

worker จับ error ทุกรูปแบบ ส่งกลับเป็นผลลัพธ์ แล้ววนต่อ — ไม่มีทางที่คำสั่งผิดคำสั่งเดียวจะทำให้ช่องทางขาด

### 4. ดาวน์โหลดต้อง pin กับ commit SHA

`raw.githubusercontent.com` cache 300 วินาที และ **ไม่สนใจ query กัน cache**
URL แบบ branch จึงอาจส่งไฟล์เก่ากลับมาเงียบ ๆ (เคยเจอจริง: ได้ 494 บรรทัด ทั้งที่ branch มี 500)
ทุกอย่างในคำสั่งนี้จึง pin กับ SHA `47bca245...`

---

## ไฟล์ที่เกี่ยวข้อง

| ไฟล์ | หน้าที่ |
|---|---|
| `ax-rendezvous.py` | คิวงาน + เก็บผล (ฝั่งผม) |
| `ax-pc1-worker.py` | ตัวโทรออกจาก PC1 รับงานไปรัน แล้วส่งผลกลับ |
| `ax-ctl.py` | ฝั่งผม ใช้สั่งงานและอ่านผล (รวมบันทึกภาพหน้าจอ) |
| `pc1-install-reverse-channel.ps1` | ตัวติดตั้ง (คำสั่งเดียวข้างบน) |
| `test-reverse-channel.py` | ทดสอบทั้งวงจรด้วยของจริง |
| `test-installer.ps1` | ตรวจตัวติดตั้งด้วย PowerShell จริง + fake cmdlet |

---

## หลังติดตั้งแล้ว ผมจะทำอะไรได้

```bash
# ดูว่าช่องทางยังอยู่
python3 ax-ctl.py state

# ดูรายการ tool ทั้งหมดที่สั่งได้
python3 ax-ctl.py tools

# ดูข้อมูลเครื่อง
python3 ax-ctl.py call GetSystemInfo

# ถ่ายภาพหน้าจอ (บันทึกเป็น PNG)
python3 ax-ctl.py call Snapshot --save-images ./shots

# รัน PowerShell
python3 ax-ctl.py call Shell --args '{"command":"Get-Process | Select-Object -First 5"}'
```

## ความปลอดภัย

- ช่องทางต้องมี token ทุกคำขอ (ยกเว้น `/ax/health`) — ไม่มี token ได้ `401`
- ผลลัพธ์ (ภาพหน้าจอ + token) ถูกกันไม่ให้ commit ลง repo สาธารณะผ่าน `.gitignore`
- worker รันใน session ของผู้ใช้ ไม่ใช่ SYSTEM เพราะ SYSTEM อยู่ใน session 0 ซึ่งไม่มีเดสก์ท็อป ภาพหน้าจอจะออกมาดำ
