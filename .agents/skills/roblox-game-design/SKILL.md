---
name: roblox-game-design
description: Build and audit a Roblox experience so it is discoverable, retentive and monetizable, using Roblox's own Creative documentation. Use when shipping or reviewing AX Arena, when a change touches onboarding, the shop, the economy, retention or discovery metadata, or when someone asks why the game has no players.
---

# Designing for Roblox (from Roblox's own docs)

Everything below is drawn from `create.roblox.com/docs`. Read the source pages
before acting on a claim; they change, and the pages carry the current wording.

## How to read the docs at all

The docs are served twice: HTML, and plain Markdown at the same URL plus `.md`.
The Markdown is a fraction of the size and has no navigation furniture.

- Index of every page: `https://create.roblox.com/docs/llms.txt`
- Search (semantic, the one behind the site search box):
  `https://create.roblox.com/docs/api/search?q=<percent-encoded question>`
- **Never guess a URL.** A plausible-looking path that is not in the index
  returns a 404 whose body is a page of HTML that tells you nothing. Search, or
  read the index. The index says this itself, in its "For Code Agents" section.

Fetch a page with:

```bash
curl -sL "https://create.roblox.com/docs/en-us/production/game-design/core-loops.md"
```

## The ranking signals, in order of importance

From `production/discovery.md`. Roblox ranks the **Recommended for You** sort on
signals measured **only** from users who arrived organically from that sort.

| Priority | Signal | Note |
| --- | --- | --- |
| Most important | Play through rate | plays / impressions |
| Most important | **First play bounce rate** | **negative signal**; measured under 60s and 61-180s |
| Most important | Play days per user | D8-28 > D2-7 > D1 |
| Most important | Playtime per user | capped at 60 min/user/game/day |
| Important | Intentional co-play days | playing with friends |
| Important | Qualified play sessions | filters accidental clicks |
| Important | Spend days / Robux spent per user | |

Two consequences that shape everything:

1. **A first session shorter than 60 seconds is actively penalised.** The FTUE
   is not a nicety; it is the signal. A player who cannot find something to do
   in the first minute costs the game distribution.
2. **Signals are per-user averages, not totals.** A small game with engaged
   players is not disadvantaged by its size. "We have no players" is not the
   reason a game does not get recommended; low per-user engagement is.

## Hard eligibility rules

- **A custom thumbnail is required** to receive homepage recommendation
  impressions. A game with only the default thumbnail is not eligible.
- **Do not lead metadata with giveaways.** "Robux! Play now!" is deprioritised.
- **Metadata must match the content.** A title/thumbnail that promises what the
  game does not deliver is not recommended and ranks lower in search.
- **Do not resemble an existing game.** Near-duplicate names and place files are
  deprioritised.

Verify the live metadata rather than assuming:

```bash
curl -s "https://games.roblox.com/v1/games?universeIds=<id>"
curl -s "https://thumbnails.roblox.com/v1/games/multiget/thumbnails?universeIds=<id>&size=768x432&format=Png&isCircular=false"
curl -s "https://thumbnails.roblox.com/v1/games/icons?universeIds=<id>&size=150x150&format=Png&isCircular=false"
curl -s "https://games.roblox.com/v1/games/multiget-playability-status?universeIds=<id>"
```

## The onboarding rules (production/game-design/onboarding*.md)

- **Teach the essentials, get to the fun quickly, leave them wanting more.**
- The opening instruction must name **a concrete next action the player can
  actually take right now**, in the place they are standing.
- Visual, not textual. Younger players skip text; visuals also survive
  translation, which matters because this game's text is Thai.
- Early levels must come fast, so progression is felt in the first minutes.
- Give starter items/currency so the systems are usable immediately.
- Short, mid and long-term goals must be visible, and the session should end on
  a moment of joy (a reward, a level-up, a celebration).

## The monetization rules (monetization-foundations.md, contextual-purchases.md)

- A shop is **integrated, contextual and inviting**. Integrated: consistent with
  the rest of the UI, quick to enter and leave. Contextual: a player knows what
  each item is for and how it compares. Inviting: a place to browse.
- Items are **durable** (cosmetics, passes) or **consumable** (boosts), and
  **enhancement** (power) or **expression** (identity). Say which, and be
  truthful about what the player gets.
- **Contextual purchases** are "right item, right time": in-play, pre-play,
  lobby, complementary, or a UI badge. An in-play prompt must allow time for the
  whole purchase flow, so do not raise one mid-fight.
- A purchase surface that no button reaches earns nothing. Verify the button
  path, not just the handler.

## The economy rules (balance-virtual-economies.md)

- **Every source needs a sink.** New currency without a way to spend it removes
  the incentive to buy more.
- Estimate impact with **expected value**: `sum(value x probability)`, and
  compare an event day against a normal day.
- The safest event design is a **separate event currency** with its own shop, so
  the main economy is untouched.

## Mobile and adaptive design (adaptive-design.md, design-for-roblox.md)

- **Most Roblox players are on phones.** Design UI mobile-first.
- Responsive layout, dynamic sizing, high contrast, legible text on a small
  screen.
- Respect the shared UI: chat, player list, topbar. Do not sit under them.
- Performance is a feature; the audience is sensitive to friction and load time.

## Core loop (core-loops.md)

Every game is minute-to-minute interaction -> most repeated actions ->
progression engine. If any leg is missing the game feels shallow. For AX Arena:
walk/fight -> fight/farm -> level, gear, classes, pets.

## How to audit this repo against the above

The doc rules are only useful if something checks them. In this repo:

```bash
cd roblox && ../tools/luau/luau tests/run.luau    # logic, incl. Thai text
python3 scripts/check-hud-wiring.py               # source-level wiring checks
```

Wiring checks exist because a defect can pass every unit test: the code is
correct, and nothing calls it. Two that came from real bugs:

- **WIRING S** — `Intent.buyProduct` was defined but no button called it, so the
  money path was unreachable. A defined-but-uncalled function is invisible to
  every other check.
- **WIRING T** — the client read `state.quest` to draw the objective tracker but
  never assigned it, so the panel that tells a new player what to do rendered
  nothing, for every player, from the first join. Reading a missing key is
  `nil`, which is a valid value for the tracker to draw around, so nothing
  failed. **When a lookup can silently return "nothing", assert the result is
  non-empty, not merely well-formed.**

The general lesson: for every payload field the server sends, confirm the client
both **stores** it and **draws** it. And for every objective the game gives the
player, confirm the objective is reachable from where the player is standing.

## Metadata and reach, in this repo

- `roblox/src/shared/Text.luau` is the only place Thai lives; ids stay English.
- Keep the live game page's title, description, thumbnail and icon accurate and
  distinct; those are eligibility, not decoration.
- Maturity & Compliance must be submitted or the experience stays unplayable;
  only the account owner can do it.
