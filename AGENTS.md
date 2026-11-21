# AGENTS.md

Repository-specific notes for agents working in this repo.

## Account playbook (read first)

`.agents/skills/ax-account/` is the consolidated playbook for the whole account
(this repo plus `ai-content-lab`, `autonomous-zero-baht`, `autonomous-zero-baht-1`).
It holds the identity/authority model, Rule #1 (free only), the project map, the
shared conventions, and the environment/delivery reality. Load it when a task
mentions AKATH, AX, K, PC1, Roblox, a Thai story video, music938, karaoke, a Drive
upload, or "free only". Install it for every conversation with
`.agents/skills/ax-account/scripts/install-agent-skills.sh`.

Then read `.openhands/CHARTER.md`: K's standing mandate (2026-10-31) that AR
administers **all** of K's work in K's place — decide, execute, verify, record, no
per-step approval. It also carries the perpetual loop and the live priority queue,
so it is the first place to look for "what should I do next".

Then run `python3 ops/brief.py`. It prints the live state — publish hold, compass
result, the catalogue counted from the release, the last saved login — derived
from artifacts rather than memory, because a cold session has no memory and the
injected card is capped at 6 KB. Report numbers from a command that read the
artifact, never from recollection; `ops/brief.py` is that command.

## AR's team (file-based sub-agents)

`.agents/agents/` holds the curated sub-agents — six, each bound to a tool that
exists on disk and to a standing rule, so none is a persona without hands. The
loader scans that directory at conversation start (README.md is skipped).

| Agent | Job | Drives |
| --- | --- | --- |
| `ax-advisor` | Gemini-only consultation gate (K, 2026-11-18); follow its advice when blocked | `ops/consult.py`, `ops/gemini_ask.py`, `websearch.py` |
| `ax-evidence` | the 4 surfaces, fresh/stale/unknown, no bad-data verdicts | `aeris938-2/scripts/evidence.py`, `ops/studio_read.py` |
| `ax-experiment` | one recorded non-duplicate test per constraint, respects HOLD | `experiment_loop.py`, `goal_watch.py` |
| `ax-session` | keeps/recoveries the free browser session without asking K | `check_login.py`, `ops/login_vault.py` |
| `ax-delivery` | gets an artifact to a reachable destination and proves it | `gh-api.py`, `use-app-token.sh` |
| `ax-hygiene` | keeps the guards green (memory cap, tests, wiring, risk) | `memory_guard.py`, `memory_search.py` |

Every member is bound by: free only; the HOLD (no upload/render/enable); never ask K
for a Google login; never decide on stale data; consult before deciding.
`music938-1/tests/run.py::test_ax_team_is_well_formed` pins the format (name ==
filename, >=2 `<example>` tags, tools present) and that each member's tools exist,
so a broken file fails the suite instead of silently doing nothing.

## Layout

| Path | Purpose |
| --- | --- |
| `AKATH_CORE/` | Task registry (`CANONICAL_TASK_REGISTRY.json`) and the Roblox goal scripts. |
| `AX_MASTER_BRAIN/`, `AX_PC_CONTROL/` | Windows automation scripts driven by GitHub Actions (Roblox publish). |
| `roblox/` | AX Arena game (Luau). Pure logic in `src/shared`, Roblox glue in `src/server` + `src/client`. |
| `scripts/` | Tooling: Luau install/test, GitHub App token minting. |
| `tools/` | Vendored binaries. Gitignored — fetch with `scripts/install-luau.sh`. |
| `docs/` | Project documentation. |

## Environment

- Linux sandbox, x86_64. `node` and `npm` are available; there is no Roblox
  Studio here, so game logic must stay testable under the plain Luau CLI.
- `unzip` is **not** installed. Extract archives with
  `python3 -c "import zipfile; zipfile.ZipFile(p).extractall(d)"`.
- The sandbox shell mangles `<<'EOF'` heredocs (tab completion fires inside
  them). Prefer the file editor tool, or `printf '%s\n' 'line'` for scripts.

## Luau

`src/shared` must not call Roblox APIs. That constraint is what makes the test
suite possible; keep it intact when adding features.

Standalone Luau 0.743 limitations, verified in this environment:

- **No `as` casts.** `x as T` fails to parse. Use `x :: T` instead, which both
  `luau` and `luau-analyze` accept.
- **No bitwise operators.** `&`, `|`, `~`, `<<`, `>>` are all parse errors in
  the CLI. Use the `bit32` library (`bit32.bxor`, `bit32.lshift`, ...), which
  works in both the CLI and Roblox.

Run the tests:

```bash
scripts/test-roblox.sh                     # uses luau from PATH, else tools/luau
./tools/luau/luau-compile --binary <file>  # syntax check the Roblox glue
```

