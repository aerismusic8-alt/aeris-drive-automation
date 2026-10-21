# AGENTS.md

Repository-specific notes for agents working in this repo.

## How to work on this repository

Five rules, each one paid for by a mistake made here. They are not style
preferences; each has a failure behind it.

**1. Measure, do not assume.** Before reporting what a credential, an endpoint or
a permission can do, ask the live system and report what came back. A key was
assumed to have `universe:write` for several sessions; the probe showed it never
had it, and the assumption had been shaping decisions the whole time.

**2. Never report success from a status code alone.** On this API a 200 means the
request was accepted, not that anything changed. Sending `visibility` on the
universe PATCH returned 200 and changed nothing, and the pipeline went green
while the game was unreachable. Read the field back and compare it, or the
failure hides inside a success.

**3. A wrong path and a missing permission look identical.** Both answer 404 on
this API. To tell them apart, send a throwaway credential: a wrong path still
answers 404, a real path answers 401. A 404 that survives a bogus key is a path
problem. This cost an hour and sent someone to add a scope they may already have
had.

**4. Prove a check can fail before trusting it.** A check that has only ever
passed carries no information. Every failure path in `check-live-state-linux.sh`
was exercised on purpose, and doing that found a real hole: a redirect to
`/request-error?code=404` was reading as a pass.

**5. Check the thing the player sees.** A green pipeline is not a playable game.
Publishing a place, naming an experience and making a universe public are three
separate facts. `scripts/check-live-state-linux.sh` runs last on every publish and
asks the player's questions from outside, with no credential for the public ones.

The order matters: measure first, then change, then verify from outside, then
write down what was learned. Everything below is the accumulated result of
working that way.

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
- **Panel geometry lives in `src/client/HudLayout.luau`, never in `Hud.luau`.**
  Most players are on a phone, and a panel measured against the 1280x720
  reference does not fit a 640x360 one. The module takes the viewport as an
  argument, so `tests/layout.luau` drives every device size without an engine.
  A new panel adds its width and height to the tables there, and the HUD asks
  `HudLayout.builtHeight` rather than hard-coding pixels. Do not centre a panel
  with a bare `(viewport - height) / 2`: that is what put the character sheet's
  close button off the top of the screen. Use `HudLayout.centredTop`, which
  pins a too-tall panel inside the safe area.
- Every monster needs a drop table of its own. A table-less monster still rolls
  the two generic potions, so it passes every check that only asks whether the
  drops are real items while identifying nothing. `Items.dropsFor` is keyed by
  archetype id, never by display name. Two tests in `tests/run.luau` guard this.
- The story spine is driven by events the server already produces, not by
  polling. A new objective kind is dead until some server path calls
  `questEvent(record, KIND, ...)`, so `check-hud-wiring.py` asserts each kind
  the spine uses has a call site. Adding a quest step means adding that event.
- `SaveSchema.serialize` is a second save path alongside the DataStore table.
  A new field must be added to both `serialize` and `migrate`, or it survives
  one path and not the other.

Run the tests before every push:

```bash
cd roblox && ../tools/luau/luau tests/run.luau
```

- **A Luau test file must fail loudly.** The standalone `luau` CLI exits 0 even
  when a script returns a non-zero number, so `luau test.luau || exit 1` never
  fires. A suite printed 20 failures and CI stayed green for weeks because of
  this. `TestRunner.finish()` raises when anything failed, which is what
  actually sets the exit code. A new suite must call `t.finish()` for the same
  reason; a suite that only prints a tally is not wired to CI at all.
- **A regression test must fail on the old code.** Before trusting a new test,
  put the bug back and watch the suite exit 1. Two tests written for the phone
  HUD passed against the broken layout until the naive centring was
  reintroduced and the -35 measurement showed up. A test that passes both
  before and after proves nothing.
- **The headless shim is the engine contract, not a stub.** When game code
  needs something the shim lacks, model the real behaviour (`script.Parent`
  resolves, `Workspace.CurrentCamera` exists) rather than editing the game to
  dodge the shim. The other direction hides a bug that only appears in Roblox.

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

## The game is AX Garden Legends, not the arena

The arena in `roblox/` was built and tested carefully and was not fun. The reason
is structural, and worth writing down so the same mistake is not repeated: an
arena is a game about *combat feel*, and combat feel cannot be verified by a test
suite or read off a diff. Every design decision was a guess, and the guesses did
not add up to something a person wants to play. The tests were green the whole
time, because "is this fun" is not a test that existed.

