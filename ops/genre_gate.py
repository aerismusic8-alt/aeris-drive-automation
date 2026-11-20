"""The genre chokepoint for every publish route.

K (2026-11-18): "ทำแนวสนุกอย่างเดียว" — pop/synthpop/edm/rock/hiphop/rap/
alternative only. Every other genre is PARKED and must never be uploaded.
`genres.publishable()` is the rule; this module makes sure no route can skip it.

YouTube has had this gate since 2026-11-19. Facebook and TikTok did not, so a
parked song could reach them even though the identical clip was refused for
YouTube — and the Facebook queue held 81 such items on 2026-11-20 (lukthung,
indie, symphonic, and the twenty เพื่อชีวิต originals that carry no genre at
all). The gate lives here, next to `clip_standard`, because those are the two
things every upload route already calls.
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

_HERE = os.path.dirname(os.path.abspath(__file__))
_ROOT = os.path.dirname(_HERE)
for _p in (_HERE, os.path.join(_ROOT, "music938-1", "scripts")):
    if _p not in sys.path:
        sys.path.insert(0, _p)

import genres  # noqa: E402  (path set up above)


def assert_ok(path: str, *, allow: str | None = None) -> None:
    """Raise SystemExit unless the clip's song is in a publishable genre.

    The song is read from the filename. A clip that matches no lyric file is
    refused rather than assumed safe: that is how the twenty เพื่อชีวิต
    originals slipped out on 2026-11-19. `allow` names a slug explicitly for a
    clip whose filename is not the song (a bank variant, an exhibit), so a
    caller that knows the song never has to guess.
    """
    slug = allow or genres.resolve_slug(os.path.basename(path))
    if slug is None:
        raise SystemExit(
            f"GENRE GATE: refusing to publish {os.path.basename(path)} — its name "
            f"matches no lyric file, so its genre is unknowable")
    ok, why = genres.publishable(slug)
    if not ok:
        raise SystemExit(f"GENRE GATE: refusing to publish {os.path.basename(path)} — {why}")