Note `luau-compile --binary` needs a file path, not stdin.

## GitHub App credentials

Write access comes from a GitHub App, not a personal token. The default
`GITHUB_TOKEN` in this sandbox is read-only (all writes return 403).

- Key and config: `~/.config/aeris/gh-app.pem` + `gh-app.json`
- Mint a token: `node scripts/gh-app-token.mjs` (add `--export` for a shell line)
- Installation tokens expire after ~1 hour. Mint fresh per operation.

Push with an app token:

```bash
TOKEN=$(node scripts/gh-app-token.mjs 2>/dev/null)
git push "https://x-access-token:${TOKEN}@github.com/aerismusic8-alt/aeris-drive-automation.git" <branch>
```

`create_pr` and similar tools use the read-only token and will 403. Create PRs
via the REST API with an app token instead.

**A fresh pod has no App key.** `~/.config/aeris/` was on the ephemeral overlay,
so the recipe above only works while that directory survives. The route that works
from a clean pod is the durable vault: read the KV key
`axsecrets:gh-workflow-token` (value is a **dict** — `.token`, `.login`,
`.scopes`) and put the token in the push URL.

```bash
TOK=$(python3 -c "import sys;sys.path.insert(0,'ops');import ax_vault;\
aid=ax_vault.ensure_anchor();print(ax_vault.kv_get(aid,'axsecrets:gh-workflow-token')['token'])")
GIT_TERMINAL_PROMPT=0 git push \
  "https://x-access-token:${TOK}@github.com/aerismusic8-alt/aeris-drive-automation.git" main
```

The `git -c http.extraheader="AUTHORIZATION: bearer <tok>"` form fails with
"invalid credentials" even though the same token answers the REST API with 200.
Verified 2026-11-13: `6592a7e..1eb9cc1 main -> main`.

**Workflow files need a `workflow` scope the App token does not have.** A push
that touches `.github/workflows/` is rejected with `refusing to allow an OAuth
App to create or update workflow ... without 'workflow' scope`. Use the classic
token at `/workspace/ax-tools/ar-identity/gh-workflow-token` (scopes
`repo, workflow`) for those pushes; everything else uses the App token.

```bash
WFT=$(cat /workspace/ax-tools/ar-identity/gh-workflow-token)
git push "https://x-access-token:${WFT}@github.com/OWNER/REPO.git" main:main
```

`scripts/push-via-pc1.sh` is the older route and needs PC1's Tailscale endpoint
up; when it is down the push hangs on the MCP call.

Two helpers exist so this is not hand-rolled each time:

```bash
./scripts/use-app-token.sh            # point the remote at a fresh token
./scripts/use-app-token.sh push origin <branch>
python3 scripts/gh-api.py PATCH /repos/OWNER/REPO/pulls/46 --body-file body.json
```

`scripts/gh-api.py` mints its own token per run, so it is safe to call after
the previous token has expired. Leave the remote without a token between
sessions: `git remote set-url origin https://github.com/OWNER/REPO.git`.

## The Roblox game

`roblox/` holds AX Arena. Two standing goals are recorded in
`AKATH_CORE/CANONICAL_TASK_REGISTRY.json` and must not be closed as ordinary
tasks: a game anyone can enter and play, and real revenue from it.

**Parked 2026-11-09.** K set the focus to the four aeris938-2 jobs (Facebook,
TikTok, YouTube `@aerismusicth`, Shopee Affiliate); the Roblox goals are `PARKED`,
not closed — `AKATH_CORE/park_roblox_goals.py` sets that state and the registry's
`focus` block names the four jobs. Resume by setting the status back to
`IN_PROGRESS`. A parked goal is inert until it is moved back.

The shape that matters:

- `roblox/src/shared/` is pure Luau with no Roblox globals, so it runs under
  the standalone CLI and is where all the real logic lives.
- `roblox/src/server/` and `roblox/src/client/` are thin glue. The server is
  authoritative; the client renders and sends intent only.
- Every remote goes through `guard()`, which rate limits and validates. Never
  trust a value that came from the client.
- All reward paths share one multiplier chain in the server's
  `coinMultiplier()`. Add new multipliers there, not at the call site.
- Bump `Config.Persistence.SchemaVersion` when the save shape changes and
  extend `SaveSchema.migrate` so older saves keep their progress.

Run the tests before every push:

```bash
cd roblox && ../tools/luau/luau tests/run.luau
```

The Python suite is `python3 music938-1/tests/run.py` (a few minutes, no pytest).
It has **no test discovery**: `main()` calls every test by name, so adding or
renaming one means editing that list too. A rename alone fails at the very end
with `NameError: name 'test_x' is not defined` — after the whole run has looked
green.

