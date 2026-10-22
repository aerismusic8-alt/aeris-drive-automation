#!/usr/bin/env python3
"""Check the dispatch inputs of the publish workflows.

A `type: choice` input lists its allowed values in `options:`. Written
unquoted, YAML 1.1 reads `yes`/`no`/`on`/`off` as booleans, so GitHub is
given `true`/`false` instead of the words in the file. Two things then break,
both silently:

  - a human or a `gh workflow run` passing the documented word gets HTTP 422;
  - a guard like `inputs.publish != 'no'` is never false, because the value is
    the boolean `false`, not the string `'no'`. The "build and verify only"
    option published anyway.

That second one is the reason this file exists. It published a live place when
the operator asked for a dry run, and nothing in the run looked wrong.

Only `choice` inputs are judged. A `type: boolean` input with `default: true`
is correct and must not be flagged, so the declared type decides what is legal
rather than the word alone.

The check is deliberately text-based: importing a YAML library to re-read the
same file would apply the same coercion that caused the bug.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
WORKFLOW_DIR = REPO_ROOT / ".github" / "workflows"

# Words YAML 1.1 coerces to a boolean. Quoting any of them is required.
BOOLEAN_WORDS = {"yes", "no", "on", "off", "true", "false", "y", "n"}

failures: list[str] = []


def check_input(
    workflow: Path, lineno: int, line: str, input_type: str | None
) -> str | None:
    """Flag unquoted boolean words; return the input type if this line set it.

    `options:` only exists on a choice input, whose values are strings, so every
    option is judged. `default:` is judged only for choice and string inputs --
    a boolean input's `default: true` is exactly right.
    """
    options = re.search(r"options:\s*\[(.*)\]", line)
    if options:
        for raw in options.group(1).split(","):
            token = raw.strip()
            if not token:
                continue
            bare = token.strip("'\"")
            if token == bare and bare.lower() in BOOLEAN_WORDS:
                failures.append(
                    f"{workflow.name}:{lineno}: choice option {bare!r} is "
                    f"unquoted, so YAML makes it a boolean. Write '{bare}'."
                )

    declared = re.search(r"type:\s*(\S+)\s*$", line)
    if declared:
        input_type = declared.group(1)

    default = re.search(r"default:\s*(\S+)\s*$", line)
    if default and input_type in (None, "choice", "string"):
        token = default.group(1)
        bare = token.strip("'\"")
        if token == bare and bare.lower() in BOOLEAN_WORDS:
            failures.append(
                f"{workflow.name}:{lineno}: default {bare!r} is unquoted, so "
                f"YAML makes it a boolean. Write '{bare}'."
            )

    return input_type


def main() -> int:
    workflows = sorted(WORKFLOW_DIR.glob("*.yml"))
    if not workflows:
        print("no workflows found", file=sys.stderr)
        return 1

    for workflow in workflows:
        input_type: str | None = None
        for lineno, line in enumerate(
            workflow.read_text(encoding="utf-8").splitlines(), start=1
        ):
            # Comments explain the bug using the buggy text, so they must not be
            # read as configuration.
            if line.lstrip().startswith("#"):
                continue
            # An input block is a handful of lines; resetting the remembered
            # type when a new top-level key appears keeps a `type: boolean`
            # from leaking onto the next input's `default:`.
            if re.match(r"^\s{0,8}\S", line) and ":" in line and line.rstrip().endswith(":"):
                input_type = None
            input_type = check_input(workflow, lineno, line, input_type)

    if failures:
        for failure in failures:
            print(f"FAIL {failure}")
        print(f"workflow inputs: {len(failures)} failed")
        return 1

    print(f"workflow inputs: {len(workflows)} files, 0 failed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