The replacement copies a loop that is already proven rather than inventing one.
The genre leader on Roblox sits at roughly 36 billion visits and a 90% rating
with no combat in it at all. Its loop is buy a seed, plant it, wait, harvest,
sell, and upgrade -- patience and collection, with one mutation roll per harvest
as the variance. The decisive property is that the whole loop is arithmetic on a
timestamp: it is fully testable with no engine, so it is possible to know whether
it works before a player sees it.

`roblox-garden/` is the live game. `roblox/` is the previous one, kept because
its test suites and its shim still run and still pass; it is not the thing to add
features to.

**The build and publish path must point at the game that is live.** For a while
it did not. Every script and workflow still read `roblox/`, so the pipeline
reported green, built the arena, and published the arena -- the garden was in the
repo and not in the game. The failure is invisible from the outside because the
publish really does succeed, on the wrong bytes. When a game is replaced, the
defaults in `build-place-linux.sh`, `publish-place-linux.sh`,
`name-experience-linux.sh`, `check-live-state-linux.sh` and the shipping workflow
are part of the replacement, not an afterthought. The one place the old name
lingers on purpose is the workflow's filename, because renaming a workflow whose
triggers are path-scoped to itself churns more than it fixes; the name it prints
is the garden's.

Rules that came out of the pivot:

- **Pick a loop with a verifiable core.** If the fun of a feature cannot be
  expressed as a number a test can check -- a ratio, a curve, a clamp, an
  ordering -- then building it is a guess. The garden's fun is measurable: does
  payout rise with patience, does a rare mutation stay rare, does an offline
  absence ripen a crop, does a dearer egg give a better pet.
- **Copy a proven loop, then change the items.** The genre is not the thing to
  innovate on. The seeds, mutations, pets and their numbers are where this game
  differs, and those are data in `Config.luau`, not code.
- **Check the tests against broken code, always.** Three real defects were found
  while writing the garden suite by putting the bug back and watching it fail:
  a coarse price rounding that gave two different seeds the same cost, a sell
  floor that paid one coin for a crop that no longer existed, and a flat pet
  ladder where an egg 1500x dearer bought a pet only 2x better. None of them
  would have been caught by reading the code.
- **A build verifier's markers must be identifiers that exist.** The PC1 build
  script greps the built place for markers to prove the code shipped, not just
  the instance names. When the verifier was retargeted at the garden, three
  markers (`growthSeconds`, `buildWorld`, `cropName`) did not exist in the garden
  sources and would have failed the build. Each marker was checked against a real
  `rojo build` of the garden before the change was trusted.

### The shim must not be kinder than the engine

`roblox/tests/RobloxShim.luau` is shared by both games' runtime suites. A shim
that is *simpler* than Roblox is worse than no shim, because it makes a test
pass on behaviour the real game does not have. Three of these were found and
fixed while bringing the garden runtime up, and each one had been silently
weakening the arena's suite too:

- **A remote payload is deep-copied on the way out.** The engine serialises a
  table across a remote, so the client never shares a table with the server. The
  shim used to hand the *live* save to the client, so a test that captured a
  payload and then watched the server mutate its own save saw the captured value
  change -- a test failing for a reason that cannot happen in Roblox. `FireClient`
  and `FireAllClients` now copy, skipping tables with a metatable (those are
  Instances, which really are passed by reference).
- **`Signal:Disconnect` actually disconnects.** It used to be a no-op, so a test
  that connected, disconnected, then fired still ran the dead handler. Connect
  returns a connection whose `Disconnect` removes the handler; `Fire` iterates a
  copy so a handler that connects or disconnects mid-fire cannot disturb the walk.
- **A missing child errors, it does not hang.** `WaitForChild` raises when the
  child is absent and nothing is scheduled to create it. A hang reads as a flaky
  timeout; an error names the missing remote.

Two more gaps that were not bugs but made the suite blind: `UIPadding` was not a
modelled class, and the harness never set `Parent` on the `Remotes` folder it
created, so a test walking up from a remote found nothing.

### A save is a table, not a JSON string