Publishing does not need Roblox Studio: `AX_PC_CONTROL/pc1-roblox-build.ps1` builds the
place with Rojo and `pc1-roblox-publish.ps1` uploads it through the Open Cloud API. What
Studio is still needed for is *creating* a new experience. `roblox/PUBLISH-FROM-PHONE.md`
covers what can and cannot be done from a phone.

## Shipping to Roblox

The live place can lag the branch in three different ways, and they all look the
same to a player: "the game is still the old game". Check them in this order.

1. **Was a version published for this commit?** Open the latest
   `AX PC1 Roblox Publish` run and read `HEAD is now at <sha>` plus
   `PUBLISHED_VERSION`. If the SHA is old, the build used a stale ref.
2. **Which ref does the build actually read?** `BUILD_REF` in the log is only the
   ref the *script* was fetched from. `pc1-roblox-build.ps1` hard-codes
   `$BRANCH = 'ax-arena-roblox-game'`, so the code it builds always comes from
   that branch. A run that says `BUILD_REF=main` still publishes the branch.
   `SOURCE_BLOCKS` tells you which tree you got: 39 is the branch's `roblox/`,
   28 is `main`'s.
3. **Can the intended audience join?** Read the **maturity label**, not the
   playability probe. `games.roblox.com/v1/games/multiget-playability-status`
   answers for the *caller*: a logged-out caller gets `GuestProhibited` from
   every experience on Roblox, including Adopt Me, so it says nothing about your
   game. The label is the real gate:

   ```bash
   curl -s -X POST -H 'Content-Type: application/json' \
     -d '{"universeId":10773483379}' \
     https://apis.roblox.com/experience-guidelines-api/experience-guidelines/get-age-recommendation
   ```

   `displayName: "Content May Vary"` means **16+ only**; `Minimal`, `Mild` and
   `Moderate` are eligible for the younger tiers. The label comes from the
   Maturity & Compliance questionnaire, and a *partial* one defaults to the
   strictest — the first page alone yields 16+. Fill in the **whole** form at
   Creator Dashboard -> experience -> **Publish settings -> Content rating**.
   Only the account owner can do this.
   `ContextualPlayabilityUnrated` is a different symptom and also means the
   questionnaire is outstanding.
   `scripts/roblox-live-state.py` reads this for every owned universe on an
   hourly schedule and keeps Adopt Me in the same call as a control.

Rules learned the hard way:

- The publish workflow must **not** carry a `workflow_run` trigger here. GitHub
  only honours `workflow_run` when the workflow carrying it exists on the
  **default branch**, and the publish workflow lives on `ax-arena-roblox-game`.
  The trigger never fired and nothing failed. The test workflow dispatches the
  publish instead, with the tested SHA as the ref.
- The publish workflow must **not** carry a `push` trigger on its own files
  either. It bypasses the tests, and it races the dispatch, so one commit
  produces two publishes.
- A red test run must never reach players, so the dispatch sits after the last
  test step and only runs for a push to `ax-arena-roblox-game`.

## The product is a MUSIC VIDEO (K, 2026-11-20)

> "วีดีโอผ่านใช้ได้ แต่เราทำเพลงนะไม่ใช่คลิปบรรยาย แก้ไขคำสั่ง k ด้วย ทำเป็น mv"

The first delivered batch passed QC and was still the wrong product. This is a
**music** channel: the video is the **song**, and the picture serves it. A Thai
voice-over narrating a story over stills is not our format, no matter how clean
the render.

- **The video rail is `music938-1/scripts/make_music_video.py`.** The song is the
  mix — there is no narration track. Many shots, each with a real camera move,
  cut on the song's own BPM (a whole number of beats per shot, 2.8–5.5 s), a
  title card and a follow card, an audio-reactive VJ bar, and `loudnorm` at the
  mux so every MV meets the floor.

### The picture must not move too fast (K, 2026-11-20)

> "ภาพเลื่อนเร็วเกิน" / "ภาพเลื่อแทค"

The cut used to land every two beats, and a 120 bpm song changed shot every
1.6 s — 140 shots in 222 s, 37.7 cuts a minute. Each shot also slid 45% of the
frame, so the picture moved 28% of the screen width every second. Measured on
the shipped MV-12: motion median 14.8, p99 81.9.

Two numbers set the pace, and both are pinned by tests:

- `shot_seconds()` picks a whole number of beats that lasts at least
  `SHOT_MIN` (2.8 s) and at most `SHOT_MAX` (5.5 s). 68 bpm → four beats
  (3.53 s), 120 bpm → six (3.0 s). No tempo exceeds **22 cuts/min**.
