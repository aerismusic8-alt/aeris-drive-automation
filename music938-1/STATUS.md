# music938-1 — สถานะงาน (2026-11-02)

## 1. ช่อง YouTube — ตัวเลขจริง (Data API, ch3 = AERIS Music)
| เมตริก | ค่า |
| --- | --- |
| ผู้ติดตาม | 5 |
| ยอดดูรวม | 2,182 |
| วิดีโอ | 24 |
| เป้าหมาย monetize | 1,000 sub + 4,000 ชม. |

Shorts คือเครื่องยนต์เดียวที่ได้ผล (149–232 วิว/คลิป), long-form แทบไม่ถูกดัน
(0–18 วิว, ยกเว้น compilation 56 นาที = 213 วิว).

## 2. แบรนด์ (อัพเดทเป็นระดับครีเอเตอร์มืออาชีพ 2026-11-02)
ทิศทาง "Calm Minimalist Sanctuary" (จาก Gemini design pass): พื้น twilight-indigo,
เส้นคลื่นเสียงที่วาดเป็นตัว A, สีเน้น coral #FF6B6B.

สร้างด้วย `scripts/brand_pro.py`:
- `channel/avatar-pro-800x800.png` — มาร์กคลื่นเสียง+ตัว A อ่านได้ที่ 88px
- `channel/banner-pro-2560x1440.png` — ทุกตัวอักษรอยู่ในแถบปลอดภัย 1546x423 (ยืนยัน)
- `channel/cover-pro-1640x624.png` — สำหรับ Facebook Page

สี: `#1E1B2E` ink · `#95A5A6` silver · `#DFE6E9` fog · `#FF6B6B` coral

## 3. สถานะแต่ละ surface (ยืนยันสด)
| Surface | สถานะ | หมายเหตุ |
| --- | --- | --- |
| YouTube แบนเนอร์ | ✅ อัพเดทแล้ว (API) | banner-pro ขึ้นจริง |
| YouTube คำอธิบายช่อง | ✅ อัพเดทแล้ว (API) | viewer-focused + ลิงก์ 4 surface |
| YouTube avatar | ✅ อัพเดทแล้ว (desktop) | K ล็อกอิน 2026-11-02; ยืนยันสี live ตรงกับ asset (50,35,58 ≈ 49,36,58) |
| Facebook Page avatar+cover+bio | ✅ อัพเดทแล้ว (desktop) | ใช้ avatar-pro + cover-pro + bio ใหม่ |
| Facebook Page username | ✅ มีอยู่แล้ว `@aerismusicth` | URL ยาว resolve ไม่ได้ (เพจใหม่) — ใช้ id ไปก่อน |
| TikTok avatar+bio | ✅ อัพเดทแล้ว (desktop) | K ล็อกอิน 2026-11-02; bio ยืนยันจาก POST /api/update/profile/ (signature ใหม่) |

### TikTok — บทเรียนที่ต้องจำ
- ปุ่ม Save ของ TikTok ไม่ตอบสนองต่อ `element.click()` (JS) — ต้องใช้ **mouse press จริง**
  (`page.mouse.move/down/up` ที่พิกัดปุ่ม)
- ช่อง bio เป็น React-controlled: native-setter + dispatchEvent ไม่บันทึก (ค่าเดิมถูกส่ง)
  ต้อง **พิมพ์ด้วยคีย์จริง** (`locator.type`) แล้วยืนยันด้วย `input_value()`
- ต้องเซ็ต **bio ก่อน avatar**: อัพโหลดรูปจะแทนที่ dialog ด้วยหน้าครอป ทำให้ช่อง bio หาย
- test id ของ TikTok เป็น `data-e2e` ไม่ใช่ `data-testid` → `get_by_test_id()` ไม่ match
  ใช้ `[data-e2e="edit-profile-entrance"]`
- หน้าโปรไฟล์สาธารณะมี CDN cache — ค่า bio ที่เพิ่งเซฟอาจโชว์ค่าเก่าชั่วครู่
  ยืนยันที่ response ของ `POST /api/update/profile/` แทน (ฟิลด์ `user.signature`)
- ทั้งหมดอยู่ใน `scripts/profile_setup.py` แล้ว (`_tiktok_set_bio`, `_real_click_text`,
  `_open_tiktok_edit`)

## 4. Rails อัตโนมัติ
- **AX Music Daily Release** (cron 07:05 UTC): ล้มทุกครั้งเพราะ
  `Timed out: Sandbox not available` (platform provisioning) — ไม่ใช่ bug ในโค้ด.
  รันมือบน pod ได้ปกติ (`daily_release.py`) แต่ติด YouTube quota วันละ 6 uploads.
- **AX Rail Watchdog** (ทุกชั่วโมง): ส่วนใหญ่ SKIPPED, ไม่มี failure.
- **Crosspost**: TikTok 39/39 ✅ · Facebook Page 5/39 (เหลือ 34, cap 4/วัน).

## 5. ค้าง — ต้อง K
1. **ล็อกอิน desktop ครั้งเดียว** (Google + TikTok) ที่
   `https://work-1-<work-host>/vnc.html?autoconnect=1&resize=scale`
   → แล้ว AR อัพเดท avatar YouTube + TikTok ให้เอง
2. ยืนยันว่าต้องการกรอก **ที่อยู่/เบอร์/อีเมลจริง** ลงเพจหรือไม่ (สำหรับเช็คลิสต์ FB)
   — ยังไม่กรอกเพื่อเลี่ยงการใส่ข้อมูลเท็จ (เสี่ยงโดนระงับ)
