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
- Appearance is data, not code in the builder. A monster's body comes from
  `MonsterShapes`, a job's clothes and held weapon from `ClassLook`, and an
  item's icon from `ItemIcons`. All three are pure shared modules, so a new
  monster or item is a recipe entry and a test, not a change to `World.luau`.
- The HUD is built in code and read by `scripts/check-hud-wiring.py`. That
  script cannot run the HUD, so it reads the source: rename a node and it fails
  CI. Any new panel, button or label the client touches must appear there.

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
  `Enemies.scale().name`. `Text.enemyName` maps those English names. Loot is
  the exception: `Enemies.scale()` also carries `id`, and drop tables are keyed
  by that id (see below).
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

### The first field cannot kill, and later fields ramp up

- `Zones` carries a `lethal` flag per zone. `Meadow` is `lethal = false`; every
  later field is `lethal = true`. `Zones.isLethal(id)` is the only reader, and
  it answers `true` for an unknown id so a typo cannot make the game safe.
- `Combat.damageCombatant(target, amount, nonLethal)` floors health at 1 instead
  of 0 when `nonLethal` is set. The safe field still deals damage and still
  drains the health bar; it just cannot land the killing blow. Do not turn this
  into immunity, or the first field stops teaching anything.
- The server passes the flag at the one place a monster damages a player
  (`RunService.Heartbeat`). There is exactly one player-damage call site, so a
  new source of player damage must pass the flag too.
- Travel calls `applySpawnStats`, which heals to full. A player who grinds the
  safe field down to 1 HP and then walks into a lethal map would otherwise die
  to the first hit, which would make the safe field a trap.
- Difficulty is already ordered by `Zones.difficultyMultiplier` (1.0, 1.5, 2.4,
  4.0, 7.0), and `Enemies.scale` applies it. A test asserts the ramp is strictly
  increasing in difficulty, coin payout and unlock level, so the fields cannot
  silently flatten.

### Every standing panel folds away

- `Hud` has a `fold(panel, label)` helper and `Hud.applyFolds(collapsed)`. A
  folded panel shrinks to a 44px bar holding one caret button; the bar names the
  panel so the player knows what comes back.
- `applyFolds` records exactly which children were visible and restores only
  those, so unfolding does not force-show a badge that some other rule hid.
- Folding is idempotent: `entry.folded` guards the hide pass. Without it a
  second render would record an empty child list and unfolding would leave a
  blank panel.
- `applyFolds` runs at the end of `render`, because it hides children. Anything
  set visible earlier in the frame is subject to it, so a conditional element
  (the safe-field badge) must also check `Hud.isFolded` before showing itself.

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

### Loot is keyed by archetype id, never by display name

`Items.DROPS` is keyed by archetype id, but a monster's display name is not its
id: `Enemies.def("RockGolem", "Rock Golem", ...)`. Passing the display name into
`Items.rollDrops` misses the table and silently falls back to the generic
potions, so a rare monster becomes a recoloured common one and nobody notices.

- `Enemies.scale()` returns `id` alongside `name`; `World.spawnEnemy` stores it
  as `enemy.archetype`, and the kill path rolls `enemy.archetype or enemy.name`.
- Key every drop lookup off `id` in tests too. `roblox/tests/run.luau` has a
  "multi-word monster keeps its own drop table" test that pins the difference.

`Skills.hotbar` had the same shape of bug from the other direction: it iterated
the `ORDER` id list but read definition fields (`def.id`, `def.kind`) off the
strings, so it always returned an empty hotbar. Resolve an id to its definition
before reading any field. When a lookup can silently return "nothing", assert
the result is non-empty in a test, not just that it is well-formed.

### Map dressing has to keep the play space clear

`Scenery.luau` scatters props with a seeded RNG so every map looks the same on
every server. The seed comes from `Scenery.seedFor(placeId)`, and the scatter
takes a `keepOut` list of circles that must stay empty. The keep-outs are not
decoration: without them a tree lands on the arrival pad, or on the ring where
monsters spawn, and the map looks broken.

- `World.buildField` protects the arrival pad, the portal home, and sixteen
  points around the monster spawn ring (two radii, because `Fields.spawnPoint`
  alternates two radii). `buildTown` protects the spawn, the portals and the
  farm plot ring.
- Enemies are anchored and moved by `CFrame`, so a prop cannot trap one; the
  keep-outs exist so a monster never *looks* like it is standing inside a tree.
- The ring clearance is 8 studs, not 11. A wider ring carved the smaller maps
  hollow (Volcano fell from 43 props to 28). Check prop counts after any change
  to a keep-out radius.

### A Cone is not a shape you can build, and a Cylinder lies about its height

