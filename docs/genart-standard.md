# Generative art standard

K (2026-11-19): "สร้างงานคุณภาพสูงด้วยโค้ดเอง — generative art แบบ algorithmic
ที่ขายได้จริงและไม่ต้องพึ่ง API ใดๆ".

`ops/genart.py` is the whole tool. No API, no key, no model, no download: every
pixel is arithmetic over a seeded PRNG.

## Why this is sellable and a downloaded image is not

| Property | What it buys |
| --- | --- |
| Computed, not sampled | The copyright is ours outright — no model terms, no stock licence, no credit line |
| `(algorithm, palette, seed)` | A listing can say "edition 1/1, seed 4242" and the buyer can rebuild it; verified byte-identical |
| 4096 px, 300 DPI tag | 13.7 in at print resolution, which is what a print shop requires |
| Curated palettes | Twelve works made together read as a collection, not a pile |
| SVG for line work | Scales to a mural with no resolution argument |

## The five algorithms

| Name | Construction | Looks like |
| --- | --- | --- |
| `warp` | Domain-warped fractional Brownian motion, gradient-mapped | Soft atmospheric fields, smoke and light |
| `flow` | Streamlines integrated through a noise-derived vector field | Ribbon/engraving line work (also SVG) |
| `react` | Gray-Scott reaction-diffusion | Organic cells, coral, vein textures |
| `attr` | Clifford strange-attractor density, rank-equalised | Fine filament structures |
| `tiles` | Periodic fBm | A seamless, tileable pattern (seam measured 0.00) |

## The gate

`check()` runs **inside `make()`**, so a bad draw cannot enter the library at
all — the same rule as the clip floor: nothing below standard ships.

- **≥ 1600 px** on the short edge.
- **Not flat**: luma std ≥ 8.
- **Enough tones**: luma entropy ≥ 2.0 over 8-level buckets.

Three real defects were found and fixed by this gate, and each is recorded in
the code where the fix lives:

1. **Reaction-diffusion died out** on random `(feed, kill)` — 2 of 3 draws were a
   blank sheet. Now walks six known-good pairs and retries.
2. **Clifford attractors collapsed** to a line — 2 of 6 parameter sets covered
   0–1% of the frame. Now uses four measured-good sets plus a coverage floor.
3. **Narrow tonal band** — a live pattern still failed at 1.90 against the 2.0
   floor because its values clustered. Fixed at the source with rank
   equalisation rather than by lowering the floor.

## Storage

A 4096 px PNG is 10–20 MB, so 1,000 works is ~15 GB — more than the pod holds.
The split is the same as the stock bank:

- **committed**: `library/art/manifest.json` (the index) and `counter.json` (the
  next seed), so a fresh pod knows what exists and never re-renders a seed.
- **release**: the pixels, packed into `genart-NNNN.tar` on `media-938`.

```bash
python3 ops/genart.py shard    # pack + upload + delete local
python3 ops/genart.py pull     # bring works back for a listing
```

## The rail

`.github/workflows/ax-genart.yml` runs daily at 05:40 UTC: renders a batch
through `ops/genart_plan.py`, gates every file, shards to the release, commits
the manifest and the counter. Rotation walks algorithms and palettes in a fixed
order, so a week's output is varied by design rather than by PRNG luck.
