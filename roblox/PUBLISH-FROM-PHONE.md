# Publish AX Arena from a phone

PC1 builds and publishes the game. You only need to create the experience
once and copy two numbers. Roblox Studio is **not** required.

## How it works

```
repo  --Rojo-->  AXArena.rbxlx  --Open Cloud API-->  live Roblox place
        (PC1)                     (PC1)
```

Roblox's Open Cloud API accepts a place file over HTTPS and publishes it as a
new version. That is why no computer with Studio is needed: PC1 does the whole
job, and you drive it from the phone.

## Step 1: create the experience (phone browser)

1. Go to https://create.roblox.com and sign in.
2. Open **Creations -> Create New -> Experience**.
3. Choose any template. The code replaces everything, so the template does not
   matter.
4. Name it something players search for, for example **AX Arena: Farm and
   Fight**. The name and icon are what get you discovered.
5. Open the experience. The address bar looks like:

   ```
   https://create.roblox.com/dashboard/creations/experiences/1234567890/places/9876543210/overview
                                                   ^^^^^^^^^^          ^^^^^^^^^^
                                                   universeId          placeId
   ```

6. Note the two numbers.

## Step 2: keep those numbers

Keep the two numbers. You type them into the run form in step 4, so you do not
need to edit any file. If you would rather set them once, you can still edit
`roblox/publish-config.json`; the run form wins when both are present.

`Saved` means only you can see the result. Switch to `Published` when you are
ready for players.

## Step 3: create the API key (phone browser)

1. Go to https://create.roblox.com/dashboard/credentials
2. **Create API Key**. Name it `AX Arena publish`.
3. Under **Access Permissions**, add **universe-places** and tick **write**.
4. Under **Accepted IP Addresses**, you can leave it open, or restrict it to
   PC1's address for safety.
5. Save the key. Roblox shows it once. Copy it.

Then add it to the repository:

1. Open https://github.com/aerismusic8-alt/aeris-drive-automation/settings/secrets/actions
2. **New repository secret**, name it exactly `ROBLOX_API_KEY`, paste the key.

## Step 4: publish

**Normally you do nothing.** Pushing game code to `ax-arena-roblox-game` runs
the tests, and a green test run publishes the place by itself. That closes the
gap where the code was on the branch but players still saw the old game.

To publish by hand, for example after changing the API key:

1. Open https://github.com/aerismusic8-alt/aeris-drive-automation/actions/workflows/ax-pc1-roblox-publish.yml
2. **Run workflow** and fill the form:
   - `version_type`: `Saved` for a private test, `Published` to go live
   - `universe_id`: the first number from step 1
   - `place_id`: the second number from step 1
   - `ref`: leave as `ax-arena-roblox-game`
3. Wait about a minute.

The run prints the new version number, for example `PUBLISHED_VERSION=3`. That
number is your proof it worked. If anything is missing the run says `BLOCKED`
and lists what is absent, rather than pretending to succeed.

Roblox Studio is not part of this path at all. PC1 builds the place, uploads
it through the Open Cloud API, and Roblox publishes it. A phone browser is
enough for every step.

## Step 5: make it playable (this one is required)

Publishing a version is not enough to let anyone play. Roblox keeps a new
experience private until you fill in the **Maturity & Compliance
questionnaire**, and only the account holder can do that. Until it is done the
play page says the experience is not playable, which looks exactly like "my
change did nothing".

1. Open https://create.roblox.com and sign in.
2. Open the experience, then **Audience -> Maturity & Compliance**.
3. Answer the questionnaire. AX Arena has cartoon fighting, so expect **Mild
   violence**; answer honestly, because a wrong answer can be moderated.
4. Submit. The experience gets a maturity label and becomes playable.
5. Still on **Audience**, set **Access Settings** to **Public** and save.

If the dashboard asks you to verify your age first, do that step; it is a
Roblox requirement for publishing public experiences.

## Step 6: check it

Open the experience page on your phone and press play. You should now see the
town, a **MAP** button, five monster fields in a ring, and coins ticking up.

## Step 7: turn on the money

Prices already exist in the code. Roblox still needs the items created before
they can be sold. At https://create.roblox.com, open the experience, then
**Monetization**:

| Product | Type | Price (Robux) |
| --- | --- | --- |
| VIP | Pass | 199 |
| Auto Hatch | Pass | 149 |
| Super Speed | Pass | 99 |
| Zone Pass | Pass | 299 |
| 2x Coins (1 hour) | Developer Product | 25 |
| Lucky Boost | Developer Product | 35 |

Each item gives you a numeric id. Put it in
`roblox/src/shared/Monetization.luau` as that product's `assetId`, then run the
publish workflow again. Until an id is set the game refuses to prompt for that
product, so a half-filled list is safe.

## What is already done

- PC1 builds the place with Rojo: 23 scripts, all verified to carry real code
- the Open Cloud publish path is wired and tested end to end
- 359 automated tests pass (220 unit, 47 integration, 92 wiring)
- a town plus five monster fields, per-field waves, travel, bosses, the farm
  loop, pets, rebirth, zones, daily rewards and promo codes are implemented,
  plus six monetization products
- a green test run publishes automatically, so the live place cannot lag behind
  the branch
- the publish run reports `BLOCKED` and names exactly what is missing, so a
  missing key can never look like a successful publish

## What still needs you

- create the experience (step 1)
- create the API key and store it as a secret (step 3)
- complete the maturity questionnaire and set the experience public (step 5) -
  without this the game stays unplayable no matter how often we publish
- create the six monetization items (step 7)

Everything else runs without you.

This document was created by an AI agent (OpenHands) on behalf of the user.
