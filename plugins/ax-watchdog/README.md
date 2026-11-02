# ax-watchdog

An OpenHands automation plugin (script runner, no LLM) that watches the rest of
the AX rail and says something when part of it stops.

## The gap it closes

On 2026-11-01 the platform auto-paused **AX Music Daily Release** after five
consecutive failures, every one of them `Timed out: Sandbox not available`. The
rail went quiet and nothing reported it: a paused release automation looks
exactly like a working one from outside, and the reason is only visible in the
run history. The other automations *do* things; none of them noticed a peer that
had stopped.

This runs on the automation service, not inside the sandbox, so the failure it
is watching for cannot also stop the watcher.

## Each run

1. Lists every automation. Flags any that is disabled, distinguishing
   `consecutive_failures` (the platform paused it) from `manual` (a human did).
2. **Heals** the auto-paused ones by re-enabling them, unless `heal` is false. A
   paused rail is worse than a retrying one. Manual pauses are never touched.
3. Reads each channel's newest upload; flags one past `stale_hours`.
4. Pushes one alert to ntfy (`ntfy_topic`) when anything is wrong, with a
   `cooldown_hours` per alert signature so a long outage does not page hourly.

The newest reading is written to the automation KV store under `latest`, and the
last alert under `last_alert`.

## Why ntfy

It needs no account, no key and no paid tier, which is the project's
zero-cost-first rule. The operator subscribes to the topic in the ntfy app on a
phone, so an alert reaches a person even when the sandbox is gone — which is the
whole point, since the failure being watched is the sandbox being gone.

## Config

| Key | Default | Meaning |
|---|---|---|
| `stale_hours` | 30 | Flag a channel with no upload for longer than this |
| `cooldown_hours` | 6 | Minimum gap between repeats of the same alert |
| `ntfy_topic` | `""` | ntfy.sh topic to push to; empty disables push |
| `heal` | `true` | Re-enable automations the platform auto-paused |
