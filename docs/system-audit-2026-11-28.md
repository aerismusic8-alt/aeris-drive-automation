# System audit — 2026-11-28 03:15 UTC / 2026-11-28 10:15 เวลาไทย

K's order came on 2026-11-27; this audit and the removals were done on the 28th.

K's order: audit the whole system, and remove every outside advisor that works
inside it — ChatGPT, Gemini, Duck, Pollinations and the rest. AR decides from
now on.

สรุปภาษาไทย: ที่ปรึกษาภายนอกถูกถอดออกจากระบบทั้งหมดแล้ว 20 ไฟล์
ตัวที่เคยเรียกที่ปรึกษาถูกเขียนใหม่ให้ AR ตัดสินเอง เกตคุณภาพของคลิป/ปก/ซ้ำ
ยังอยู่ครบและยังกันที่ทางอัพทุกทาง เทสต์ผ่าน 3958 ข้อ (music938-1) และ 51 ข้อ
(aeris938-2) ยังเหลือช่องว่าง 4 ข้อที่เขียนไว้ท้ายเอกสาร

Every number below was read from a file or a command at the time above. Nothing
here is inferred; a field that could not be read says so.

## 1. Advisors removed (20 files, deleted — not archived)

| file | what it was | replaced by |
| --- | --- | --- |
| `ops/consult.py` | browser-driven advisor panel, quorum gate | AR decides; no gate |
| `ops/consult10.py` | 10-vendor panel runner | deleted with it |
| `ops/consult-log.jsonl` | the panel's answer log | deleted with it |
| `ops/gemini_ask.py` | ask Gemini web for text | — |
| `ops/gemini_api.py` | Gemini `generateContent` drafter | — |
| `ops/gemini_gate.py` | fail-closed render/upload review gate | the technical floor (`clip_standard`) only |
| `ops/gemini_review.py` | review sheet + prose verdict parser | — |
| `ops/gemini_calibrate.py` | score calibration for the gate | — |
| `ops/chatgpt_ask.py` | ask ChatGPT web for text | — |
| `ops/duck_ask.py` | ask Duck.ai for text | — |
| `ops/pollinations_ask.py` | ask Pollinations for text | — |
| `ops/ask_agents.py` | dispatcher over the above | — |
| `music938-1/scripts/run_panel.py` | ran the multi-vendor panel | — |
| `music938-1/scripts/forge_song.py` | multi-AI lyric forge + A/B judge | AR writes the lyric |
| `tools/af_advisor.py` | keyless rail-side advisor (g4f/HTTPS) | — |
| `tools/af_vendor_bench.py` | bench: is the pipe alive | — |
| `tools/af_pick_trading_advisor.py` | bench: does it do arithmetic | — |
| `tools/af_ceo_bench.py` | bench: does it make a decision | — |
| `tools/af_advisor_roster.json` | the advisor roster | — |
| `.agents/agents/ax-advisor.md` | sub-agent persona that drove them | — |

## 2. Callers rewired

| file | before | after |
| --- | --- | --- |
| `music938-1/scripts/ai_lyrics.py` | drove Gemini/ChatGPT/Duck/Pollinations, then a "meaning check" that asked a model again | keeps the brief, the parser and the lint; `load_ar()` reads the lyric AR wrote; the CLI only lints |
| `music938-1/scripts/produce_loop.py` | tried three drafters per song | reads `lyrics/inbox/<slug-word>.txt`; missing or failing the lint → `result: no-lyric`, naming the file AR must write |
| `aeris938-2/scripts/admin.py` | refused to run without a recorded quorum | no gate; reads, drafts, alerts, never sends |
| `aeris938-2/scripts/experiment_loop.py` | an exhausted diagnosis said "ask the advisors" | says AR must fill `LIBRARY` — a diagnosis with no method stays exhausted |
| `music938-1/tests/run.py` | 6 advisor tests | 1 test that pins their absence |
| `aeris938-2/tests/test_surfaces.py` | pinned the admin consult gate | pins that no gate is left |

