# AGENTS.md

Repository-specific notes for agents working in this repo.

## Layout

| Path | Purpose |
| --- | --- |
| `AKATH_CORE/` | Task registry and runtime state (`CANONICAL_TASK_REGISTRY.json`). |
| `AX_MASTER_BRAIN/`, `AX_PC_CONTROL/` | Windows automation scripts driven by GitHub Actions. |
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
via the REST API with the app token instead.

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

Publishing needs Roblox Studio, which is desktop-only. `roblox/PUBLISH-FROM-PHONE.md`
covers what can and cannot be done from a phone.

## Workflows

`runs-on: self-hosted` is a **Windows** machine (PC1, `DESKTOP-RGK6JKB`), so
`shell: powershell` is the correct default there. `ubuntu-latest` also works
for pure Linux jobs — the Luau test workflow uses it.

Do not commit binaries; `tools/` is gitignored on purpose.