- `OVERSIZE` (1.20) is both the pan source's margin and the distance a pan
  travels in one shot, so it sets the slide speed. 1.45 over a 1.6 s shot was a
  whip pan; 1.20 over 3 s is **6.7%/s**. `ZOOM_RATE` 0.10 (max 1.18) replaces the
  0.16–0.34 lunge.

The re-rendered MV-12 measures motion median **9.5** (from 14.8) and p99 **56.9**
(from 81.9) at **18.1 cuts/min**, and still passes every clip-floor check. When
changing pacing, re-render and re-measure — do not trust the constants alone.

### One song, one take (K, 2026-11-20)

> "เพลงเก่าลบออกให้หมด ใช้เพลงใหม่ล่าสุด"

The auto-producer appends a template suffix when it wants more songs (อีกครั้ง /
ในฝัน / ยามเช้า / ยามค่ำ), so one song became up to five files with different
lyrics but the same structure. They are not versions of one master — the audio
differs, so a SHA comparison does not catch them. `ops/song_prune.py` groups a
*family* (the slug minus its leading number and trailing `-vNN`) and keeps only
the **newest take**, the highest number.

```bash
python3 ops/song_prune.py            # dry run: print the plan
python3 ops/song_prune.py --apply --release
```

- `--release` is not optional in practice. `pull_media.py` restores **every**
  asset on `media-938`, so pruning only the local file means a fresh pod pulls
  the deleted takes straight back.
- It also drops queued clips for a deleted song from `crosspost-queue.json`.
  The crosspost *state* (what already went out) is history and is left alone.
- Anything that pins a slug by name has to move to the kept take:
  `work/release-priority.json` named `48-luai-mai-yut-v48` and now names `-v49`.
  A stale pin makes `release.py` look for a file that no longer exists.
- `review-pending.html` links release assets directly, so rebuild it after a
  prune (`ops/review_gallery.py`) or the gallery shows dead links.
- Masters are recoverable from the release before the prune, and the lyric text
  is tracked in git, so this is not a one-way door — but the audio is not
  recoverable after `--release`, so read the dry run first.

Applied 2026-11-20: 47 files → 32 songs, 15 superseded takes and 145 release
assets deleted (175 MB local).

- **Scenes come from the 4K picture library first.** `ops/picture_library.py`
  fills a themed shelf (horror/lesson/humour/city/nature/temple/abstract) from
  Wikimedia Commons at ≥3840 px plus `ops/genart.py` originals at 4096 px. The
  song's `# MOOD:` picks the theme. The free AI image route (Pollinations) is a
  gap-filler only: it answers at 1024×576, which softens the moment the camera
  moves, so it is never mixed in beside a 3840 px still.

- **A camera move must not squash the picture.** The library is landscape 4K and
  the frame is 9:16, so every move carries
  `scale=...:force_original_aspect_ratio=increase` before its `crop`. Without it
  a 1.5 source is squeezed to 0.56 — a 2.7× horizontal squash that flattens
  every face. Verified by rendering a circle through all eight moves and
  measuring it: correct moves give ratio 1.000, the bug gave 0.34. The test
  `test_mv_keeps_picture_proportions` pins the whole move table.
- **The genre gate and the clip floor both run in `build()`.** An MV is a
  publish, so a parked genre is refused before any render and a below-floor
  render is deleted rather than left on disk looking shippable. A passing MV is
  shelved with `media_home.finished()`.

### The Gemini review is not part of the video system (K, 2026-11-20)

> "ตอนนี้ตัดการตรวจสอบของ gemini ออกจากระบบสร้างวีดีโอใหม่เลย"

The review was a fail-closed gate on every render and every upload route: a
verdict hash-bound to the exact file, or nothing shipped. It is **optional** now.
`ops/gemini_gate.py` and `ops/gemini_review.py` remain as tools you may run by
hand; no pipeline path calls them, and `test_no_gemini_gate_in_the_video_system`
fails if one is wired back in.

Do not confuse this with QC. **QC is still mandatory** and still blocks:

- `ops/clip_standard.py` — the technical floor (codec, −16…−12 LUFS, ≤ −1.0 dBTP,
  no dead silence, not frozen, no black bars), measured on the file itself.
- `ops/genre_gate.py` — fun-only genres; a parked genre never publishes.
- `ops/thumb_standard.py` — the thumbnail floor.

The distinction that matters: those measure the artifact and run anywhere. The
Gemini review needed a signed-in desktop, so on a runner its absence was
permanent — a rail that can never go green is not a gate. Its rubric was also
written for a 9:16 Short (captions, hook timing), which is the wrong test for an
MV.

