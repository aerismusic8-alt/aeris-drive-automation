# Recover AX knowledge after a sandbox dies

A sandbox is disposable. When this session ends, `/workspace`, the home
directory and every file in them are gone. The knowledge we built lives in the
**AX knowledge vault**, which is account-scoped and outlives the sandbox.

Read this first if you are a new session and the workspace looks empty.

## What survives, and what does not

| Store | Survives sandbox death | Writable | Holds |
| --- | --- | --- | --- |
| OpenHands KV store | yes | yes | the knowledge vault (the important one) |
| OpenHands secrets | yes | yes | YouTube tokens, `OPENHANDS_API_KEY`, `PC1_MCP_TOKEN` |
| OpenHands automations | yes | yes | the 4 channel agents + the vault anchor |
| OpenHands uploads | yes | yes | tarballs (metadata only; not readable back) |
| GitHub repo | yes | **no** | read-only for this token |
| `/workspace`, `~` | **no** | yes | everything else |

The GitHub token in this account is read-only: every push, branch create and
repo create returns 403. Do not plan around writing to GitHub.

## Recovery, in one step

The vault is anchored to a disabled automation named
**`AX KNOWLEDGE VAULT (do not delete)`**. The secret **`AX_VAULT_BOOTSTRAP`**
holds its id, and the secret's description repeats these instructions.

```bash
# 1. fetch the tool (it is stored in the vault before you need it)
python3 - <<'EOF'
import json, os, urllib.request
host = "https://app.all-hands.dev"
aid  = os.environ["AX_VAULT_BOOTSTRAP"]
def kv(key):
    req = urllib.request.Request(
        f"{host}/api/automation/v1/kv/{key}?automation_id={aid}",
        headers={"Authorization": f"Bearer {os.environ['OPENHANDS_API_KEY']}"})
    with urllib.request.urlopen(req, timeout=60) as r:
        v = json.load(r)["value"]
    return v["value"] if isinstance(v, dict) and set(v) == {"value"} else v
open("ax_vault.py", "w").write(kv("axvault:tool"))
EOF

# 2. restore the knowledge set
python3 ax_vault.py restore /workspace/project
python3 ax_vault.py list        # confirm what came back
```

If `AX_VAULT_BOOTSTRAP` is not injected into your session, find the anchor by
name in the automation list, or read the KV key `axvault:readme` under the
anchor id. The automation's own description carries the same instructions.

## After restoring

```bash
python3 ops/yt_auth.py whoami --all      # all 4 channels must authenticate
python3 ops/ax_channels.py               # the 4-channel table with goals
```

Then read `.openhands/memory/MEMORY.md` — it is the curated index of what we
learned, and it is inside the vault.

## The other docs, and what each is for

| file | read it when |
| --- | --- |
| `ops/AX_CHANNELS.md` | the task is about a channel — table, goals, clip recipe |
| `ops/AX_CHANNEL_DOSSIERS.md` | building channel content — positioning, formulas, 30-day plan |
| `ops/ax_channels.json` | you need the channel data machine-readable |
| `ops/AX_MIGRATION.md` | moving accounts, or asking about the GitHub repo |
| `ops/AX_RECOVER.md` | this file — a sandbox died |
| `.openhands/memory/MEMORY.md` | the index of everything learned |
| `.agents/skills/youtube-channel-builder/TOOLS.md` | you know the job, not the script |

## Moving to another account

The KV vault is **account-scoped**, so it cannot follow K by itself.

```bash
# leaving
python3 ops/ax_vault.py export /tmp/ax-migrate/knowledge.tar.gz
# arriving
python3 ops/ax_vault.py import /tmp/ax-migrate/knowledge.tar.gz
python3 ops/ax_vault.py restore /workspace/project
```

The bundle is ~320 KB and carries **no credentials**. On the new account, re-create the
secrets (`YT_CLIENT_ID`, `YT_CLIENT_SECRET`, `YT_CH1..4_REFRESH_TOKEN`,
`OPENHANDS_API_KEY`, `PC1_MCP_TOKEN_2`) and the 4 channel automations; `ops/ax_channels.json`
holds each automation's name, channel key and cron.

## Keeping it current

Pack again at the end of any session that learned something:

```bash
python3 ops/ax_vault.py pack      # re-pack the knowledge set
python3 ops/ax_vault.py bootstrap # refresh the self-recovery keys
python3 ops/ax_vault.py verify    # confirm the local tree matches the vault
```

`pack` refuses credentials. It skips any file whose name carries `token`,
`secret`, `credential`, `password`, `passwd` or `apikey`, and any file whose
bytes contain a real token shape. Do not weaken those rules — an earlier pack
captured a live token this way and it had to be purged.

## The rules this exists to enforce

1. **Knowledge outlives the sandbox.** If it is only on disk, it is already lost.
2. **Never store a credential in the vault.** Credentials belong in OpenHands
   secrets, which are injected, not packed.
3. **Do not re-learn what is already in the vault.** Restore first, then work.
4. **A fresh session must find this without being told.** That is why the
   anchor is a named automation and the secret name is self-describing.
