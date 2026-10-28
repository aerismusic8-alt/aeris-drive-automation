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

## What still needs K (one thing)

**Reissue the Roblox Open Cloud key with `universe-places:write` for universe
10771844216.** The current `ROBLOX_API_KEY` returns 404 on place reads, so
unattended publishes cannot run. Everything else is now in the agent's hands.

The 1,000-Robux fee for under-16 reach is deliberately left undone — it is a paid
option and Rule #1 cancels it.