Roblox `Enum.PartType` has no `Cone`, and `SpecialMesh` is the deprecated way to
fake one, so `Scenery.taper()` stacks shrinking discs instead. WIRING 14 fails
the build if either reappears.

`Enum.PartType.Cylinder` runs along its **X** axis, so a cylinder rotated 90
degrees about Z stands upright and its height is `size[1]`, not `size[2]`. Any
code that reads `size[2]` as "height" reports a hem disc as a tall column sunk
into the ground. `roblox/tests/run.luau` has a `halfHeight` helper that accounts
for the rotation, and the ground test uses it. Do not inline the maths again.

### Flying monsters are data, not a special case

`MonsterShapes.hovers(id)` reads the hand-kept `HOVERING` set (bat, hornet,
elemental, wraith, wisp, sovereign). `World.buildEnemyModel` lifts those by
`HOVER_LIFT` studs on top of the lift already drawn into the recipe.

The set and the recipes must agree in both directions, so the "hovering set and
the recipes agree" test fails if a recipe is drawn in the air but unlisted, or
listed but drawn on the ground. When a recipe legitimately changes height,
update the set in the same commit or the gate stops meaning anything.

### A green publish does not mean the game is playable

The publish pipeline can report `status: PUBLISHED` with a real version number
and the place is still unplayable. A brand new experience has no content
maturity label, and Roblox hides unrated experiences entirely: the game page
reads "This experience is not accessible because it is unrated" and
`games.roblox.com/v1/games/multiget-playability-status` returns
`playabilityStatus: ContextualPlayabilityUnrated, isPlayable: false`.

There is no Open Cloud endpoint for this. The Universes API can update name,
description and social links, but the maturity and compliance questionnaire is
Creator Dashboard only. A human has to answer it once at
`create.roblox.com/dashboard/creations/experiences/<universeId>/audience`; the
experience then goes live on its own.

So when a publish "succeeds" but the game is unreachable, check playability
status before debugging the build. The upload was never the problem.

### Seeing the game without publishing it

An unrated universe cannot be joined, so the live place is not a way to look at
the code. Run the built place file on PC1 instead:

- `AX_PC_CONTROL/pc1-roblox-open.ps1` does it in two phases. `--task RunScript`
  runs `pc1-roblox-open-smoke.luau` in Edit mode, which requires every shared
  module, checks both entry points exist, and calls `World.buildWorld()` and
  asserts one town, five fields, real geometry, and a floor in each. Then
  `--task EditFile` opens the place and F5 starts Play mode, running the real
  server and client, and screenshots are captured across the run.
- `.github/workflows/ax-pc1-roblox-open.yml` drives it. The client opens a
  window, so the script runs from a scheduled task in the interactive user's
  session, the same way the foreground capture does.
- Edit mode does not execute `Script` or `LocalScript` instances, so the smoke
  test cannot prove the server loop or the HUD run. Play mode and the
  screenshots cover that.

Use only documented Studio flags. The undocumented `StartServer` and
`StartClient` tasks have changed behaviour between Studio versions, so a failure
there is indistinguishable from a failure in the game.

### The PC1 runner goes offline quietly

Work queued for the self-hosted runner sits in `queued` with no runner assigned
when PC1 is off or its runner service is stopped. There is no API to read runner
status with the integration token (`/actions/runners` returns 403), so the
signal is the queue itself: a job that has not been picked up in minutes, while
an earlier job on the same runner finished in seconds, means the runner is down
and someone has to start it on PC1.

## Reaching PC1 from a phone

There are two independent paths to PC1 and they do different jobs:

- The **GitHub Actions runner** carries queued jobs. Good for running scripts,
  useless for looking at the screen.
- The **MeshCentral agent** dials out to a MeshCentral server, which gives
  browser remote desktop, terminal and file transfer. This is the path that
  works from a phone, and it needs no inbound port because the agent connects
  out. That is why MeshCentral is the answer rather than RDP or a tunnel.

The repository already knows PC1's MeshCentral mesh: the adapter
`AX_PC_CONTROL/pc1-meshcentral-ax-dispatch.ps1` pins the mesh id and host. What
is missing on the control host is the `AKATH_MESHCTRL_*` environment, so
dispatch through MeshCentral is not configured here. Those values are per-host
environment, never committed.

When both paths are down the machine is unreachable by every path and needs a
person at the desk. `AX_PC_CONTROL/pc1-keepalive.ps1` exists to stop that: it
starts the runner service and the MeshCentral agent service when either has
stopped, and writes
`C:\AX-Runtime\evidence\pc1-keepalive-heartbeat.json`.
`install-pc1-keepalive.ps1` registers it as a scheduled task running as SYSTEM,
so it survives a reboot and needs no logged-on user. `-Once` does a single
repair pass by hand.

