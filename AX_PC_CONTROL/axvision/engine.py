"""The always-on eye: a daemon that watches PC1 and answers questions fast.

Why a daemon rather than a script per look: the slow part of the old approach
was never the pixels, it was starting a process and shipping a PNG. A process
that stays resident can capture ten times a second, keep the last few seconds in
a ring buffer, and answer "what changed", "what state is the game in" and "what
was on screen 2 seconds ago" from memory. The agent then asks one short question
over the existing channel and gets one short answer.

The engine is deliberately thin: all the arithmetic lives in ``signature`` and
``state``, which are testable without Windows. This file only owns the loop, the
ring buffer, and the question dispatch, and it takes its capture function as an
argument so a test can drive it with synthetic frames.

It also records what it sees to a small JSON-lines file. That is the difference
between "the game did not react" and "the game reacted and then something else
happened": the log survives the moment.
"""

from __future__ import annotations

import json
import os
import threading
import time
from collections import deque
from dataclasses import dataclass, field

from . import geometry, signature, state


@dataclass
class Frame:
    """One captured frame with the facts about when and where it came from."""

    index: int
    at: float
    rect: geometry.Rect
    pixels: object
    state: state.ScreenState = None  # type: ignore[assignment]

    def stats(self) -> dict:
        return self.state.as_dict() if self.state else {}


