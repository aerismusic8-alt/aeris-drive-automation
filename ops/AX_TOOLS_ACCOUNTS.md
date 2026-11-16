# AR — tools and accounts it uses (single inventory)

The answer to K's request (2026-11-16): *what tools and accounts does AR use, and
which of them can AR open by itself?* Everything here is **free** (Rule #1).

Statuses were read from the repo and the live APIs on 2026-11-16, not copied from
an old note. A tool is listed with the one-line purpose from its own docstring.

## Accounts

| Account | Identity | Opened by | Status |
| --- | --- | --- | --- |
| **AR mailbox** | `araeris4770d7@fldubai.com` (mail.tm) | AR (`ops/ar_identity.py`) | active |
| **Nostr** | `npub15km3dw0xx8kp0tazwslj3a4dr9xcqep39jhjwxnxwpvlx8mnapkq29ftuw` | AR (keypair, no signup) | active — live release rail |
| **Telegraph** | `AERIS Music` | AR (`createAccount`, no captcha/phone) | active — search-indexable pages |
| **Bluesky** | — | — | **blocked** — server verification |
| **AR Google Account** | — | K taps the QR once | blocked on `crossflowverification` |
| **YouTube ×4** | `@tatagenxgeny`, `@farmmer-n9t`, `@aerismusicth` ⭐, `@kongkeatpratumma` | K's account `aerismusic8@gmail.com` holds the 4 tokens | tokens account-scoped |
| **Facebook Page** | AERIS Music (Meta Graph API) | K | posting paused pending `FB_PAGE_TOKEN` |
| **TikTok** | `@aeris.music4` | K | Content Posting API; unaudited → `SELF_ONLY` |
| **Shopee Affiliate** | `navintas` | K | onboarded |
| **GitHub** | `aerismusic8-alt` | K | App token (writes) + classic `workflow` token |

The only surfaces **AR opens entirely by itself** are the mailbox, Nostr and
Telegraph. Everything else needs K once (a credential, a phone, or an approval).

## Tools (`ops/`)

Grouped by what they do. Every file lives in `ops/`.

### Free media — pictures, footage, music

- `stills_rail.py` — Wikimedia + Openverse + NASA + Cleveland/Art Institute (CC0/PD).
- `footage_rail.py` — Commons video (webm 1080p/4K) + Openverse audio (Jamendo).
- `stock_kit.py` — build and ship the stills stock the 4 channels draw from.
- `poster_maker.py` — cinematic movie-poster covers.

### Audio + video build

- `audio_bed.py` — the audio-first episode rail (narration → loudnorm → ducked bed).
- `thai_tts.py` — Thai narration via `edge-tts` with its retry.
- `video_build.py` — stills into a calm long-form video, then mux the audio bed.
- `story_reel.py` / `post_story_reel.py` — render and post a Thai story Reel.
- `episode_meta.py`, `ax_make_episode.py`, `ax_audio_qc.py`, `serve_songs.py`.

### Publish + promote

- `yt_publish.py` — upload an episode to one of the 4 channels.
- `fb_graph.py` — post a Reel to the AERIS Music Page (Meta Graph API).
- `tiktok_api.py` — post a Short (official Content Posting API).
- `announce_releases.py` — announce new songs on AR's Nostr (live rail).
- `ar_telegraph.py` — publish a search-indexable page on AR's Telegraph.
- `publish_telegraph.py` — one Telegraph page per new song (live rail).
- `ar_promo_site.py` — generate and publish the landing page (GitHub Pages).
- `shopee_mint.py`, `social_cleanup.py`.

### Free AI advisors + search

- `pollinations_ask.py` — free, keyless text model.
- `duck_ask.py`, `gemini_ask.py`, `chatgpt_ask.py`, `ask_agents.py` — web advisors.
- `consult.py`, `consult10.py` — the consult gate before deciding.
- `websearch.py` — free web search + page reading (the no-quota Tavily replacement).

### AR identity + accounts

- `ar_identity.py` (mailbox), `ar_mail.py` (several free providers).
- `ar_nostr.py` (no-signup social), `ar_telegraph.py` (no-captcha publishing).
- `ar_accounts.py` (register), `ar_browser.py`, `login_vault.py`, `vault_session.py`.

### YouTube + analytics

- `yt_auth.py`, `yt_branding.py`, `apply_channel_art.py`, `set_avatar_studio.py`.
- `yt_list_videos.py`, `yt_monitor.py`, `yt_comment.py`, `yt_delete.py`,
  `yt_video_delete.py`, `yt_video_status.py`, `yt_public_scan.py`, `yt_quota.py`.
- `studio_read.py` (numbers the API hides), `heartbeat.py` (the green board).

### Infra, health, secrets

- `ax_vault.py` (durable KV), `ax_secrets.py`, `ax_setup.py`, `ax_readiness.py`.
- `k_free_status.py`, `surface_status.py`, `session_guard.py`, `token_heartbeat.py`.
- `risk_audit.py`, `memory_guard.py`, `memory_search.py`, `fb_relogin.py`.

### PC1 + cloud desktop control

- `pc1mcp.py`, `pc1_live.py`, `pc1_uia.py`, `pc1_desktop.py`, `check_pc1.py`.
- `live_view.py`, `live_view_server.py`, `desk_tab.py`.

## External services (free)

| Service | Use | Key? |
| --- | --- | --- |
| Wikimedia Commons | stills + **video** | no key |
| Openverse | stills + audio (Jamendo/Freesound) | no key |
| NASA, Cleveland, Art Institute | stills (CC0/PD) | no key |
| Jamendo | full CC music tracks | no key |
| Telegraph API | publish pages | no captcha/phone |
| Nostr relays | social posts | keypair only |
| pollinations.ai, Duck.ai | free text AI | no key |
| Gemini / ChatGPT web | free AI | login (cloud desktop) |
| `edge-tts`, `ffmpeg`, sfizz, Luau | narration, video, instruments | local, free |
| GitHub Releases + Pages | delivery | free |
| ntfy (`ax-ar-aeris-9f3k7q`) | alerts | free |
| YouTube / Meta / TikTok / Shopee APIs | publish + affiliate | K's tokens |

## Delivery

Finished work reaches people through **GitHub Releases** (tag `media-938`) and
**GitHub Pages** (`farmmer938-lgtm.github.io/aeris-store/`). Free file hosts were
re-tested 2026-11-16: `tmpfiles.org` uploads but serves an HTML page (preview, not
a download); catbox/litterbox/uguu/0x0/file.io reject this host. Releases + Pages
remain the working route.
