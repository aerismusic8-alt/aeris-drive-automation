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
### ต้นเหตุจริง (แก้แล้ว 2026-11-02)
`Timed out: Sandbox not available` **ไม่ใช่** platform ล่มชั่วคราว แต่คือ
**โควต้า sandbox วันละ 20 ใบเต็ม** — `status_detail.kind = daily_sandbox_limit`
ข้อความคือ "Daily sandbox limit of 20 reached". สองตัวที่รันทุกชั่วโมง
(WATCHDOG + YouTube Activity Monitor) กิน 24+24 = 48 ใบ/วัน จึงดูดโควต้าหมด
ก่อน 07:05 ที่ Daily Release จะได้รัน → FAILED ทุกวัน และ Watchdog เองก็ SKIPPED
(heal ตัวเองไม่ได้เพราะถูก skip ก่อนถึงโค้ด).

**แก้:** ลดรอบตัวมอนิเตอร์จากทุกชั่วโมง → ทุก 6 ชม.
- `AX Rail Watchdog` : `15 * * * *` → `0 */6 * * *`
- `AX YouTube Activity Monitor` : `0 * * * *` → `30 */6 * * *`

งบใหม่ ≈ 10/วัน (จาก 48) เหลือที่ให้ release + marketing. ยัง**ไม่**ยืนยันว่าโควต้า
20/วันเป็น hard limit ของแพ็กเกจหรือปรับได้ — ถ้าปรับได้ ควรขอเพิ่มที่ /settings/quota.

### สถานะแต่ละ rail
- **AX Music Daily Release** (cron 07:05 UTC): ล้มเพราะโควต้าข้างบน. ยืนยันแล้วว่า
  6 uploads ของวันนี้ (2026-11-02) ขึ้น YouTube จริง (ตั้งเวลา public ไว้ 15/19/23:06Z
  + พรุ่งนี้) — คือ rail ทำงานได้ แต่ run ถูก mark FAILED.
  รันมือบน pod ได้ปกติ (`daily_release.py`) แต่ติด YouTube quota วันละ 6 uploads.
- **AX Rail Watchdog**: ถูก throttle แล้ว (ดูข้างบน).
- **Crosspost**: TikTok 60/60 ✅ หมดคิวแล้ว · Facebook Page 6/60 (เหลือ 54, cap 4/วัน).
  คิว TikTok จะหมดเพราะทุกเพลง (20 เพลง × 3 hook) ลงครบแล้ว — **ต้องมีเพลงใหม่**
  เพื่อให้ TikTok มีของลงต่อ.
- **Shopee affiliate**: 0 ออเดอร์/0 ค่าคอม (แดชบอร์ดติด CAPTCHA "Verify to Continue"
  เมื่อ AR อ่าน — ต้องให้ K ปลดล็อกเอง).

## 5. ค้าง — ต้อง K
1. **Shopee affiliate**: แดชบอร์ดติด CAPTCHA "Verify to Continue" (ลากชิ้นส่วนปริศนา)
   — AR อ่านยอดออเดอร์/ค่าคอมไม่ได้จนกว่าจะปลดล็อก. K ปลดล็อกที่เบราว์เซอร์ desktop
   (`https://work-1-<work-host>/vnc.html?autoconnect=1&resize=scale`) แล้วแจ้ง AR.
2. **เพิ่มโควต้า sandbox ต่อวัน** (ถ้าปรับได้) ที่ /settings/quota — ตอนนี้ 20/วัน
   จำกัดจำนวน automation ที่รันได้จริง. ถ้าขอเพิ่มได้ จะคืนรอบมอนิเตอร์ให้ถี่ขึ้น.
3. **เพลงใหม่** เพื่อให้ TikTok มีของลงต่อ (คิว 20 เพลงหมดแล้ว). ถ้า K มีเพลง/เนื้อร้องใหม่
   AR render short + release ต่อได้.
4. **ล็อกอิน Google บน desktop** ถ้าจะใช้ path ที่ไม่ใช่ API (Studio UI) — ตอนนี้
   cookie ใน vault ยังไม่พอ (Studio เด้ง signin). YouTube publish ใช้ API rail ไม่ต้องพึ่ง.
5. ยืนยันว่าต้องการกรอก **ที่อยู่/เบอร์/อีเมลจริง** ลงเพจหรือไม่ (สำหรับเช็คลิสต์ FB)
   — ยังไม่กรอกเพื่อเลี่ยงการใส่ข้อมูลเท็จ (เสี่ยงโดนระงับ)
