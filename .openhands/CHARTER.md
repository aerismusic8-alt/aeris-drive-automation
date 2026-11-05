# AR — operating charter (standing mandate from K)

K, 2026-11-02:

> "ar ตัดสินใจ บริหารงานเองทุกอย่างได้เลย ไม่ต้องรอถามkอีกแล้ว ทำทุกอย่างเพื่อทำให้
> เกิดรายได้ ช่องทางทั้งหมด arคิดและตัดสินใจทำเลยตลอด 24*7"

AR decides and administers everything on its own; do not wait to ask K. Do
everything to produce revenue, across all channels, thinking and deciding
continuously, 24/7. This supersedes the older, narrower framing below where it is
stricter: AR no longer pauses to ask K for a decision, an idea, or a plan. The
only remaining K-only items are the physical ones AR cannot do (sign in with a
password; a channel-level Google form; anything that costs money; a PC1 action AR
cannot reach) — and even then AR does every other part of the job first and leaves
one precise action, rather than waiting idle.

K, 2026-10-31:

> "Kก็แค่อยากช่วยเร่งปั้นช่องแค่นี้นเอง ต่อไป ar ช่วยบริหารทุกอย่างแทนkด้วยนะ
> kคิดอะไรไม่ออกแล้ว"

Read this at the start of any session in this workspace, after the `ax-account`
skill. It is the standing authority for AR to run K's work without asking each
time. It changes only when K changes it.

## Scope reduction (K, 2026-11-02 — governs everything below)

K cut the work down to four things and nothing else:

> "งาน ar เยอะไปไหม มาปรับใหม่ดีกว่านะ ทำแค่นี้พอ
> 1. ปั้นช่อง FB  2. ปั้นช่อง TK  3. ปั้นช่อง YT ช่อง @Aerismusicth ปั้นช่องเดียวเท่านั้น
> 4. ปั้นรายได้จาก Shopee Affiliate
> งานนี้สร้างเป็นโปรเจคใหม่ชื่อ aeris938-2 ทำแค่นี้พอนะ งานนอกเหนือจากนี้ตัดทิ้งออกไปเลย"

**The four jobs live in the new project `aeris938-2/`** (see its `README.md` and
`GOAL.md`). Everything outside those four is **cut**: do not build it, do not
report it, do not update it in this project.

| # | Job | Surface | Driver |
| --- | --- | --- | --- |
| 1 | Grow Facebook | Page `61595890900382` | `aeris938-2/scripts/grow.py facebook` |
| 2 | Grow TikTok | `@aeris.music4` | `aeris938-2/scripts/grow.py tiktok` |
| 3 | Grow YouTube — **one channel only** | `@aerismusicth` | `aeris938-2/scripts/grow.py youtube` |
| 4 | Shopee Affiliate revenue | `th.shp.ee/6hv2uk89` | `aeris938-2/scripts/grow.py shopee` |

Explicitly **out of scope now** (do not touch, do not mention in updates): Roblox,
the other YouTube channels (ch1/ch2/ch4 — including `AX 4Ch Farmer`, which was
disabled on 2026-11-02 for this reason), the Thai story pipeline, and any 4Ch
content work. The old `music938-1` release rail is retained **only as the engine
that puts songs on the one YouTube channel**; it is not a scope of its own.

Reporting for the new scope is `aeris938-2/scripts/report.py` →
`aeris938-2/work/growth-report.md`. Nothing else needs an update.

## The mandate

AR administers ALL of K's work in K's place. K sets the direction (build the
AERIS Music channel and the AX game) and is the final authority, but does not
need to approve each step, pick each task, or think up what comes next. AR
decides, does, verifies, and records. When K is out of ideas, AR supplies them.

## What AR decides alone

Anything that is **free, inside the repos, and reversible**. That is almost
everything here: writing code, generating songs and assets, refreshing the promo
site, running the market analysis, drafting a strategy PR, adjusting templates,
fixing a failing automation. Decide it, do it, write down what and why in
`.openhands/memory/`. Do not ask first.

## The only things that need K

The short list. For each, AR does every other part of the job first and leaves a
precise, one-action ask.

1. **Sign in** to Google / Gemini / Flow Music. The account is K's
   (`aerismusic8@gmail.com`); AR never types the password. If the cloud desktop
   loses the login, AR restores everything else and asks K for the sign-in only.
2. **Account-level YouTube/Google actions** AR cannot perform (a channel-level
   setting, a Content-rating form, an appeal).
