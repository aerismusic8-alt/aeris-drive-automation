"""The Windows-only part: grab pixels, and find and focus windows.

Everything here needs Windows, so the DLLs are looked up on first use rather
than at import. That matters: the CLI imports this module in a try block so a
missing screen becomes a JSON error instead of a traceback, and an import-time
``ctypes.windll`` lookup would break that on any machine that is not Windows.

Two choices matter for speed, and both were made after measuring the old way:

* Capture goes through GDI (``BitBlt``) into a bitmap that is reused between
  calls. The old path wrote a PNG to disk and read it back, which is a
  millisecond of pixels wrapped in tens of milliseconds of file I/O, and it
  grew the disk by a megabyte a second while watching a game.
* A capture returns a numpy array directly. That is what the analysis modules
  want, so no format conversion sits between the screen and the answer.

Window lookup uses GDI rather than ``PrintWindow`` on purpose: Roblox is a GPU
surface, and ``PrintWindow`` on a Direct3D window often returns black.
``BitBlt`` from the screen works because Roblox renders when it is foreground,
which is also why the focus helpers here exist.
"""

from __future__ import annotations

import ctypes
import os
from ctypes import wintypes

import numpy as np

# GDI constants. SRCCOPY copies the source pixels straight through, which is
# what a screenshot wants; CAPTUREBLT includes layered windows, which matters
# because part of Roblox's UI is layered.
SRCCOPY = 0x00CC0020
CAPTUREBLT = 0x40000000

DIB_RGB_COLORS = 0
BI_RGB = 0

_IS_WINDOWS = os.name == "nt"


def _libs():
    """The Windows DLLs, looked up on first use.

    Raises OSError off Windows, which the caller turns into a JSON error.
    """
    if not _IS_WINDOWS:
        raise OSError("screen capture needs Windows")
    return ctypes.windll.user32, ctypes.windll.gdi32


class BITMAPINFOHEADER(ctypes.Structure):
    _fields_ = [
        ("biSize", wintypes.DWORD),
        ("biWidth", wintypes.LONG),
        ("biHeight", wintypes.LONG),
        ("biPlanes", wintypes.WORD),
        ("biBitCount", wintypes.WORD),
        ("biCompression", wintypes.DWORD),
        ("biSizeImage", wintypes.DWORD),
        ("biXPelsPerMeter", wintypes.LONG),
        ("biYPelsPerMeter", wintypes.LONG),
        ("biClrUsed", wintypes.DWORD),
        ("biClrImportant", wintypes.DWORD),
    ]


class BITMAPINFO(ctypes.Structure):
    _fields_ = [("bmiHeader", BITMAPINFOHEADER), ("bmiColors", wintypes.DWORD * 3)]


class Screen:
    """The primary screen's size in pixels."""

    def __init__(self) -> None:
        user32, _ = _libs()
        self.width = user32.GetSystemMetrics(0)
        self.height = user32.GetSystemMetrics(1)

    def rect(self) -> tuple[int, int, int, int]:
        return (0, 0, self.width, self.height)


class Grabber:
    """Captures rectangles of the screen into numpy arrays.

    One device context and one bitmap are created up front and reused. Creating
    them per capture is what made the old per-screenshot scripts slow, and a
    daemon that looks ten times a second cannot afford it.
    """

    def __init__(self) -> None:
        self._user32, self._gdi32 = _libs()
        self._screen_dc = self._user32.GetDC(0)
        self._mem_dc = self._gdi32.CreateCompatibleDC(self._screen_dc)
        self._bitmap = None
        self._bitmap_old = None
        self._size = (0, 0)
        self._buffer = None
        self._info = None

    def _ensure(self, w: int, h: int) -> None:
        if self._size == (w, h):
            return
        self._release_bitmap()
        self._bitmap = self._gdi32.CreateCompatibleBitmap(self._screen_dc, w, h)
        self._bitmap_old = self._gdi32.SelectObject(self._mem_dc, self._bitmap)
        # biHeight is negative for a top-down bitmap, so row 0 is the top of the
        # screen. The default bottom-up layout would return every frame upside
        # down and cost a flip on every capture.
        self._info = BITMAPINFO()
        self._info.bmiHeader.biSize = ctypes.sizeof(BITMAPINFOHEADER)
        self._info.bmiHeader.biWidth = w
        self._info.bmiHeader.biHeight = -h
        self._info.bmiHeader.biPlanes = 1
        self._info.bmiHeader.biBitCount = 32
        self._info.bmiHeader.biCompression = BI_RGB
        self._buffer = ctypes.create_string_buffer(w * h * 4)
        self._size = (w, h)

    def _release_bitmap(self) -> None:
        if self._bitmap:
            self._gdi32.SelectObject(self._mem_dc, self._bitmap_old)
            self._gdi32.DeleteObject(self._bitmap)
            self._bitmap = None
            self._bitmap_old = None

    def grab(self, rect: tuple[int, int, int, int]) -> np.ndarray:
        """The pixels of ``rect`` as an (h, w, 3) uint8 RGB array."""
        x, y, w, h = rect
        if w <= 0 or h <= 0:
            return np.zeros((0, 0, 3), dtype=np.uint8)
        self._ensure(w, h)
        ok = self._gdi32.BitBlt(
            self._mem_dc, 0, 0, w, h, self._screen_dc, x, y, SRCCOPY | CAPTUREBLT
        )
        if not ok:
            raise OSError(f"BitBlt failed for {rect}")
        self._gdi32.GetDIBits(
            self._mem_dc, self._bitmap, 0, h, self._buffer, ctypes.byref(self._info), DIB_RGB_COLORS
        )
        raw = np.frombuffer(self._buffer, dtype=np.uint8, count=w * h * 4)
        # BGRA from GDI, RGB for everything else.
        bgra = raw.reshape(h, w, 4)
        return np.ascontiguousarray(bgra[:, :, [2, 1, 0]])

    def close(self) -> None:
        self._release_bitmap()
        if self._mem_dc:
            self._gdi32.DeleteDC(self._mem_dc)
            self._mem_dc = None
        if self._screen_dc:
            self._user32.ReleaseDC(0, self._screen_dc)
            self._screen_dc = None


