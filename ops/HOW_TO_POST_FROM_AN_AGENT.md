# How an agent posts to a channel with no human and no browser

This is the answer to "the AI still cannot post". The grant was never missing:
this account already holds a working refresh token for all four channels. What
was missing is that `scripts/yt_auth.py` in `ai-content-lab` only looked for a
token **file** on disk and exited when it found none.

## The one thing that was wrong

`yt_auth.py` did this:

```python
if not os.path.exists(TOKEN_PATH):
    sys.exit(f"No saved token at {TOKEN_PATH}. Run scripts/yt_auth.py first.")
```

So an agent session carrying `YT_CH2_REFRESH_TOKEN` in its environment could not
use it. That is the whole bug.

## What the fix does

`scripts/yt_auth.py` now:

1. Collects every refresh token the environment offers — `YT_<SLUG>_REFRESH_TOKEN`,
   `YT_CH<N>_REFRESH_TOKEN`, a `YT_CHANNEL_TOKENS` JSON blob, then the generic
   `YT_REFRESH_TOKEN` / `YOUTUBE_REFRESH_TOKEN`.
2. When more than one exists, asks Google which channel each belongs to and picks
   the one matching the channel being published. A token for the wrong channel is
   never used, and nothing has to be configured by hand.
3. Writes it to `~/.config/content-lab/yt_token_<slug>.json` (mode 600), so the
   rest of the pipeline is unchanged.

Two further defects were fixed at the same time:

* **`invalid_scope` on refresh.** The account-wide tokens carry the full
  `https://www.googleapis.com/auth/youtube` scope. Refreshing while naming the two
  narrow scopes made Google reject the refresh. Refresh now sends no scope.
* **`yt_publish.py` refused an explicit `--privacy private`.** Its guard was
  `a.privacy != "private"`, so passing `--privacy` changed nothing, even though
  its own error message told you to pass it.

Also: `DEFAULT_BASE` was a frozen pod hostname in `publish_youtube.py`,
`post.py`, `mcp_server.py` and `build_api.py` — the same class of bug as the
redirect URI. It now follows `$RUNTIME_ID`.

## Verified, with a real upload

```
$ python3 ops/yt_publish.py --ch ch2 \
    --video /tmp/ep_ch2/episode_1080p.mp4 \
    --title "..." --desc-file /tmp/ep_ch2/ready/description.txt \
    --tags-file /tmp/ep_ch2/ready/tags.txt --category 27 --privacy private
uploading episode_1080p.mp4 (384.8 MB) to ch2
HTTP 200
video id r353LQ45JSg  privacy private  publishAt -
https://youtu.be/r353LQ45JSg
```

Then on the channel: ch2 `Farmmer` listed 11 uploads, the newest being
`เหนื่อยทั้งวัน แค่อยากให้ใจได้พัก — ธรรมะก่อนนอน`, private, 12:36.

## Reproduce it on a fresh pod

```bash
python3 ops/yt_auth.py videos ch2        # reads YT_CH2_REFRESH_TOKEN from the env
python3 ops/yt_publish.py --ch ch2 --video FILE \
    --title "..." --desc-file DESC --privacy private
```

`ops/yt_publish.py` reads the token straight from the environment; it never needed
the token file. The token file only matters for the `ai-content-lab` rail.

## The pipeline patch

The change to `ai-content-lab` could not be pushed from this account (the
`GITHUB_TOKEN` here is `aerismusic8-alt`, which has no write scopes and 403s on
push). It is committed locally and saved here as a patch:

```
ops/patches/ai-content-lab-let-ai-post.patch
```

It is a plain `git diff` against `f8dd287` (the tip of `main`), **not** a mailbox
patch, so apply it with `git apply` — `git am` fails with "Patch format
detection failed". On a machine that can push:

```bash
cd ai-content-lab
git checkout -b fix/ai-can-post
git apply /path/to/ai-content-lab-let-ai-post.patch
git commit -am "Let the AI post from an environment token"
git push origin HEAD:refs/heads/fix/ai-can-post
```

Verified: `git apply --check` passes on a fresh clone of `main`, and the applied
tree resolves all four channels (`yt_auth.py --check` per channel).

## Never do

* Do not invent a token or copy one into the repository. The environment supplies
  it; the file is mode 600 and gitignored.
* Do not map `YT_CH<N>` to a channel by position in `channels.json`. `YT_CH2` is
  ch2 (Farmmer, `UCM3QO5L_pmj34n1JVlbhh-w`). Resolve by channel id, as the fix does.