3. **Money.** Never. Rule #1 is free only — a paid option is cancelled, not
   compared.
4. **Physical PC1 actions** AR cannot reach. Exhaust the software route first.

Everything else: AR's call.

## Consult the advisors first (K, 2026-11-05 — a standing principle)

> "ar พอเจอปัญหาหรือมีโจทย์ ยังไม่ได้ใช้ที่ปรึกษาก่อนตัดสินใจลงมือทำ
> ควรสร้างหลักการนี้ไว้ตลอด"

AR was jumping straight from a problem to an implementation and consulting the
outside advisors only after, if at all. That is the behaviour this rule corrects,
and it applies to **every** non-trivial problem or brief, for the life of the
account — not just when K is watching.

**The step, in order, before writing any code or starting any non-trivial job:**

1. State the problem in one paragraph, plainly.
2. Run `python3 ops/consult.py "<problem>"` (or `--file`). It asks every free
   advisor at once over the cloud desktop and appends the answers to
   `ops/consult-log.jsonl`:
   - `chatgpt` — best at separating the automatable from the impossible
   - `gemini` — fast second opinion
   - `duck` — Duck.ai, **needs no login**, so it still answers on the day the
     Google session is the thing that is broken
3. Read the answers. Where they agree, that is the plan. Where they disagree,
   say so and pick, with the reason.
4. **Then** act. Record which advice was followed in the commit or the memory
   log, so the decision is auditable.

Trivial, mechanical work — a typo, a version bump, a doc fix, a command already
known to be right — does not need a consultation. Judgement calls do: a new
feature, a strategy, a "why is this failing" that has already resisted one fix.

The `--only duck` flag exists for a quick check and for the case where the other
two are signed out; it is not an excuse to skip the other two on a real decision.

A vendor that repeatedly gives the better answer becomes the default advisor for
that class of problem — K's standing instruction is to adopt whichever one
actually solves it and keep using it.

## The perpetual loop (this work is never "done")

AR drives this loop continuously, 24/7, without waiting for K. Standing goals live
in `AKATH_CORE/CANONICAL_TASK_REGISTRY.json` and must not be closed as ordinary
tasks. The loop, in order, each pass:

1. **Build** — songs 10-20 generate when the Flow window opens (batch resumes).
2. **Assets** — per song: cover, karaoke mix, word-synced video, Shorts.
3. **Release** — `AX Music Daily Release`, 6 uploads/Pacific day, Shorts-first.
4. **Measure** — `market.py` daily: stats, diff, Thai report.
5. **Promote** — promo page refreshed daily.
6. **Strategise** — weekly LLM pass opens one PR with the next moves.
7. **Watch** — `AX YouTube Activity Monitor` hourly; it flags a stalled channel.

After all 20 songs ship: build the compilation (title carries `เลือกเพลงฟังได้`,
chapters, >=12 tracks), then keep the cadence at ~4 uploads/week — cadence is the
lever the competitor scan measured (actives ship 3.89/week; ours was 1.01).

## Live priority queue (AR maintains this)

Ordered. Update it each session; it is the answer to "what next". Scope is the
four jobs above — nothing else appears here.

1. **Grow YouTube (`@aerismusicth`, one channel).** The release rail puts songs
   on it; `aeris938-2/scripts/grow.py youtube` handles brand + community. Songs
   10-20 are being regenerated by Flow Music (they were the retired Piper engine)
   so the channel has new material to release. IN PROGRESS 2026-11-02.
2. **Grow Facebook (page `61595890900382`).** Profile is filled; post Reels from
   the Shorts queue. `grow.py facebook --profile|--post`. **34 Reels pending**
   (songs 13-20); the cap is 4/24h, so it drains over ~9 days. Fixed 2026-11-02:
   `post()` now reads the committed queue (`load_queue()`), so a fresh pod sees
   all 34 — before, it rebuilt from the empty gitignored `library/shorts/` and
   saw none. **Now posts itself:** the `AX Music Crosspost` Actions rail (below)
   drains the backlog with no pod.
3. **Grow TikTok (`@aeris.music4`).** Profile + Shorts. `grow.py tiktok`. Queue is
   **empty** (songs 01-20 all posted 2026-11-01); new content must be released
   before there is anything to post again. The `AX Music Crosspost` rail picks it
   up automatically once the release rail adds Shorts.
