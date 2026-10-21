# รีโมท PC1 จากมือถือ (Remote PC1 from a phone)

เอกสารนี้ตอบคำถามว่า "จะคุม PC1 จากมือถือได้ยังไง" และอธิบายว่าทำไม
คำตอบจึงเป็น MeshCentral ไม่ใช่ RDP หรือ TeamViewer

## ทำไม MeshCentral

agent บน PC1 เป็นฝ่าย **dial ออก** ไปหาเซิร์ฟเวอร์เอง
ไม่ต้องเปิดพอร์ต inbound ที่ router ไม่ต้องมี public IP ไม่ต้อง VPN
เพราะการเชื่อมต่อเริ่มจากฝั่ง PC1

ผลคือได้หน้าเว็บที่เปิดจากเบราว์เซอร์มือถือได้เลย ใช้ดูจอ (remote desktop)
เปิด terminal และโอนไฟล์ได้ และไม่ผูกกับ IP ของบ้าน

ทางเลือกอื่นเทียบกัน:

| วิธี | ใช้จากมือถือ | ต้อง forward port | หมายเหตุ |
| --- | --- | --- | --- |
| MeshCentral | ได้ (เบราว์เซอร์) | ไม่ต้อง | agent ต่อออกเอง เหมาะกับมือถือที่สุด |
| RDP | ได้ (แอป) | ต้อง | ต้องมี public IP หรือ VPN และ NAT ให้ถูก |
| TeamViewer / AnyDesk | ได้ | ไม่ต้อง | ฟรีเฉพาะส่วนตัว ข้อมูลผ่านเซิร์ฟเวอร์เจ้าอื่น |
| SSH tunnel | ได้ | ต้องมีที่ปลายทาง | ไม่มี GUI ต้องมีเครื่องปลายทางอีกเครื่อง |
| GitHub Actions runner | ไม่ได้ | ไม่ต้อง | รันสคริปต์ได้ แต่ดูจอไม่ได้ |

สรุป: **runner ใช้รันงาน, MeshCentral ใช้ดูจอ** สองอย่างนี้แยกกันและต้องมีทั้งคู่
ถ้า runner ตาย งานค้างคิว ถ้า MeshCentral agent ตาย มองไม่เห็นเครื่องเลย

## สถานะปัจจุบันของ PC1

PC1 คือ `DESKTOP-RGK6JKB` และโปรเจกต์นี้รู้จัก MeshCentral mesh ของมันแล้ว:

- mesh id: `mesh//HUDxIAER8NjFSHwMsSgbnomozWA6r0POFmTffaFngdSiQVcm2deqn4tnseiBBaTV`
- host ที่ลงทะเบียนไว้: `192.168.250.41`

ตัว adapter `AX_PC_CONTROL/pc1-meshcentral-ax-dispatch.ps1` มีอยู่แล้ว
แต่มันต้องมีค่า environment `AKATH_MESHCTRL_*` บน **เครื่องที่สั่งงาน** (control host)
ไม่ใช่บน PC1

ตรวจว่าอะไรพร้อมแล้วบ้าง รันบน PC1:

```powershell
powershell -ExecutionPolicy Bypass -File AX_PC_CONTROL\pc1-remote-access-status.ps1
```

สคริปต์นี้รายงานว่าอะไรพร้อม อะไรขาด และต้องทำอะไรต่อ โดยไม่อ่านรหัสผ่าน
หรือ login key ใด ๆ — รายงานแค่ว่ามีอยู่หรือไม่มี

## ขั้นตอนเปิดรีโมท (ทำครั้งเดียว)

### 1. เตรียมเซิร์ฟเวอร์ MeshCentral

ต้องมี MeshCentral server ที่ PC1 ต่อออกไปหาได้ ที่นิยมคือ
รันบน VPS ตัวเล็ก ๆ แล้วเปิดพอร์ต 443

ถ้ามีเซิร์ฟเวอร์อยู่แล้ว ข้ามข้อนี้ไป