`AX_PC_CONTROL/pc1-remote-access-status.ps1` reports which paths are up, which
agent is installed, and what has to happen next. It reports only whether the
`AKATH_MESHCTRL_*` credentials are present, never their values.

There is a bootstrap problem worth knowing: the keepalive workflow needs the
runner, so it cannot recover a dead runner. The first install has to be done by
hand on PC1. After that the scheduled task keeps the machine reachable.
`AX_PC_CONTROL/REMOTE-FROM-PHONE.md` is the phone-facing guide.

### Tailscale is a path, not a door

This distinction cost real time, so it is written down. Tailscale gives an
encrypted route between machines. It does not give anyone a way to run a
command on a machine that has nothing listening.

Reachability and executability are separate questions:

- *Can a packet get to PC1?* Tailscale answers this. It is up on PC1 today.
- *Is anything on PC1 going to answer?* This is the question that matters,
  and Tailscale does not answer it. With the runner stopped, no MCP server
  installed and no SSH server enabled, PC1 is reachable and inert.

There is no supported way to make Tailscale start a process on a peer. The
admin console can toggle Tailscale's own features for a device, but not run
arbitrary code, and its SSH console needs Tailscale SSH, which brings us to:

**Tailscale SSH cannot run on Windows as a server.** Its server component is
Linux and macOS (open-source `tailscaled`) only. `tailscale set --ssh` on
Windows does nothing. Windows OpenSSH Server is the equivalent, with Tailscale
carrying the connection. Confirmed against Tailscale's own docs plus three
independent write-ups.

**Wake-on-LAN does not cross Tailscale.** WoL is a layer-2 broadcast and
Tailscale is layer 3, so a tailnet node cannot wake a sleeping PC1. Every
working setup sends the magic packet from an always-on machine already on the
same LAN. Without one, a sleeping PC1 needs a person.

The practical consequence: if PC1 is off, or on with nothing listening and no
one to run a command, no amount of network configuration reaches it. That is
a property of the situation, not a gap in the tooling, and saying so is more
useful than another workaround.

What does make PC1 durable, in order of value:

1. An always-on LAN device (a Pi, a NAS, a router) that can run WoL and hold a
   tailnet route. This removes the "person at the desk" requirement for good.
2. A remote-desktop agent that dials out and starts at boot, so it survives a
   reboot without anyone logging in.
3. The keepalive, which recovers a stopped runner or agent service as long as
   the machine is on.

### Driving PC1 through MCP

MeshCentral gives a *person* the screen. `winremote-mcp` gives an *agent* the
screen: it is a standard MCP server that runs on the Windows machine and exposes
screenshots, PowerShell, file transfer, GUI clicks, services and scheduled
tasks. Both are useful and neither replaces the other.

