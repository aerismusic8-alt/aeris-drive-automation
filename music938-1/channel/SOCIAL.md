# ปั้นช่อง FB / TikTok / Shopee — บันทึกของ AERIS Music

> `channel/GROWTH.md` คือแผนปั้น **YouTube** เอกสารนี้คือคู่ของมัน สำหรับ
> **Facebook / TikTok / Shopee** — สามผิวที่เหลือของแบรนด์เดียวกัน
> วัดสดเมื่อ **2026-11-01** ด้วยการขับเบราว์เซอร์บน cloud desktop (CDP)
> กติกาเดิม: **ห้ามเดา** ข้อไหนพิสูจน์จากข้างนอกไม่ได้ เขียน **UNKNOWN**

---

## 1. ทำไมต้องมีเอกสารนี้

งาน FB/TikTok/Shopee **มีโค้ดและ state อยู่ในโปรเจคแล้ว** (`scripts/crosspost.py`,
`work/crosspost-queue.json`, `work/crosspost-state.json`) และมี `SHOPEE.md`
แต่ **ไม่มีการบันทึกว่า "ได้ผลแค่ไหน"** — เหมือน GROWTH.md ที่ทำไว้ให้ YouTube

`scripts/market.py` วัด **YouTube เท่านั้น** → marketing loop ตัดสินใจโดย
**มองไม่เห็น** FB/TikTok/Shopee เลย นี่คือช่องว่างที่เอกสารนี้ปิด

---

## 2. สถานะจริง 3 ผิว (วัดสด 2026-11-01)

### 2.1 Facebook Page — `AERIS Music` (id 61595890900382)

| ตัวชี้วัด | ค่า |
| --- | ---: |
| ผู้ติดตาม | **0** |
| วิวรวม (28 วัน) | **11** |
| รับชมนาน 3 วินาที | 1 |
| รับชมนาน 1 นาที | 0 |
| เวลาในการรับชมรวม | **6 วินาที** |
| การมีส่วนร่วม (ถูกใจ+คอมเมนต์+แชร์) | **0** |

- Reels ที่ **ส่งไป** ตาม state: **60** (+2 ผ่านเพจ)
- หน้าเพจยังขึ้น *"ตั้งค่าเพจของคุณให้เสร็จสิ้น … ยังไม่เริ่ม"* — **โปรไฟล์ยังไม่ครบ**

### 2.2 TikTok — `@aeris.music4`

| ตัวชี้วัด | ค่า |
| --- | ---: |
| ผู้ติดตาม | **1** |
| วิว (7 วัน) | **0** |
| ถูกใจ / คอมเมนต์ | 0 / 0 |
| Est. rewards | $0.00 |
| **โพสต์ที่สร้าง (TikTok Studio)** | **63** |
| **คลิปที่เห็นบนโปรไฟล์สาธารณะ** | **16** |

**สิ่งที่พบเพิ่มและสำคัญ:** TikTok Studio แสดง 63 โพสต์ แต่โปรไฟล์สาธารณะ
แสดงแค่ 16 → **~47 โพสต์ไม่ปรากฏต่อสาธารณะ**

### 2.3 Shopee Affiliate — **UNKNOWN**

ยังไม่ onboard (ต้อง QR login จากมือถือ K) → คำสั่งซื้อ/ค่าคอมมิชชั่น **UNKNOWN**
อัตรา 2.00% / 0.60% (cap 225 บาท) คือ **นโยบาย ไม่ใช่ผลลัพธ์** ดู `SHOPEE.md`

---

## 3. ปัญหาที่พบ (พิสูจน์ได้ / พิสูจน์ไม่ได้)

### 3.1 พิสูจน์ได้: มีโพสต์ซ้ำบน TikTok

TikTok Studio แสดงสองแถวที่ **แคปชันเดียวกัน เวลาเดียวกัน ความยาวเดียวกัน**:

```
00:49 | ขอบคุณที่ยังหายใจ … | Nov 1, 4:47 AM | 0 | 0 | 0
00:49 | ขอบคุณที่ยังหายใจ … | Nov 1, 4:47 AM | 1 | 0 | 0
```

