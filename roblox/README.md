# AX Arena

A wave-survival arena game for Roblox. Players fight escalating enemy waves,
earn coins, and spend them on permanent upgrades that persist across sessions.

## What is here

```
roblox/
  default.project.json      Rojo project (syncs src/ into a place)
  src/shared/               Pure Luau game logic, no Roblox globals
    Config.luau             All tunable numbers in one place
    Random.luau             Deterministic RNG (seeded, reproducible)
    Stats.luau              Upgrade costs and derived player stats
    Combat.luau             Damage, death, healing, enemy attack cadence
    WaveDirector.luau       Wave phase state machine and spawn scaling
    Inventory.luau          Stacking inventory with capacity limits
    SaveSchema.luau         Save validation, migration, deterministic JSON
    RateLimiter.luau        Per-player token bucket for remotes
  src/server/               Authoritative server loop
  src/client/               Rendering and input only
  tests/run.luau            Test suite for everything in src/shared
```

The split is deliberate: `src/shared` contains no Roblox API calls, so the whole
rule set runs and is tested under the plain Luau CLI. The server owns every
number; the client only draws state and asks permission.

## Running the tests

```bash
scripts/test-roblox.sh          # uses luau from PATH if present
scripts/install-luau.sh         # downloads a pinned Luau CLI into tools/
```

Both fall back to `tools/luau/luau`. The suite covers RNG determinism and
bounds, upgrade cost curves, damage and death handling, wave scaling and phase
transitions, inventory stacking and overflow, save migration, and rate limiting.

CI runs the same suite on every change under `roblox/`.

## Playing it in Roblox Studio

1. Install [Rojo](https://rojo.space/) (`aftman install` or the VS Code extension).
2. `rojo serve` from this `roblox/` directory.
3. Connect from the Rojo plugin in Studio.
4. Press Play. Enable Studio access to API services for DataStore persistence;
   without it the game still runs, saves just fail with a warning.

## Design notes

**Server authority.** `RequestUpgrade` is a `RemoteFunction` handled on the
server. The client sends only an upgrade id; cost, level caps, and coin balance
are all re-checked server side. A client that lies gets `INSUFFICIENT_COINS` or
`MAX_LEVEL` back.

**Rate limiting.** Every upgrade request consumes a token from a per-player
bucket (`Config.Network`). Excess requests get `RATE_LIMITED` instead of
reaching the upgrade logic.

**Deterministic saves.** `SaveSchema.serialize` writes keys in a fixed order and
floors fractional numbers, so identical state produces byte-identical output.
That makes stored blobs diff-friendly and migration testable.

**Migration.** `SaveSchema.migrate` carries legacy values forward, clamping them
into the current legal ranges, then `load` validates the result. A save that
cannot be salvaged is rejected with reasons rather than silently reset.

## Tuning

Everything gameplay-facing lives in `roblox/src/shared/Config.luau`. Wave count,
health growth, upgrade costs and caps, reward scaling, and network limits are all
there. `Config.UpgradeOrder` must list every entry in `Config.Upgrades`; a test
enforces that.