`ops/story_reel.py` remains as a tool (and its 4K stills, instrumental-bed and
crossfade fixes are real), but it is no longer a format to produce. The trivia
lane (`ops/trivia_reel.py`) is a separate factual format K named explicitly and
is unaffected.

## Clip quality — one floor, every format (K, 2026-11-17)

> "อันนี้เป็นแค่มาตรฐานเริ่มต้นสามารถทำได้ ห้ามมาตรฐานต่ำกว่านี้เด็ดขาดในช่องของเรา"

K supplied a trivia clip as a **sample** of the quality wanted; the goal is a
standard for **all** our work. It is a **floor, not a target** — nothing below it
may ship on any channel — and it is enforced by code, not a doc.

`ops/clip_standard.py` measures a finished clip. It defines a **universal floor**
(h264, aac 48k stereo, **−16…−12 LUFS**, ≤ −1.0 dBTP, ≥ 1 s) plus **one profile per
format we render** (trivia 1280×720/24, vertical 1080×1920/30, film 1920×1080/30,
horizontal 1920×1080/25, motion 832×480/16). Style rules apply only where the
format calls for them: *no hard cut* is trivia (a film cuts by design), *not
frozen* is trivia + vertical (a karaoke lyric sheet is nearly still). A profile may
**tighten** the floor; raising a number is welcome, lowering one is what K forbade.

```bash
python3 ops/clip_standard.py <clip.mp4>     # auto-detects the profile
```

Enforced at both ends:

- `ops/trivia_reel.py` runs the gate after every render and, on a fail, **deletes
  the MP4 and exits non-zero**.
- `ops/yt_publish.py` is the one YouTube upload chokepoint for all 4 channels; it
  measures every clip and **blocks** a below-floor one. The Facebook and TikTok
  posters (`ops/fb_graph.py`, `ops/tiktok_api.py`) and the browser composers
  (`crosspost.post_tiktok` / `post_facebook`) call `assert_ok` before any network
  call. The rule is **every channel, every route**, with **no override** (K
  2026-11-17: "คลิปวีดีโอที่ต่ำกว่าเกณฑ์มาตรฐาน ห้ามอัพขึ้นเด็ดขาด").
- `music938-1/tests/run.py::test_clip_standard_is_a_floor` pins the floor and
  builds deliberately bad clips to prove the gate rejects them.

The first library-wide run found a real defect: **24 of 28 song masters clipped**
(up to +1.6 dBTP) and ranged −11.9…−24.0 LUFS. The lanes mux those masters raw, so
every Short/MV/film/karaoke inherited it. It is not a bug in `make_song.py` (its
two-pass loudnorm is correct) — the masters are stale. `ops/remaster_songs.py`
(free) brings each into the band and is idempotent. Masters are pulled from the
`media-938` release, so refresh that release for the fix to reach a fresh pod.

`docs/clip-standard.md` is the full standard; `docs/trivia-clip-standard.md` is
the measured reference the trivia profile came from.

### The trivia lane (เกร็ดความรู้) and its publish half

K's 2026-11-17 ask had three parts: build the lane, make the reference quality the
standard, then **upload it**. `ops/trivia_reel.py` is the first two — it renders a
Thai-narrated landscape clip (edge-tts + Wikimedia Commons footage + ffmpeg, all
free) and enforces the clip floor. `ops/trivia_publish.py` is the third: it renders,
builds the title/description/thumbnail, and uploads to `ch3` **through**
`yt_publish.py`, so both the clip and thumbnail floors are enforced before any
network call.

- Facts live as one Markdown file each under `scripts_trivia/*.md`
  (`# TITLE:`, `# THEME:`, then the cards). Adding a fact is adding a file.
- `--next` picks the first fact not yet in `music938-1/work/trivia-state.json`
  (the ledger), so a re-run or a retry never double-posts one. The ledger is
  committed by the rail.
- `.github/workflows/ax-music-trivia.yml` runs `--next --now` once a day. A
  YouTube per-channel daily new-video cap surfaces as `uploadLimitExceeded`
  (HTTP 400) — a normal, non-fatal outcome; the ledger records only successes, so
  the same fact lands on the next tick.
- `music938-1/tests/run.py::test_trivia_publish` pins the publishing contract.

## Language

The player-facing text is Thai. `roblox/src/shared/Text.luau` is the only place
a Thai string lives; every screen, sign and notification reads from it.

- **Ids stay English.** `Fields`, `Zones`, `Enemies`, `Farm` and the client
  intents key off `id`, and a save stores the zone by id. Renaming an id to
  translate it would break saves, travel and the tests. Translate the display
  text only, through `Text.placeName` / `Text.cropName` / `Text.enemyName` /
  `Text.tagline`.
