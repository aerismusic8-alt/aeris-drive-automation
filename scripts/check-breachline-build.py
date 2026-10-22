#!/usr/bin/env python3
"""Fail when the Breachline overlay no longer builds a coherent place.

Every check here exists because the corresponding mistake already happened
once and was only caught by rebuilding and reading the result:

  * the overlay was applied but a mirror target was not, so the shop copy of a
    weapon kept the old input code while the starting copy got the new one;
  * a new module was created at a path that did not exist in the base, so the
    build reported success and the module was never parented anywhere;
  * the shared tunables the modules read had no value, so the aim parameters
    were nil at runtime and only failed on a phone.

The script replays the overlay against the base and asserts the result. It
needs rbxmk; it exits 2 with a clear message when rbxmk is not present, so a
checkout without the tool reports why instead of failing mysteriously.
"""

import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BASE = ROOT / "breachline/base.rbxl"
BASE_SRC = ROOT / "breachline-src/breachline-place.rbxl"
OVERLAY = ROOT / "breachline/overlay"
BUILD_LUA = ROOT / "breachline/build.lua"
SCENE_LUA = ROOT / "breachline/scene.lua"

checks = 0
failures: list[str] = []


def check(label: str, condition: bool, detail: str = "") -> None:
    global checks
    checks += 1
    if condition:
        print(f"  ok   {label}")
    else:
        print(f"  FAIL {label} {detail}")
        failures.append(label)


def find_rbxmk() -> str | None:
    env = os.environ.get("RBXMK")
    if env and Path(env).is_file():
        return env
    local = ROOT / "tools/rbxmk/rbxmk"
    if local.is_file():
        return str(local)
    return shutil.which("rbxmk")


def run_rbxmk(rbxmk: str, script: Path, *args: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        [rbxmk, "run", "--allow-insecure-paths", str(script), *args],
        capture_output=True,
        text=True,
    )


