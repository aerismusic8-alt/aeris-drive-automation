# roblox938-1 — status

Answers to the three questions, each with the evidence behind it. Measured
2026-10-28 UTC. The standing goals in `AKATH_CORE/CANONICAL_TASK_REGISTRY.json`
(`AKATH-ROBLOX-GOAL-PLAYABLE-001`, `AKATH-ROBLOX-GOAL-REVENUE-001`) stay open.

## 1. Login as @navintas938 — DONE

K signed in through the cloud desktop. Verified with the site's own authenticated
endpoint, not the page title:

```
GET users.roblox.com/v1/users/authenticated
-> {"id":11825689233,"name":"navintas938","displayName":"navintas938"}
```

`.ROBLOSECURITY` is present (1178 chars; 17 `roblox.com` cookies). The session was
saved to `/workspace/ax-tools/aeris938-state/roblox-storage.json`, which lives on
persistent storage, so it survives a pod recycle. The agent now acts as the owner.

## 2. Can a player get in and play? — the answer depends on who asks

The same universe, two calls seconds apart:

| Viewer | Result |
| --- | --- |
| authenticated owner | `{"playabilityStatus":"Playable","isPlayable":true}` |
| anonymous | `{"playabilityStatus":"GuestProhibited","isPlayable":false}` |

So the game **is** playable and public. The earlier `isPlayable: false` reading was
an **anonymous probe**, not a broken build — that is why it looked like a defect.

The real limit is the **audience setting**. Creator Hub, `จัดการผู้ชม`:

- access: `สาธารณะ` (public) — already set
- audience: `อายุ 16 ปีขึ้นไปและเพื่อนที่เชื่อได้` (16+ and trusted friends)

To open it to under-16 players, Roblox lists four steps, and **two of them cost
money or require a government ID**:

| Step | State | Cost |
| --- | --- | --- |
| Enable 2FA | incomplete | free |
| 250 engaged players / high-engagement review | 0 people at 2026-10-28 | free, needs real players |
| Kids & Select publishing fee | incomplete | **1,000 Robux** |
| Verify identity with government ID | complete | — |

**Rule #1 forbids the paid route**, so the 1,000-Robux fee is not an option and is
not proposed. The free road to a wider audience is the 16+ rating plus the free
250-engaged-player review.

## 3. Can we create a game? — not via API, yes via Studio

The Open Cloud API **cannot** create an experience: the full spec
(`create.roblox.com/docs/cloud/openapi.json`, 835 paths) has no POST that creates a
universe or place. The Creator Hub creations page has **no create affordance**
either — its only buttons are menu, search, notifications and sort.

Roblox's own docs are explicit — *"When you open Studio and create a new game, your
project starts with a single place..."*. New experiences come from **Studio**.

Studio is installed on PC1:
`C:\Program Files\Roblox\Versions\version-7aaa6838d36c4448\RobloxStudioBeta.exe`
(player at `version-9ac85957...`). It is the free path, and no paid API is involved.

The account already owns **three** experiences, which proves creation works here:

| universeId | name |
| --- | --- |
| 10771844216 | AX Garden Legends |
| 10772257179 | Breachline: Two Sites |
| 10772257646 | Legends of Celestia |

## What was fixed on the way here

- **PC1's Actions runner served a different repo** — it was registered to
  `farmmer938-lgtm/ax-ai-benchmark`, so every dispatch for this repo sat at `queued`
  forever. A second runner, `PC1-AERIS`, is now registered to
  `aerismusic8-alt/aeris-drive-automation` and **online**.
- **Chromium CDP died silently after a pod recycle** — a stale `SingletonLock`
  pointing into the dead pod's `/tmp` stopped Chromium binding port 9222, while
  every status check still said "UP". Cleared, and the desktop is healthy.

## The list-places 404 — solved, and it was our bug (2026-10-28)

After K updated the key, the workflow still failed, so I read the raw log instead of
the conclusion. The universe read had actually been working all along:

```
UNIVERSE_HTTP_STATUS=200   UNIVERSE_NAME=AX Garden Legends   UNIVERSE_VISIBILITY=PUBLIC
LIST_URL=https://apis.roblox.com/cloud/v2/universes/10771844216/places
HTTP_STATUS=404
```

The script was calling a URL that **does not exist**. The 835-path spec has
`/cloud/v2/universes/{universe_id}/places/{place_id}` (singular, id required) and **no
list path at all**, so that 404 was guaranteed for any key with any scope — which is why
it read as a permissions problem.

The correct call is on a different host and needs no credential:

```
GET https://develop.roblox.com/v1/universes/10771844216/places
-> 200 {"data":[{"id":79945905295644,"name":"AX Garden Legends",...}]}
```

Fixed in `AX_PC_CONTROL/pc1-roblox-list-places.ps1` and pushed. The workflow now ends
`completed success` with `PLACE_ID=79945905295644`.

## What still needs K

Nothing, for the place id. The one open item is the 1,000-Robux under-16 publishing fee,
and that is deliberately not paid — it is a paid option and Rule #1 cancels it. The free
route is the 16+ rating plus the free 250-engaged-player review.

## 4. A brand-new game exists and is public (2026-10-28)

Section 3 said new experiences need Studio. That is true for a human clicking through the
Creator Hub, but it is not the whole truth: **Studio itself creates a universe over HTTP**,
and the endpoint is visible in the Studio binary.

```
POST https://apis.roblox.com/universes/v1/universes/create
body: {"templatePlaceID": <int>, "placeName": "...", "description": "..."}
-> 200 {"universeId":..., "rootPlaceId":...}
```