- **An unknown key returns the key**, not an empty string. A missing line then
  shows as `Cavern` in a screenshot instead of a blank button.
- **Monsters arrive as display names**, not ids, because the server sends
  `Enemies.scale().name`. `Text.enemyName` maps those English names. Loot is
  the exception: `Enemies.scale()` also carries `id`, and drop tables are keyed
  by that id (see below).
- **Thai needs more vertical room than Latin.** A tone mark sits above the
  baseline and a vowel below it, so a label row sized for `Coins: 0` clips
  `เงิน`. Row heights in `Hud.luau` are set for Thai, not for the English the
  layout was first drawn with.
- **`roblox/tests/run.luau` guards this.** The "Thai text" suite asserts every
  field, crop and monster has a translation, that the format lines keep their
  `%d` placeholders, and that each line actually contains a Thai codepoint
  (U+0E00-U+0E7F). Add a key to the checked list when you add a string.

## Workflows

`runs-on: self-hosted` is a **Windows** machine (PC1, `DESKTOP-RGK6JKB`), so
`shell: powershell` is the correct default there. `ubuntu-latest` also works
for pure Linux jobs — the Luau test workflow uses it.

Do not commit binaries; `tools/` is gitignored on purpose.

## The cloud desktop (login-only web apps)

Some tools here have no API and are behind a Google login the agent must never type:
**Flow Music** (`flowmusic.app`, real music beds) and **Gemini web**
(`gemini.google.com`, episode images). The route is a desktop the agent can drive and
the operator can sign into once. Read
`.agents/skills/ax-cloud-desktop/SKILL.md` before touching either.

```bash
python3 .agents/skills/ax-cloud-desktop/scripts/bootstrap.py    # bring it up (idempotent)
python3 .agents/skills/ax-cloud-desktop/scripts/check_login.py  # is it signed in?
```

Three facts that cost real time and will bite again:

- **`$HOME` is not persistent.** `/home/openhands` is on the container overlay; only
  `/workspace` survives a pod recycle. State (the chrome profile, hence the Google
  login) lives in `/workspace/ax-tools/aeris938-state/`. A profile under `$HOME` loses
  the login on every recycle and the operator has to sign in again.
- **A *new sandbox* still loses the login.** `/workspace` survives a recycle, but a
  replaced sandbox gets a fresh, empty volume, so the profile is gone. That is what
  forced K to sign in more than once. The fix is `ops/login_vault.py`: after K signs
  in, `save` snapshots the session cookies to the durable KV store; on a fresh pod,
  `restore` puts them back before the browser is used. Sign in once, not per pod.
- **Chrome needs `--remote-allow-origins=*`** or every CDP websocket is refused with
  403 and Playwright cannot attach, even though the browser is running.
- **`vnc.html` returns 200 even when the VNC backend is dead** — it is a static page.
  Run `bootstrap.py --status`, not a curl, to know whether the desktop is up.
- **The X screen does not repaint on this sandbox**, so noVNC shows a frozen picture
  even with every process up (`scrot` of `:99` is byte-identical across seconds). The
  view to use is the **live view**, which serves the browser *tab* from CDP on 12001:
  `https://work-2-<work-host>/`. `bootstrap.py` starts it (`start_liveview`) together
  with the phone pages (`start_phone_login`, proxied through it).

The operator signs in via the live view —
`https://work-2-<work-host>/` (the `work-2-...` host from the session's work_hosts,
never `hostname`). noVNC
(`https://work-1-<work-host>/vnc.html?autoconnect=1&resize=remote`) still exists as a
fallback but shows the frozen X screen. Sending a `flowmusic.app/session/<id>`
link does not help: that is an in-app route, not a credential, and without the cookie it
redirects to the landing page.

A real track is registered in `library/music/` (`source: flowmusic-web`), and
`make_story.py` prefers a library track over the synth bed. `compose.py` loops a short
track with `-stream_loop -1`, so a 3-minute song fills a 5-minute episode.

### Never ask K for a Google login again

K's rule (2026-11-13): recover the session from the vault; asking K is the failure.
A fresh context plus vault cookies **and** stored storage restores the account with no
password (verified — the device-trust token lives in localStorage, so a cookie-only
restore still makes Google ask).

- On a fresh pod `bootstrap.py` already calls `restore_login()`; do not gate it on K.
- If a surface reads signed out, run `ops/login_vault.py restore` and re-check.
- **A `restore` must never overwrite a live surface.** Doing that on 2026-11-13 turned
  a working Studio login into the password prompt, which cost K a re-login. `restore`
  now keeps any live surface and replaces only the dead ones (`--force` overrides).
