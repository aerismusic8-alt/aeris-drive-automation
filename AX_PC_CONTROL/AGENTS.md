# AX_PC_CONTROL

Remote control of PC1 (Windows) from this Linux sandbox, over a reverse channel:
the Windows worker polls a rendezvous service that runs here, so no inbound port
is needed on PC1.

## How it fits together

| Piece | Runs where | Purpose |
| --- | --- | --- |
| `ax-rendezvous.py` | sandbox, port 12000 | Queue of tool calls and their results. `/ax/jobs` for the worker, `/ax/enqueue` + `/ax/state` for us. |
| `ax-pc1-worker.py` | PC1, as a scheduled task | Polls `/ax/jobs`, calls the local winremote MCP server, posts the result back. |
| `ax-push-script.py` | sandbox | Upload a PowerShell script to PC1 and run it, returning its output. |
| `ax-pull-file.py` | sandbox | Download a file from PC1 as base64. |
| `windows/` | source in repo | The PowerShell tools that get pushed, plus the C# helper they depend on. |

## Three limits that shape every tool

These are not preferences. Each one broke a working script before it was written
down, and each cost most of a session.

**1. A remote `Shell` call is killed at 30 seconds, and a killed call returns no
result at all.** Not an error, not partial output — nothing, so the caller hangs
and the queue stalls. Any script that compiles something, waits on a key, or
sleeps more than a few seconds must be started detached and its output polled
from a file. `ax-push-script.py` does this: it launches the script with
`Start-Process`, writes output and an `AX_DONE` marker to a file, then polls
`FileRead`. Use it rather than sending a long command over `Shell`.

**2. `Add-Type` with inline C# costs a minute or more.** csc start-up plus the
antivirus scan of the fresh assembly dominate, and it does not fit the 30 second
cap. Compile the helper once into `ax-helper.dll`
(`windows/ax-build-helper.ps1`, driven by `windows/ax-push-helper.py`)
and load it with `Add-Type -Path`, which takes about a second. Re-run the build
only after editing `windows/ax-helper.cs`.

**3. The worker has no per-job timeout.** If an MCP call never returns, the worker
sits on what it already dequeued and everything queued behind it looks stuck. It
usually recovers on its own when the call finally times out, so wait a couple of
minutes and re-check `/ax/state` before concluding the machine is gone. A
`GetSystemInfo` that returns is the cleanest liveness test.

## Driving the Roblox game

**Roblox only renders when its window is the foreground window.** Backgrounded,
it stops drawing and screenshots go stale or black. Focus before every capture —
`ax-game.ps1`, `ax-move.ps1` and `ax-see.ps1` all do this themselves.

**A stray always-on-top window steals the clicks.** PC1 also carries other people's
sessions, and an always-on-top terminal sat exactly over the game's Close button:
every click was delivered to that window, the dialog never closed, and movement
keys did nothing. `ax-unblock.ps1` finds the window under a point, moves it off
screen (move, never kill — it is not ours), and confirms the point now belongs to
the game before clicking.

**ESC opens the Roblox client menu, and WASD does nothing until it is closed.** ESC
toggles it. `ax-play2.ps1` uses frame darkness as the test: the world is bright,
the menu is almost all black.

**Prove input landed by measuring the frame, not by trusting the call.** A key can
be sent successfully and do nothing. Capture before and after in the same process
(a separate call loses the focus) and compare. `ax-move.ps1` does exactly this.
An ESC press that changes 84% of the frame is proof the keyboard reaches the game;
identical frames mean it does not.

## Reading the screen

**Windows OCR here only has en-US, and the game interface is Thai.** Read text
comes out as mojibake, so do not plan actions from it. What works instead:

- Frame brightness: `ax-play2.ps1` reports a darkness percentage, which reliably
  separates the world from the menu, a loading screen or a modal panel.
- Image differencing: a changed frame proves the game reacted. A static frame
  while the process is responding and using CPU means something is covering it.
- OCR for coordinates only when the text is Latin (`ax-see.ps1` returns a
  bounding box and centre point per line, in screen coordinates).

Thai OCR is **not installable on this machine**, and that is measured, not
assumed (`windows/ax-ocr-langs.ps1`). The image has `Language.Basic~~~th-TH`
installed but `Language.OCR` for Thai is `NotPresent`, adding it returns
`NotPresent`, and the recogniser answers `AvailableRecognizerLanguages = en-US`
with `IsLanguageSupported('th-TH') = False`. Do not spend another session on
`Add-WindowsCapability` for Thai; read the game from pixels instead.

## The rendering ceiling on PC1

PC1 is an Intel HD Graphics adapter (driver 9.17.10.4459). It cannot supply
several of Roblox's shaders, and the client log repeats `shader
DefaultUnifiedFlatTransparentVS... is not available`; the world then draws almost
black with only the HUD visible. This is why a moved character cannot be seen
moving here.

It is also the useful finding: the machines that cannot run the game are the ones
most players own, so the fix belongs in the game, not only on this box. The place
now ships Voxel lighting with `GlobalShadows` off (see `roblox/default.project.json`
and `World.applyLook`). Anything added to the lighting should be checked against
the same question first: does it need a shader the low end does not have?

Measured before and after, with `windows/ax-darkness.ps1`:

| | dark pixels | distinct colours |
| --- | --- | --- |
| before (lit as the client default) | ~83-97% | 16,308 |
| after (Voxel, no global shadows) | 3.6% | 45,782 |

**The "character falls into darkness" report was this bug, not a spawn bug.**
Eight steps of walking now hold the dark-pixel share between 15.3% and 16.1%,
with no spike, so the platform is not losing the player. Do not go looking in
`World.luau` for a fall when a screenshot goes black: check the lighting first.

Movement is proved with a pixelwise difference, not a coarse grid signature.
`ax-burst.ps1`'s own `sig` number barely moves when the character walks, because
averaging a whole frame hides a small avatar; diffing frame 00 against frame 05
shows 18% of pixels changed. Compare the images themselves.

## Conventions

- Keep tooling in the repo, not in `/tmp`. The sandbox `/tmp` is volatile and a
  day's tooling was lost to it once.
- `AX_TOKEN` is read from `ax-results/.ax-token`; never put it on a command line,
  where every process on the machine can read it.
- Scripts take plain numeric parameters rather than comma strings. A comma inside
  a PowerShell argument becomes an array and the script then receives several
  arguments instead of one.
- Timestamps on PC1 run in local time (UTC+7) while the sandbox logs UTC, so the
  same event shows two different times.
