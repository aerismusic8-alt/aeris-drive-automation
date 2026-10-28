# Push status — resolved

## Pushing works now, through PC1

The four commits listed below were pushed long ago; they are in `main`. What was
blocked was *further* pushes, because the sandbox token is read-only.

- The sandbox `GITHUB_TOKEN` is a **GitHub App installation token** with no write
  scope. `x-oauth-scopes` is empty and `allows_permissionless_access=true`, so
  every push returns 403. `GET /repos/...` reporting `push: true` is the **user's
  role**, not the token's scope — do not trust it.
- The App key that would mint a write token lived at `~/.config/aeris/gh-app.pem`,
  on the ephemeral overlay. It is gone in a fresh pod, and `ax_vault.py` excludes
  `.pem`/`.key` by design.
- **PC1 holds a classic PAT that can write.** So the sandbox hands the commits to
  PC1 and PC1 pushes.

```bash
./scripts/push-via-pc1.sh          # bundle -> PC1 -> git push -> prints remote SHA
```

Verified 2026-10-28: `0001ef8d..90da7a80` then `90da7a80..e111653e`, both
`main -> main`.

## The commits that were once waiting

All four are in `main` and on `origin/main`:

```
9e27393 aeris938-1: generate the music bed automatically from the story's MOOD line
ee449b5 aeris938-1: second story, and session findings in memory
5149c65 aeris938-1: treat flowmusic.app as third-party, fix driver errors
46e4d05 aeris938-1: Thai story -> karaoke episode pipeline
```

The `aeris938-1-pipeline` branch is obsolete; work happens on `main`.