`SaveSchema.snapshot(save)` returns a deep copy of the save as plain data, and
that is what the DataStore is given -- the same shape the arena stores. The
snapshot matters: writing the live save would let the game mutate the record
after it was handed over. `migrate` still accepts a string, so a save written by
an older JSON build loads and is repaired.

The hand-rolled encoder must handle **integer keys**, because a garden's plots
are keyed by plot index. A string-only key sorter throws on any planted garden,
which is to say on every save a real player would ever write.

### Reintroduce every fixed bug

`roblox-garden/tests/reintroduce.py` puts each fixed defect back one at a time,
runs **both** garden suites, and fails unless the expected test fails. A test
that passes with and without the fix proves nothing. It regenerates the source
bundle inside the loop, because the runtime suite loads the generated bundle and
an edit to `src/` would otherwise have no effect at all. Run it after adding a
test that is meant to guard a fix.

Both garden suites are wired into `scripts/test-roblox.sh`, so the fast unit
suite (137 tests) and the runtime suite (37 tests) run with the rest of the repo.

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

Status as of the last check: `GuestProhibited`, not `ContextualPlayabilityUnrated`.
The questionnaire has been answered, so the game is reachable by logged-in
players and only guests are turned away. `isPlayable` still reads `false` for an
unauthenticated request, because that request is itself a guest; do not read it
as "the game is down". Check the page slug and the games API name alongside it,
which is what `scripts/check-live-state-linux.sh` does.

### `playableDevices` is not a field; do not chase it

`https://games.roblox.com/v1/games?universeIds=<id>` has no `playableDevices`
key. Reading it with a `.get()` default prints `None`, which looks like a
misconfigured place and is not: Brookhaven, one of the most played experiences on
the platform, prints `None` the same way because the key is absent there too. The
player-device setting lives in the Creator Dashboard and is not exposed by this
endpoint. If the device list needs changing, it is a dashboard edit, not an API
call, and the missing key is not evidence of anything.

### The tests never ran the game, so the game shipped broken

Every test in this repo loaded only the pure modules in `src/shared` through the
CLI's own `require`. `World.luau`, `init.server.luau` and `init.client.luau` --
the code that actually runs in Roblox -- were never executed. The suite passed
while the game was unplayable, because the failures were all runtime ones that
no text check and no pure-logic test can see.

`roblox/tests/RobloxShim.luau` is a headless stand-in for the engine. It
implements the parts of Roblox the glue touches -- `Instance` with children,
`Parent`, `FindFirstChild(name, recursive)`, class defaults and auto-created
signals; the services (`Players`, `RunService`, `ReplicatedStorage`,
`Workspace`, `Lighting`, `DataStoreService`, `MarketplaceService`); the
datatypes (`Vector3`, `CFrame`, `Color3`, `UDim2`, `TweenInfo`, the sequence
types); `Enum`; and `task`. Anything it does not implement raises a clear error,
so a new engine call is a loud failure rather than a silent nil.

`roblox/tests/runtime.luau` uses it to boot the real server, build the real
world, load the real client and join a real player. It is wired into
`scripts/test-roblox.sh` and the CI workflow, and the source bundle it needs is
generated by `scripts/gen-roblox-sources.py` (the standalone Luau CLI has no
`io`, so the sources are emitted as a Luau table).

Three bugs it found on the first run, all of which shipped:

- `World.buildWorld()` threw inside `Scenery`. `Scenery` is pure Luau and takes
  `{ x, y, z }` tables; `World` works in `Vector3`. It converted `centre` at
  every call but passed the arrival point straight through, so `arrival.x` was
  nil and the subtraction threw. The call runs at server start, before
  `PlayerAdded` is connected, so the whole server script died there: no remotes,
  no player handling, no stats. That is what "no systems at all" was.
- `pushPlayerState` passed `broadcastNow` to `Farm.snapshot`. That name is a
  local inside the heartbeat loop, so here it resolved to an undefined global
  and was nil; `Farm.secondsUntilReady` then did arithmetic on nil. Any player
  holding a crop threw their own state push.
- The state payload carried none of the character sheet the client reads
  (`attributes`, `class`, `skills`, `equipment`, `bag`, `sp`, `hotbar` and the
  rest), so the Stats, Skills, Job and Bag tabs rendered the client's empty
  defaults.

`Config.Codes` was also defined twice, and the second table replaced the first
wholesale, dropping `MaxAttemptsPerMinute`. Assigning the same key twice is
silent in Luau, so grep for a duplicate top-level assignment when a config value
reads as missing.

