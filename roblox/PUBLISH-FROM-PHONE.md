# Publish AX Arena from a phone

The code is done and tested. This is the part that still needs a computer,
because Roblox only lets you publish from Roblox Studio.

## Why a phone is not enough

Roblox Studio is the tool that uploads a place to Roblox. There is no mobile
version. You can **play** on a phone, but you cannot **publish** from one.

So the split is:

| Step | Phone | Computer |
| --- | --- | --- |
| Read the code, review the PR | yes | yes |
| Open Studio, paste the scripts | no | yes |
| Publish the place | no | yes |
| Play the published game | yes | yes |
| Create gamepasses and products | yes | yes |
| Check revenue | yes | yes |

## What you need once

1. A Roblox account (you have one).
2. Roblox Studio on a computer, signed in to that account.
3. About 20 minutes.

## Step 1: get the code onto the computer

Open this link on the computer and click **Code -> Download ZIP**:

https://github.com/aerismusic8-alt/aeris-drive-automation/tree/ax-arena-roblox-game

Unzip it. The game lives in the `roblox/` folder.

## Step 2: open the project in Studio

1. Open Roblox Studio.
2. Choose **New -> Baseplate**. This gives you a world to stand in.
3. In the Explorer panel, right-click **ServerScriptService**, choose
   **Insert Object -> Folder**, and name it `Shared`.
4. Right-click the new `Shared` folder, and insert a **ModuleScript** for each
   file in `roblox/src/shared/`. Name each one after its file, without the
   `.luau` part. So `Config.luau` becomes a ModuleScript called `Config`.
5. Paste the contents of each file into its ModuleScript.
6. Right-click **ServerScriptService**, insert a **Script** named `Server`,
   and paste `roblox/src/server/init.server.luau` into it.
7. Right-click **StarterPlayer -> StarterPlayerScripts**, insert a
   **LocalScript** named `Client`, and paste
   `roblox/src/client/init.client.luau` into it.

The server creates the remotes and the HUD itself, so there is nothing else to
wire up.

## Step 3: press Play

Press **Play** in Studio. You should see:

- coins ticking up as waves die
- a level and XP bar climbing
- a zone name
- a rebirth counter

If the Output panel shows `[AX Arena] server ready (schema v3)`, the loop is
running.

## Step 4: publish

1. **File -> Publish to Roblox As...**
2. Give it a name, a description and a genre. Say it is a farming game, because
   that is what players search for.
3. Set **Playability** to **Public** so anyone can join.
4. Click **Create**.

You now have a public game. Open it on your phone to confirm it loads.

## Step 5: turn on the money

The prices already exist in the code, but Roblox needs the items created on its
website before they can be sold. Do this from a phone browser at
https://create.roblox.com.

For each row below, create the item, then copy its numeric id into
`roblox/src/shared/Monetization.luau` as the `assetId` of that product.

| Product | Type | Price (Robux) |
| --- | --- | --- |
| VIP | Pass | 199 |
| Auto Hatch | Pass | 149 |
| Super Speed | Pass | 99 |
| Zone Pass | Pass | 299 |
| 2x Coins (1 hour) | Developer Product | 25 |
| Lucky Boost | Developer Product | 35 |

Until an `assetId` is set, the client refuses to prompt for that product, so
nothing breaks while the list is half filled in.

## Step 6: check it earns

After a purchase, the Roblox dashboard shows the Robux. If a purchase is made
while the player is offline, the server keeps the receipt and grants it when
they return, so nobody pays without receiving.

## Where things stand

Done and tested:

- 145 automated tests, all passing
- the full farm loop: coins, XP, levels, pets, eggs, rebirths, zones
- six products with server-side prices and replay protection
- saves that migrate from older versions without losing progress

Still needed:

- a computer with Roblox Studio to publish
- Roblox asset ids for the six products

This document was created by an AI agent (OpenHands) on behalf of the user.