### 2. ติดตั้ง agent บน PC1

โหลด agent จากหน้า MeshCentral ของกลุ่มเครื่อง แล้วติดตั้งแบบเงียบ
จาก PowerShell ที่เปิดเป็น Administrator:

```powershell
.\meshagent64-ชื่อกลุ่ม.exe -fullinstall
```

ตัวติดตั้งจะลงเป็น Windows service ให้เอง และ agent จะต่อออกไปเองภายในไม่กี่วินาที
ไม่ต้องตั้งค่า firewall ขาเข้าเลย

ตรวจว่าต่อติด:

```powershell
Get-Service -Name 'Mesh Agent*'
& 'C:\Program Files\Mesh Agent\MeshAgent.exe' -state
```

### 3. เปิด MeshCentral บนมือถือ

เปิดเบราว์เซอร์มือถือไปที่ URL ของเซิร์ฟเวอร์ ล็อกอิน
เลือกเครื่อง `DESKTOP-RGK6JKB` แล้วกด **Desktop**

ได้ทั้งดูจอ ควบคุมด้วยนิ้ว เปิด **Terminal** สั่งคำสั่ง
และโอนไฟล์ได้จากหน้าเดียวกัน

### 4. ให้ PC1 ไม่หลุดอีก

รันครั้งเดียวบน PC1 จาก PowerShell ที่เป็น Administrator:

```powershell
powershell -ExecutionPolicy Bypass -File AX_PC_CONTROL\install-pc1-keepalive.ps1
```

ตัวนี้จะสร้าง scheduled task ชื่อ `AERIS-PC1-KEEPALIVE` ที่รันด้วยบัญชี SYSTEM
คอยเช็คทุก 30 วินาที ว่าบริการสองตัวนี้ยังทำงานอยู่ไหม:

- `actions.runner.*` — ตัวรับงานจาก GitHub
- MeshCentral agent — ตัวที่ทำให้รีโมทได้

ถ้าตัวไหนหยุด มันจะ start ให้เอง เขียน heartbeat ไว้ที่
`C:\AX-Runtime\evidence\pc1-keepalive-heartbeat.json`

นี่คือสิ่งที่กันปัญหาเดิม: เมื่อวันที่ 19 ต.ค. runner หยุด แล้วต้องมีคนไปกดที่เครื่อง
หลังติดตั้งแล้ว เรื่องแบบนั้นจะหายไป

## ลำดับการกู้เมื่อ PC1 หาย

ไล่ตามนี้ทีละข้อ:

1. **งานค้างคิว แต่ MeshCentral ยังเห็นเครื่อง** — runner ตาย
   กด Start ที่ `services.msc` หรือรอ keepalive 30 วินาที
2. **MeshCentral ไม่เห็นเครื่อง แต่เน็ตยังมี** — agent ตาย
   กด Start บริการ `Mesh Agent` หรือรอ keepalive
3. **ไม่เห็นทั้งคู่** — เครื่องปิด หลุดเน็ต หรือเน็ตบ้านล่ม
   อันนี้รีโมทไม่ได้จริง ๆ ต้องมีคนไปที่เครื่อง

## ขอบเขตความปลอดภัย

- เอกสารและสคริปต์ในโฟลเดอร์นี้ไม่เก็บรหัสผ่าน login key หรือ certificate
  ค่า `AKATH_MESHCTRL_KEYFILE` และ `AKATH_MESHCTRL_LOGINPASS` อยู่ใน
  environment ของเครื่องที่สั่งงานเท่านั้น
- adapter รับเฉพาะ intent ที่อยู่ใน allowlist ของ PC1 Brain
  ไม่รับคำสั่ง shell อะไรก็ได้
- MeshCentral เป็นแค่ทางขนส่ง ไม่ใช่ผู้ตัดสินใจ และไม่ใช่ผู้ยืนยันผลสำเร็จ
  หลักฐานยังต้องมาจาก PC1 เอง
