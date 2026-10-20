"""What changed between two frames, and where.

The agent's fastest useful question is "did anything happen". A screenshot
answers it slowly and by eye; this answers it in microseconds and as a number.
The functions take frames as numpy arrays shaped (h, w, 3) of uint8, and the
only engine-specific part is the capture that produced them.

Frame-diffing is deliberately coarse. Two frames of a running game are never
byte-identical, so an exact comparison would report "changed" for a still scene
with a flickering light. A pixel counts as changed only when it moves by more
than ``threshold`` on any channel, and the frame counts as changed only when
more than ``min_ratio`` of pixels moved. Both are arguments, so a test can pin
them down.
"""

from __future__ import annotations

import numpy as np

from . import geometry

Frame = np.ndarray

# A pixel that moves by less than this on every channel is the same pixel.
# Roblox's ambient light and anti-aliasing make a still frame jitter by a few
# levels, so 0 would report motion in a paused game.
DEFAULT_PIXEL_THRESHOLD = 24

# Below this share of changed pixels the frame is "still". A blinking cursor or
# a single animating badge is not a game event.
DEFAULT_MIN_RATIO = 0.005


def changed_mask(
    a: Frame, b: Frame, threshold: int = DEFAULT_PIXEL_THRESHOLD, step: int = 1
) -> np.ndarray:
    """A boolean array, True where the two frames differ by more than threshold.

    ``step`` samples every Nth pixel. A full-HD comparison costs about 57ms in
    numpy, which is most of a frame's budget at ten frames a second; sampling
    every second pixel cuts that fourfold and still catches a character moving,
    because a moving avatar covers many sampled pixels. Use step 1 when a
    pixel-exact answer is needed.
    """
    if a.shape != b.shape:
        raise ValueError(f"frame shapes differ: {a.shape} vs {b.shape}")
    if step > 1:
        a = a[::step, ::step]
        b = b[::step, ::step]
    # max-min on uint8 is the same as abs-difference without the int16 cast,
    # and it avoids a temporary of a wider dtype on every frame.
    return (np.maximum(a, b) - np.minimum(a, b)).max(axis=2) > threshold


def change_ratio(
    a: Frame, b: Frame, threshold: int = DEFAULT_PIXEL_THRESHOLD, step: int = 1
) -> float:
    """Share of pixels that changed, 0.0 to 1.0."""
    mask = changed_mask(a, b, threshold, step)
    total = mask.size
    return float(mask.sum()) / total if total else 0.0


def has_changed(
    a: Frame,
    b: Frame,
    threshold: int = DEFAULT_PIXEL_THRESHOLD,
    min_ratio: float = DEFAULT_MIN_RATIO,
    step: int = 1,
) -> bool:
    return change_ratio(a, b, threshold, step) >= min_ratio


def changed_boxes(
    a: Frame,
    b: Frame,
    threshold: int = DEFAULT_PIXEL_THRESHOLD,
    cols: int = 8,
    rows: int = 6,
    min_ratio: float = DEFAULT_MIN_RATIO,
    step: int = 1,
) -> list[geometry.Rect]:
    """Which tiles of the frame changed, as frame-relative rectangles.

    Tiles rather than per-pixel bounds because the caller wants to aim a look or
    a click at the region that moved, and a bounding box around scattered
    changed pixels covers the whole screen and says nothing.
    """
    mask = changed_mask(a, b, threshold, step)
    h, w = mask.shape
    boxes: list[geometry.Rect] = []
    for (tx, ty, tw, th) in geometry.tile((0, 0, w, h), cols, rows):
        if tw <= 0 or th <= 0:
            continue
        sub = mask[ty:ty + th, tx:tx + tw]
        if sub.size and (sub.sum() / sub.size) >= min_ratio:
            # Report in the coordinates of the original frames, so a caller that
            # sampled does not have to remember it did.
            boxes.append((tx * step, ty * step, tw * step, th * step))
    return boxes


def downscale(frame: Frame, max_width: int) -> tuple[Frame, int]:
    """A smaller copy of a frame for analysis, and the factor it was reduced by.

    The ring buffer holds a few seconds of frames. At full HD that is 373MB for
    sixty frames, which is enough to matter on a machine that is also running
    the game. Analysis does not need the detail: change detection, colour
    finding and the state classifier all work on a 480-wide copy. The factor is
    returned so coordinates can be scaled back to the screen.
    """
    if max_width <= 0 or frame.shape[1] <= max_width:
        return frame, 1
    factor = int(np.ceil(frame.shape[1] / max_width))
    return frame[::factor, ::factor], factor


def colour_share(frame: Frame, colour: tuple[int, int, int], tolerance: int = 40) -> float:
    """Share of pixels within ``tolerance`` of a colour on every channel.

    The game's panels are drawn in known colours, so "how much of this panel
    colour is on screen" is a cheap way to tell a HUD-heavy screen from a world
    screen without reading any text.
    """
    target = np.array(colour, dtype=np.int16)
    diff = np.abs(frame.astype(np.int16) - target)
    match = (diff.max(axis=2) <= tolerance)
    total = match.size
    return float(match.sum()) / total if total else 0.0


