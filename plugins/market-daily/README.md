# market-daily

An OpenHands automation plugin (script runner, no LLM) that keeps the marketing
loop turning once a day.

Each run:

1. fetches the repo tarball over HTTPS (the automation sandbox has no git
   transport, so a `git clone` hangs until the run times out),
2. runs `music938-1/scripts/market.py`: it reads the stats of every video the
   release ledger says is live, diffs them against the previous
   `work/market-snapshot.json`, and writes `work/market-report.md` (a Thai brief —
   totals, what grew, what to promote),
3. refreshes the GitHub Pages promo page from the channel's newest uploads,
4. commits the report and the snapshot back to `main` through the Contents API,
   skipping a no-op commit, so the next run can diff and the weekly strategy pass
   has a file to read.

Config: `channel` (default `ch3`), `promo_repo` (default
`aerismusic8-alt/site-aeris-music`). The GitHub and YouTube credentials are
OpenHands secrets (`AX_GH_TOKEN`, `YT_CLIENT_ID`, `YT_CLIENT_SECRET`,
`YT_CH3_REFRESH_TOKEN`), read at run time.

The matching strategy pass is the `market-weekly` prompt automation, which reads
`work/market-report.md` plus `COMPETITOR-ANALYSIS.md` and opens one PR with the
changes it decides on.
