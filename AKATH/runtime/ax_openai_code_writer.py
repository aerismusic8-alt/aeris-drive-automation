#!/usr/bin/env python3
"""Run an OpenAI coding task and emit the actual generated code into AX_CODE_STREAM_V1."""
from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WRITER = ROOT / "AKATH" / "runtime" / "ax_code_stream_writer.ps1"

from ax_openai_helper import ask_openai, OpenAIHelperError


def extract_code(text: str) -> str:
    blocks = re.findall(r"```(?:[A-Za-z0-9_+.-]+)?\s*\n(.*?)```", text, flags=re.S)
    if blocks:
        return blocks[0]
    return text.strip() + "\n"


def emit(agent: str, task_id: str, file: str, event: str, text: str = "") -> None:
    command = [
        "powershell", "-NoProfile", "-ExecutionPolicy", "Bypass",
        "-File", str(WRITER), "-Agent", agent, "-TaskId", task_id,
        "-File", file, "-Event", event, "-Text", text,
    ]
    subprocess.run(command, cwd=ROOT, check=True, capture_output=False)


def stream_code(code: str, task_id: str, file: str) -> None:
    emit("OPENAI", task_id, file, "START")
    for line in code.splitlines():
        emit("OPENAI", task_id, file, "LINE", line)
    emit("OPENAI", task_id, file, "END")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("prompt")
    parser.add_argument("--task-id", default="OPENAI-CODE-LIVE")
    parser.add_argument("--file", default="AKATH/runtime/generated_task.py")
    parser.add_argument("--model", default=None)
    args = parser.parse_args()

    system = (
        "You are an implementation worker for AKATH. Return only the requested source code "
        "inside one fenced code block. Do not include secrets, credentials, or destructive commands."
    )
    try:
        response = ask_openai(args.prompt, system=system, model=args.model)
        code = extract_code(response)
        stream_code(code, args.task_id, args.file)
        print(f"AX_OPENAI_CODE_STREAM_PASS task={args.task_id} lines={len(code.splitlines())}")
        return 0
    except (OpenAIHelperError, subprocess.SubprocessError, OSError) as exc:
        try:
            emit("OPENAI", args.task_id, args.file, "ERROR", str(exc))
        except Exception:
            pass
        print(f"AX_OPENAI_CODE_STREAM_ERROR={exc}")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