def window_title(hwnd: int) -> str:
    """A window's title text, or an empty string."""
    if not hwnd:
        return ""
    user32, _ = _libs()
    length = user32.GetWindowTextLengthW(hwnd)
    if length <= 0:
        return ""
    buf = ctypes.create_unicode_buffer(length + 1)
    user32.GetWindowTextW(hwnd, buf, length + 1)
    return buf.value


def find_window(title_part: str, exclude: str = "") -> int:
    """The handle of the first visible top-level window whose title contains a
    string, or 0.

    A substring match rather than an exact one: the Roblox window title changes
    with the experience name and with Studio's open file. ``exclude`` skips
    titles containing another string, which is how the game window is found on a
    machine that also has the editor open - both are "Roblox", and picking the
    editor reports a healthy viewport for the wrong thing.
    """
    user32, _ = _libs()
    found = []

    @ctypes.WINFUNCTYPE(ctypes.c_bool, wintypes.HWND, wintypes.LPARAM)
    def cb(hwnd, _lparam):
        if not user32.IsWindowVisible(hwnd):
            return True
        length = user32.GetWindowTextLengthW(hwnd)
        if length <= 0:
            return True
        buf = ctypes.create_unicode_buffer(length + 1)
        user32.GetWindowTextW(hwnd, buf, length + 1)
        title = buf.value.lower()
        if title_part.lower() in title and (not exclude or exclude.lower() not in title):
            found.append(hwnd)
            return False
        return True

    user32.EnumWindows(cb, 0)
    return int(found[0]) if found else 0


def find_game_window() -> int:
    """The live Roblox *player* window, preferring it over Studio.

    Studio's title contains "Roblox Studio"; the client's is the experience
    name. When both are open the game is the one to watch.
    """
    return find_window("Roblox", exclude="Studio") or find_window("Roblox")


def window_rect(hwnd: int) -> tuple[int, int, int, int]:
    user32, _ = _libs()
    r = wintypes.RECT()
    if not user32.GetWindowRect(hwnd, ctypes.byref(r)):
        return (0, 0, 0, 0)
    return (r.left, r.top, r.right - r.left, r.bottom - r.top)


def client_rect(hwnd: int) -> tuple[int, int, int, int]:
    """The drawable area of a window, in screen coordinates.

    The window rectangle includes the title bar and borders, which are not part
    of the game. Cropping to the client area is what makes a coordinate read
    from a capture clickable in the game.
    """
    user32, _ = _libs()
    r = wintypes.RECT()
    if not user32.GetClientRect(hwnd, ctypes.byref(r)):
        return (0, 0, 0, 0)
    origin = wintypes.POINT(0, 0)
    user32.ClientToScreen(hwnd, ctypes.byref(origin))
    return (origin.x, origin.y, r.right - r.left, r.bottom - r.top)


def focus(hwnd: int) -> bool:
    """Bring a window to the front and give it keyboard focus.

    Roblox only renders while it is the foreground window, so this is a
    precondition for a meaningful capture, not a convenience.
    """
    if not hwnd:
        return False
    user32, _ = _libs()
    user32.ShowWindow(hwnd, 9)  # SW_RESTORE
    user32.SetForegroundWindow(hwnd)
    user32.SetFocus(hwnd)
    return user32.GetForegroundWindow() == hwnd


def is_foreground(hwnd: int) -> bool:
    user32, _ = _libs()
    return bool(hwnd) and user32.GetForegroundWindow() == hwnd


def window_at(x: int, y: int) -> tuple[int, str]:
    """The window handle and title under a point, for the "who stole my click"
    question."""
    user32, _ = _libs()
    pt = wintypes.POINT(x, y)
    hwnd = user32.WindowFromPoint(pt)
    length = user32.GetWindowTextLengthW(hwnd)
    buf = ctypes.create_unicode_buffer(length + 1)
    user32.GetWindowTextW(hwnd, buf, length + 1)
    return int(hwnd), buf.value
