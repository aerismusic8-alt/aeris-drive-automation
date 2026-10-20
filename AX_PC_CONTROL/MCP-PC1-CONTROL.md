# คุม PC1 ผ่าน MCP (winremote-mcp)

MCP ใช้ได้ และมี server ที่ทำงานนี้โดยตรง ชื่อ **winremote-mcp**
เอกสารนี้บอกว่ามันคืออะไร ต่างจาก MeshCentral ยังไง และเปิดใช้ยังไง

## MCP คืออะไร และใช้ได้ไหม

MCP (Model Context Protocol) เป็นมาตรฐานเปิดสำหรับให้ AI เรียกเครื่องมือภายนอก
เซสชันนี้ใช้ MCP อยู่แล้ว (Tavily ที่ใช้ค้นข้อมูล)

winremote-mcp เป็น MCP server ที่รัน **บนเครื่อง Windows ที่ต้องการคุม**
แล้วเปิดเครื่องนั้นให้ AI สั่งงานได้ 45 เครื่องมือ แบ่งเป็น:

| กลุ่ม | ตัวอย่าง |
| --- | --- |
| ดูจอ | Snapshot (แคปจอ + รายการหน้าต่าง), AnnotatedSnapshot, OCR, ScreenRecord |
| สั่งงาน | Click, Type, Scroll, Shortcut, Move |
| เชลล์ | Shell (รัน PowerShell) |
| ไฟล์ | FileRead, FileWrite, FileList, FileSearch, FileUpload, FileDownload |
| ระบบ | ServiceList, ServiceStart, TaskList, TaskCreate, ListProcesses, KillProcess |
| เน็ตเวิร์ก | Ping, PortCheck, NetConnections, EventLog |

**ความต่างจาก MeshCentral ที่สำคัญ:** winremote-mcp ให้ *AI* คุมเครื่อง
ส่วน MeshCentral ให้ *คน* คุมเครื่องผ่านเบราว์เซอร์ ทั้งคู่มีที่ใช้ต่างกัน

- K อยากกดดูจอเองจากมือถือ → **MeshCentral**
- เอเจนต์ (เช่นผม) อยากแคปจอ/รันคำสั่ง/กดปุ่มเอง → **winremote-mcp**

## สิ่งที่พิสูจน์แล้วในเซสชันนี้

ผมติดตั้งและทดสอบจริงบนเครื่องนี้ (Linux) ไม่ใช่แค่อ่านเอกสาร:

```
server: winremote-mcp 4.1.1   protocol: 2025-11-25
health:  {"status":"ok","version":"0.4.23"}
tools:   30 (tier 1+2 เปิด, tier 3 ปิดโดยค่าเริ่มต้น)
call:    GetSystemInfo -> isError=false  (ได้ข้อมูลเครื่องจริง)
```

ผลทดสอบ edge case:

| กรณี | ผล |
| --- | --- |
| เรียก tool ที่มีอยู่ | exit 0 |
| เรียก tool ที่ไม่มี | exit 1 + บอกชื่อ tool ที่มีให้ |
| ต่อเซิร์ฟเวอร์ไม่ได้ | exit 2 |

## เปิดใช้บน PC1

รันครั้งเดียวบน PC1 จาก PowerShell **as Administrator**:

```powershell
powershell -ExecutionPolicy Bypass -File AX_PC_CONTROL\install-pc1-winremote-mcp.ps1
```

สคริปต์จะทำให้ทั้งหมดนี้:

1. ติดตั้งแพ็กเกจ `winremote-mcp` ด้วย Python บนเครื่อง
2. สุ่ม auth key เก็บใน `C:\AX-Runtime\winremote\winremote-auth.key`
   ตั้งสิทธิ์ให้อ่านได้เฉพาะ SYSTEM และ **ไม่พิมพ์ค่าจริงออกจอ**
3. ลง scheduled task `AERIS-PC1-WINREMOTE-MCP` รันด้วย SYSTEM ตอนบูต
4. เช็ค `/health` จริง
5. เรียก `GetSystemInfo` จริง เพื่อพิสูจน์ว่าไม่ใช่แค่เซิร์ฟเวอร์ขึ้นแต่ใช้งานไม่ได้
6. เขียนหลักฐานที่ `C:\AX-Runtime\evidence\pc1-winremote-mcp-install.json`

## ต่อจากเครื่องอื่น — ใช้ Tailscale (แนะนำ)

ค่าเริ่มต้นผูกกับ `127.0.0.1` เท่านั้น และตั้งใจให้เป็นแบบนั้น
เพราะ **auth key ส่งผ่าน HTTP ธรรมดาบนเน็ตเวิร์กไม่ถือว่าปลอดภัย**

**Tailscale แก้ปัญหานี้ตรงจุด** เพราะมันทำ 3 อย่างพร้อมกัน:

1. **TLS ให้ฟรี** — ผ่าน `tailscale serve` ได้ใบรับรองจริง ไม่ต้องตั้งเอง
2. **ไม่ต้องเปิดพอร์ตที่ router** — เป็น outbound connection ทั้งสองฝั่ง
3. **auth ระดับเครื่อง** — เฉพาะเครื่องใน tailnet เดียวกันเท่านั้นที่เข้าได้