The lyric is now a file, so it can be read and corrected before anything is sung.
`python3 scripts/ai_lyrics.py --slug <slug>` lints it; the same
`lint_sections` that judged a model's draft judges AR's text.

## 3. What is still outside — and is not an advisor

These produce sound or pictures or publish; none of them is asked for an opinion:

- **Flow Music** (Google, K's session) — renders a sung take. Revived headlessly
  by `ops/session_guard.py` (`AUTO_REVIVE = {"flow", "google"}`).
- **Image generation** — Pollinations HTTP and `aeris938-1/scripts/gemini_image.py`
  (signed-in Gemini web) draw cover art and story stills.
- **Platform APIs** — YouTube Data/Analytics, Facebook Graph, TikTok Content
  Posting, Shopee link.

If K wants the picture generators gone too, that is a second order and it costs
cover art and the AI stills in the clip lanes.

## 4. Rails — 34 workflow files (read from `.github/workflows`)

| group | rails | schedule |
| --- | --- | --- |
| publish | `ax-bank-publish`, `ax-music-crosspost`, `ax-music-release` | 03:25, hourly, 08/14/20:05 |
| produce | `ax-music-produce`, `ax-music-mv`, `ax-music-compilation`, `ax-music-surreal-render`, `ax-music-reactive`, `ax-music-concert-render`, `ax-music-trivia`, `ax-music-affiliate-render`, `ax-genart`, `ax-image-bank`, `ax-clip-lane` | 4 h / 5 h / 3 h / weekly / daily |
| measure | `ax-music-dashboard`, `ax-yt-audit-weekly`, `ax-fb-page`, `ax-rail-watchdog`, `ax-token-heartbeat`, `ax-risk-audit`, `ax-memory-guard` | 8/14/20:30, Tue 07:00, Mon 06:10, hourly |
| keep alive | `ax-session-heal`, `ax-music-admin`, `ax-pc1-bank-sync` | 6 h, hourly, 4 h |
| parked (manual) | `ax-pc1-*` roblox + pull rails, `ax-arena-tests`, `ax-breachline-source-probe`, `ax-gh-app-token` | manual |

## 5. Gates that still stand (no override at any upload route)

| gate | file | what it refuses |
| --- | --- | --- |
| clip floor + per-format profile | `ops/clip_standard.py` | a clip under the floor, on every route |
| thumbnail floor | `ops/thumb_standard.py` | dead silence ≤3 s, VFR >2% |
| genre | `ops/genre_gate.py`, `channel/genres.json` | off-direction genres, fails closed |
| lane compass | `ops/compass.py` | a lane rendering or listing what it may not |
| no repeats | `ops/no_repeat.py` | audio SHA-256, lyric shingle ≥90%, picture SHA-1 |
| publish hold | `ops/hold_gate.py`, `ops/PUBLISH-HOLD` | any publish while the hold file exists |

## 6. Inventory (measured today)

- masters: **34** total, **17** on-direction (publishable), **17** off-direction
  (never publish), **24** planned but short across the five lanes.
- bank clips: **6** `.mp4` in `music938-1/library/bank`.
- per lane: rock 7/9 mastered, pop 7/8, hiphop 1/8, rap 1/8, alternative 1/8.

## 7. Open gaps (named, not hidden)

1. `ax-music-produce.yml` still passes `GEMINI_API_KEY` to the produce step.
   Nothing reads it any more. The workflow file cannot be pushed from this pod
   (the token lacks `workflow` scope), so the dead env var stays until a push
   with that scope.
2. TikTok publishing is blocked: `TT_POLICY_EMAIL` is unset (K's order).
3. L3 (1,000 subs / 4,000 watch-hours) is not measured — the Analytics read has
   not been run against the live channel.
4. The lyric lane: AR seeded `lyrics/inbox/` with three lyrics (pop ×2, rock ×1),
   all passing the lint. The other eleven themes have no words yet, so a run that
   reaches one of them stops with `no-lyric` — by design, and it names the file.
