# roblox938-1 — status

Answers to the three questions, each with the evidence behind it. Measured
2026-10-28 UTC. The standing goals in `AKATH_CORE/CANONICAL_TASK_REGISTRY.json`
(`AKATH-ROBLOX-GOAL-PLAYABLE-001`, `AKATH-ROBLOX-GOAL-REVENUE-001`) stay open.

## 1. Can we log in as @navintas938?

**Not yet, and there is no credential to log in with.** The account exists —
`navintas938`, user id `11825689233` — but nothing holds its password or a live
session:

| Where checked | Result |
| --- | --- |
| Sandbox env / OpenHands secrets | no Roblox secret |
| PC1 env, `C:\AX-Runtime`, Chrome profiles | no `navintas938`, no `ROBLOSECURITY` cookie |
| PC1 Roblox client session | **expired** — Studio log says `Authenticated : NO`, then `Failed to logout discarded security cookie ... 401` |

A login needs K to type the password once, into a screen the agent can drive. The
free path is already standing up:

```
https://work-1-<work-host>/vnc.html?autoconnect=1&resize=scale
VNC password: in /workspace/ax-tools/aeris938-state/vnc.pass.txt
```

The Roblox login page is open in that desktop. The agent never types the
password; K does, and the session then lives in the persistent profile under
`/workspace`.

## 2. Can a player get in and play?

**No. `isPlayable: false`.**

```
GET games.roblox.com/v1/games/multiget-playability-status?universeIds=10771844216
-> playabilityStatus: "GuestProhibited", isPlayable: false
```

The game page reports maturity **"Minimal • Ages 16+"**, 3 visits, 0 playing. The
experience is not reachable by a normal player.

The build is not the problem. Publishes **succeeded** on 2026-10-19
(`AX PC1 Roblox Publish` run 39238793933), and the repo secret `ROBLOX_API_KEY`
exists. The gate is the **maturity & compliance questionnaire** plus activation —
the `ContextualPlayabilityUnrated` condition `AGENTS.md` already describes. Only
the account holder can clear it.

## 3. Can we create a game?

**Not through the API. Yes through Studio, which is installed on PC1.**

Read from the full OpenAPI spec (`create.roblox.com/docs/cloud/openapi.json`,
835 paths): there is **no** POST that creates a universe or a place. The API can
only publish to one that already exists:

```
POST /universes/v1/{universeId}/places/{placeId}/versions   # publish a version
POST /v1/universes/{universeId}/activate                     # go public
POST /legacy-develop/v1/universes/{universeId}/activate      # legacy switch
```

So creating a *new* experience needs either the Creator Dashboard web UI or
Roblox Studio. Studio is on PC1 — `C:\Program Files\Roblox\Versions\version-7aaa6838d36c4448\RobloxStudioBeta.exe`,
with the Player at `version-9ac85957...`. Both are the free path: no paid API is
involved anywhere in this project.

`AX Garden Legends` already exists as an experience, so publishing our game needs
no new creation step — only the maturity gate above.

## What was fixed on the way here

- **PC1's Actions runner served a different repo.** It was registered to
  `farmmer938-lgtm/ax-ai-benchmark`, so every dispatch for this repo sat at
  `queued` forever. A second runner, `PC1-AERIS`, is now registered to
  `aerismusic8-alt/aeris-drive-automation` and **online**.
- **`ROBLOX_API_KEY` cannot list places** — `GET` returns 404 for
  `universe 10771844216` (evidence `pc1-roblox-list-places.json`). The key is
  present but does not carry `universe-places:read` for this universe, so publish
  capability is unproven for the current key.

## What K has to do (three things, all one-time)

1. **Sign in to Roblox as @navintas938** through the noVNC link above.
2. **Submit the maturity & compliance questionnaire** in the Creator Dashboard
   (Maturity & Compliance), which is what flips `isPlayable` to true.
3. **Reissue the Roblox Open Cloud key** with `universe-places:write` for universe
   `10771844216`, so publishes can run unattended again.
