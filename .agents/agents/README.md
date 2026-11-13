# AR's team — curated, each tied to a real tool

Six file-based sub-agents that do actual work in this repo. Each one is bound to
**tools that exist on disk** and to a **standing rule** (K's rules, the HOLD, the
free-only gate), so none of them is a persona without hands. Loaded automatically
from `.agents/agents/` at conversation start (README.md is skipped by the loader).

| Agent | Does | Real tools it drives |
| --- | --- | --- |
| `ax-advisor` | Runs the consultation gate, keeps dissent, reports quorum | `ops/consult.py`, `duck_ask.py`, `pollinations_ask.py`, `websearch.py` |
| `ax-evidence` | Reads the 4 surfaces, classifies fresh/stale/unknown, refuses bad-data verdicts | `aeris938-2/scripts/evidence.py`, `surfaces.py`, `ops/studio_read.py` |
| `ax-experiment` | Turns a constraint into ONE recorded non-duplicate test, respects the HOLD | `experiment_loop.py`, `goal_watch.py`, `metadata_ab.py` |
| `ax-session` | Keeps/recoveries the free browser session without asking K | `check_login.py`, `ops/login_vault.py`, `fb_relogin.py`, `bootstrap.py` |
| `ax-delivery` | Gets an artifact to a reachable destination and proves it | `gh-api.py`, `use-app-token.sh`, `vault_session.py`, `ffprobe` |
| `ax-hygiene` | Keeps the repo guards green (memory cap, tests, wiring, risk) | `memory_guard.py`, `memory_search.py`, tests, `check-hud-wiring.py` |

## Rules that bind all of them

1. **Free only** (K, Rule #1). No paid API, subscription or credit pack, ever.
2. **The HOLD is in force** (2026-11-13): no upload, no render, no enabling a rail.
   Prepare, measure and record — do not publish.
3. **Never ask K for a Google login.** Recover it yourself; a 2FA challenge is the
   only thing that goes back to K.
4. **Never decide on stale/missing data** — `evidence.py` is the contract.
5. **Consult before deciding** — `ax-advisor`, and count vendors, not channels.

## Adding a member

Keep the bar: a new agent earns a slot only if it (a) drives a tool that exists,
(b) has a rule that would otherwise be forgotten, and (c) is not a rename of an
existing one. The pinning test `test_ax_team_is_well_formed` checks the format and
the coverage, so a broken file fails the suite rather than silently doing nothing.
