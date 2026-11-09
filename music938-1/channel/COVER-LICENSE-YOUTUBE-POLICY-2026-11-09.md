# Cover เพลง / ลิขสิทธิ์ / ยูปจ่ายไหม — สรุปจากนโยบายยูปเอง
(AR, 2026-11-09 · แหล่งอ้างอิงคือหน้า support.google.com ของ YouTube เอง)

## คำถาม K: "ถ้าทำ cover แล้วตรวจลิขสิทธิ์ชัด ผ่านเกณฑ์ไหม ยูปจ่ายเงินไหม"

### 1) ยูปจ่ายค่า cover — แต่ต้องมี 2 เงื่อนไขครบ
หน้า "Monetizing eligible cover videos" (answer/3301938) เขียนตรง ๆ ว่า:

> "Creators participating in the YPP can share revenue from eligible cover song
> videos on YouTube, **once music publisher owners claim those videos**. You'll
> be paid revenue for these videos on a **pro rata basis**."

แปล:
- เราต้องเข้า YPP ได้ก่อน (1,000 subs + 4,000 ชม. หรือ 1,000 subs + 10 ล้านวิว Shorts)
- แล้ว **เจ้าของลิขสิทธิ์ (publisher) ต้องเป็นคน claim คลิปเราผ่าน Content ID**
  และเปิด "Sharing ad earnings" ให้
- ถ้าเข้าเงื่อนไข เราจะได้เงิน **แบบเฉลี่ยตามส่วน (pro rata)** ไม่ใช่ได้ทั้งหมด
- **ถ้ามีใบอนุญาต (licence) แต่ publisher ไม่ claim → ไม่มีช่องทางแชร์รายได้เลย**
  (หน้าเดียวกัน: ต้องเห็นไอคอน "Sharing ad earnings" บนคลิป)

### 2) ถ้าโดน claim จะเกิดอะไร
หน้า "Learn about copyright claims" (answer/6013276):
- คลิป **ยาวเกิน 3 นาที**: ถ้า claim แบบ "monetize" → ยังดูได้ แต่ **คน claim เก็บเงิน**
- คลิป **1–3 นาที**: ถ้ามี claim → **ถูกบล็อกทั้งคลิป** (ดูไม่ได้)
- claim ไม่เท่ากับ strike (ไม่โดนใบเหลือง) แต่รายได้หาย / คลิปหาย

### 3) เกณฑ์ YPP และการขึ้นเพดาน 2027-02-01
- ตอนนี้: 1,000 subs + 4,000 ชม.สาธารณะ ใน 12 เดือน **หรือ** 1,000 subs + 10 ล้านวิว Shorts ใน 90 วัน
- **1 ก.พ. 2027 ขึ้นเป็น: 8,000 ชม. หรือ 20 ล้านวิว Shorts**
- แชร์รายได้ Shorts ต้องมี **≥10 ล้านวิว Shorts ที่ผ่านเกณฑ์ ใน 90 วัน**
- เนื้อหา "ทำซ้ำ/ผลิตเป็นจำนวนมาก" (inauthentic content, เดิมชื่อ repetitious) = **ไม่มีสิทธิ์ monetize**

### 4) ที่ปรึกษา (2/2: duck + pollinations) ตอบตรงกัน
- duck: *"A licence makes the upload legally safer; it doesn't guarantee YouTube ad
  revenue… As a revenue plan for a tiny channel, covers are a poor bet."*
- pollinations: *"A properly licensed cover can give a fire-starter boost, but it
  is a mixed-bag… For a truly safe strategy, focus on your own originals first."*

## สรุปคำตอบให้ K
1. **cover ผ่านเกณฑ์ได้ไหม** → ผ่าน **แต่ไม่ใช่เพราะเรามีใบอนุญาต** ต้องรอ publisher
   claim ผ่าน Content ID และเปิด sharing — เราได้แค่ส่วนแบ่ง (pro rata)
2. **ยูปจ่ายไหม** → จ่าย **เฉพาะเมื่อ publisher claim + เปิด sharing** เท่านั้น
   ถ้าไม่มี claim = ไม่มีรายได้จากคลิปนั้น
3. **ควรทำไหม** → **ไม่ควร** เอามาเป็นแกนรายได้ เพราะความเสี่ยงคลิปโดนบล็อก
   (คลิปสั้น 1–3 นาทีโดนบล็อกทันที), เกณฑ์ขึ้น 2027 และกฎ inauthentic content
4. **ทางที่ปลอดภัยกว่า** → ทำเพลงใหม่ของเราเอง ตั้งชื่อตามเจตนาค้นหา + ทำอัลบั้มยาว
   (ตรงกับเลเวอร์ที่ทำไปแล้วใน commit d52b26cf)

## ถ้า K ยังอยากทำ cover — ต้องมีครบ
- ใบอนุญาต **mechanical + sync** (จาก Thai rights org / broker)
- เลือกเพลงที่ไม่ hit จัด (โดน claim น้อย) และใส่ twist ให้ต่าง
- จำนวนน้อย + สลับกับเพลงเอง (กัน inauthentic flag)
- และยังต้องเข้า YPP ก่อนอยู่ดี
