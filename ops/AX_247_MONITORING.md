# 24/7 monitoring and auto-reconnect

K's question: if auto-reconnect does not work, how can AR still create channels,
and how do we watch the project around the clock?

Short answer: **the sandbox is not the thing that needs to run 24/7, and it must
not be the thing that watches.** Two separate jobs got confused. Creating
channels and uploading needs only a token; watching needs a machine that is not
the one being watched.

## 1. Creating a channel or uploading does not need the desktop

A YouTube OAuth **refresh token** is a string. It does not expire on its own and
it can be handed to any machine. Refresh it and you get an access token that can
read and write the channel, with no sandbox, no browser and no login:

```
POST https://oauth2.googleapis.com/token
  client_id, client_secret, refresh_token, grant_type=refresh_token
  -> access_token, expires_in 3599
GET  https://www.googleapis.com/youtube/v3/channels?part=statistics&mine=true
```

Verified on 2026-11-01 with `YT_CH3_REFRESH_TOKEN`: scope
`https://www.googleapis.com/auth/youtube` (upload included), channel read as
"AERIS Music", 5 subs, 22 videos. So the desktop is not on the critical path for
anything programmatic. It is only needed for surfaces that have no API — YouTube
Studio's own UI, Facebook, TikTok, Shopee.

## 2. The real failure is the sandbox, not the login

"AX Music Daily Release" was **paused by the platform**, not by a person: five
consecutive failures, every one `Timed out: Sandbox not available`
(`disabled_detail.source == consecutive_failures`). A run dispatched by hand sat
at phase `Starting automation` for over 25 minutes.

That is the answer to the second half of the question. It is not that
reconnection fails and then nothing works; it is that **getting a sandbox at all
is the unreliable step**, and a watcher that also needs a sandbox shares the
failure it is meant to report.

Re-enabling a paused automation works through the API:

```
PATCH /api/automation/v1/{id}  {"enabled": true}
```

## 3. The 24/7 layer is GitHub Actions

`aeris-drive-automation` is a **public** repo now, so Actions minutes are free
(the private-repo limit that was hit before no longer applies), and it already
holds the tokens as repo secrets (`YT_CH1..CH4_REFRESH_TOKEN`, `YT_CLIENT_ID`,
`YT_CLIENT_SECRET`). `ax-roblox-live-state.yml` has run on `cron '0 * * * *'`
successfully for days, which is the proof that a scheduled job here actually
runs.

This layer has no sandbox and no OpenHands API key, so the two things that break
the automation tier cannot break it.

## 4. What was built

**`plugins/ax-watchdog`** — a plugin (script runner, no LLM) that runs hourly at
minute 15 and:

- lists every automation and separates a **platform** pause
  (`disabled_detail.source == consecutive_failures`) from a **human** one
  (`manual`);
- **heals** the platform-paused ones by re-enabling them, and never touches a
  manual pause — a person's decision is not the watchdog's to overrule;
- reads each channel's newest upload and flags one past `stale_hours`;
- pushes one alert to **ntfy** with a per-signature cooldown, so a long outage
  does not page every hour.

It runs in two places, from the same code:

| Caller | State | Automation audit |
|---|---|---|
| OpenHands automation `AX Rail Watchdog` (hourly :15) | automation KV store | yes |
| GitHub Actions `ax-rail-watchdog.yml` (hourly :15) | `data/ax-watchdog-state.json`, committed | skipped, and says so |

The audit needs the OpenHands API key, which Actions does not have; the job
prints that it skipped rather than reporting a false "all clear".

## 5. Alerts reach a phone with no account and no key

ntfy.sh needs nothing but a topic name. Subscribe to the topic in the ntfy app
and an alert arrives even when the sandbox is gone — which is the point, since
the failure being watched is the sandbox being gone.

Topic: `ax-ar-aeris-9f3k7q`
Stored as the repo variable `AX_NTFY_TOPIC` and in the automation's config.

## 6. What still needs K

One thing only, because no token in the sandbox carries the `workflow` scope:

- **`.github/workflows/ax-rail-watchdog.yml` is committed locally but not
  pushed.** GitHub rejects a workflow file pushed by an OAuth app without
  `workflow` scope. K can either paste the file into the repo through the web UI,
  or run `gh auth login --web` and authorize from a phone; after that AR can push
  workflows directly.

Until that file lands, the watchdog still runs on the OpenHands automation tier
(deployed and working), which is the weaker of the two layers. The GitHub Actions
layer is what makes it independent of the sandbox.

## 7. Honest limits

- The Actions job is skipped by GitHub under load, and a scheduled run can be
  late. The plugin records its own capture time, so a late run is still honest,
  but the interval is not exact.
- `stale_hours: 30` is a guess at a normal upload cadence, not a measured one.
  Adjust it once there is enough history to know.
- The watchdog heals a pause, but if the platform keeps pausing the same
  automation, that is a real problem the heal only masks. The alert names the
  automation so it is visible rather than silent.
