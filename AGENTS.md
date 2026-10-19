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

## Shipping to Roblox

The live place can lag the branch in two different ways, and both look the same
to a player: "the game is still the old game". Check them in this order.

1. **Was a version published for this commit?** Open the latest
   `AX PC1 Roblox Publish` run and read `HEAD is now at <sha>` plus
   `PUBLISHED_VERSION`. If the SHA is old, the build used a stale ref.
2. **Is the experience playable at all?** A version can be published and still
   be unplayable. Roblox keeps a new experience private until the account
   holder submits the Maturity & Compliance questionnaire. Query
   `https://games.roblox.com/v1/games/multiget-playability-status?universeIds=<id>`
   and expect `isPlayable: true`. `ContextualPlayabilityUnrated` means the
   questionnaire is outstanding, and only the account owner can fix it.

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
  `Enemies.scale().name`. `Text.enemyName` maps those English names.
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