def colour_boxes(
    frame: Frame,
    colour: tuple[int, int, int],
    tolerance: int = 40,
    cols: int = 16,
    rows: int = 9,
    min_ratio: float = 0.08,
) -> list[geometry.Rect]:
    """Where on screen a colour appears, as coarse tiles.

    This is how a coloured button or a gold reward badge is located without
    OCR, which matters because the game's text is Thai and this machine's
    recogniser is English-only.
    """
    target = np.array(colour, dtype=np.int16)
    diff = np.abs(frame.astype(np.int16) - target)
    mask = (diff.max(axis=2) <= tolerance)
    h, w = mask.shape
    boxes: list[geometry.Rect] = []
    for (tx, ty, tw, th) in geometry.tile((0, 0, w, h), cols, rows):
        if tw <= 0 or th <= 0:
            continue
        sub = mask[ty:ty + th, tx:tx + tw]
        if sub.size and (sub.sum() / sub.size) >= min_ratio:
            boxes.append((tx, ty, tw, th))
    return boxes


def brightness(frame: Frame) -> float:
    """Mean luminance, 0 to 255. A near-black frame means nothing is drawing."""
    if frame.size == 0:
        return 0.0
    # Rec. 601 weights: the eye is far more sensitive to green than to blue, so
    # an unweighted mean calls a dark blue frame brighter than it looks.
    lum = (0.299 * frame[:, :, 0] + 0.587 * frame[:, :, 1] + 0.114 * frame[:, :, 2])
    return float(lum.mean())


def dark_share(frame: Frame, cutoff: int = 20) -> float:
    """Share of pixels that are essentially black."""
    if frame.size == 0:
        return 1.0
    lum = (0.299 * frame[:, :, 0] + 0.587 * frame[:, :, 1] + 0.114 * frame[:, :, 2])
    return float((lum < cutoff).mean())


def distinct_colours(frame: Frame, step: int = 4) -> int:
    """How many different colours the frame uses, sampled every ``step`` pixels.

    A rendered 3D world has thousands; a flat panel or a solid black screen has
    a handful. It is the cheapest way to tell "the game is drawing" from "the
    game is showing one panel".

    The count scales with resolution, so compare two frames of the same size
    with it, or use ``colour_density`` when the sizes differ. This bit the
    classifier: thresholds calibrated on PC1's 1600x900 screen called a
    320x180 capture "unknown", because the same scene has twenty-five times
    fewer pixels and therefore twenty-five times fewer colours.
    """
    if frame.size == 0:
        return 0
    return int(np.unique(_packed_sample(frame, step)).size)


def colour_density(frame: Frame, step: int = 4) -> float:
    """Share of sampled pixels whose colour is unique, 0.0 to 1.0.

    Resolution-independent, which is what a threshold needs to be. A rendered
    scene is mostly unique colours (measured 0.51 on PC1's 1600x900 screen); a
    flat panel is almost all one colour (about 0.0003).
    """
    if frame.size == 0:
        return 0.0
    sample = _packed_sample(frame, step)
    total = sample.size
    return float(np.unique(sample).size) / total if total else 0.0


def _packed_sample(frame: Frame, step: int) -> np.ndarray:
    """The frame sampled on a grid, each colour packed into one uint32.

    Packing lets ``np.unique`` compare whole colours instead of triples, which
    is several times faster and is what keeps a full-HD classification under a
    millisecond.
    """
    sample = frame[::step, ::step]
    return (
        (sample[:, :, 0].astype(np.uint32) << 16)
        | (sample[:, :, 1].astype(np.uint32) << 8)
        | sample[:, :, 2].astype(np.uint32)
    )


def signature(frame: Frame, cols: int = 8, rows: int = 6) -> list[int]:
    """A small fingerprint of a frame: mean luminance per tile.

    Kept for a quick "is this the same screen as last time" check that survives
    small jitter. For "did the character move" it is not enough on its own: the
    avatar is a small part of the frame, so averaging tiles hides it. Use
    ``change_ratio`` for motion.
    """
    if frame.size == 0:
        return []
    lum = (0.299 * frame[:, :, 0] + 0.587 * frame[:, :, 1] + 0.114 * frame[:, :, 2])
    out: list[int] = []
    for (tx, ty, tw, th) in geometry.tile((0, 0, frame.shape[1], frame.shape[0]), cols, rows):
        if tw <= 0 or th <= 0:
            continue
        out.append(int(lum[ty:ty + th, tx:tx + tw].mean()))
    return out


def crop(frame: Frame, rect: geometry.Rect) -> Frame:
    """The part of a frame inside a rectangle, clamped to the frame."""
    x, y, w, h = geometry.clamp(rect, (0, 0, frame.shape[1], frame.shape[0]))
    if w <= 0 or h <= 0:
        return frame[0:0, 0:0]
    return frame[y:y + h, x:x + w]
