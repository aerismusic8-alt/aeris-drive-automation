# Moving AX between accounts, and the GitHub repo question

Answers K's 2026-10-24 question: should we create a repo, will it hit limits, does
it help when the session changes, and can the work move to another account.

## 1. Account migration — solved

The KV vault is **account-scoped**: it cannot follow K to another OpenHands account
by itself. So the vault ships a portable bundle.

```bash
# on the account you are leaving
python3 ops/ax_vault.py export /tmp/ax-migrate/knowledge.tar.gz

# carry that file any way you like (repo, drive, email to yourself, paste)
# then, on the account you are moving to:
python3 ops/ax_vault.py import /tmp/ax-migrate/knowledge.tar.gz
python3 ops/ax_vault.py restore /workspace/project
```

Measured: the whole knowledge set is **41 files, ~320 KB** — small enough to move by
hand. The bundle is a plain tar.gz plus a `.manifest.json` carrying the file list and
the sha256; `import` refuses a bundle whose hash does not match. Round-trip verified:
export -> import -> restore returned all 41 files and the channel registry opened.

**What does not move with the bundle:** the credentials. Secrets are account-scoped
too. On the new account, re-create these secrets before anything will authenticate:

| secret | what it is |
| --- | --- |
| `YT_CLIENT_ID`, `YT_CLIENT_SECRET` | YouTube OAuth app |
| `YT_CH1_REFRESH_TOKEN` … `YT_CH4_REFRESH_TOKEN` | one per channel |
| `OPENHANDS_API_KEY` | needed by the vault itself |
| `PC1_MCP_TOKEN_2` | PC1 remote control (prefer `_2`; `PC1_MCP_TOKEN` hangs) |

The 4 channel automations are account-scoped as well. On a new account they must be
re-created; `ops/ax_channels.json` holds each one's name, channel key and cron.

## 2. The repo question — measured, not guessed

| question | measured answer |
| --- | --- |
| Can this account create a repo? | **No.** `POST /user/repos` -> `403 Resource not accessible by integration` |
| Can it push to an existing repo? | **No.** `git push` -> `403`; the token is `aerismusic8-alt`, GitHub App, **no scopes** |
| Can it dispatch a workflow? | **No.** `POST .../actions/workflows/{f}/dispatches` -> `403` (no `actions:write`) |
| Can it read Actions secrets? | **No.** -> `403` |
| Are the repos public? | **Yes** — all 3 are public |
| Actions minute limit? | **Not binding.** Public repos get free Actions; this repo already has **40,000 runs** |
| Repo storage limit? | Not binding. The knowledge set is ~320 KB against a 5 GB soft cap |
| Rate limit? | 4,999/5,000 REST calls remaining — not a concern |

**Conclusion: do not create a repo for the knowledge set.** A repo cannot be created
or written from this account, so a new one would be a dead end. The KV vault already
does the job a repo would do, and does it better: it is **readable and writable by the
agent with no token at all**.

## 3. Does a repo help when the session changes?

Only in one way the vault does not: a repo URL is a stable, human-readable pointer
that any session can `git clone`. But the vault already gives a session everything
without a clone, and the vault is the only one of the two the agent can **write**.

So: a repo is worth having **only once there is a write token**. The moment K supplies
a GitHub App key or a write-scoped token, the repo becomes useful as a second copy and
as the place to run CI. Until then, adding to it is not possible and should not be
planned around.

## 4. The write path that is actually broken

`scripts/gh-app-token.mjs` mints a write token from a GitHub App key, and
`.github/workflows/ax-gh-app-token.yml` stages that key from the repo secret
`AERIS_GH_APP_KEY`. That workflow has run 3 times and **failed every time at the step
"Check secret presence"** — the secret is not set (or was removed). Last attempt
2026-10-18.

So there are two routes back to GitHub write access, and K owns both:

1. **Re-add `AERIS_GH_APP_KEY` (and `AERIS_GH_APP_ID`) as repo secrets** on
   `aerismusic8-alt/aeris-drive-automation`, then run the `AX GitHub App Token`
   workflow. It mints a short-lived token on PC1.
2. **Hand over a write-scoped token** for the account, which the agent can use directly.

Until one of those happens, treat GitHub as read-only and keep all durable state in the
KV vault.

## 5. What to do when a sandbox dies

Read `ops/AX_RECOVER.md`. In short: find the automation named
`AX KNOWLEDGE VAULT (do not delete)` (secret `AX_VAULT_BOOTSTRAP` = its id), fetch
`axvault:tool` from its KV store, then `restore`. Then run
`python3 ops/yt_auth.py whoami --all` and `python3 ops/ax_channels.py` to pick the work
back up. Do not re-learn anything that is already in the vault.
