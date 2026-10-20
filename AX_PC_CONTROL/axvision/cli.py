"""What the agent runs on PC1.

    python -m axvision start                 # begin watching, detached
    python -m axvision state                 # what is on screen, in one word
    python -m axvision changed --seconds 1   # did anything move, and where
    python -m axvision motion                # peak frame-to-frame change
    python -m axvision colour --rgb 255,206,84   # where a HUD colour is
    python -m axvision snapshot --out shot.png   # save the frame it analysed
    python -m axvision health                # is the watcher alive
    python -m axvision stop                  # stop watching

Every command prints one JSON object and exits, so the caller parses a line
rather than scraping prose.

The watcher and the commands talk through a mailbox in the runtime directory: a
request file and a response file. That is deliberate. A listening socket would
be faster still, but PC1's whole design avoids inbound ports, and a mailbox
costs one small file write plus a poll of a few milliseconds. The expensive part
of the old way was never this - it was starting a process and shipping a PNG per
look, and neither of those happens here.

If the watcher is not running, a command falls back to a single in-memory grab,
which still costs one process and no disk I/O.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time


def _default_runtime() -> str:
    """Where the mailbox and pid file live.

    On PC1 that is a fixed Windows directory. Anywhere else - a test, the
    sandbox - it is a temp directory, because the Windows default would be
    created as a literal ``C:\\AX-Runtime\\vision`` folder in the current
    directory, which is how a junk directory appears in the repo.
    """
    import tempfile

    override = os.environ.get("AX_VISION_DIR")
    if override:
        return override
    if os.name == "nt":
        return r"C:\AX-Runtime\vision"
    return os.path.join(tempfile.gettempdir(), "axvision")


RUNTIME = _default_runtime()
PID_FILE = os.path.join(RUNTIME, "axvision.pid")
STATE_FILE = os.path.join(RUNTIME, "axvision.state.json")
LOG_FILE = os.path.join(RUNTIME, "axvision.log")
REQ_FILE = os.path.join(RUNTIME, "request.json")
RES_FILE = os.path.join(RUNTIME, "response.json")

# How long a command waits for the watcher to answer before falling back. The
# watcher polls the mailbox every ~50ms, so this is generous.
MAILBOX_TIMEOUT = 3.0


def _ensure_runtime() -> None:
    os.makedirs(RUNTIME, exist_ok=True)


def _read_pid() -> int:
    try:
        with open(PID_FILE, encoding="utf-8") as fh:
            return int(fh.read().strip() or 0)
    except (OSError, ValueError):
        return 0


def _pid_alive(pid: int) -> bool:
    if pid <= 0:
        return False
    if os.name == "nt":
        import ctypes

        PROCESS_QUERY_LIMITED_INFORMATION = 0x1000
        handle = ctypes.windll.kernel32.OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, False, pid)
        if not handle:
            return False
        ctypes.windll.kernel32.CloseHandle(handle)
        return True
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False


def _read_state() -> dict:
    try:
        with open(STATE_FILE, encoding="utf-8") as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return {}


def _atomic_write(path: str, payload: dict) -> None:
    # Write to a temp name and rename, so a reader never sees a half-written
    # file. Rename is atomic on both NTFS and POSIX.
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(payload, fh)
    os.replace(tmp, path)


def cmd_start(args) -> int:
    _ensure_runtime()
    pid = _read_pid()
    if _pid_alive(pid):
        print(json.dumps({"ok": True, "already_running": True, "pid": pid}))
        return 0
    # Detached so the caller's 30 second cap does not kill the watcher.
    creation = 0
    if os.name == "nt":
        DETACHED_PROCESS = 0x00000008
        CREATE_NEW_PROCESS_GROUP = 0x00000200
        creation = DETACHED_PROCESS | CREATE_NEW_PROCESS_GROUP
    log = open(LOG_FILE, "a", encoding="utf-8")
    proc = subprocess.Popen(
        [sys.executable, "-m", "axvision", "_serve",
         "--interval", str(args.interval), "--seconds", str(args.seconds)],
        stdout=log, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL,
        creationflags=creation, close_fds=True,
        cwd=os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    )
    with open(PID_FILE, "w", encoding="utf-8") as fh:
        fh.write(str(proc.pid))
    # Wait for the first frame so a caller can ask a question immediately.
    deadline = time.time() + 5.0
    while time.time() < deadline:
        if _read_state().get("frames", 0) > 0:
            break
        time.sleep(0.2)
    print(json.dumps({"ok": True, "pid": proc.pid, "runtime": RUNTIME, "log": LOG_FILE}))
    return 0


def cmd_stop(args) -> int:
    pid = _read_pid()
    if not _pid_alive(pid):
        print(json.dumps({"ok": True, "already_stopped": True}))
        return 0
    try:
        if os.name == "nt":
            subprocess.run(["taskkill", "/PID", str(pid), "/F"], capture_output=True)
        else:
            os.kill(pid, 15)
    except OSError as exc:
        print(json.dumps({"ok": False, "error": str(exc)}))
        return 1
    print(json.dumps({"ok": True, "stopped": pid}))
    return 0


def _ask(question: str, **kwargs) -> dict:
    """Ask the watcher a question through the mailbox."""
    _ensure_runtime()
    request_id = f"{os.getpid()}-{int(time.time() * 1000)}"
    _atomic_write(REQ_FILE, {"id": request_id, "question": question, **kwargs})
    deadline = time.time() + MAILBOX_TIMEOUT
    while time.time() < deadline:
        try:
            with open(RES_FILE, encoding="utf-8") as fh:
                answer = json.load(fh)
            if answer.get("id") == request_id:
                return answer
        except (OSError, ValueError):
            pass
        time.sleep(0.02)
    return {"ok": False, "error": "watcher did not answer", "running": _pid_alive(_read_pid())}


def cmd_serve(args) -> int:
    """The daemon loop: capture, keep a ring buffer, answer the mailbox."""
    from . import capture, engine, geometry

    hwnd = capture.find_game_window()
    rect = engine.default_rect()
    # Which window is being watched is the first thing to check when the state
    # looks wrong: Roblox Studio also carries "Roblox" in its title, so a
    # watcher can be aimed at the editor instead of the game and report a
    # perfectly healthy "world" for an empty viewport.
    title = capture.window_title(hwnd) if hwnd else ""
    grabber = capture.Grabber()
    eng = engine.Engine(
        grabber.grab, rect,
        interval=args.interval,
        log_path=os.path.join(RUNTIME, "axvision.jsonl"),
    )
    eng.start()
    started = time.time()
    try:
        while time.time() - started < args.seconds:
            _answer_mailbox(eng)
            snap = eng.answer("state")
            snap["pid"] = os.getpid()
            snap["frames"] = eng.answer("health").get("frames", 0)
            snap["window"] = hwnd
            snap["window_title"] = title
            snap["rect"] = geometry.as_dict(rect)
            _atomic_write(STATE_FILE, snap)
            time.sleep(0.05)
    finally:
        eng.stop()
        grabber.close()
    return 0


def _answer_mailbox(eng) -> None:
    """Serve one pending request, if there is one, from the ring buffer."""
    if not os.path.exists(REQ_FILE):
        return
    try:
        with open(REQ_FILE, encoding="utf-8") as fh:
            request = json.load(fh)
    except (OSError, ValueError):
        return
    question = request.pop("question", None)
    request_id = request.pop("id", None)
    if not question or not request_id:
        return
    try:
        answer = eng.answer(question, **request)
    except Exception as exc:  # a bad question must not kill the watcher
        answer = {"ok": False, "error": str(exc)}
    answer["id"] = request_id
    _atomic_write(RES_FILE, answer)


def _ask_oneshot(question: str, **kwargs) -> dict:
    """One answer from a fresh in-memory grab, when the watcher is not running.

    A machine with no screen is a normal case, not a crash: the caller wants to
    know the watcher is down and why, and a traceback on stderr gives it
    neither. The failure comes back as JSON like every other answer.
    """
    try:
        from . import capture, engine

        rect = engine.default_rect()
        grabber = capture.Grabber()
    except Exception as exc:
        return {"ok": False, "error": f"no screen available: {exc}", "source": "oneshot"}
    try:
        eng = engine.Engine(grabber.grab, rect, interval=1.0, classify_every=1)
        eng.capture_once()
        eng.capture_once()  # two frames, so "changed" has something to compare
        answer = eng.answer(question, **kwargs)
        answer["source"] = "oneshot"
        return answer
    finally:
        grabber.close()


def cmd_ask(args) -> int:
    request = json.loads(args.payload)
    question = request.pop("question")
    answer = _ask_oneshot(question, **request)
    print(json.dumps(answer))
    return 0 if answer.get("ok") else 1


def cmd_query(args) -> int:
    kwargs = {}
    if args.question in ("changed", "motion"):
        kwargs["seconds"] = args.seconds
    elif args.question == "colour":
        kwargs["colour"] = [int(v) for v in args.rgb.split(",")]
        kwargs["tolerance"] = args.tolerance
    elif args.question == "snapshot":
        kwargs["out"] = args.out
    answer = _ask(args.question, **kwargs)
    if not answer.get("ok") and "did not answer" in str(answer.get("error", "")):
        # Fall back to a single in-memory grab so a question still works when
        # the watcher is down. Slower, but it never returns nothing.
        answer = _ask_oneshot(args.question, **kwargs)
    print(json.dumps(answer))
    return 0 if answer.get("ok") else 1


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="axvision", description="AX Vision: a fast eye for PC1")
    sub = parser.add_subparsers(dest="command", required=True)

    p_start = sub.add_parser("start", help="begin watching, detached")
    p_start.add_argument("--interval", type=float, default=0.1, help="seconds between frames")
    p_start.add_argument("--seconds", type=float, default=3600, help="how long to watch")
    p_start.set_defaults(func=cmd_start)

    sub.add_parser("stop", help="stop watching").set_defaults(func=cmd_stop)

    for name in ("state", "health", "motion", "changed", "colour", "snapshot"):
        p = sub.add_parser(name, help=f"ask the watcher for {name}")
        p.add_argument("--seconds", type=float, default=1.0)
        p.add_argument("--rgb", default="255,206,84", help="colour for 'colour', R,G,B")
        p.add_argument("--tolerance", type=int, default=40)
        p.add_argument("--out", default=os.path.join(RUNTIME, "snapshot.png"),
                       help="path for 'snapshot'")
        p.set_defaults(func=cmd_query, question=name)

    p_serve = sub.add_parser("_serve", help=argparse.SUPPRESS)
    p_serve.add_argument("--interval", type=float, default=0.1)
    p_serve.add_argument("--seconds", type=float, default=3600)
    p_serve.set_defaults(func=cmd_serve)

    p_ask = sub.add_parser("_ask", help=argparse.SUPPRESS)
    p_ask.add_argument("payload")
    p_ask.set_defaults(func=cmd_ask)

    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