Two rules came out of this:

- When glue code and a pure module meet, convert the datatype at the boundary
  and pass the plain table in. `landmarkOpts` in `World.luau` does this now.
- A function must not read a local that belongs to a different scope. `--!strict`
  would catch this, but Rojo ships the source without typechecking, so nothing
  did. Only executing the code catches it.

When adding a new engine API to the glue, add it to the shim too. The shim is
deliberately not a Roblox emulator: it is the smallest thing that lets the real
code run, and it fails loudly on anything it does not know.

### A local declared below a closure is a nil global inside it

The skill bar was built to put a learned skill one tap away, because casting one
used to mean opening the character sheet mid-fight. Every button drew, the layout
test passed, and every tap threw `attempt to index nil with 'castSkill'`.

`Intent` is a local declared at the bottom of `init.client.luau`, after `render`
and the tab builders. The closures those functions connect run on tap, but they
are compiled where they sit, so `Intent` inside them is not the later local -- it
is the global, which is nil. A button that draws is not a button that works, and
nothing in a static read of the file shows the difference.

`Intent` is now forward-declared at the top of the file and assigned later, which
is the only shape that makes a closure see a table defined below it. When a
handler in this file calls something declared further down, forward-declare it
and check with a runtime test that actually fires the button, not just that it
exists.

### The screen can be too full for a feature that fits the design

The compact combat panel was 232px of a 360px phone screen, stacked. That was
fine until the skill bar needed the space above the attack button, and then the
bar measured off the top of the screen at `390 > 360`. The layout suite caught
it before a phone did.

The fix was not to shrink the bar. It was to reflow the three utility toggles
into one row, which frees 56px and still clears the 44px touch minimum. When a
new control does not fit, look at what is already on the screen before making the
new thing smaller. `COMBAT_COMPACT_HEIGHT` in `HudLayout.luau` is the number the
bar's room is measured against, so it and `COMBAT_COMPACT.panelHeight` in
`Hud.luau` must be changed together.

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

### A running runner can still be pointed at the wrong repository

`STATE=Running` plus a live `Runner.Listener` process is not proof that jobs
will run. A runner is registered for exactly one repository, and its service
name encodes which one:

```
actions.runner.<owner>-<repo>.<runner-name>
```

On PC1 the service was `actions.runner.farmmer938-lgtm-ax-ai-benchmark.PC1-MAIN`
while this repository is `aerismusic8-alt/aeris-drive-automation`, so the
service was healthy, the listener was alive, and every job for this repository
queued forever. The two owners are different accounts with different ids, and
the target repository no longer exists, so the runner has nowhere to connect.
`.runner` inside the runner folder holds the same `gitHubUrl`, and the folder
name is not predictable, so search for `.runner` rather than guessing paths.

A machine can hold several configured runners. When the service points at the
wrong one, the right one is often still on disk and can be started with its
`run.cmd`, which needs no token and no re-registration.

### A desktop-control server must run in the user's session

The winremote MCP server has to run as the logged-on user, not as SYSTEM. A
SYSTEM process lives in session 0, which has no desktop, so a screenshot returns
a black frame and the input tools act on nothing. This is worse than a crash:
the health endpoint answers and the server looks fine while being useless for
the one job it was installed for. Register the task with `-LogonType
InteractiveToken`, which needs no stored password and runs exactly when a
desktop exists.

Related: when a background task starts a server, redirect its output to a file.
Without that, a start-up failure leaves nothing to read and the only symptom is
a health check that never answers.

### GitHub's raw endpoint serves a cached copy for 5 minutes

`raw.githubusercontent.com` sends `cache-control: max-age=300`. A file fetched
within that window can be the previous revision, and a cache-busting query
string does not defeat it. This was observed directly: the GitHub contents API
returned the new 500-line script while the raw URL returned the old 494-line
one for the same branch and path. The symptom is a fix that is demonstrably
pushed and still not in effect, which reads as a code bug and wastes a round
trip to the person running it.

Pin the fetch to a commit SHA instead of a branch name:

```
https://raw.githubusercontent.com/<owner>/<repo>/<full-commit-sha>/<path>
```

A SHA cannot be stale. When handing a one-line fetch command to someone else,
always use the SHA and have the script print a version marker as its first
output, so the run itself says which build it is.

