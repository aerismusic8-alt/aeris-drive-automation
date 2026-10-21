#!/usr/bin/env python3
"""Reintroduce each fixed bug and confirm the runtime suite catches it.

A test that passes both with and without a fix proves nothing. This script puts
each bug back one at a time, runs the garden runtime suite, and checks that the
expected test fails. Any bug that is NOT caught is printed as a gap.
"""
import subprocess
import sys

ROOT = "/workspace/project/aeris-drive-automation"
LUAU = f"{ROOT}/tools/luau/luau"

CASES = [
    (
        "duplicate Remotes folder",
        f"{ROOT}/roblox-garden/src/server/init.server.luau",
        """local remotesFolder = ReplicatedStorage:FindFirstChild(Remotes.Folders.Remotes)
if not remotesFolder then
        remotesFolder = Instance.new("Folder")
        remotesFolder.Name = Remotes.Folders.Remotes
        remotesFolder.Parent = ReplicatedStorage
end""",
        """local remotesFolder = Instance.new("Folder")
remotesFolder.Name = Remotes.Folders.Remotes
remotesFolder.Parent = ReplicatedStorage""",
        "only ever one Remotes folder",
    ),
    (
        "World requires Config from the wrong place",
        f"{ROOT}/roblox-garden/src/server/World.luau",
        """local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)""",
        """local Config = require("./Config")
local Remotes = require("./Remotes")""",
        "builds a world with one plot",
    ),
    (
        "remote payload aliases the live save",
        f"{ROOT}/roblox/tests/RobloxShim.luau",
        """        local sig = rawget(self, "signals").OnClientEvent
        if sig then
                sig:Fire(copyForRemote(...))
        end
end

function Instance:FireAllClients(...)
        local sig = rawget(self, "signals").OnClientEvent
        if sig then
                sig:Fire(copyForRemote(...))
        end
end""",
        """        local sig = rawget(self, "signals").OnClientEvent
        if sig then
                sig:Fire(...)
        end
end

function Instance:FireAllClients(...)
        local sig = rawget(self, "signals").OnClientEvent
        if sig then
                sig:Fire(...)
        end
end""",
        "an upgrade raises the level",
    ),
    (
        "plot tap is not wired to the server",
        f"{ROOT}/roblox-garden/src/client/Hud.luau",
        """                local plotIndex = index
                button.Activated:Connect(function()
                        if Hud.Intent then
                                Hud.Intent.tapPlot(plotIndex)
                        end
                end)""",
        """                local plotIndex = index
                button.Activated:Connect(function()
                        -- deliberately dead
                end)""",
        "tapping an empty plot asks the server to plant",
    ),
    (
        "panel offsets forget the screen padding",
        f"{ROOT}/roblox-garden/src/client/HudLayout.luau",
        """HudLayout.PANEL = {
        topOffset = HudLayout.PAD + HudLayout.TOP_BAR.height + HudLayout.GAP,
        bottomOffset = HudLayout.BOTTOM_BAR.height + HudLayout.GAP + HudLayout.PAD,
}""",
        """HudLayout.PANEL = {
        topOffset = HudLayout.TOP_BAR.height + HudLayout.GAP,
        bottomOffset = HudLayout.BOTTOM_BAR.height + HudLayout.GAP,
}""",
        # Two tests guard this: the pure-arithmetic one in the unit suite, and
        # the one that measures the panel the client actually drew. Either
        # failing is a pass for this check.
        ("panel sits between the two bars", "an open panel clears both bars"),
    ),
    (
        "harvest does not check basket space first",
        f"{ROOT}/roblox-garden/src/server/init.server.luau",
        """        if Basket.count(save.basket) >= Config.Basket.Capacity then
                return false, nil, Text.get("noSpace")
        end
        local reward, reason = Garden.harvest(save.garden, index, now(), session.rng)""",
        """        local reward, reason = Garden.harvest(save.garden, index, now(), session.rng)""",
        "a full basket refuses a harvest",
    ),
]


def run_suite():
    # The runtime suite loads the generated bundle, not src/ directly, so the
    # bundle is regenerated before every run. Without this the src edits below
    # would have no effect and every bug would look uncaught.
    subprocess.run(
        ["python3", "scripts/gen-roblox-sources.py",
         "roblox-garden/tests/.generated/Sources.luau", "--src", "roblox-garden/src"],
        cwd=ROOT, capture_output=True, text=True, timeout=300,
    )
    # Both suites, because some bugs are only visible to one of them: a layout
    # mistake is caught by the pure arithmetic in the unit suite, a dead button
    # only by the runtime suite.
    output = ""
    for suite in ("roblox-garden/tests/run.luau", "roblox-garden/tests/runtime.luau"):
        result = subprocess.run(
            [LUAU, suite], cwd=ROOT, capture_output=True, text=True, timeout=900,
        )
        output += result.stdout + result.stderr
    return output


def failing_tests(output):
    """The names of every test that failed, read from the FAIL lines.

    A plain substring search for the name would also match the PASS line, so a
    test that passed would look like it caught the bug. Only the FAIL lines
    count.
    """
    names = []
    for line in output.splitlines():
        stripped = line.strip()
        if stripped.startswith("FAIL"):
            names.append(stripped)
    return names


def main():
    gaps = []
    for name, path, original, broken, expected in CASES:
        # A case may name one test or several; a bug that more than one test
        # guards is caught if any of them fails.
        expected_names = expected if isinstance(expected, tuple) else (expected,)

        text = open(path, encoding="utf-8").read()
        if text.count(original) != 1:
            print(f"SKIP  {name}: anchor found {text.count(original)} times")
            gaps.append(name)
            continue

        open(path, "w", encoding="utf-8").write(text.replace(original, broken, 1))
        try:
            output = run_suite()
        finally:
            open(path, "w", encoding="utf-8").write(text)

        failures = failing_tests(output)
        caught = any(
                any(name_fragment in line for line in failures)
                for name_fragment in expected_names
        )
        if caught:
            print(f"CAUGHT  {name}  ->  {expected_names}")
        else:
            print(f"MISSED  {name}  ->  expected one of {expected_names} to fail")
            gaps.append(name)

    print()
    if gaps:
        print(f"GAPS: {len(gaps)} not caught: {gaps}")
        return 1
    print(f"ALL {len(CASES)} reintroduced bugs were caught")
    return 0


if __name__ == "__main__":
    sys.exit(main())