def main() -> int:
    rbxmk = find_rbxmk()
    if not rbxmk:
        print("SKIP reason=rbxmk_not_found (run scripts/fetch-rbxmk.sh)")
        return 2

    if not BASE.is_file() and BASE_SRC.is_file():
        subprocess.run(
            ["bash", str(ROOT / "scripts/unpack-breachline.sh"), str(BASE_SRC), str(BASE)],
            check=True,
        )

    if not BASE.is_file():
        print(f"SKIP reason=base_place_missing ({BASE})")
        return 2

    work = Path(tempfile.mkdtemp(prefix="breachline-check-"))
    built = work / "built.rbxl"
    try:
        stage1 = work / "stage1.rbxl"
        build = run_rbxmk(rbxmk, BUILD_LUA, str(BASE), str(OVERLAY), str(stage1))
        check("overlay build succeeds", build.returncode == 0, build.stderr[-400:])
        check("overlay build reports no failures", "BUILD_FAILED" not in build.stdout, build.stdout[-400:])

        scene = run_rbxmk(rbxmk, SCENE_LUA, str(stage1), str(built))
        check("scene pass succeeds", scene.returncode == 0, scene.stderr[-400:])

        # Read the built place back and assert the things the overlay promised.
        # rbxmk runs this in its embedded Lua, not Luau: no `if` expressions,
        # no `continue`. Plain Lua 5.1 only.
        probe = work / "probe.lua"
        probe.write_text(
            """
local place = fs.read(...)
local function find(segs)
  local c = place
  for _, s in ipairs(segs) do
    c = c:FindFirstChild(s)
    if not c then return nil end
  end
  return c
end
local function count(i)
  local n = 1
  for _, c in ipairs(i:GetChildren()) do n = n + count(c) end
  return n
end
print("INSTANCES=" .. count(place))
local paths = {
  {"ReplicatedStorage","FourD","Common","MobileControls"},
  {"ReplicatedStorage","FourD","Architects","Firearm2","Common","AimAssist"},
  {"StarterPack","TrainingCarbine","ClientModules","ClientInput"},
  {"StarterPack","TrainingCarbine","ClientModules","ClientCamera"},
  {"ServerStorage","WeaponTemplates","CompactSMG","ClientModules","ClientInput"},
  {"ServerStorage","WeaponTemplates","CompactSMG","ClientModules","ClientCamera"},
  {"StarterPlayer","StarterPlayerScripts","MatchHud"},
  {"StarterPlayer","StarterPlayerScripts","BuyHud"},
}
for _, p in ipairs(paths) do
  local i = find(p)
  local verdict = "no"
  if i then verdict = "yes" end
  print("HAVE " .. table.concat(p, "/") .. "=" .. verdict)
end
local ci = find({"StarterPack","TrainingCarbine","ClientModules","ClientInput"})
local ciM = find({"ServerStorage","WeaponTemplates","CompactSMG","ClientModules","ClientInput"})
local mirror = "differ"
if ci and ciM and ci.Source == ciM.Source then mirror = "same" end
print("MIRROR=" .. mirror)
local l = place:FindFirstChild("Lighting")
-- Every one of these is a singleton: Roblox renders all copies, so a second
-- one stacks. The place shipped with two of each, which is why this counts by
-- class rather than checking Atmosphere alone.
local SINGLETON_CLASSES = {
  "Atmosphere", "SunRaysEffect", "BloomEffect",
  "ColorCorrectionEffect", "DepthOfFieldEffect", "Sky",
}
local counts = {}
for _, name in ipairs(SINGLETON_CLASSES) do counts[name] = 0 end
for _, c in ipairs(l:GetChildren()) do
  if counts[c.ClassName] ~= nil then counts[c.ClassName] = counts[c.ClassName] + 1 end
end
for _, name in ipairs(SINGLETON_CLASSES) do
  print("EFFECT " .. name .. "=" .. counts[name])
end
print("ATMOSPHERES=" .. counts["Atmosphere"])
print("CLOCKTIME=" .. tostring(l.ClockTime))
local const = find({"ReplicatedStorage","FourD","Architects","Firearm2","Common","Constants"})
local tunables = "no"
if const and string.find(const.Source, "AIM_ASSIST_STRENGTH") then tunables = "yes" end
print("ASSIST_TUNABLES=" .. tunables)
""",
            encoding="utf-8",
        )
        result = run_rbxmk(rbxmk, probe, str(built))
        out = result.stdout

        def value(key: str) -> str | None:
            for line in out.splitlines():
                if line.startswith(key + "="):
                    return line.split("=", 1)[1].strip()
            return None

        check("probe reads built place", result.returncode == 0, result.stderr[-400:])

        have = {
            line[5:].rsplit("=", 1)[0]: line.rsplit("=", 1)[1]
            for line in out.splitlines()
            if line.startswith("HAVE ") and "=" in line
        }
        for expected in have:
            check(f"present {expected}", have[expected] == "yes")

        check("weapon copy is mirrored", value("MIRROR") == "same", str(value("MIRROR")))
        # A second copy of any of these stacks at runtime, so exactly one of
        # each is required. Checking only Atmosphere let the duplicated Bloom,
        # colour correction and sun-rays through.
        effects = {
            line.split()[1]: int(line.rsplit("=", 1)[1])
            for line in out.splitlines()
            if line.startswith("EFFECT ") and "=" in line
        }
        for name, n in effects.items():
            check(f"exactly one {name}", n == 1, str(n))
        check("exactly one atmosphere", value("ATMOSPHERES") == "1", str(value("ATMOSPHERES")))
        check("scene clock is set", value("CLOCKTIME") not in (None, "nil"), str(value("CLOCKTIME")))
        check("aim tunables present", value("ASSIST_TUNABLES") == "yes")

        instances = int(value("INSTANCES") or 0)
        check("instance count grew past the base 1661", instances >= 1661, str(instances))
    finally:
        shutil.rmtree(work, ignore_errors=True)

    print(f"\n{checks - len(failures)}/{checks} checks passed")
    for name in failures:
        print(f"  FAILED: {name}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
