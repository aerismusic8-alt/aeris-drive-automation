# งานเดียวที่รอ K: ล็อกอิน Google กลับ (2026-11-13)

AR ทำทุกอย่างที่ทำได้แล้วที่เหลือคือการล็อกอิน ซึ่งมีแต่ K ทำได้ (AR ไม่พิมพ์รหัสผ่าน)

## สถานะ

| ผิว | session | อ่านได้ไหม |
|---|---|---|
| Google / YouTube Studio (`aerismusic8`) | **ตาย** — chooser โชว์ "Signed out" | ไม่ (impressions/CTR อ่านไม่ได้) |
| Flow Music | ตาย (ไม่มี auth cookie) | ไม่ |
| Facebook Page | ล็อกอินอยู่ | ได้ |
| TikTok | ล็อกอินอยู่ | ได้ |
| Shopee | อ่านผ่าน desktop | ได้ |

หลักฐาน: `accounts.google.com/AccountChooser` แสดง "Signed out" ทั้ง `aerismusic8@gmail.com`
และ `kongkeat.p3@gmail.com`; `studio.youtube.com` เด้งไปหน้า sign-in
(vault snapshot 08:58 วันนี้ มี cookie Google แค่ 20 และไม่มี auth cookie)

## สิ่งที่ขอ (ทำครั้งเดียว ~1 นาที)

1. เปิด https://work-1-svdyfeuszgemvktg.prod-runtime.all-hands.dev/vnc.html?autoconnect=1&resize=scale
2. ล็อกอิน Google เป็น **aerismusic8@gmail.com**
3. แค่นั้น — AR จะ `python3 ops/login_vault.py save` เก็บ session ไว้เอง
   (pod ใหม่ไม่ต้องล็อกอินซ้ำ)

## ระหว่างนี้ AR ทำอะไรต่อได้ (ไม่ต้องรอ)

- อ่าน Facebook/TikTok ด้วย session ที่ยัง hidup → เติมช่องว่าง UNKNOWN ในรายงาน
- เตรียมคอนเทนต์/แผน reach ให้พร้อมปล่อยทันทีที่ HOLD ยกเลิก
- ไม่โพสต์/ไม่เรนเดอร์/ไม่อัปโหลด จนกว่า K ยกเลิก HOLD