`AX_PC_CONTROL/install-pc1-winremote-mcp.ps1` installs it on PC1, stores the
auth key in `C:\AX-Runtime\winremote\` readable only by SYSTEM, and registers an
auto-start task. `AX_PC_CONTROL/ax-winremote-mcp.py` is the client; it was
tested against a live server (30 tools, `GetSystemInfo` returning real data).
`AX_PC_CONTROL/MCP-PC1-CONTROL.md` is the Thai guide.

Two things the client has to do carefully, both learned the hard way against the
real server:

- An unknown tool name comes back as `isError: false` with a plain
  "Unknown tool" string, so a typo looks like success. The client checks the
  advertised tool list first and exits non-zero instead.
- `Shell` and `FileWrite` are tier 3 and disabled by default. The default
  install therefore cannot run PowerShell; that needs `--enable-tier3`.

The server binds loopback only by design. A bearer token over plain HTTP on a
network is not protection, so reaching it from another machine needs a tunnel
with TLS. Do not bind `0.0.0.0` on a routed network.

There is a second bootstrap problem here too: the MCP server needs Python and a
hand install on PC1, and it cannot be driven until it is running. Installing it
through the Actions runner is possible once the runner is up, which is why the
keepalive comes first.

## Publishing the place needs no PC1, and the version number is the proof

The place is built and published entirely from a GitHub-hosted runner. Rojo
7.7.1 ships a Linux binary, so `scripts/build-place-linux.sh` produces the place
without Studio, and `scripts/publish-place-linux.sh` sends it to the Open Cloud
place-publishing endpoint as one HTTPS POST. Neither step needs PC1, the
Tailnet, or any self-hosted runner.

`versionNumber` in the POST response is the only reliable confirmation that a
publish landed, and it has a trap. Roblox deduplicates identical bytes: publish
the same binary twice and the second call returns the *previous* version number
with HTTP 200. That is documented behaviour, not an error (see the devforum bug
report `/t/open-cloud-publishing-api-no-longer-seems-to-increment-version-number-on-place/3820071`).
Watching for the number to increment therefore only proves anything when the
bytes changed. Verified in this repo:

- 514,656 bytes (no HUD change) -> versionNumber 10 on two consecutive runs
- 515,314 bytes (HUD build stamp added) -> versionNumber 11

The read-back endpoint `GET /universes/v1/{u}/places/{p}/versions` returns 404
for this key. Listing versions needs a read scope and the key carries only
write, so an empty or 404 response from that endpoint says nothing about whether
a publish happened. Do not treat it as a failure.

The HUD shows `Config.Version`, so which build is live can be read off a phone
without any API call. Bump `Config.Version` in `roblox/src/shared/Config.luau`
whenever a publish must produce a new version.

### The test gate has to live inside the pipeline on a feature branch

Dispatching a workflow that is not present on the default branch returns 404,
and `workflow_run` has the same restriction. Both are why a "tests pass, then
dispatch the publish" gate cannot work from `ax-arena-roblox-game`. The gate
therefore runs as the first job of `ax-arena-build-publish.yml`, with build and
publish depending on it. The dispatch left in `ax-arena-tests.yml` still points
at the PC1-bound workflow on purpose: repointing it would 404 here and turn the
tests workflow red for reasons unrelated to the tests.

### The experience name needs a scope the publish key does not have

Publishing a place does not name the experience. The place created by the first
publish had no name, so `https://www.roblox.com/games/<placeId>` redirected to
`/Title-Unavailable`. A page with no title cannot be opened from a phone, which
left the game effectively unreachable even though the publish worked.

`scripts/name-experience-linux.sh` sets it through the Universes API
(`PATCH /universes/v1/universes/{id}`), reading the name from `Config.GameName`.
It is wired into `ax-arena-build-publish.yml` as a best-effort job.

It returns `NAME_HTTP=404`. Setting a name needs `universe:write`; the key
carries `universe-places:write` only, and this endpoint answers 404 for a key it
will not accept, which is the same response as an unknown path. Confirmed on run
39267768716: `NAME_TARGET=AX Arena: Farm and Fight`, `NAME_HTTP=404`,
`NAME=SKIPPED reason=key_lacks_universe_write_scope_or_unknown_endpoint`, and
the public page still redirects to `/Title-Unavailable`.

Either add `universe:write` (Universes API, Read and Write) to the existing API
key, or set the name once in the Creator Dashboard. The first keeps it
automatic.

### What the key can actually do, measured

`scripts/probe-scopes-linux.sh` calls one read-only endpoint per capability and
reports GRANTED or DENIED next to the scope the docs name for it. Read-only
throughout, so it is safe against the live experience. Run 39271289227:

| Capability | HTTP | Verdict | Scope the docs name |
| --- | --- | --- | --- |
| universe_read | 200 | GRANTED | `universe:read` |
| place_read | 200 | GRANTED | `universe.place:read` |
| data_stores | 403 | DENIED | `universe-datastores.control:list` |
| secrets | 403 | DENIED | `universe.secret:read` |
| place_history | 403 | DENIED | `place-version-history:read` |
| team_create | 403 | DENIED | `legacy-team-collaboration:manage` |
| universe_stats | 404 | DENIED | `universe:read` |
| universe_config | 404 | DENIED | `universe:read` |
| badges | 404 | DENIED | `legacy-badge:manage` |
| game_passes | 404 | DENIED | `legacy-game-pass:manage` |
| developer_products | 404 | DENIED | `legacy-developer-product:manage` |
| localization | 404 | DENIED | `legacy-universe:manage` |
| publish_place | - | SEE_JOB | `universe-places:write` |

So the key carries `universe:read`, `universe.place:read` and
`universe-places:write`. That is enough to build and ship the place, and nothing
else.

The 404s are not missing endpoints. Roblox answers 404 for a key it will not
accept, the same status as a path that does not exist, so from outside the two
cannot be told apart. The 403s are the clearer signal, and they come from the
endpoints that do report scope failures honestly.

Two traps this table exists to prevent:

- `universe_stats` and `universe_config` both name `universe:read`, which is
  granted, yet both return 404. Those are legacy `develop.roblox.com` endpoints
  and the key is not valid for that domain at all. Reading a 404 here as "the
  scope is missing" would send someone to add a scope they already have.