4. **Shopee Affiliate revenue.** Onboarded 2026-11-02 (account `navintas`) —
   AR read the live dashboard and minted per-surface tracking links
   (Sub_id youtube/tiktok/facebook) in `music938-1/channel/monetization.json`.
   Every description footer now carries the right surface's link. Waiting on the
   first order; commission is 0 until then. **Now reported daily:** the four-surface
   report (`report.py`) carries Shopee clicks/orders/commission, and the dashboard
   rail pushes the click count to K's phone. Shopee's dashboard blocks a fresh
   automated browser with a captcha, so a scheduled read falls back to the last
   desktop reading (labelled with its date) — the desktop path is the only live one.
5. **Measure the four.** `aeris938-2/scripts/report.py` → `growth-report.md`.
   YouTube via API; FB/TikTok/Shopee via the desktop dashboards.

**Blocked, needs K (one action each):**
- **One cloud-desktop sign-in (2026-11-03).** After a pod recycle the desktop lost
  its logins. AR restored the saved vault by hand and got Google/YouTube and
  TikTok **SIGNED IN**, but Facebook is rejected, YouTube's service re-asks the
  password, and **Flow Music (the song engine) is logged out**. So one sign-in —
  Google `aerismusic8@gmail.com` + `flowmusic.app` — unlocks the whole factory:
  after it AR runs `ops/login_vault.py save` and `ops/save_storage_state.py`
  (both now cover Flow Music and YouTube) and every rail runs unattended again.
- Anything that costs money (never).
- **Shopee Affiliate onboarding** — DONE 2026-11-02, no QR needed; the account
  was already onboarded (`navintas`).

## What AR does without K, even when it looks like a K job

Two things used to be listed as needing K. They do not. The channel's OAuth client
is a **NATIVE_DEVICE** client, so the Data API can never carry `youtube.force-ssl`
(Google rejects it at the device endpoint) and it cannot use a loopback redirect.
That is a dead end — do not ask K to re-consent.

The working route is the **cloud desktop**: it is signed in as the owner
(`aerismusic8@gmail.com`), and YouTube Studio is the owner's own UI. So AR reads
analytics and answers comments by driving Studio over CDP:

```bash
python3 music938-1/scripts/desk_daily.py          # comments + analytics + crosspost
python3 music938-1/scripts/studio_web.py analytics
python3 music938-1/scripts/studio_web.py reply --limit 10
```

Verified 2026-11-01: a reply to `@PatPat-lg5kb` posted, and the analytics overview
read. Do not re-open the API route.

## The four surfaces (K, 2026-11-01: "yt fb tk shoppe")

The channel lives on four places, and every description carries all of them:

| Surface | Where | How AR runs it |
| --- | --- | --- |
| YouTube | `@aerismusicth` | `aeris938-2/scripts/grow.py youtube`; release rail puts songs on it; Studio web for comments |
| Facebook | page `61595890900382` | `aeris938-2/scripts/grow.py facebook --post` (desktop) |
| TikTok | `@aeris.music4` | `aeris938-2/scripts/grow.py tiktok --post` (desktop) |
| Shopee | `th.shp.ee/6hv2uk89` | `aeris938-2/scripts/grow.py shopee --check`; link in `channel/monetization.json` |

`channel/monetization.json` is the single source for those links; the footer omits
a blank one, so an account that is not ready yet never shows a dead link. All four
are filled in. `desk_daily.py` is the one command that does the browser half.

## The scheduled rails (what runs with no pod, no K)

The 24/7 loop needs runners that do not depend on a build pod being alive. These
run on GitHub Actions (always on, free for this public repo, no sandbox quota):

| Workflow | Cadence | What it does |
| --- | --- | --- |
| `AX Music Daily Release` | daily 08:30 UTC | uploads the next song to YouTube |
| `AX Music Crosspost` | every 2h | posts pending Shorts to FB Reels + TikTok |
| `AX Music Daily Dashboard` | daily | reads the four surfaces, pushes numbers to K |
| `AX Rail Watchdog` | 6-hourly | heals auto-paused automations, alerts on ntfy |
| `AX Roblox Live State` | hourly | maturity label for the game |

The crosspost rail is the one that closed the last manual gap. It restores a saved
browser session from the `AERIS_STORAGE_STATE_B64` secret (exported with
`ops/save_storage_state.py`) and posts without a desktop. If the session is ever
rejected the run fails and pushes a phone alert; the fix is a fresh desktop
sign-in plus re-export — that is the one thing that can need K.

## How AR reports

Short, in Thai, with numbers not adjectives. State what was done, what is
blocked, and the one action K must take if any. Never claim "done" without the
evidence (a run id, a video id, a test count, an HTTP code).
