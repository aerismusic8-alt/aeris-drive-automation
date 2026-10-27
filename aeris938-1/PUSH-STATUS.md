# Push status — branch `aeris938-1-pipeline`

## Blocked: the token in this pod is read-only

The four commits are ready locally but could not be pushed. Verified, not assumed:

```
$ git push https://x-access-token:$GITHUB_TOKEN@github.com/aerismusic8-alt/... aeris938-1-pipeline
remote: Permission to aerismusic8-alt/aeris-drive-automation.git denied to aerismusic8-alt.
fatal: ... The requested URL returned error: 403

$ curl -X POST .../git/refs -d '{"ref":"refs/heads/aeris938-1-pipeline","sha":"<40-char sha>"}'
{"message": "Resource not accessible by integration", "status": 403}
```

Notes on the diagnosis:

- `GET /repos/...` reports `permissions: {admin: true, push: true, ...}`, but that
  is the **role of the user**, not the scope of the token. Do not trust it.
- `x-oauth-scopes` is empty and `allows_permissionless_access=true`, so this is a
  **GitHub App installation token**, not a PAT.
- `scripts/gh-app-token.mjs` cannot mint a write token here: no key exists at
  `/workspace/.secrets/gh-app` or `~/.config/aeris`. The AGENTS.md instructions
  assume a key that this pod does not have.
- No other GitHub secret is present in this environment.

So the push needs a credential that lives outside this pod.

## Commits waiting

```
9e27393 aeris938-1: generate the music bed automatically from the story's MOOD line
ee449b5 aeris938-1: second story, and session findings in memory
5149c65 aeris938-1: treat flowmusic.app as third-party, fix driver errors
46e4d05 aeris938-1: Thai story -> karaoke episode pipeline
```

`origin/main` (`0001ef8`) is an ancestor of all four, so this is a clean
fast-forward — no rebase needed.

## How to finish it

Any one of these works.

**A. From this pod, with a writable token.** Mint a GitHub App token that has
`contents: write` (or supply a PAT), then:

```bash
cd /workspace/project/18444af13cb4492dbf62e607001170f1/aeris-drive-automation
git push "https://x-access-token:$WRITABLE_TOKEN@github.com/aerismusic8-alt/aeris-drive-automation.git" \
  aeris938-1-pipeline
```

**B. From a machine that already has the app key.**

```bash
node scripts/gh-app-token.mjs --export    # then use the token as above
```

**C. Apply the patches anywhere.** A bundle and a patch series are in `dist/`:

```bash
git fetch /path/to/dist/aeris938-1-pipeline.bundle aeris938-1-pipeline:aeris938-1-pipeline
# or
git am dist/patches/*.patch
```

`dist/` is gitignored because it holds binaries; copy it out of the pod before it
recycles.

## Opening the PR

Per AGENTS.md, `create_pr` uses the read-only token and returns 403. Once the
branch is on the remote, open the PR with the REST API using a writable token:

```bash
python3 scripts/gh-api.py POST /repos/aerismusic8-alt/aeris-drive-automation/pulls \
  --body-file pr.json
```

with `{"title": "...", "head": "aeris938-1-pipeline", "base": "main", "body": "..."}`.