class Engine:
    """Captures frames in a background thread and answers questions about them.

    ``grabber`` is any callable taking a rectangle and returning an (h, w, 3)
    uint8 array. On PC1 that is ``capture.Grabber().grab``; in a test it is a
    function returning whatever frame the test wants the engine to have seen.
    """

    def __init__(
        self,
        grabber,
        rect: geometry.Rect,
        *,
        interval: float = 0.1,
        history: int = 60,
        classify_every: int = 5,
        analysis_width: int = 480,
        log_path: str | None = None,
        frozen_after: float = 8.0,
        clock=time.time,
    ) -> None:
        self.grabber = grabber
        self.rect = rect
        self.interval = interval
        self.classify_every = max(1, classify_every)
        # Frames are stored reduced. Sixty full-HD frames is 373MB, which is a
        # lot to hold on a machine that is also running the game, and none of
        # the analysis needs the detail. The factor is kept so a box found in a
        # reduced frame can be reported in screen coordinates.
        self.analysis_width = analysis_width
        self.history = history
        self.frames: deque[Frame] = deque(maxlen=history)
        self.log_path = log_path
        # A stalled client keeps drawing the same picture, and "the world is
        # there" is the wrong answer for it. Eight seconds is longer than any
        # real pause in a game that is running (a loading screen still animates)
        # and short enough to notice before acting on a dead surface.
        self.frozen_after = frozen_after
        self.clock = clock
        self._stop = threading.Event()
        self._thread: threading.Thread | None = None
        self._lock = threading.Lock()
        self._next_index = 0
        self._last_error: str | None = None
        self._scale = 1
        self._still_since: float | None = None
        self._prev_pixels = None

    @property
    def scale(self) -> int:
        """How much a stored frame is reduced compared to the screen."""
        return self._scale

    def _to_screen(self, box: geometry.Rect) -> geometry.Rect:
        """A box found in a stored frame, in screen coordinates."""
        s = self._scale
        return (box[0] * s + self.rect[0], box[1] * s + self.rect[1], box[2] * s, box[3] * s)

    # --- lifecycle ------------------------------------------------------
    def start(self) -> None:
        if self._thread and self._thread.is_alive():
            return
        self._stop.clear()
        self._thread = threading.Thread(target=self._run, name="axvision", daemon=True)
        self._thread.start()

    def stop(self, timeout: float = 2.0) -> None:
        self._stop.set()
        if self._thread:
            self._thread.join(timeout=timeout)
            self._thread = None

    def _run(self) -> None:
        while not self._stop.is_set():
            began = time.time()
            self.capture_once()
            # Sleep the remainder of the interval rather than a fixed amount, so
            # a slow capture does not silently halve the frame rate.
            rest = self.interval - (time.time() - began)
            if rest > 0:
                self._stop.wait(rest)

    # --- capture --------------------------------------------------------
    def capture_once(self) -> Frame | None:
        try:
            pixels = self.grabber(self.rect)
        except Exception as exc:  # a capture failure must not kill the loop
            self._last_error = str(exc)
            return None
        pixels, factor = signature.downscale(pixels, self.analysis_width)
        self._scale = factor
        now = self.clock()
        # Whether the picture is moving is tracked on the raw comparison rather
        # than on the classifier, because a frozen world and a frozen menu are
        # the same problem and both need the same answer.
        if self._prev_pixels is not None and not signature.has_changed(self._prev_pixels, pixels, step=4):
            if self._still_since is None:
                self._still_since = now
        else:
            self._still_since = None
        self._prev_pixels = pixels
        index = self._next_index
        self._next_index += 1
        frame = Frame(index=index, at=now, rect=self.rect, pixels=pixels)
        if index % self.classify_every == 0:
            frame.state = state.classify_frame(pixels)
        with self._lock:
            self.frames.append(frame)
        self._log(frame)
        return frame

    def _log(self, frame: Frame) -> None:
        if not self.log_path or not frame.state:
            return
        try:
            with open(self.log_path, "a", encoding="utf-8") as fh:
                fh.write(json.dumps({"i": frame.index, "t": round(frame.at, 3), **frame.state.as_dict()}) + "\n")
        except OSError:
            pass

    # --- questions ------------------------------------------------------
    def latest(self) -> Frame | None:
        with self._lock:
            return self.frames[-1] if self.frames else None

    def at_or_before(self, when: float) -> Frame | None:
        with self._lock:
            best = None
            for f in self.frames:
                if f.at <= when:
                    best = f
            return best

    def window(self, seconds: float) -> list[Frame]:
        cutoff = self.clock() - seconds
        with self._lock:
            return [f for f in self.frames if f.at >= cutoff]

    def frozen(self) -> tuple[bool, int]:
        """Whether the picture has stopped changing, and for how long.

        A caller that only sees "world" cannot tell a running game from a hung
        one. Both are reported, so the answer is actionable: a frozen screen
        means restart the client, not press the key again.
        """
        since = self._still_since
        if since is None:
            return False, 0
        still = self.clock() - since
        return still >= self.frozen_after, int(still * 1000)

    def _freshness(self) -> dict:
        frozen, still_ms = self.frozen()
        return {"frozen": frozen, "still_ms": still_ms}

    def answer(self, question: str, **kwargs) -> dict:
        """Answer one of the questions the agent asks.

        Each answer carries the frame it came from, because "the screen is
        black" is only useful with "at 12.4s, 300ms ago".
        """
        if question == "state":
            f = self.latest()
            if not f:
                return {"ok": False, "error": "no frames captured yet", "last_error": self._last_error}
            st = f.state or state.classify_frame(f.pixels)
            return {"ok": True, "age_ms": int((self.clock() - f.at) * 1000), **st.as_dict(),
                    **self._freshness()}

        if question == "changed":
            return self._answer_changed(**kwargs)

        if question == "colour":
            return self._answer_colour(**kwargs)

        if question == "motion":
            return self._answer_motion(**kwargs)

        if question == "health":
            return {
                "ok": True,
                "frames": len(self.frames),
                "next_index": self._next_index,
                "rect": geometry.as_dict(self.rect),
                "interval": self.interval,
                "scale": self._scale,
                "analysis_width": self.analysis_width,
                "last_error": self._last_error,
                "running": bool(self._thread and self._thread.is_alive()),
            }

        if question == "snapshot":
            return self._answer_snapshot(**kwargs)

        return {"ok": False, "error": f"unknown question '{question}'"}

    def _answer_snapshot(self, out: str = "", width: int = 0) -> dict:
        """Save the exact frame the last answer came from.

        This exists so evidence matches analysis. A separate screenshot tool
        grabs the screen at a different moment, possibly after the focus
        changed, so the picture saved for a human to look at is not the picture
        the numbers were computed from. Writing the stored frame removes that
        gap, and it is what lets a visual check be trusted.

        It works off the reduced frame, so the saved image is small and comes
        back through the remote channel quickly.
        """
        f = self.latest()
        if not f:
            return {"ok": False, "error": "no frames captured yet"}
        try:
            from PIL import Image
        except ImportError as exc:
            return {"ok": False, "error": f"Pillow missing: {exc}"}
        if not out:
            return {"ok": False, "error": "snapshot needs an output path"}
        pixels = f.pixels
        image = Image.fromarray(pixels)
        if width and width < pixels.shape[1]:
            ratio = width / pixels.shape[1]
            image = image.resize((width, max(1, int(pixels.shape[0] * ratio))))
        image.save(out)
        return {
            "ok": True,
            "path": out,
            "frame": f.index,
            "age_ms": int((self.clock() - f.at) * 1000),
            "stored": {"w": int(pixels.shape[1]), "h": int(pixels.shape[0])},
            "saved": {"w": image.width, "h": image.height},
            "scale": self._scale,
        }

    def _answer_changed(self, seconds: float = 1.0, threshold: int = signature.DEFAULT_PIXEL_THRESHOLD,
                        min_ratio: float = signature.DEFAULT_MIN_RATIO) -> dict:
        frames = self.window(seconds)
        if len(frames) < 2:
            return {"ok": False, "error": f"only {len(frames)} frames in the last {seconds}s"}
        first, last = frames[0], frames[-1]
        ratio = signature.change_ratio(first.pixels, last.pixels, threshold)
        boxes = signature.changed_boxes(first.pixels, last.pixels, threshold)
        # Boxes are in frame coordinates; the caller wants screen coordinates.
        screen_boxes = [geometry.as_dict(self._to_screen(b)) for b in boxes]
        return {
            "ok": True,
            "changed": ratio >= min_ratio,
            "ratio": round(ratio, 4),
            "boxes": screen_boxes,
            "frames_compared": [first.index, last.index],
            "span_s": round(last.at - first.at, 3),
            **self._freshness(),
        }

    def _answer_colour(self, colour=(255, 206, 84), tolerance: int = 40, min_ratio: float = 0.08) -> dict:
        f = self.latest()
        if not f:
            return {"ok": False, "error": "no frames captured yet"}
        colour = tuple(colour)
        share = signature.colour_share(f.pixels, colour, tolerance)
        boxes = signature.colour_boxes(f.pixels, colour, tolerance, min_ratio=min_ratio)
        screen_boxes = [geometry.as_dict(self._to_screen(b)) for b in boxes]
        return {
            "ok": True,
            "colour": list(colour),
            "share": round(share, 4),
            "boxes": screen_boxes,
            "age_ms": int((self.clock() - f.at) * 1000),
        }

    def _answer_motion(self, seconds: float = 1.0, threshold: int = signature.DEFAULT_PIXEL_THRESHOLD) -> dict:
        """Frame-to-frame change across the window, which is what motion is.

        A single before/after comparison can miss a character that walked and
        came back. Looking at every consecutive pair and reporting the peak
        catches a brief move that a two-frame diff would average away.
        """
        frames = self.window(seconds)
        if len(frames) < 2:
            return {"ok": False, "error": f"only {len(frames)} frames in the last {seconds}s"}
        peaks = []
        for a, b in zip(frames, frames[1:]):
            peaks.append(signature.change_ratio(a.pixels, b.pixels, threshold))
        peak = max(peaks) if peaks else 0.0
        return {
            "ok": True,
            "moving": peak >= signature.DEFAULT_MIN_RATIO,
            "peak_ratio": round(peak, 4),
            "mean_ratio": round(sum(peaks) / len(peaks), 4) if peaks else 0.0,
            "samples": len(peaks),
        }


def default_rect(padding: int = 0) -> geometry.Rect:
    """The Roblox client area if a game window is found, otherwise the screen."""
    from . import capture  # imported here so Linux never needs it at module load

    hwnd = capture.find_game_window()
    if hwnd:
        r = capture.client_rect(hwnd)
        if not geometry.is_empty(r):
            return r
    screen = capture.Screen()
    return screen.rect()