- A GET can never show a write scope. Publishing is the only honest test of
  `universe-places:write`, which is why the publish job is the proof and not a
  probe row.

### Editing a key can silently drop the scope that ships the game

After the key was edited to add permissions, the next run (39271289227) changed
in two ways at once:

- `team_create` went 403 to 200, so `legacy-team-collaboration:manage` was
  genuinely added.
- `publish` went from success to `PUBLISH_HTTP=403` with
  `{"errors":[{"code":0,"message":"Scope not authorized."}]}`.

Publishing needs `universe-places:write`. Adding permissions to the key removed
that one, and nothing warned about it. The key gained scopes and lost the one
that ships the game.

Two consequences worth remembering:

- No probe can catch this in advance. The publish endpoint is the only endpoint
  that uses `universe-places:write` and it is a POST, so there is no read call
  sharing the scope that could report it. Publishing is the test.
- 403 on the publish endpoint has exactly one cause, so the script now prints
  the fix when it sees one rather than leaving a bare failure.

The official steps, from the place publishing guide: add **universe-places** to
Access Permissions and tick **Write** for the selected experience.

After a key edit, re-run the pipeline before believing anything else about it.
The measured table above is a snapshot, and a key edit invalidates it.

### A name is not enough; the universe must be public

Setting `displayName` succeeded and was confirmed by read-back, and the public
page still redirected to `/Title-Unavailable`. The name was never the whole
story.

The `Universe` resource carries `visibility: PUBLIC | PRIVATE`, and a private
universe is not reachable from its game page whatever it is called. This one was
private. `scripts/name-experience-linux.sh` now writes `displayName`,
`description` and `visibility` together and reads all three back, because
writing the name alone could never have fixed the page.

`EXPERIENCE_VISIBILITY=PRIVATE` reverses it. Making the game public is a launch,
and it is reversible from the same place it was made.

One more trap worth writing down, because it cost time here. The naming script
first patched `/universes/v1/universes/{id}`. The documented endpoint is
`PATCH /cloud/v2/universes/{universe_id}`, scope `universe:write`. The wrong
path returns 404, and 404 from this API reads exactly like a missing scope, so
the failure looked like a permission problem and sent someone to add a scope
they may already have had.

The way to tell a wrong path from a missing scope is to send a throwaway key:
the wrong path answers 404, the right path answers 401 Invalid API Key. A 404
that survives a bogus credential is a path problem, not a permission problem.

### Some things cannot be done by API at all

Roblox lists these as not exposed through any REST API, so no scope unlocks
them and no amount of automation will either. They need the Creator Dashboard:

- Daily and monthly active users, and engagement analytics
- Revenue breakdowns, earnings reports and payout history
- Moderation history, content review status and appeals
- Experience ratings and review management
- Team Create collaborator permissions (Studio)
- Marketplace fee and tax settings

Worth knowing before adding scopes: for these, scopes change nothing.

### Scopes to add, if the key should manage more than the place

The full official list lives at
`https://create.roblox.com/docs/cloud/reference/scopes` and per-feature pages at
`https://create.roblox.com/docs/cloud/reference/features/<feature>.md`. Names
below are taken from those pages, not guessed.

| What it unlocks | Scope |
| --- | --- |
| Experience name, description, playability, social links | `universe:write` |
| Read and write player data (the game's saves) | `universe-datastores.objects:read`, `universe-datastores.objects:write` |
| List and inspect data stores | `universe-datastores.control:list`, `universe-datastores.control:create` |
| Read and roll back place versions | `place-version-history:read`, `versions:rollback` |
| Upload icons, thumbnails, models, audio | `asset:write`, `asset:read` |
| Read thumbnails (confirm the icon actually rendered) | `thumbnail:read` |
| Restart servers after a publish | `universe:write` (`:restartServers`) |
| Badges | `legacy-badge:manage` |
| Game passes | `game-pass:read`, `game-pass:write` |
| Developer products | `developer-product:read`, `developer-product:write` |
| Analytics, DAU and retention | `universe.analytics:read` |
| Run Luau inside a live server (read or set state without a deploy) | `universe.place.luau-execution-session:read`, `universe.place.luau-execution-session:write` |
| Ban and unban players | `universe.user-restriction:read`, `universe.user-restriction:write` |
| In-experience notifications | `user.user-notification:write` |
| Configs, feature flags and rollout | `universe:read`, `universe:write` |
| Secrets used by the experience | `universe.secret:read`, `universe.secret:write` |
| Per-place settings and playability | `universe.place:read`, `universe.place:write` |

A key is capped by its target restrictions as well as its scopes: the selected
resources limit what the scopes can act on, so the experience has to stay
selected for any of the above to apply.