It needs the signed-in `.ROBLOSECURITY` cookie and a CSRF token
(`POST auth.roblox.com/v2/logout`, read `x-csrf-token`), not the Open Cloud API key.
`templatePlaceID` must be a Roblox base template id — our own place ids are rejected with
`place id ... is not a valid template`.

The new experience, created this way and then published into:

| field | value |
| --- | --- |
| universeId | 10773483379 |
| rootPlaceId | 98458071284292 |
| name | AX Arena 2: Monster Fields |
| privacyType | Public |
| isActive | true |
| published version | 2 (576,246 bytes, 39 source blocks) |
| playability (owner) | `Playable` |

### The three steps that made it real

1. **Rename** — `PATCH develop.roblox.com/v1/universes/{id}/configuration` with
   `{"name": ...}` returns 200. The first attempt also wrote the Thai working title.
2. **Publish** — the Open Cloud path (`POST apis.roblox.com/universes/v1/{u}/places/{p}/versions?versionType=Published`)
   returned **403** because `ROBLOX_API_KEY` was scoped to the three older universes only.
   Fixed by editing the key in Creator Hub → ส่วนขยาย API → แก้ไข → the "ค้นหาประสบการณ์"
   box now offers the new experience; tick it and save. Then the same workflow run
   returned `HTTP_STATUS=200 PUBLISHED_VERSION=2`.
3. **Make it public** — `privacyType` will **not** change by PATCH; the field is
   read-only. The free path is Creator Hub → จัดการผู้ชม → เปิดตัวต่อสาธารณะบน Roblox,
   answer the maturity questionnaire (our cartoon combat is "no restricted content"),
   then **เผยแพร่**. After that `privacyType=Public isActive=true`.

### Still true

Anonymous play still reads `GuestProhibited` — that is the audience rating gate, not a
broken build (see section 2). Under-16 reach still needs the paid 1,000-Robux fee or the
free 250-engaged-player review, and Rule #1 keeps the fee unpaid.

## 5. Re-verified 2026-10-28 13:1x UTC — and the real risk is the branch, not the publish

Re-measured from the sandbox, not from the previous write-up. Everything below is a
response I read myself this session.

**Live state of the new universe.**

```
GET games.roblox.com/v1/games?universeIds=10773483379
-> name "AX Arena 2: Monster Fields", rootPlaceId 98458071284292,
   creator navintas938 (11825689233), created 2026-10-28T12:25:54Z,
   updated 2026-10-28T12:59:23Z, visits 0, playing 0
GET games.roblox.com/v1/games/multiget-playability-status?universeIds=10773483379
-> {"playabilityStatus":"GuestProhibited","isPlayable":false}   (anonymous probe)
```

The last publish was **version 2**, `PUBLISHED_VERSION=2`, `HTTP_STATUS=200`,
`UPLOAD_BYTES=576246`, from the run at `2026-10-28T12:59:22Z`. The artifact
`pc1-roblox-publish-evidence.json` on PC1 says the same:

```json
{"status":"PUBLISHED","versionNumber":2,"universeId":"10773483379",
 "placeId":"98458071284292","versionType":"Published","uploadBytes":576246}
```

**Where the published code actually came from — read this before trusting a green run.**
The build step reported `BUILD_REF=main`, which reads as "main was published". It was
not. `AX_PC_CONTROL/pc1-roblox-build.ps1` carries `$BRANCH = 'ax-arena-roblox-game'`
hard-coded, so the script was *fetched* from main but it clones and builds the **branch**:

```
BUILD_REF=main
HEAD is now at 967753a Temporary: dump both universe objects from the live-state job
Building project 'AXArena'
SOURCE_BLOCKS=39   SCRIPT_INSTANCES=39
```

39 source blocks is the branch's `roblox/` (32 shared + 5 client + 2 server = 39 files).
`main`'s `roblox/` has 28 files (24 + 2 + 2), so **main's newer game code is not what is
live**. The two refs diverged at `6f2e48b` (2026-10-19) and `main` is 35 ahead / 135 behind
the branch. The live place is the branch snapshot.

**The 12:33 failure was not the game.** That run had `ref=ax-arena-roblox-game`, so the
build step fetched the *branch's* build script, which builds `roblox-garden/`:

```
HEAD is now at 967753a ...
Building project 'AXGardenLegends'
[ERROR rojo] failed to create file `C:\AX-Build\AXGarden.rbxlx`
        Caused by: Access is denied. (os error 5)
```

`AXGarden.rbxlx` already exists on PC1 and is locked, so Rojo could not overwrite it. That
is a stale artifact, not a code fault — and the same `ref` choice is why the file path
differs between the two runs.

**The 12:48 failure was the key, and it is fixed.** `HTTP_STATUS=403` on the publish POST,
because `ROBLOX_API_KEY` did not yet list the new universe. After the key was edited in
Creator Hub, the next run at 12:59 returned `HTTP_STATUS=200 PUBLISHED_VERSION=2`.

**Sandbox GitHub write is still read-only** (re-checked): `POST /git/refs` -> **403**,
`x-oauth-scopes` empty, `allows_permissionless_access=true`. The write path remains
`scripts/push-via-pc1.sh`. PC1's MCP is reachable and answering
(`GetSystemInfo` -> Windows 11, 4 cores, 5.8/8.1 GB used, booted 2026-10-22).

### The open question for K

Two refs both call themselves the game. `main` holds the newer `roblox/` (Ragnarok
systems, `Config.Version = "1.0.0"`); the branch holds a larger `roblox/` (32 modules,
`Config.Version = "1.0.1"`, plus `roblox-garden/` and `breachline/`). The live place runs
the branch's. Reconciling them is the thing that decides what players actually get, and
it is a deliberate choice, not a mechanical merge.
