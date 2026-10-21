# Breachline: Two Sites — recovered source

## What this is

The editable source of **Breachline: Two Sites**, the tactical FPS that lives at
`roblox.com/games/136310542172942`. Until now the source existed only inside an
open Studio session on PC1: it was on no branch, no reachable disk directory, and
Studio had written no AutoSave for it.

It is here because the Open Cloud key can read the published place back. The
asset-delivery API returns a signed CDN URL for the current place version, and
that file is the whole project — instances, hierarchy, and every Luau script.

## How it was recovered

`scripts/probe-breachline-source.sh` asks, one GET at a time, which capabilities
the key has for universe 10772257179. `asset_delivery_v1` answered 200 with a
`location`, so the run downloaded it:

```
curl -H "x-api-key: $ROBLOX_API_KEY" \
  "https://apis.roblox.com/asset-delivery-api/v1/assetId/136310542172942"
```

The file is a binary `.rbxl`: a 32-byte header followed by named chunks. Each
chunk payload is a full **zstd** frame. `breachline-place.rbxl` is that download,
byte-for-byte; `raw/` holds every Luau source recovered from the decompressed
chunks, in chunk order.

## Reproducing

Re-dispatch the probe workflow and the download repeats. It is read-only: no
call in that path writes, publishes, or restarts anything.

```bash
gh workflow run ax-breachline-source-probe.yml
```

## What is in here

`raw/` is a flat dump: 438 source blobs, ~1.9 MB, in chunk order. Names are
positional (`287.luau`), not the in-experience names, because the binary format
keeps instance names in a separate string table. The blobs that matter for the
game are the ones that mention `MatchState`, `PrototypeRange`, and `BombSites`.

## Status

Recovered, not yet rebuilt. Converting this dump into a Rojo project with the
correct instance hierarchy is the next step.