### PowerShell turns native stderr into a terminating error

With `$ErrorActionPreference = 'Stop'`, a native command that writes to stderr
raises a terminating `NativeCommandError` **even when it exits 0**. `pip` does
exactly this whenever it prints a dependency-conflict warning, which killed the
PC1 bootstrap mid-run and silently skipped every step after it. Check
`$LASTEXITCODE` instead, and wrap the call with a temporarily relaxed
`$ErrorActionPreference` when the output is only advisory.

### A dispatch-only workflow on a non-default branch never registers

This cost real time twice, so it is written down. GitHub registers a workflow
that lives on a non-default branch only when one of its triggers fires on that
branch. A file whose only trigger is `workflow_dispatch` is therefore never
registered, and `POST .../actions/workflows/<file>/dispatches` answers **404**
forever. It looks exactly like a missing file or a permissions problem, and it
is neither: `ax-pc1-tailnet-reach.yml` sat on a branch, pushed and present, and
returned 404 on every dispatch.

The fix is a `push:` trigger scoped to the workflow file itself:

```yaml
on:
  workflow_dispatch:
  push:
    paths:
      - '.github/workflows/this-file.yml'
```

The presence of any branch-firing trigger is what makes the file register; after
that `workflow_dispatch` works normally. Keep the push trigger narrow and make
the no-input default path read-only, so a push cannot start a write operation.

A second signal helps distinguish the two cases: compare a workflow that
dispatches (204) with one that does not (404) and check their triggers. The one
with `push` works.

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

### The shortest path is loopback, and it needs no tailnet

The winremote MCP server binds `127.0.0.1`, so only something already on PC1 can
call it. The self-hosted runner is on PC1, which makes it the shortest possible
route and removes every other dependency at once: no tailnet, no MeshCentral
server, no port forward, and no credential handed to anyone. This is the path
`AX_PC1_DESKTOP_CONTROL` uses.

It has one precondition, and it is the same one that breaks everything else: the
runner has to be alive. When the runner is down this path queues like the rest,
so it cannot be the recovery route. It is the normal route once the machine is up.

A remote-control client that reports screenshots as a byte count is useless, so
`ax-winremote-mcp.py` takes `--save-images DIR` and writes the PNG, reporting its
path. Note that servers vary in how they send image content: some emit an `image`
item, others serialise the same thing to JSON and send it as a **text** item. A
client that only handles the first case silently drops the screenshot, which was
observed against a real MCP server. Handle both.

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

### The channel that runs the other way, and why it is the one that works

Every path above needs something to already be working on PC1: a runner that is
alive, a MeshCentral agent that is registered, a tailnet that both ends have
joined. Each one ends the same way when it is missing, with K at the desk
running a command and pasting the output back, which is the thing to avoid.

So invert it. PC1 polls an endpoint this side hosts, runs whatever MCP tool call
it finds, and posts the result back. All traffic is outbound, so there is no port
forward, no tunnel, no tailnet and no inbound firewall rule, and nothing new to
arrange on the Windows side. The agent gets screen capture, PowerShell and file
transfer without anyone at the keyboard.

- `ax-rendezvous.py` holds the job queue and the results, token guarded, and
  writes every result to disk as it arrives so a restart does not lose them.
- `ax-pc1-worker.py` is the PC1 side. It polls, calls the local MCP server, and
  posts the result. It reports a failing job as a failure and keeps running.
- `pc1-install-reverse-channel.ps1` installs the worker as an auto-restarting
  task and turns on tier3.
- `test-reverse-channel.py` runs the real rendezvous, a real MCP server and the
  real worker and checks the whole path.

Six things this cost, worth not repeating:

- **The default tier set has no `Shell`.** Tiers 1+2 are screen viewing only, so
  an agent on the far end could watch but not act. Anything that means to control
  the machine needs `--enable-tier3`, and the test asserts `Shell` is present.
- **A task command line is public.** Any process on the machine can read it, so
  the channel token goes in a config file, not in the task's arguments.
- **PowerShell 5.1's `Set-Content -Encoding UTF8` writes a byte order mark**, and
  `json.load` rejects a leading BOM outright. This killed the worker on the first
  real run, before it ever polled, while the installer still printed SUCCESS. Write
  with `[IO.File]::WriteAllText` and a `UTF8Encoding($false)`, read with
  `utf-8-sig` so either writer works, and read the file back before registering a
  task that depends on it.
