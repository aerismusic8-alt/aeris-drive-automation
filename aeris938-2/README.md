# aeris938-2 — ปั้น 4 ช่องทาง (AERIS Music growth project)

โปรเจคนี้ตั้งขึ้นตามคำสั่ง K (2026-11-02):

> "งาน ar เยอะไปไหม มาปรับใหม่ดีกว่านะ ทำแค่นี้พอ
> 1. ปั้นช่อง FB
> 2. ปั้นช่อง TK
> 3. ปั้นช่อง YT ช่อง @Aerismusicth ปั้นช่องเดียวเท่านั้น
> 4. ปั้นรายได้จาก Shopee Affiliate
> งานนี้สร้างเป็นโปรเจคใหม่ชื่อ aeris938-2 ทำแค่นี้พอนะ งานนอกเหนือจากนี้ตัดทิ้ง"

## ขอบเขต (มีแค่ 4 อย่าง)

| # | เป้าหมาย | ผิว | ตัวขับ |
| --- | --- | --- | --- |
| 1 | ปั้นช่อง **Facebook** | Page `61595890900382` | `grow.py facebook` |
| 2 | ปั้นช่อง **TikTok** | `@aeris.music4` | `grow.py tiktok` |
| 3 | ปั้นช่อง **YouTube** | `@aerismusicth` **ช่องเดียว** | `grow.py youtube` |
| 4 | ปั้นรายได้ **Shopee Affiliate** | `th.shp.ee/6hv2uk89` | `grow.py shopee` |

**ทุกอย่างนอกเหนือจาก 4 ข้อนี้ ตัดออก** — ไม่สร้าง ไม่รายงาน ไม่แตะ
(Roblox, ช่อง YouTube อื่น ๆ, 4Ch Farmer, story pipeline — คนละงาน)

## หลักการ

- **ฟรีเท่านั้น (Rule #1)** — ไม่มี API ที่ต้องจ่าย ไม่มี subscription
- **AR ตัดสินใจเอง** — ทุกอย่างในโปรเจคนี้ทำได้โดยไม่รอ K
- **ต้อง K เท่านั้น** — ล็อกอินด้วยรหัสผ่าน (Google / FB / TikTok / Shopee QR)
  และเรื่องเงิน (ห้ามเด็ดขาด)
- **ห้ามเดา** — ตัวเลขที่อ่านไม่ได้เขียน `UNKNOWN` ไม่ประมาณเอา

## โครงสร้าง

```
aeris938-2/
  channel.json          # 4 ผิว + ลิงก์ (แหล่งความจริงเดียว)
  GOAL.md               # เป้าหมาย + เกณฑ์สำเร็จ
  scripts/
    surfaces.py         # โหลด channel.json + path ของเครื่องมือที่ใช้ร่วม
    grow.py             # ตัวขับเดียว: facebook | tiktok | youtube | shopee | status
    report.py           # อ่านตัวเลขสด -> work/growth-report.md
  work/
    growth-report.md    # รายงานล่าสุด (สร้างโดย report.py)
  tests/
    test_surfaces.py
```

## วิธีใช้

```bash
# ดูสถานะทุกผิว + งานค้าง
python3 aeris938-2/scripts/grow.py status

# ปั้น Facebook: เติมโปรไฟล์ แล้วโพสต์ Shorts ที่ยังไม่โพสต์
python3 aeris938-2/scripts/grow.py facebook --profile
python3 aeris938-2/scripts/grow.py facebook --post --limit 3

# ปั้น TikTok
python3 aeris938-2/scripts/grow.py tiktok --profile
python3 aeris938-2/scripts/grow.py tiktok --post --limit 3

# ปั้น YouTube (ช่องเดียว): แบรนด์ + Shorts + คอมมูนิตี้
python3 aeris938-2/scripts/grow.py youtube --brand
python3 aeris938-2/scripts/grow.py youtube --community --limit 2

# ปั้น Shopee: ตรวจลิงก์ + ตัวเลขค่าคอม
python3 aeris938-2/scripts/grow.py shopee --check

# รายงานรวม 4 ผิว
python3 aeris938-2/scripts/report.py
```

## ทำไมเป็นโปรเจคใหม่ ไม่ใช่สคริปต์เพิ่มใน music938-1

K สั่งให้เป็นโปรเจคใหม่ เพราะ music938-1 โตเกินขอบเขต (มี Roblox, story,
4Ch, release rail เต็มรูปแบบ). โปรเจคนี้ **ใช้เครื่องมือที่พิสูจน์แล้ว** จาก
`music938-1/scripts/` (browser, crosspost, profile_setup, social_stats) ผ่าน
ตัวขับบาง ๆ — ไม่ fork โค้ด แต่มี identity, config, ทางเข้า และเอกสารของตัวเอง.