### ติดตั้งบน PC1

```powershell
# ติดตั้ง Tailscale (หรือโหลดจาก tailscale.com/download/windows)
winget install --id Tailscale.Tailscale -e

# ล็อกอิน (เปิดเบราว์เซอร์ให้กดยืนยันครั้งเดียว)
tailscale up

# ดู IP ของ PC1 (จะเป็น 100.x.y.z)
tailscale ip -4

# เปิด HTTPS ให้ MCP server ที่พอร์ต 8090
# คำสั่งนี้จะขอเปิด HTTPS ใน tailnet ให้เองถ้ายังไม่เปิด
tailscale serve --bg 8090

# ดู URL ที่ได้
tailscale serve status
```

จะได้ URL หน้าตาแบบนี้:
```
https://desktop-rgk6jkb.<ชื่อ-tailnet>.ts.net/
```

### เรียกจากฝั่ง client

```bash
python3 AX_PC_CONTROL/ax-winremote-mcp.py \
  --url https://desktop-rgk6jkb.<ชื่อ-tailnet>.ts.net/mcp \
  --auth-key "$WINREMOTE_AUTH_KEY" \
  --list-tools
```

ถ้าเครื่องที่รัน client อยู่ใน tailnet อยู่แล้ว **ไม่ต้องใช้ `--tailnet-proxy`**
เพราะต่อ 100.x ได้ตรง ๆ

### ถ้า client ไม่ได้อยู่ใน tailnet (เช่นกล่อง sandbox)

ใช้ `tailscaled` โหมด userspace ซึ่งไม่ต้องมี root และไม่ต้องมี `/dev/net/tun`:

```bash
tailscaled --tun=userspace-networking \
  --state=/var/lib/tailscale/tailscaled.state \
  --socks5-server=localhost:1055 \
  --outbound-http-proxy-listen=localhost:1055 &
tailscale up --auth-key=<auth-key ของ tailnet>
```

แล้วส่ง proxy ให้ client:

```bash
python3 AX_PC_CONTROL/ax-winremote-mcp.py \
  --url https://desktop-rgk6jkb.<ชื่อ-tailnet>.ts.net/mcp \
  --auth-key "$WINREMOTE_AUTH_KEY" \
  --tailnet-proxy socks5://127.0.0.1:1055 \
  --list-tools
```

**ทำไมต้องส่ง proxy ไม่ใช่ตั้ง `ALL_PROXY`:** proxy ของ Tailscale โหมด userspace
**ส่งได้เฉพาะทราฟฟิกใน tailnet** ถ้าตั้ง `ALL_PROXY` ทั้ง process
ทุกคำขออื่น (เช่นต่อ PyPI, GitHub) จะถูกส่งเข้า proxy ที่ไปไม่ถึง แล้วพังทั้งหมด

client จึงผูก proxy แบบ **เจาะจงปลายทาง** แทน:

| URL ที่เรียก | ผ่าน proxy? |
| --- | --- |
| `127.0.0.1:8090` | ไม่ผ่าน (local ยังใช้ได้เสมอ) |
| `100.101.102.103:8090` | ผ่าน (ช่วง `100.64.0.0/10`) |
| `pc1.tailnet.ts.net` | ผ่าน (ตามชื่อ origin ของ URL) |

### ถ้าไม่อยากใช้ Tailscale

```powershell
# SSH remote forward
ssh -N -R 8090:127.0.0.1:8090 user@your-server

# Cloudflare Tunnel
cloudflared tunnel --url http://127.0.0.1:8090
```

ทั้งสองแบบต้องมีเซิร์ฟเวอร์ปลายทางหรือบัญชี Cloudflare
Tailscale ตั้งง่ายกว่าเพราะไม่ต้องมีทั้งคู่

ห้ามใช้ `--allow-insecure-remote` บนเครือข่ายที่คนอื่นเข้าถึงได้
และ **ห้ามใช้ Tailscale Funnel** กับ MCP เพราะ Funnel เปิดให้ทั้งอินเทอร์เน็ตเข้าได้
`serve` เท่านั้นที่จำกัดอยู่ใน tailnet

## เรียกใช้จากฝั่ง client

สคริปต์ `AX_PC_CONTROL/ax-winremote-mcp.py` เป็น MCP client ขนาดเล็ก
ทดสอบกับเซิร์ฟเวอร์จริงแล้ว

```bash
# ดูว่ามี tool อะไรบ้าง
python3 AX_PC_CONTROL/ax-winremote-mcp.py --url http://127.0.0.1:8090/mcp --list-tools

# แคปจอ
python3 AX_PC_CONTROL/ax-winremote-mcp.py --url http://127.0.0.1:8090/mcp \
  --call Snapshot --args '{"max_width": 1280}'

# รัน PowerShell (tier 3 ต้องเปิดก่อน)
python3 AX_PC_CONTROL/ax-winremote-mcp.py --url http://127.0.0.1:8090/mcp \
  --call Shell --args '{"command": "hostname"}'
```