- Judge sign-in by positive evidence (the account email / YouTube avatar), never by
  cookie presence or by a word like "บัญชี" that both states show.

### AR's own identity (mailbox + browser profile)

AR (the agent) has its own identity, kept **outside** the public repo at
`/workspace/ax-tools/ar-identity/`: `creds.json` (the mail.tm mailbox, mode 600),
`browser-profile/` (the cookies that keep AR signed in), `accounts.json` (which
services AR has accounts on). Tools: `ops/ar_identity.py` (mailbox), `ops/ar_accounts.py`
(register), `ops/ar_browser.py` (profile).

- **K's rule:** a newly-registered mailbox is for throwaway signups only. Flow Music
  and Gemini stay on **K's account `aerismusic8@gmail.com`**; `check_login.py` returns
  `WRONG_ACCOUNT` (exit 3) on any other.
- **It does not survive a replaced sandbox on its own.** `/workspace` survives a
  *recycle* but a replaced sandbox gets a fresh, empty volume — and the vault excludes
  credential-shaped files, so on 2026-11-13 the mailbox, profile and register were
  gone. The mailbox password is now mirrored to the vault (`aridentity:creds`) and
  `ar_identity.py ensure` restores from it before creating a new address. **Run
  `ensure` first on a fresh pod.** The browser profile is still local; re-sign-in on
  the services AR uses is not automatic.

### The farm loop

`Farm.luau` and `Axe.luau` are the "farm" half of the game. Farming is not a
side activity: harvesting charges the axe, and the axe is what clears a wave.
Keep that link intact when adding content.

- The server owns every crop timer. `Farm.plant` and `Farm.harvest` take `now`
  as an argument, so the loop is testable without a clock and a client cannot
  speed growth up.
- Harvesting early returns `NOT_READY` and leaves the crop planted. A mistap
  must never destroy progress.
- The FARM button is a single tap on purpose. It harvests a ripe plot if one
  exists, otherwise plants in the first free plot. Mobile players should not
  have to aim at a plot.

### Enemy damage and death

Two bugs came from a real play session and are now guarded by source checks in
`scripts/check-hud-wiring.py` (WIRING 10):

- An enemy attacks only inside `Config.Wave.EnemyMeleeRange` and only after
  `Config.Wave.SpawnGraceSeconds`. Without both gates every enemy on the map
  damaged the player from any distance and a new player died in seconds.
- `humanoid.BreakJointsOnDeath = false` must be set before the `Died`
  connection. Roblox breaks the joints by default, which sends the head
  rolling; that reads as far more violent than this game wants.
- The `Died` handler calls `applySpawnStats` before `LoadCharacter`, because
  `Combat.damageCombatant` clears `combatant.alive` and only the spawn path
  sets it back. Without it a player can never fight again after dying.

Adding a module under `roblox/src/` means bumping the `SOURCE_BLOCKS` floor in
`AX_PC_CONTROL/pc1-roblox-build.ps1` and adding a marker, or the build
verifier will not prove the new code is inside the published place.

## Fields, travel and the HUD cadence

The game is now a town plus five monster fields, so the rules that used to be
implicit in "one arena" are written down here.

### Fields

- `Fields.luau` is the single source of truth for place ids, unlock levels,
  positions and arrival points. `Fields.list()` is the five fields;
  `Fields.getDef("Town")` is nil on purpose, because town is not a field.
- `Fields.spawnPoint(fieldId, index, count)` places monsters and never lands
  them on the arrival platform. Spawning on the platform dropped a wave on the
  player the moment they travelled in.
- `Fields.canEnter(id, level, ownedPass)` is the only gate. The server calls it
  in the `TravelZone` handler, and the client shows the same lock state from
  `Fields.snapshot`, so a button never promises a trip the server will refuse.

### Waves are per field

- `WaveDirector` keeps its own wave state, and the server keeps one director
  per field (`directorFor`). Two players farming two different maps do not
  share a wave.
- Only fields with somebody standing in them are advanced, so an empty map
  costs nothing. That is what makes five maps affordable.
- Travelling into a field calls `skipIntermission`, so the first wave starts on
  arrival instead of leaving the player alone for twelve seconds.
- A player in town sees `phase = "TOWN"` rather than another player's wave.

### Broadcast cadence (mobile)

The HUD snapshots used to be sent from the top level of the `Heartbeat`
connection, which is once per frame. On a phone that is a flood of events for a
bar that moves a few times a second, and it was the single biggest source of
client work. Now:

- `WaveState` snapshots go out at `Config.Tick.BroadcastInterval` (10 Hz), not
  the 30 Hz simulation rate.
