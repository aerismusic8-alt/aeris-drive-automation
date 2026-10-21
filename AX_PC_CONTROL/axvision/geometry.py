"""Rectangles, in the one shape the rest of AX Vision agrees on.

A rectangle is a 4-tuple ``(x, y, w, h)`` in pixels with the origin at the top
left of the screen, which is what Windows uses for window rectangles and what
GDI uses for a capture. Everything here is pure arithmetic: no engine, no
screen, so a test can drive it on the sandbox.
"""

from __future__ import annotations

Rect = tuple[int, int, int, int]


def width(r: Rect) -> int:
    return r[2]


def height(r: Rect) -> int:
    return r[3]


def right(r: Rect) -> int:
    return r[0] + r[2]


def bottom(r: Rect) -> int:
    return r[1] + r[3]


def area(r: Rect) -> int:
    return max(0, r[2]) * max(0, r[3])


def is_empty(r: Rect) -> bool:
    return r[2] <= 0 or r[3] <= 0


def clamp(r: Rect, bounds: Rect) -> Rect:
    """The part of ``r`` that lies inside ``bounds``.

    A window can be dragged so that half of it is off screen. Capturing the
    requested rectangle then fails or returns a wrong-sized bitmap, so callers
    clamp first and use the result to know what they actually got.
    """
    x1 = max(r[0], bounds[0])
    y1 = max(r[1], bounds[1])
    x2 = min(right(r), right(bounds))
    y2 = min(bottom(r), bottom(bounds))
    return (x1, y1, max(0, x2 - x1), max(0, y2 - y1))


def intersect(a: Rect, b: Rect) -> Rect:
    x1 = max(a[0], b[0])
    y1 = max(a[1], b[1])
    x2 = min(right(a), right(b))
    y2 = min(bottom(a), bottom(b))
    return (x1, y1, max(0, x2 - x1), max(0, y2 - y1))


def contains(outer: Rect, inner: Rect) -> bool:
    return (
        inner[0] >= outer[0]
        and inner[1] >= outer[1]
        and right(inner) <= right(outer)
        and bottom(inner) <= bottom(outer)
    )


def union(a: Rect, b: Rect) -> Rect:
    if is_empty(a):
        return b
    if is_empty(b):
        return a
    x1 = min(a[0], b[0])
    y1 = min(a[1], b[1])
    x2 = max(right(a), right(b))
    y2 = max(bottom(a), bottom(b))
    return (x1, y1, x2 - x1, y2 - y1)


def overlap_area(a: Rect, b: Rect) -> int:
    return area(intersect(a, b))


def iou(a: Rect, b: Rect) -> float:
    """Intersection over union, 0.0 to 1.0.

    Used to decide whether two detections on consecutive frames are the same
    thing that moved a little, or two different things.
    """
    inter = overlap_area(a, b)
    if inter == 0:
        return 0.0
    total = area(a) + area(b) - inter
    return inter / total if total else 0.0


def tile(r: Rect, cols: int, rows: int) -> list[Rect]:
    """Split a rectangle into a grid, used to say *where* a frame changed.

    The remainder pixels are given to the last column and row so the tiles
    cover the whole rectangle with no gaps.
    """
    if cols < 1 or rows < 1:
        return []
    cw = r[2] // cols
    ch = r[3] // rows
    out: list[Rect] = []
    for row in range(rows):
        for col in range(cols):
            x = r[0] + col * cw
            y = r[1] + row * ch
            w = cw + (r[2] - cw * cols if col == cols - 1 else 0)
            h = ch + (r[3] - ch * rows if row == rows - 1 else 0)
            out.append((x, y, w, h))
    return out


def centre(r: Rect) -> tuple[int, int]:
    return (r[0] + r[2] // 2, r[1] + r[3] // 2)


def as_dict(r: Rect) -> dict:
    return {"x": r[0], "y": r[1], "w": r[2], "h": r[3]}