- **Do not treat any hello as proof of a live channel.** The rendezvous keeps
  state, so a hello left by an earlier session reads as success for a machine that
  is not connected. The first real run reported SUCCESS with the agent's own test
  host as the "connected" machine. Compare the hostname and check the age.
- **A native command that writes to stderr kills the script.** With
  `$ErrorActionPreference = 'Stop'`, `& $exe` raises a terminating error on any
  stderr output even when the exit code is 0, and pip does that on an ordinary
  dependency warning. Route native calls through a helper that sets a local
  `Continue` and returns the exit code.
- **`raw.githubusercontent.com` caches for 300 seconds and ignores a
  cache-busting query.** A branch URL can silently serve the previous revision,
  which is exactly what happened: 494 lines served where the branch had 500.
  Pin the fetch to a commit SHA.

PowerShell is installable on the Linux sandbox (`DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1`,
or `pwsh` exits on a missing ICU), which makes syntax checks and fake-cmdlet
tests possible before anything reaches K. `test-installer.ps1` fakes the
scheduled-task cmdlets and asserts the `LogonType` value Windows accepts is the
one used; a wrong value there ended a run before.

**The channel token is a secret and never goes in this repository.** This repo is
public, so a token committed here is a token the whole internet can use to run
PowerShell on K's machine. It is handed to K in chat and stored only in
`AX_PC_CONTROL/ax-results/.ax-token` and on PC1 in
`C:\AX-Runtime\reverse\worker-config.json`. A token was briefly committed in the
guide during development; the rendezvous was stopped and the token discarded
immediately, which is the response if it ever happens again. Rotate by deleting
`ax-results/.ax-token` and restarting the rendezvous.

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

`visibility` is not writable through the universe PATCH either. Sending it
returns 200 and changes nothing, which is the worst kind of response because it
looks like it worked: the run reported `VISIBILITY=UNCONFIRMED expected=PUBLIC
got=PRIVATE` next to `NAME_HTTP=200`. The legacy activate and deactivate pair
flips it, and they take `legacy-universe:manage` rather than `universe:write`:

    POST /legacy-develop/v1/universes/{universeId}/activate
    POST /legacy-develop/v1/universes/{universeId}/deactivate

Confirmed end to end afterwards:

- `VISIBILITY_AFTER_ACTION=PUBLIC`, read back from the API.
- The game page stopped redirecting to `/Title-Unavailable` and now resolves to
  `/games/79945905295644/AX-Arena-Farm-and-Fight`.
- `games.roblox.com/v1/games?universeIds=10771844216` reports
  `name: "AX Arena: Farm and Fight"`, `maxPlayers: 50`.

The lesson generalises: on this API a 200 means the request was accepted, not
that the field changed. Read the field back and compare, or the failure hides
inside a success.

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

## axvision, the always-on eye on PC1

`AX_PC_CONTROL/axvision` is a resident screen reader for the live game. It
captures PC1's screen through GDI, keeps the last few seconds of frames, and
answers one short question per call over the reverse channel:

    python -m axvision start          # begin watching, detached
    python -m axvision state          # one word: world, menu, black, unknown
    python -m axvision changed --seconds 1
    python -m axvision motion --seconds 4
    python -m axvision colour --rgb 255,206,84
    python -m axvision snapshot --out shot.png
    python -m axvision health
    python -m axvision stop

Every command prints one JSON object. The runtime directory is
`C:\AX-Runtime\vision` on Windows and a temp directory anywhere else;
override it with `AX_VISION_DIR`.

### A frozen picture is not a quiet game

The client on PC1 had been up four hours and its surface had stopped updating.
Two captures forty seconds apart were byte-identical, and so were two
independent screenshots taken with the older `ax-see` path, which ruled out a
fault in the capture code. The desktop itself was alive: moving the mouse cursor
changed the pixels under the cursor, and the cursor is composited, so the
surface was not locked either.

`state` was still answering `world`, which is the dangerous part. An agent
that trusts that sends input into a dead surface and then concludes the game
ignored it. `state` and `changed` now also report `frozen` and
`still_ms`, and a frozen screen is reported as frozen even when it still
classifies as the world. The flag clears itself when the picture moves again,
because a client that hangs and recovers is the common case.

