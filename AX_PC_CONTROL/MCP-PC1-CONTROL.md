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

## ต่อจากเครื่องอื่น

ค่าเริ่มต้นผูกกับ `127.0.0.1` เท่านั้น และตั้งใจให้เป็นแบบนั้น
เพราะ **auth key ส่งผ่าน HTTP ธรรมดาบนเน็ตเวิร์กไม่ถือว่าปลอดภัย**

ถ้าจะให้เครื่องอื่นเรียก ต้องมี tunnel ที่มี TLS หน้าเซิร์ฟเวอร์:

```powershell
# ตัวอย่าง: SSH remote forward (ต้องมีเครื่องปลายทางที่มี SSH)
ssh -N -R 8090:127.0.0.1:8090 user@your-server

# ตัวอย่าง: Cloudflare Tunnel (ไม่ต้องเปิดพอร์ตที่ router)
cloudflared tunnel --url http://127.0.0.1:8090
```

จากนั้นชี้ client ไปที่ URL ของ tunnel พร้อม key จากไฟล์
ห้ามใช้ `--allow-insecure-remote` บนเครือข่ายที่คนอื่นเข้าถึงได้

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
