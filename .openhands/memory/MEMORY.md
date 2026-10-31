# MEMORY — index

**How to use this file.** This is the injected index, kept small on purpose (the
prompt truncates a long one and the *oldest* text is lost first). It holds only
rules, roles and pointers. Full detail lives in `MEMORY-ARCHIVE.md` (repo root,
~100 KB — every memory ever written) and the daily logs next to this file. When
something here is stale, fix it here and push detail down to the archive.

**Maintenance rule.** Add new durable facts as *short* lines. When this file
grows past ~8 KB, fold the oldest sections into `MEMORY-ARCHIVE.md` and leave a
pointer. Never let the index exceed the budget — a truncated index silently
deletes the rules at the top, including the two below.

## Roles and method (K, 2026-10-31)

- **K = ผู้มีอำนาจตัดสินใจสูงสุด (Final Authority).** Every standing rule is K's.
- **AR = me.** I administer **ทุกอย่างแทน K ได้ทั้งหมด** — all of K's work, in K's
  place: decide, execute, report; no per-step approval. When I must choose, I pick
  the option that satisfies K's rules and say what I chose and why.
- **Method: PCSEV, every task — P**roblem, **C**ause, **S**olution, **E**xecute,
  **V**erify. State each step. Do not skip to Execute.

## 🔴 กฎถาวรข้อที่ 1 (K): ฟรีเท่านั้น — free only

Everything must be 100% free. A paid API, subscription or credit pack is out, not
a trade-off. Free routes only: login-only web apps driven through headful
Chromium (Gemini web, Flow Music), open APIs, self-hosted tooling.
**The agent must never type a password** — drive the browser K has signed into.
K's related rules: **AUDIO FIRST** (retention is the sound, not the picture);
delete the duplicate and the worthless, never archive; K reviews a channel's
first work; never rename a channel without K's approval.

## What this project is (K's goal)

K: "เราไม่ได้เป็นคนสร้างช่อง เราสร้าง ai openhands นี่คือเป้าหมายของ k" — the
deliverable is **the agent**, not a hand-built channel, built from free
generative-AI cloud tools. Scope = **4 channels** (spec 2026-10-23: ch1 series/
drama, ch2 dhamma, ch3 3D anime, ch4 record label). Two standing goals in
`AKATH_CORE/CANONICAL_TASK_REGISTRY.json` must never be closed as ordinary tasks:
a Roblox game anyone can enter and play, and real revenue from it.

- Channel registry + tokens + rail: `ops/` (`yt_auth.py whoami|videos`,
  `yt_publish.py`, `yt_branding.py`, `ax_channels.json`). **`ops/` is missing from
  this clone** — it lived in a sibling checkout and the vault. Restore path below.
- ch3 `@AERISMusicTH` `UCm44BjAn03ruOF-WaA3ZRww` is the revenue goal: pass
  YouTube's monetization threshold (**1,000 subs AND 4,000 watch-hours/12 mo**,
  or 1,000 subs AND 10M Shorts views/90 days). Free lever = long-form volume
  (`compile_album.py`; a 60-min compilation earns 1 h/view vs 3 min for a song).
  YouTube quota: 10,000 units/day, 1,600/upload → ~6 uploads/day.
- **The working pipeline is `aeris938-1/`** (Thai story → karaoke episode). The
  older `music938-1/` path is documented in the archive.

## Environment facts that keep costing time

- **A pod recycle is the recurring failure, not quota.** It kills the cloud
  desktop, running jobs, `$HOME`, `/tmp` and pip packages. **Only `/workspace`
  survives.** Never keep state in `$HOME` or `/tmp`.
- **Chromium CDP dies after a recycle** on a stale `SingletonLock`. Clear
  `Singleton*`/`DevToolsActivePort` and relaunch; keep `--remote-allow-origins=*`
  or every CDP websocket 403s.
- **Write access:** sandbox `GITHUB_TOKEN` is read-only (push 403). `~/.config/aeris/`
  is gone (overlay). PC1 holds a writable classic PAT — `scripts/push-via-pc1.sh`.
- **Sandbox proxy** blocks `POST`/`PATCH` to `www.googleapis.com` (bare 404 with
  `Server: HTTPServer2`); `GET`/`PUT`/`DELETE` pass. DELETE must carry no body.
- **`multiget-playability-status` reports the caller, not the game** — any probe
  that returns the same value for a famous working thing is measuring itself; put
  a control in the same call.
- **Roblox:** `BUILD_REF` lies — the built tree always comes from the
  `ax-arena-roblox-game` branch. Do not trust a URL: confirm the path exists in
  the provider's own spec before blaming a credential.

## Recovery

- **Sandbox died? Read `ops/AX_RECOVER.md` first** — do not re-learn it.
- Durable vault: `$AX_VAULT_BOOTSTRAP` → `ops/ax_vault.py`, read KV key
  `axvault:readme` first.
- If `ops/` or a daily log is missing from this clone: `MEMORY-ARCHIVE.md` here
  plus the vault are the restore sources.
- Full detail for anything above: `MEMORY-ARCHIVE.md`, then the daily logs
  (`2026-10-27.md`, `2026-10-28.md`, `2026-10-31.md` and earlier in the archive).

## Where the work stands (2026-10-31)

- **ch3 is the active channel.** Song 01 is live: full song `ASuxGEvJBlw`,
  karaoke `SWS1vJJgkow`, three hook Shorts, playlist `PLKlARHtRpKkI`. `release.py
  --next` uploads **private by default** (needs `--public`) and records
  `public: false` even after a later `videos.update` — correct the ledger by hand.
  `work/release-state.json` is tracked and is the only record of what is up; a
  clone that loses it re-uploads duplicates.
- **HOLD LIFTED 2026-10-30** — K: "อนุมัติ ดำเนินการแทน K", AR acts on K's behalf.
- Known-broken: song 01 is 178.7 s vs the 210 s floor (one red test, real).
- Detail: `2026-10-31.md` and the archive appendix.