ตั้งค่าได้ผ่าน environment:

- `WINREMOTE_MCP_URL` — URL ของเซิร์ฟเวอร์
- `WINREMOTE_AUTH_KEY` — key (หรือใช้ `--auth-key`)
- `WINREMOTE_SAVE_IMAGES` — โฟลเดอร์สำหรับเซฟรูป (หรือใช้ `--save-images`)

## เซฟรูปได้จริง — ไม่งั้นเอเจนต์ตาบอด

เดิม client รายงานรูปเป็น "ขนาด" เท่านั้น (`base64Length`) ซึ่งดูไม่ได้
ตอนนี้เพิ่ม `--save-images DIR` แล้ว เขียน PNG ลงดิสก์และบอก path กลับมา:

```bash
python3 AX_PC_CONTROL/ax-winremote-mcp.py --url http://127.0.0.1:8090/mcp \
  --call Snapshot --args '{"max_width": 1280}' --save-images /tmp/shots
```

ได้ผลลัพธ์แบบนี้ แล้วเปิดไฟล์ดูได้เลย:

```json
{ "type": "image", "mimeType": "image/png",
  "base64Length": 100, "savedTo": "/tmp/shots/Snapshot-1.png", "savedBytes": 73 }
```

client ยังรองรับเซิร์ฟเวอร์ที่ส่งรูปมาเป็น **ข้อความ JSON** แทน `image` item
(เจอจริงตอนทดสอบ) โดยแกะ base64 ออกมาเซฟให้ด้วย ไม่งั้นรูปจะกลายเป็นข้อความเฉย ๆ

## ทางที่สั้นที่สุด: ผ่าน runner บน PC1 เอง (ไม่ต้องมี tailnet)

ถ้า runner บน PC1 กลับมาแล้ว **นี่คือทางที่ต้องใช้น้อยที่สุด** เพราะ MCP server
ผูกกับ `127.0.0.1` อยู่แล้ว และ runner ก็รันอยู่บน PC1 เดียวกัน
จึงเรียก loopback ได้ตรง ๆ ไม่ต้องมี tailnet, ไม่ต้องมี MeshCentral,
ไม่ต้อง forward port และ **ไม่ต้องส่ง credential ให้ใคร**

`.github/workflows/ax-pc1-desktop-control.yml` ทำหน้าที่นี้:

```bash
# เปิด server ถ้ายังไม่ขึ้น แล้วแคปจอ
gh workflow run ax-pc1-desktop-control.yml -f tool=Snapshot -f 'args={"max_width":1600}'
```

workflow จะ:

1. ตรวจว่าเป็น PC1 จริง (`COMPUTERNAME`)
2. ถ้า `/health` ไม่ตอบ → สตาร์ท scheduled task `AERIS-PC1-WINREMOTE-MCP`
3. เรียก tool ที่สั่ง พร้อม `--save-images` ให้เขียน PNG
4. อัปโหลด artifact ชื่อ `pc1-desktop-control` (มีทั้ง PNG และ JSON)

แล้วเอเจนต์ดึง artifact กลับมาดูได้ด้วย token ของ GitHub App

| ทาง | ต้องมีอะไร | เอเจนต์ดูจอได้ | เหมาะกับ |
| --- | --- | --- | --- |
| runner bridge (workflow นี้) | runner บน PC1 ทำงาน | ได้ (ผ่าน artifact) | เอเจนต์สั่งงาน |
| Tailscale + MCP | tailnet + serve | ได้ | เอเจนต์/คน นอกบ้าน |
| MeshCentral | MeshCentral server | ได้ | คนดูจากมือถือ |
| RDP | public IP/VPN | ได้ | คนนั่งดูเต็มจอ |

## Tier และความปลอดภัย

| Tier | ความเสี่ยง | ค่าเริ่มต้น | ตัวอย่าง |
| --- | --- | --- | --- |
| 1 | อ่านอย่างเดียว | เปิด | Snapshot, GetSystemInfo, FileList |
| 2 | โต้ตอบ | เปิด | Click, Type, Shortcut |
| 3 | เขียน/ทำลายได้ | **ปิด** | Shell, FileWrite, App |

`Shell` อยู่ tier 3 จึงยังใช้ไม่ได้จนกว่าจะเปิดด้วย `--enable-tier3`
ถ้าจะเปิด ควรเปิดเท่าที่จำเป็นด้วย `--tools` และคิดถึงความเสี่ยงก่อน
เพราะ Shell บน PC1 คือสิทธิ์รันคำสั่งอะไรก็ได้บนเครื่องนั้น

หลักการที่เอกสารนี้ยึด:

- ค่า `AKATH_MESHCTRL_*` และ auth key **ไม่เคย** commit ลง Git
- สคริปต์รายงานแค่ว่ามี credential หรือไม่ ไม่รายงานค่า
- อย่าเปิดพอร์ตออกอินเทอร์เน็ตโดยไม่มี TLS และ key
- MeshCentral และ MCP เป็นทางขนส่ง/เครื่องมือ ไม่ใช่ผู้ตัดสินความสำเร็จ
  หลักฐานยังต้องมาจาก PC1 เอง