The fix for a frozen client is to relaunch it, not to press the key again:
`AX_PC_CONTROL/windows/ax-relaunch.ps1` closes `RobloxPlayerBeta`, reopens
through the `roblox://` protocol, and reports the darkness reading as evidence
the world rendered.

### Do not point the runtime default at a Windows path

`cli.RUNTIME` used to default to the literal string `C:\AX-Runtime\vision`.
On Linux that is a valid relative path, so importing the CLI created a real
directory named `C:\AX-Runtime\vision` in the working tree. The default is
now chosen by `os.name`, with the environment override kept, and a test
asserts the Linux default contains no backslash.

### Renaming an experience needs the desktop, not the Open Cloud key

The Open Cloud `PATCH /cloud/v2/universes/{id}` accepted `displayName` and
returned `200`, then changed nothing. `universe:write` was granted on the key
and the response still echoed the old name, so this is not a scope problem: the
dashboard is the only path that actually persists a rename.

The dashboard path works, but only if the whole interaction is one process.
Each remote tool call is its own process and the browser drops the caret in
between, so `FocusWindow` -> `Click` -> `Type` as three calls types into
nothing. `AX_PC_CONTROL/windows/ax-rename-experience.ps1` does focus,
double-click, Ctrl+A, Delete, type, and a confirming OCR read in a single
process. The field reports as `FIELD|...|AX Garden Legends`, and the name is
saved by clicking the button labelled with the Thai word for Save (left button
of the pair; the right one is Cancel).

Reading those Thai labels needed a zoomed OCR pass. `ax-see.ps1` reads the whole
window at 2x and the labels are a few pixels tall, so
`AX_PC_CONTROL/windows/ax-readcrop.ps1` crops a region and scales it 4-6x
before recognising. Clicking the wrong one of the two buttons is otherwise a
coin flip.

After the dashboard save, `games.roblox.com/v1/games` reported
`AX Garden Legends` and the pipeline's `name` job logged `NAME=SET` and its
`live-state` job logged `LIVE_STATE=PASS`. The API-only attempt had left
`NAME=UNCONFIRMED` on every run before this.

### A world you cannot stand in, and a HUD that covers the phone

Two defects shipped in the same build, both of them invisible to the suite that
existed at the time, and both reported by K within a minute of playing.

The character died on join. `World.luau` built every part through one helper
that hard-coded `CanCollide = false`, ground included, and the world had no
`SpawnLocation` at all. So there was nothing to land on and nowhere defined to
land. The fix is a `collide` parameter on that helper, `true` for the ground,
and a `SpawnLocation` above it. The lesson is that the old test asserted
`FindFirstChild("Ground") ~= nil`, which is true of a ground you fall through.
A test for a floor has to assert `CanCollide`.

The HUD covered a phone. `plotCellSize` sized a plot cell from the viewport
width alone, so on a landscape phone (640x360) four columns gave 148px cells and
three rows came to 460px on a 360px screen: the grid was larger than the display.
The old test checked the grid did not pass the right edge, which is silent about
the bottom. There are now phone sizes for both orientations and the grid is
bounded by the height as well.

Two smaller versions of the same mistake were in the same file. The toast was
positioned just under the top bar, which is exactly the first row of plots, so
every message covered a plot; it is now drawn just above the bottom bar. And the
ScreenGui had `IgnoreGuiInset = true`, which put the coins label at screen y=0
underneath Roblox's own menu and chat buttons on a phone. Leaving the inset on
moves the HUD below them.

The layout module is pure arithmetic, so the fix and its tests live there, but
the bug that mattered was at the call site: `Hud.luau` passed only the width.
A test of the pure function alone would have passed on the broken build, which
is why the reintroduction check now covers the landscape case against the real
client rather than the arithmetic.

### PC1 screenshots come back stale, so do not read them as a frozen game

After the fixes above were published as version 25, the game was relaunched on
PC1 and every desktop capture returned an identical frame, which reads as "the
game is still frozen". It is not. Three checks say the client is running and
drawing:

* `Get-Process RobloxPlayerBeta` reports `Responding=True` and its CPU climbs by
  about 2.1s over 6s, which is a client rendering at roughly a third of a core.
  A hung client stops accruing CPU.
* The window is foreground and `query session` reports the console session
  `Active`.
* The player log runs to 738s with no `LoadCharacter`, `Respawn` or death line,
  and a respawn count of zero. The broken build respawned the player repeatedly,
  so the absence of that line is the difference between the two builds.

