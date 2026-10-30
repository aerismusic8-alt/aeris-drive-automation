#!/usr/bin/env python3
"""Turn a finished episode into YouTube metadata.

Chapters are computed from the ACTUAL per-paragraph TTS durations, so the times in
the description match the audio instead of being guessed. YouTube only renders
chapters when the first is 0:00 and there are at least three, each >= 10 s apart.
"""
import glob
import json
import os

import thai_tts

# Paragraph index -> chapter heading. The script's structure, not its numbering.
CHAPTERS = [
    (0, "ใจที่เหนื่อย ไม่ได้แปลว่าอ่อนแอ"),
    (6, "วางของลงได้แล้ว"),
    (14, "เรื่องที่แก้ไม่ได้ ก็ไม่ใช่ความผิดของเรา"),
    (20, "ให้อภัยตัวเอง"),
    (28, "ความสงบอยู่ที่ลมหายใจ ไม่ต้องไปหาที่ไหน"),
    (36, "พูดว่าไม่ได้ เป็นความรับผิดชอบ"),
    (44, "ขอบคุณตัวเองที่พาเรามาถึงตรงนี้"),
    (50, "คืนนี้พอแล้ว"),
    (56, "วิธีง่าย ๆ ก่อนนอน"),
]


def chapter_marks(tts_dir, gap=0.9):
    files = sorted(glob.glob(os.path.join(tts_dir, "p*.mp3")))
    times, t = {}, 0.0
    for i, f in enumerate(files):
        times[i] = t
        t += thai_tts.audio_seconds(f) + gap
    out = []
    for idx, heading in CHAPTERS:
        if idx in times:
            s = int(times[idx])
            out.append((s, heading))
    return out, t


def hhmmss(s):
    h, rem = divmod(int(s), 3600)
    m, sec = divmod(rem, 60)
    return f"{h}:{m:02d}:{sec:02d}" if h else f"{m}:{sec:02d}"


def build(script_path, tts_dir, credits_path, out_dir, extra_note=""):
    title, paras = thai_tts.read_script(script_path)
    marks, total = chapter_marks(tts_dir)
    credits = open(credits_path, encoding="utf-8").read().strip() if os.path.exists(credits_path) else ""

    desc = []
    desc.append(f"{title}\n")
    desc.append("คลิปนี้ทำขึ้นเพื่อให้คนที่เหนื่อยมาทั้งวัน ได้มีเสียงไว้ฟังก่อนนอน "
                "ไม่ต้องตั้งใจฟังอะไรมาก แค่ปล่อยให้เสียงพาใจค่อย ๆ สงบลง "
                "ถ้าฟังแล้วหลับไปก่อนจบ ก็ถือว่าคลิปนี้ทำหน้าที่ของมันแล้ว\n")
    desc.append("สารบัญ")
    for s, h in marks:
        desc.append(f"{hhmmss(s)} {h}")
    desc.append("")
    if extra_note:
        desc.append(extra_note + "\n")
    desc.append("ฟังคลิปอื่นในช่องได้เลย และถ้าคืนไหนใจหนัก ๆ กลับมาฟังคลิปนี้ซ้ำได้เสมอ\n")
    if credits:
        desc.append(credits + "\n")
    desc.append("เสียงบรรยายสร้างด้วย edge-tts (th-TH-NiwatNeural) "
                "ดนตรีประกอบ CC0 จากคลังเพลงเสรีของช่อง "
                "ภาพประกอบจาก Wikimedia Commons ตามรายการด้านบน")

    tags = ["ธรรมะก่อนนอน", "ธรรมะ", "ฟังก่อนนอน", "ปล่อยใจ", "นอนไม่หลับ",
            "ความสงบ", "สมาธิ", "ผ่อนคลาย", "ข้อคิดชีวิต", "ให้อภัยตัวเอง",
            "เหนื่อย", "กำลังใจ", "dharma", "bedtime", "thai meditation",
            "calm", "sleep", "relax", "buddhism", "mindfulness"]

    os.makedirs(out_dir, exist_ok=True)
    p_desc = os.path.join(out_dir, "description.txt")
    open(p_desc, "w", encoding="utf-8").write("\n".join(desc))
    p_tags = os.path.join(out_dir, "tags.txt")
    open(p_tags, "w", encoding="utf-8").write(",".join(tags))
    meta = {
        "title": title,
        "seconds": round(total, 1),
        "runtime": hhmmss(total),
        "chapters": [{"t": hhmmss(s), "heading": h} for s, h in marks],
        "description_file": p_desc,
        "tags_file": p_tags,
    }
    json.dump(meta, open(os.path.join(out_dir, "meta.json"), "w", encoding="utf-8"),
              ensure_ascii=False, indent=2)
    return meta


if __name__ == "__main__":
    import sys
    m = build(sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4])
    print(json.dumps(m, ensure_ascii=False, indent=2))
