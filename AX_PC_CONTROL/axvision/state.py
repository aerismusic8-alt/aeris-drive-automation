"""Turn a frame's statistics into a name the agent can act on.

Numbers are hard to reason about in the middle of a task. "Dark 94%, density
0.02" is the same fact as "the client menu is open", but only the second one
tells the agent to press ESC. This module is that translation, and it is pure:
it takes the statistics and returns a label plus the reason.

The labels are the states that actually change what the agent should do next:

    world     the 3D scene is drawing; movement and combat will work
    menu      the Roblox client menu (ESC) is over the game; it swallows keys
    panel     a large opaque panel covers the screen; close it first
    black     almost nothing is drawing; the renderer or the window is broken
    unknown   none of the above, which is worth knowing rather than guessing

Every threshold is a share or a density rather than a pixel count, and that is
the lesson from this module's own first version. The counts were calibrated on
PC1's 1600x900 screen, and then a 320x180 capture of the *same scene* was
classified "unknown", because a quarter-size frame has far fewer unique colours.
A threshold that changes with resolution is not a threshold.
"""

from __future__ import annotations

from dataclasses import dataclass, field

from . import signature

# A frame this dark is the client menu: it is a dark scrim over a dimmed game.
# The menu measured 94% dark on PC1 while the world measured 3.6%. The menu
# carries text and icons, so it is *not* flat - density is the wrong test here,
# and darkness is the right one.
MENU_DARK_SHARE = 0.80

# A frame this dark, at any resolution, is not drawing. Distinct from the menu
# because the fix is different: a menu needs ESC, a black screen needs the
# renderer checked.
BLACK_DARK_SHARE = 0.97

# The world has depth: lots of unique colours and little black. A rendered
# scene measured 0.51 colour density; a flat panel measured 0.0003. The gap is
# three orders of magnitude, so the exact cut is not delicate.
WORLD_MIN_DENSITY = 0.05
WORLD_MAX_DARK_SHARE = 0.55

# A flat, coloured screen: a loading screen or a single full-screen panel. It
# has almost no colour variety, which is what separates it from the world. The
# game's own panels are dark (its panel colour is RGB 18,20,28), so brightness
# cannot be the test: a dark panel and a dark menu look alike in brightness and
# are told apart by how much of the frame is black.
PANEL_MAX_DENSITY = 0.02


@dataclass
class FrameStats:
    """The measurements a frame contributes to a state decision."""

    brightness: float
    dark_share: float
    distinct_colours: int
    colour_density: float
    width: int = 0
    height: int = 0

    @classmethod
    def of(cls, frame, colour_step: int = 4) -> "FrameStats":
        return cls(
            brightness=signature.brightness(frame),
            dark_share=signature.dark_share(frame),
            distinct_colours=signature.distinct_colours(frame, step=colour_step),
            colour_density=signature.colour_density(frame, step=colour_step),
            width=0 if frame.size == 0 else int(frame.shape[1]),
            height=0 if frame.size == 0 else int(frame.shape[0]),
        )

    def as_dict(self) -> dict:
        return {
            "brightness": round(self.brightness, 1),
            "dark_share": round(self.dark_share, 3),
            "distinct_colours": self.distinct_colours,
            "colour_density": round(self.colour_density, 4),
            "width": self.width,
            "height": self.height,
        }


@dataclass
class ScreenState:
    """What the screen is showing, and why that was concluded."""

    label: str
    reason: str
    stats: FrameStats
    hints: list[str] = field(default_factory=list)

    def as_dict(self) -> dict:
        return {
            "state": self.label,
            "reason": self.reason,
            "hints": self.hints,
            **self.stats.as_dict(),
        }


def classify(stats: FrameStats) -> ScreenState:
    """Name the state a frame is in.

    Ordered from the most specific and most actionable to the least. The order
    matters: a truly black screen is dark *and* has almost no colour, exactly
    like the menu, so black is tested first. Otherwise the agent would press ESC
    on a dead renderer forever.
    """
    if stats.dark_share >= BLACK_DARK_SHARE:
        return ScreenState(
            "black",
            f"{stats.dark_share:.0%} of the frame is black",
            stats,
            ["check the client is running and the window is in front"],
        )

    if stats.dark_share >= MENU_DARK_SHARE:
        return ScreenState(
            "menu",
            f"{stats.dark_share:.0%} of the frame is dark",
            stats,
            ["press ESC to close the Roblox client menu", "movement keys do nothing until then"],
        )

    if stats.colour_density >= WORLD_MIN_DENSITY and stats.dark_share <= WORLD_MAX_DARK_SHARE:
        return ScreenState(
            "world",
            f"{stats.colour_density:.4f} density, {stats.dark_share:.0%} dark",
            stats,
            ["the 3D scene is drawing; input will reach the game"],
        )

    if stats.colour_density <= PANEL_MAX_DENSITY:
        return ScreenState(
            "panel",
            f"{stats.colour_density:.4f} density, {stats.dark_share:.0%} dark",
            stats,
            ["something opaque covers the screen", "look for a close button before acting"],
        )

    return ScreenState(
        "unknown",
        f"{stats.colour_density:.4f} density, {stats.dark_share:.0%} dark",
        stats,
        ["capture again, or crop to a region of interest"],
    )


def classify_frame(frame, colour_step: int = 4) -> ScreenState:
    return classify(FrameStats.of(frame, colour_step=colour_step))
