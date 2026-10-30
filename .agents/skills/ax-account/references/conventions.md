# Conventions

How work is written and verified across the account. These come from the repos'
own `AGENTS.md` files and from lessons that cost real time.

## Language and text

- **Player-facing text in the Roblox game is Thai.** `roblox/src/shared/Text.luau`
  is the only place a Thai string lives; every screen, sign and notification reads
  from it.
- **Ids stay English.** `Fields`, `Zones`, `Enemies`, `Farm` and client intents key
  off `id`, and a save stores a zone by id. Translating an id breaks saves, travel
  and tests. Translate the *display* text only.
- **An unknown translation key returns the key**, not an empty string — a missing
  line then shows as `Cavern`, not a blank button.
- **Thai needs more vertical room than Latin** (tone mark above, vowel below). Row
  heights sized for `Coins: 0` clip `เงิน`.
- **Numbers in narration scripts are spelled as Thai words**, never left as digits.
- `roblox/tests/run.luau` guards the Thai text: add a key to the checked list when
  you add a string.

## Roblox / Luau

- `roblox/src/shared/` is pure Luau, no Roblox globals — keep it that way, it is
  what makes the tests possible.
- The server is authoritative; the client renders and sends intent only. Every
  remote goes through `guard()` (rate limit + validate). Never trust a client value.
- All reward paths share one multiplier chain in the server's `coinMultiplier()`.
  Add multipliers there, not at the call site.
- Bump `Config.Persistence.SchemaVersion` when the save shape changes and extend
  `SaveSchema.migrate` so older saves keep their progress.
- Adding a module under `roblox/src/` means bumping the `SOURCE_BLOCKS` floor in
  `AX_PC_CONTROL/pc1-roblox-build.ps1` and adding a marker, or the build verifier
  will not prove the new code is in the published place.
- Enemy damage is gated by `Config.Wave.EnemyMeleeRange` **and**
  `Config.Wave.SpawnGraceSeconds`; `humanoid.BreakJointsOnDeath = false` is set
  before the `Died` connection; the `Died` handler calls `applySpawnStats` before
  `LoadCharacter`. All three are pinned by `scripts/check-hud-wiring.py`.
- Loot is keyed by **archetype id**, never display name. Resolve an id to its
  definition before reading a field; when a lookup can silently return "nothing",
  assert the result is non-empty in a test.

## Story video (ai-content-lab)

- **Copyright first.** Thai copyright = author's life + 50 years. Record the death
  date and its source before writing a line. Never use a translation.
- **The director's script, not prose.** One clause per line, blank line between
  beats, `[speaker]` tag to switch voice. Each newline is ~1 s of silence — that
  silence is the rhythm. Aim 8,000–10,000 chars / 250–300 lines for 20 minutes.
- **Only two Thai voices** (`th-TH-NiwatNeural`, `th-TH-PremwadeeNeural`). Build a
  cast by varying rate/pitch; never push rate past about −20%.
- **Timing from boundary events, never a character estimate.** Thai voices emit
  `SentenceBoundary`. Concatenate the boundary texts, keep each character's start
  time, then `find()` each script line (matched 108/108). A chars/sec estimate was
  wrong by up to 2×.
- **Audio targets −14 LUFS**, true peak ≤ −3 dBFS. `loudnorm` must run two-pass
  (measure, then encode with the measured values, `linear=true`). Single pass
  missed by ~1 LUFS.
- **Video is 1920×1080, `yuv420p`, `color_range=tv`.** JPEG decodes as
  `yuvj420p` (full range) — convert with
  `-vf "scale=in_range=full:out_range=tv,format=yuv420p" -color_range tv`, or
  levels wash out.
- `-vsync vfr` with `-r 25` is a hard error; use `-fps_mode cfr -r 25`.
- Never pad by renaming an intermediate (`out.padded.wav` → `out` replaced an mp3
  with a 56 MB WAV). Fold padding into the same encode (`apad=pad_dur=<sec>`).
- Media blobs are gitignored; they are regenerable. Fonts, images, timings and
  scripts are committed.

## Zero-cost OS

- Standard library only. `python -m engine.run`.
- `paid_providers_allowed: false` in every provider block — keep it.
- Respect source terms and rate limits. No fake reviews, engagement or spam.
- Publishing stays a manual approval stage until platform rules are verified.
- All runs write logs and structured JSON under `data/`.

## Documentation and memory

- `AGENTS.md` at the repo root is the instructions file any agent reads.
- `.openhands/memory/MEMORY.md` is the durable index; daily logs (`YYYY-MM-DD.md`)
  hold detail. Keep the index small (aim under ~6000 chars), move long detail to
  the logs, and record what was expensive to learn — root causes, environment
  quirks, decisions and their reasons.
- Never record secrets or credentials.
- Write clean code with minimal comments. Comment only genuinely unintuitive
  things (a non-obvious invariant, a workaround, a subtle ordering requirement).
  Do not narrate the diff or restate the code.
