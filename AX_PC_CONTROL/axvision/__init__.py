"""AX Vision: a fast, always-on eye for PC1.

The old way of looking at the game was one screenshot per remote call. Every
look paid for a fresh PowerShell process, a PNG written to disk, and a round
trip through the rendezvous channel, which put a floor of about a second on
anything the agent wanted to see. That is far too slow to follow a game the way
a player does, and it made every action a guess followed by a slow check.

This package replaces that with a process that stays running on PC1. It grabs
the screen through GDI straight into memory, keeps the last few seconds of
frames, and answers questions about them locally: has the picture changed, where
did it change, which of the game's colours are on screen, what text is there.
The agent asks a question over the existing channel and gets a compact answer
back, but the pixels never travel and no process is started per look.

The arithmetic lives in small pure modules so it can be tested on the Linux
sandbox without a screen:

    geometry   rectangles: union, intersection, overlap, clamping
    signature  frames: change ratio, changed area, colour boxes, tiling
    state      a frame's stats turned into "world", "menu", "loading", "black"
    capture    the Windows-only part: GDI grab and window focus
    engine     the daemon that keeps the ring buffer and serves questions
    cli        what the agent actually calls on PC1
"""

__all__ = ["geometry", "signature", "state", "capture", "engine", "cli"]
