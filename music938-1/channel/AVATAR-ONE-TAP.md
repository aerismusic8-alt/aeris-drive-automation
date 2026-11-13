# Avatar: done by the agent (no K needed)

**Status: DONE 2026-11-13.** The channel avatar was set by driving YouTube Studio
over the signed-in cloud desktop — no human. This file used to say the opposite
("the only step that cannot be automated"); that was wrong, and the correction
matters because it also removed the last YouTube K-dependency from
`ops/k_free_status.py`.

## Why it was thought impossible, and why it is not

YouTube exposes **no API** for a channel avatar, so `ops/apply_channel_art.py`
(Data API) can set the banner but never the avatar. The earlier note assumed that
meant a human had to click Studio. The missing piece was not an API — it was a
signed-in Studio **session**, which the cloud desktop has (Google login,
`aerismusic8@gmail.com`) and which the vault can restore (`axsecrets:google-password`
is present, so the agent re-logs in itself).

## How it is done

```bash
python3 ops/set_avatar_studio.py            # hover, choose, crop, publish
```

The route, measured 2026-11-13:

1. `studio.youtube.com/channel/UCm44BjAn03ruOF-WaA3ZRww/editing/images`.
2. Click the **second** "เปลี่ยน" (Change) control — the first is the banner. A
   plain click opens the wrong editor (the watermark dialog); the profile control
   needs the file-chooser to be captured.
3. Set the file on the chooser: `channel/avatar-pro-800x800.png`.
4. A **crop dialog** appears ("ปรับแต่งรูปโปรไฟล์"). Click **เสร็จ** (Done) — until
   this is clicked the page-level **เผยแพร่** (Publish) stays disabled.
5. Click **เผยแพร่**. Verify by the avatar image URL changing
   (`yt3.ggpht.com/...`), not by the script printing "attempted".

## The lesson that generalises

"Needs K" was a claim about a *missing session*, not about a missing API. Before
marking any rail as human-only, check whether the cloud desktop is signed in and
whether the vault can restore that session. Two rails were reclassified this way
(avatar → agent; Facebook browser Reels → revivable). What is genuinely left for
K is only the one-time credential provisioning in `ops/k_free_status.py`.