**และ TikTok เองมีนโยบาย Originality Policy** ที่ระบุว่าเนื้อหาที่คัดลอกมา
ทั้งหมดหรือดัดแปลงเพียงเล็กน้อย = *unoriginal* ซึ่งมีผลต่อการกระจาย
([tiktok.com/creator-academy/article/Originality-Policy](https://www.tiktok.com/creator-academy/article/Originality-Policy))

→ **การโพสต์คลิปเดียวกันซ้ำ ๆ บนบัญชีเดียว เสี่ยงตรงกับนโยบายนี้**

### 3.2 พิสูจน์ไม่ได้: สาเหตุที่วิวเป็น 0

TikTok **ไม่เปิดเผยกลไกอัลกอริทึม** คำอธิบายที่ TikTok เปิดเองมี 4 อย่าง
([why-is-my-tiktok-stuck-at-0-views](https://www.tiktok.com/discover/why-is-my-tiktok-stuck-at-0-views?lang=en)):

1. คลิปยังประมวลผลอยู่
2. คลิปถูกตรวจ/ติดธง/ถูกจำกัด
3. การตั้งค่าความเป็นส่วนตัว
4. ความล่าช้าชั่วคราวของระบบ

→ **สาเหตุจริงของเราคืออะไร: UNKNOWN** (ตรวจไม่พบคำเตือน/การละเมิดใน Studio)
→ แต่ **โพสต์ซ้ำคือความเสี่ยงที่เราควบคุมได้เอง** จึงควรแก้ก่อน

### 3.3 พิสูจน์ได้: URL ที่บันทึกไว้ใช้ตรวจสอบไม่ได้

`work/crosspost-state.json` มี 122 รายการ แต่ URL ที่เก็บมา **ไม่ใช่ URL ของโพสต์**:

| URL ที่บันทึก | จำนวน |
| --- | ---: |
| `tiktok.com/tiktokstudio/content` (หน้าเพจ ไม่ใช่โพสต์) | 59 |
| `facebook.com/reel/` (ไม่มี id) | 55 |
| มี reel id จริง | **6** |

→ **เราตรวจสอบย้อนหลังไม่ได้ว่าอะไรขึ้นจริง** นี่คือเหตุผลที่ตัวเลข FB/TikTok
ไม่เคยถูกบันทึกในโปรเจค

### 3.4 พิสูจน์ได้: ความเสี่ยงเนื้อหาซ้ำ (cross-post)

Meta แนะนำชัดเจนให้ **หลีกเลี่ยงเนื้อหาที่รีไซเคิลจากแอปอื่นและมีลายน้ำ**
([facebook.com/business/help/1708053352711643](https://www.facebook.com/business/help/1708053352711643))

→ เราส่งไฟล์แนวตั้ง **ไฟล์เดียวกันเป๊ะ** ไป YouTube Shorts + FB Reels + TikTok
→ ถ้ามีลายน้ำแพลตฟอร์มติดมา = เสี่ยงทั้ง Meta และ TikTok

---

## 4. วิจัย: แต่ละผิวให้อะไร (และอะไรยังไม่รู้)

### Facebook Reels
- Meta **ไม่เปิดเผย** ว่ามี cold-start feed แบบ Shorts ไหม → **UNKNOWN**
- วิธีที่ Meta เปิดเองว่าได้ผล: **crossposting**, **โพสต์เข้า Groups**,
  ใช้แฮชแท็ก 1–2 อัน (**Meta ระบุว่า #Explorepage / #Reels ไม่ช่วย**)
- **"invite friends" ได้ผลแค่ไหน: UNKNOWN** (ไม่มีเอกสารทางการ)

### TikTok
- **ไม่มีเอกสารทางการ** อธิบายกลไก "ทดลองกับคนกลุ่มเล็กแล้วขยาย" → **UNKNOWN**
- Analytics ละเอียด **ปลดล็อกที่ 100 ผู้ติดตาม** → เป้าแรกที่วัดได้
- **ห้ามใส่ลายน้ำ/โลโก้ผ่าน API** และการทำเช่นนั้นเสี่ยงถูกลบ/ระงับบัญชี
  ([developers.tiktok.com/doc/content-sharing-guidelines](https://developers.tiktok.com/doc/content-sharing-guidelines))

### Shopee Affiliate
- Shopee เปิดโปรแกรมจริง แต่ **ไม่เปิดเผยอัตรามาตรฐาน/benchmark conversion**
  → ยืนยันอัตรา 2.00%/0.60% จากเอกสารทางการ: **UNKNOWN**
- **ไม่มี case study ทางการ** ว่าช่องเพลง/บันเทิงสร้างรายได้จาก affiliate
  → **UNKNOWN** (นี่คือความเสี่ยงที่ต้องพูดตรง ๆ: เพลงไม่ใช่สินค้า)

---

## 5. สิ่งที่ควรทำ (เรียงตามความสำคัญ)

### 1) หยุดโพสต์ซ้ำ — สำคัญที่สุด
โพสต์ซ้ำตรงกับ Originality Policy ของ TikTok และทำให้ตัวเลขสกปรก
→ ตรวจก่อนโพสต์ว่าคลิปนั้นขึ้นไปแล้วหรือยัง (ดู §6 งานที่ต้องแก้โค้ด)

### 2) ลบลายน้ำก่อนส่งข้ามแพลตฟอร์ม
Meta แนะนำชัด → เรนเดอร์เวอร์ชันไม่มีลายน้ำสำหรับ FB/TikTok

### 3) บันทึก URL จริงของทุกโพสต์
ตอนนี้ตรวจสอบย้อนหลังไม่ได้ → แก้ `crosspost.py` ให้เก็บ URL ของโพสต์จริง
(§6) แล้ว `market.py` จึงจะวัด FB/TikTok ได้ในอนาคต

### 4) ตั้งเป้า 100 ผู้ติดตาม TikTok
เป็น milestone เดียวที่แพลตฟอร์มให้รางวัลเป็นข้อมูล (ปลดล็อก analytics)

### 5) ทำโปรไฟล์ FB Page ให้ครบ
หน้าเพจยังบอก "ยังไม่เริ่ม" — รูปโปรไฟล์/ข้อมูลยังไม่ครบ ซึ่งมีผลกับความน่าเชื่อถือ

### 6) Shopee — รอ K onboard ก่อน แล้ววัดจริง
อย่าเพิ่งทุ่มกับ affiliate จนกว่าจะเห็นยอดคลิก/ออเดอร์จริง
(ช่องเพลงกับการขายสินค้าเป็นคนละเจตนา — ต้องพิสูจน์ ไม่ใช่สันนิษฐาน)

---

## 6. งานที่ต้องแก้โค้ด (บันทึกไว้ ยังไม่แก้)

| ไฟล์ | ปัญหา | ผล |
| --- | --- | --- |
| `scripts/crosspost.py` | `post_tiktok`/`post_facebook` คืน `page.url` ซึ่งเป็นหน้าเพจ ไม่ใช่ URL โพสต์ | ตรวจสอบย้อนหลังไม่ได้ (§3.3) |
| `scripts/crosspost.py` | ไม่มีการเช็คก่อนว่าโพสต์นี้ขึ้นไปแล้วหรือยัง | โพสต์ซ้ำ (§3.1) |
| `scripts/market.py` | วัด YouTube เท่านั้น | loop ตัดสินใจโดยไม่เห็น FB/TikTok/Shopee |

---

## 7. แหล่งอ้างอิง

**Meta ทางการ**
- Reels best practices: https://www.facebook.com/business/help/1708053352711643
- About Facebook Reels: https://www.facebook.com/business/help/581040529926114
- Crossposting: https://creators.facebook.com/tools/crossposting
- Reels ใน Group: https://m.facebook.com/help/630440174682282

**TikTok ทางการ**
- Originality Policy: https://www.tiktok.com/creator-academy/article/Originality-Policy
- ทำไมวิว 0: https://www.tiktok.com/discover/why-is-my-tiktok-stuck-at-0-views
- Diagnose traffic issues: https://www.tiktok.com/creator-academy/article/diagnose-traffic-issues
- Content sharing guidelines: https://developers.tiktok.com/doc/content-sharing-guidelines

**Shopee**
- Affiliate program: https://affiliate.shopee.co.th
- ค่าบริการ: https://help.shopee.co.th/10/article/177422

**ตัวเลขทั้งหมดในเอกสารนี้: วัดสด 2026-11-01 จาก cloud desktop (CDP)**
