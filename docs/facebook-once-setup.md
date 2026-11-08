# ตั้งค่า Facebook ครั้งเดียว (ให้ AI โพสต์เองตลอดไป)

เป้าหมาย: ให้ AI โพสต์ Reel ลงเพจ **AERIS Music** ได้เอง **โดยไม่ต้องล็อกอินซ้ำอีก**
วิธีเดียวที่ทำได้จริง = **System User token ที่ตั้ง "ไม่หมดอายุ"**
(ที่ปรึกษา 4 เจ้ายืนยันตรงกัน — ทางอื่นหมดอายุใน 60 วัน)

## ทำไมต้องมี 2 ด่าน

ตอนนี้บัญชี K **ยังไม่มี** Meta Business Portfolio และ **ยังไม่เป็น** Facebook Developer
สองอย่างนี้เป็นเงื่อนไขบังคับก่อนสร้าง System User token:

| ด่าน | ต้องมี | ใครทำ |
| --- | --- | --- |
| 1 | Meta for Developers account (ยืนยันเบอร์โทร OTP) | K เท่านั้น |
| 2 | Meta Business Portfolio + เพิ่มเพจ AERIS Music | AI ช่วยกดได้ (หลัง K ยืนยันเบอร์) |
| 3 | System User → Generate Token → ตั้ง Never | AI ช่วยกดได้ |
| 4 | วาง token ลง secret `FB_PAGE_TOKEN` | อัตโนมัติ (ปุ่ม "ดึง token ให้เลย") |

## ขั้นตอน (จากมือถือ)

เปิด: `https://work-2-<work-host>/` (หน้าปุ่มของเรา)

1. กดปุ่ม **Facebook** → เข้า noVNC → กด **ดำเนินการต่อ** ในหน้า developer
2. **Verify account**: เลือกประเทศ **ไทย (+66)** → ใส่ **เบอร์มือถือของ K** → กด **ส่ง SMS**
   → รับรหัส → กรอก (รหัส OTP เห็นได้แค่ K)
3. **Contact info / About you**: กรอกให้ครบ → เสร็จสิ้นการลงทะเบียน developer
4. กลับหน้า business.facebook.com → กด **สร้างแฟ้มผลงานธุรกิจ** (Create Business Portfolio)
   → ตั้งชื่อ เช่น `AERIS Music` → เพิ่มเพจ **AERIS Music** เข้าไป
   (AI กดส่วนนี้ให้ได้ — บอกได้เลย)
5. Business Settings → **ผู้ใช้ระบบ (System Users)** → **เพิ่ม** ชื่อ `ax-poster` role Admin
   → **เพิ่มสินทรัพย์** → เพจ AERIS Music → จัดการทั้งหมด
6. ที่ผู้ใช้ระบบ → **สร้างโทเค็น (Generate Token)** → เลือกแอป → ติ๊กสิทธิ์
   `pages_manage_posts`, `pages_read_engagement`, `pages_show_list`
   → **ตั้ง Expiry = ไม่มีวันหมดอายุ (Never)** → สร้าง
7. กลับหน้า phone_login → กดปุ่มเขียว **"ดึง token ให้เลย"**
   → ระบบดึง token จากหน้าจอ, ตรวจกับเพจจริง, แล้วตั้ง secret ให้เอง → เสร็จ ✅

## หลังเสร็จ

- Facebook โพสต์ผ่าน Graph API เอง ไม่มีเบราว์เซอร์ ไม่มี K อีก
- คิว Reels ที่ค้างจะไหลออกในรอบถัดไป (workflow `ax-music-crosspost.yml`)

## ข้อจำกัดตรงไปตรงมา

- Token "ไม่หมดอายุ" = ไม่มีกำหนดหมดอายุ **ตามปฏิทิน** แต่ Meta **revoke ได้** ถ้า:
  ลบ Business Portfolio / ย้ายเพจออกจากพอร์ตโฟลิโอ / ลบ System User / เปลี่ยนรหัสผ่าน
  — นั่นคือเหตุการณ์ที่ต้องแตะ K ใหม่ **ไม่ใช่การหมดอายุตามรอบ**
- ถ้า K ยังไม่ทำ 2 ด่านนี้: Facebook จะ **park เงียบ ๆ** (ไม่โพสต์ แต่ไม่เรียก K ซ้ำ
  ไม่แจ้งเตือน ไม่นับเป็น error) — ส่วน YouTube/TikTok ทำงานต่อได้ตามปกติ