The capture path is what is broken: `Snapshot` and the window capture both
return the same pixels no matter what changes on screen. The console session has
one `1600x900` display attached and reports `OK`, so this is not a headless
display; it looks like the desktop compositor is not being updated while no RDP
client is connected, even though the console session is nominally active.

Practical consequences:

* Do not diagnose "is the game running" from a screenshot on PC1. Use the CPU
  delta and the player log instead.
* Keyboard input sent through the `Shell` tool does not reach the game, because
  the Shell runs in a non-interactive session. Use the `Shortcut`, `Click` and
  `Move` tools, which run in the interactive session. Note that `Shortcut` takes
  `keys` as a string, not a list.
* A visual check of movement still needs a real display. The layout and world
  behaviour are covered by the suites, which is what the reintroduction check
  exists to guarantee, but a screenshot of the character walking remains
  unverified on this machine.

## Reviewing your own work

The instruction on this project is to keep reviewing the pattern, the
principles and the experience while working, not only at the end. That is a
habit, not a deliverable, and this section is where its results land so the
next session starts from them instead of rediscovering them.

Work the loop: measure, act, verify, write down. Each pass through it should end
with one of three outcomes -- a fact added below, a rule added to "How to work on
this repository", or nothing learned, which is itself worth noticing. A session
that changed code but added no line here either taught nothing or did not look.

### A check that aborts early still prints pass

The Studio smoke test printed `SMOKE_PASS=True` and `SMOKE_DETAIL=22 checks
passed` while four of its checks had never run. Line 136 read
`Lighting.Technology`, which Edit mode refuses without the `RobloxScript`
capability, and the exception ended the script there. Everything below --
ground, collision, spawn -- was silently skipped. The run still looked green
because the checks that did execute passed and nothing counted the ones that did
not.

Two habits follow:

* Wrap an engine read that cannot fail safely in `pcall`, so one unreadable
  property cannot take the rest of the check list with it.
* When a check produces a count, make the count the gate. "22 passed" is
  meaningless unless the script also knows it meant to run 26 and says so when
  it does not. The failure mode to design against is not a red check; it is a
  short list of green ones.

This is the same rule as "prove a check can fail before trusting it", applied to
the number of checks rather than to one of them.

### PowerShell 5.1: `@($list)` throws on a generic List

The open-and-capture script ran the smoke test, entered Play mode, captured nine
PNGs, and then died on the line that writes its evidence file:

```
$result = [ordered]@{ ... run = @{ captures = @($captures) } ... }
```

`@($captures)` on a `System.Collections.Generic.List[object]` throws "Argument
types do not match" under Windows PowerShell 5.1, and the same throws for
`List[string]`. The script runs under `-File`, so the throw happened before
`Set-Content` and no evidence file appeared. Every downstream reader saw a
missing file and reported a Studio failure, which was the wrong diagnosis for
several runs. Turn a generic list into an array explicitly with `.ToArray()`, or
pool it through `ForEach-Object`.

The wider lesson is about where a crash lands. A script that does all its work
and then fails while serialising the result looks, from outside, exactly like a
script that did no work. When an evidence file is missing, read the run's own log
for the last line before the gap before blaming the thing the evidence was meant
to describe.

### A commit message is not a file you can trust

An amend used `git commit -F /tmp/commitmsg.txt` where the file was left over
from an earlier commit in the same session. The staged content was correct and
the message described a different change entirely. Nothing in the workflow
catches this: the commit succeeds, the tree is right, and only the history is
wrong. When the message must carry meaning, verify it after committing with
`git log -1 --format=%B` rather than assuming the file still says what it said
when it was written.

### Look for the target before promising to change it

A request arrived to upgrade an existing Counter-Strike style Roblox FPS called
"beachline". It was looked for in the working tree, every branch, the full git
history, the whole workspace filesystem, the task registries, the GitHub org's
repository list, the account's published experiences, and the Roblox-wide game
search. It exists in none of them; the only published experience is AX Garden
Legends. The report said so and asked where the project is, rather than building
a new game and calling it the existing one.

The prompt for that request said, in its own words, to modify the existing
project and not to create a new one. When a target cannot be found, the honest
move is to stop and say what was searched, because the alternative silently
turns "upgrade this" into "invent this" and the person cannot tell the
difference until the result arrives.
