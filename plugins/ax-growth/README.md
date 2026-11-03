# ax-growth

An OpenHands automation plugin (script runner, no LLM) that grows the AERIS
Music Facebook Page.

K's rule (2026-11-03): a Page grows by following suggested pages and inviting
the profile's friends, not by waiting for real friendships. This runs the
following half twice a day.

Each run:

1. fetches the repo tarball over HTTPS (the automation sandbox has no git
   transport, so a `git clone` hangs until the run times out),
2. installs Playwright's Chromium and restores the saved session from
   `AERIS_STORAGE_STATE_B64` — the same free route the crosspost rail uses,
3. runs `aeris938-2/scripts/outreach.py --follow`: it switches to the Page
   identity, follows a small paced batch of suggested pages, and records each
   one in `aeris938-2/work/outreach-state.json`,
4. commits that state back to `main` through the Contents API so a page is never
   followed twice and the next run resumes.

The identity gate matters: a follow only lands on the Page when the Page is the
acting identity *before* the follow grid loads. The grid does not offer the
switch, so switching after it is a silent no-op and every follow lands on the
personal profile. `outreach.py` switches first and confirms the Page's own
follow count rose.

Config: `limit` (default 12), `min_gap` (default 8). The credentials are
OpenHands secrets (`AX_GH_TOKEN`, `AERIS_STORAGE_STATE_B64`), read at run time.

This is a plugin-spec automation rather than a GitHub workflow because no token
here carries `workflow` scope.
