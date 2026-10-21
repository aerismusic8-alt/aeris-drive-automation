# AX Garden Legends

A collection garden for Roblox. Buy a seed, plant it, wait for it to grow,
harvest it, sell the crop, spend the coins on better seeds, more plots and pets.
Crops keep growing while the player is offline, so a session starts by seeing
what ripened overnight.

## Why this shape

The previous game in this repository was a wave-survival arena. It was built and
tested carefully and it was not fun, and the reason is structural: an arena is a
game about *combat feel*, and combat feel cannot be verified by a test suite or
inferred from a diff. Every design decision was a guess, and the guesses did not
add up to something a person wants to play.

This game copies a loop that is already proven on the platform rather than
inventing one. The genre leader sits at roughly 36 billion visits and a 90%
rating with no combat in it at all. Its loop is patience and collection:

1. Buy a seed from a rotating shop.
2. Plant it in a plot.
3. Wait. The crop grows in real time, including while the player is offline.
4. Harvest. Every harvest rolls one **mutation**, which multiplies what the crop
   sells for -- most harvests are ordinary, and occasionally one is worth 240x.
5. Sell, and spend the coins on better seeds, more plots, growth speed, sale
   value, and pet eggs.
6. The **collection** page tracks which seeds and mutations have ever been found.
   That page is the reason to open the game again tomorrow.

The important property is that the whole loop is arithmetic on a timestamp. It
can be tested completely, offline, with no engine -- which is what makes it
possible to know whether it works before a player ever sees it.

## What is here

```
roblox-garden/
  default.project.json   Rojo project (syncs src/ into a place)
  src/shared/            Pure Luau game logic, no Roblox globals
    Config.luau          Every tunable number: rarities, seeds, mutations, pets
    Random.luau          Deterministic RNG (seeded, reproducible)
    Rarity.luau          The seven collection tiers
    Seeds.luau           Seed catalogue, rotating shop, pricing, grow times
    Mutations.luau       The mutation roll and its multipliers
    Pets.luau            Eggs, hatching, equipping, passive bonuses
    Garden.luau          Plots, planting, growth, harvest, offline ripening
    Sell.luau            Sale value, upgrades, the offline time clamp
    Collection.luau      Which seeds and mutations have been discovered
    SaveSchema.luau      Save validation, migration, deterministic JSON
    Text.luau            Thai display text for everything a player reads
  tests/run.luau         Test suite for everything in src/shared
```

`src/shared` contains no Roblox API calls. The server owns every number; the
client only draws state and asks permission.

## Running the tests

```bash
scripts/test-roblox.sh          # runs every suite in the repository
./tools/luau/luau roblox-garden/tests/run.luau   # just this game
```

## Design rules that the tests enforce

- **A seed that pays more must cost more patience.** The catalogue is the
  progression, so if a later seed were cheaper *and* faster, the shop would be a
  lie. Tests walk the whole catalogue and fail on an inversion.
- **Every rarity tier must have a seed.** A tier with no seed is decoration: the
  collection can never be completed and the tier exists only to fill a colour.
- **The rarest mutation must stay rare.** Cosmic is 1-in-2400 by weight. A test
  asserts the ordinary result dominates a large sample, because a game that pays
  out a rare mutation every few harvests has no rare mutations.
- **Offline growth is capped at eight hours.** Uncapped, one long absence would
  be worth more than weeks of play. A test pins the clamp.
- **A dearer egg must give a better pet.** The egg ladder is checked for
  monotonicity in average pet value, because a coin sink a player can see
  through is worse than no sink at all.
- **A save from an older version must load.** Every field is rebuilt on load and
  anything the game no longer recognises is dropped, so a stale save cannot
  brick a garden.

Every test in this suite was checked against the broken code it guards: the bug
was put back and the suite was watched to fail. Three real defects were found
this way while writing it -- a coarse price rounding that collapsed two different
seeds onto the same cost, a sell floor that paid a coin for a crop that did not
exist, and a flat pet ladder where a 1500x dearer egg bought a 2x pet.