- `FarmState` goes out at `Config.Tick.FarmBroadcastInterval` (1 Hz), because
  crops ripen over minutes.
- Both gates live *inside* the Heartbeat connection and remember when they last
  ran. Moving a gate outside the loop silently restores the flood, so WIRING 7d
  in `scripts/check-hud-wiring.py` checks the gate's position in the source and
  the cadence values in `Config.luau`.
- `roblox/tests/run.luau` asserts the cadence is slower than the tick rate.
  A frame-rate snapshot is the bug, so the two clocks must differ.

### Loot is keyed by archetype id, never by display name

`Items.DROPS` is keyed by archetype id, but a monster's display name is not its
id: `Enemies.def("RockGolem", "Rock Golem", ...)`. Passing the display name into
`Items.rollDrops` misses the table and silently falls back to the generic
potions, so a rare monster becomes a recoloured common one and nobody notices.

- `Enemies.scale()` returns `id` alongside `name`; `World.spawnEnemy` stores it
  as `enemy.archetype`, and the kill path rolls `enemy.archetype or enemy.name`.
- Key every drop lookup off `id` in tests too. `roblox/tests/run.luau` has a
  "multi-word monster keeps its own drop table" test that pins the difference.

`Skills.hotbar` had the same shape of bug from the other direction: it iterated
the `ORDER` id list but read definition fields (`def.id`, `def.kind`) off the
strings, so it always returned an empty hotbar. Resolve an id to its definition
before reading any field. When a lookup can silently return "nothing", assert
the result is non-empty in a test, not just that it is well-formed.

### Pushing when the sandbox token is read-only

The sandbox `GITHUB_TOKEN` cannot write: every push returns 403. Do not spend time
looking for an App key under `~/.config/aeris/` — that directory was on the ephemeral
overlay and is gone in a fresh pod, and `ax_vault.py` excludes `.pem` by design.

PC1 holds a classic PAT that **can** write, so hand the commits to PC1:

```bash
./scripts/push-via-pc1.sh          # bundle -> PC1 -> git push -> prints the remote SHA
```

It unshallows first, because a bundle of a shallow clone cannot be cloned ("Failed to
traverse parents of commit ..."). It also needs the pod reachable over HTTP, which the
port-12001 server in `/tmp/serve` provides.

Verified 2026-10-28: pushed 16 commits, `0001ef8d..90da7a80 main -> main`.

## Persistent memory hygiene

`.openhands/memory/MEMORY.md` is injected into every session prompt, so it is an
**operating card capped at 6 KB** — not a transcript. On 2026-11-10 it had grown
to 128 KB against that budget, and because the prompt truncates *from the top*,
the operating method and Rule #1 (free only) were being dropped from context.

The scheme (three tiers, each with a job):

| File | Role | Bound |
| --- | --- | --- |
| `MEMORY.md` | rules + pointers, injected every session | **hard cap 6 KB** |
| `MEMORY-ARCHIVE.md` | every memory ever written, reachable by grep | unbounded |
| `YYYY-MM-DD.md` | session working notes, never injected | unbounded |

Rules:

- New durable learning goes to **today's daily log first**. Promote a line to
  `MEMORY.md` only if it would change a future decision.
- To shrink the index, **move** superseded lines into the archive and leave a
  pointer — never delete. `MEMORY-ARCHIVE.md` already holds the full pre-2026-11-10
  index as a snapshot.
- **Find anything** in any tier: `python3 ops/memory_search.py "<query>"` greps the
  card, the archive and every daily log at once, grouped by section with line
  numbers (so the next step is a plain `sed -n 'A,Bp' <file>`). `--titles` lists
  every section. Use it instead of re-deriving what was already learned.
- `python3 ops/memory_guard.py` reports the sizes and **exits 1 over cap**;
  `--check` is the quiet form. `music938-1/tests/run.py::test_memory_guard` pins
  it, and `.github/workflows/ax-memory-guard.yml` turns a push that inflates the
  index red. The guard is a pure reader, so it can never block the posting or
  revenue rails.
- Do **not** raise `CAP_BYTES` to make a red run pass — fold lines into the archive.

### More than one agent runs against this repo

K's loop runs several AR sessions against the same branch at once. On 2026-11-12 two
sessions were handed the same "the memory keeps growing" problem within minutes and
produced two overlapping fixes; one merged first and the second rebased into a
conflict. Before starting a non-trivial change, `git fetch` and check whether a
parallel commit already did it — `git --no-pager log --oneline -5 FETCH_HEAD`. If it
did, reconcile into **one** design (adopt what is better and fold in only what is
missing) rather than merging two mechanisms that do the same job.
