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
UI_LUA = ROOT / "breachline/ui.lua"
MAPS_LUA = ROOT / "breachline/maps.lua"
SCENE_LUA = ROOT / "breachline/scene.lua"
SRC = ROOT / "breachline/src/breachline-uncompressed"

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
        stage2 = work / "stage2.rbxl"
        stage3 = work / "stage3.rbxl"
        build = run_rbxmk(rbxmk, BUILD_LUA, str(BASE), str(OVERLAY), str(stage1))
        check("overlay build succeeds", build.returncode == 0, build.stderr[-400:])
        check("overlay build reports no failures", "BUILD_FAILED" not in build.stdout, build.stdout[-400:])

        ui = run_rbxmk(rbxmk, UI_LUA, str(stage1), str(stage2))
        check("ui pass succeeds", ui.returncode == 0, ui.stderr[-400:])

        maps = run_rbxmk(rbxmk, MAPS_LUA, str(stage2), str(stage3))
        check("maps pass succeeds", maps.returncode == 0, maps.stderr[-400:])
        check("maps pass reports no failures", "MAPS_FAILED" not in maps.stdout, maps.stdout[-400:])
        check(
            "maps pass built two maps",
            any(line.startswith("MAPS_OK") and "maps=2" in line for line in maps.stdout.splitlines()),
            maps.stdout[-400:],
        )

        scene = run_rbxmk(rbxmk, SCENE_LUA, str(stage3), str(built))
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
-- The firearm client clones these three templates by name out of the place and
-- silently disables the feature when one is missing. The recovered base carried
-- none of them, so the crosshair, the ammo counter and the scope overlay were
-- all off. Each entry is { path..., required child class }. A template that
-- exists but has lost the child the code looks up is the same bug.
local TEMPLATES = {
  { {"ReplicatedStorage","Assets","UI","FirearmCrosshair"}, "Holder", "Frame" },
  { {"ReplicatedStorage","Assets","UI","FirearmAmmo"}, "AmmoLabel", "TextLabel" },
  { {"ReplicatedStorage","Assets","UI","Scope"}, "Shroud", "Frame" },
  { {"ReplicatedStorage","Assets","UI","Scope"}, "Holder", "ImageLabel" },
}
for _, t in ipairs(TEMPLATES) do
  local segs = t[1]
  local i = find(segs)
  local verdict = "missing"
  if i then
    local child = i:FindFirstChild(t[2])
    if not child then
      verdict = "no-child"
    elseif child.ClassName ~= t[3] then
      verdict = "wrong-class:" .. child.ClassName
    else
      verdict = "ok"
    end
  end
  print("TEMPLATE " .. table.concat(segs, "/") .. "->" .. t[2] .. "=" .. verdict)
end
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

-- The maps. A round can only run on a map that carries the attributes the
-- registry reads and the sites and spawns the round loop needs, and a map the
-- build forgot to stamp is invisible to the rotation rather than an error --
-- the server would quietly play the first map forever. Each is checked here for
-- the same contract MapRegistry enforces at runtime.
local ws = place:FindFirstChild("Workspace")
local groundX = {}
for _, child in ipairs(ws:GetChildren()) do
  if child.ClassName == "Model" and child:GetAttribute("MapId") then
    local id = tostring(child:GetAttribute("MapId"))
    local name = tostring(child:GetAttribute("MapName"))
    local order = tostring(child:GetAttribute("MapOrder"))
    local sites = 0
    local folder = child:FindFirstChild("BombSites")
    if folder then
      for _, site in ipairs(folder:GetChildren()) do
        if site.ClassName == "Part" and site:FindFirstChild("PlantPrompt") then
          sites = sites + 1
        end
      end
    end
    local spawns = 0
    for _, spawnName in ipairs({ "Attackers Spawn", "Defenders Spawn" }) do
      local s = child:FindFirstChild(spawnName)
      if s and s.ClassName == "SpawnLocation" then spawns = spawns + 1 end
    end
    local ground = child:FindFirstChild("Ground")
    if ground then groundX[id] = ground.CFrame.Position.X end
    print(string.format("MAP %s id=%s name=%s order=%s sites=%d spawns=%d",
      child.Name, id, name, order, sites, spawns))
  end
end
-- Two maps that overlap in the world put one team's spawn inside the other map.
-- The rotation never has both active, but an overlap is still a build mistake.
local xs = {}
for _, x in pairs(groundX) do table.insert(xs, x) end
local apart = "no"
if #xs == 2 and math.abs(xs[1] - xs[2]) > 90 then apart = "yes" end
print("MAPS_APART=" .. apart)
print("MAPS_FOUND=" .. tostring(#xs))
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
        # Every template the client clones must exist with the child it looks up.
        templates = {
            line.split()[1]: line.rsplit("=", 1)[1]
            for line in out.splitlines()
            if line.startswith("TEMPLATE ") and "=" in line
        }
        for name, verdict in templates.items():
            check(f"ui template {name}", verdict == "ok", verdict)
        check("ui templates checked", len(templates) == 4, str(len(templates)))
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

        # Every map in the place must satisfy the contract the rotation reads.
        # A map that is missing its attributes is invisible to MapRegistry, so
        # the failure mode is a rotation that silently plays one map forever --
        # which is exactly what shipped before this pass existed.
        maps_seen = {
            line.split()[1]: dict(
                part.split("=", 1) for part in line.split()[2:] if "=" in part
            )
            for line in out.splitlines()
            if line.startswith("MAP ") and "=" in line
        }
        check("two maps are in the built place", len(maps_seen) == 2, str(list(maps_seen)))
        for name, fields in maps_seen.items():
            check(f"map {name} has an id", fields.get("id") not in (None, "nil", ""), str(fields.get("id")))
            check(f"map {name} has a name", fields.get("name") not in (None, "nil", ""), str(fields.get("name")))
            check(f"map {name} has an order", fields.get("order") not in (None, "nil"), str(fields.get("order")))
            check(f"map {name} has two plantable sites", fields.get("sites") == "2", str(fields.get("sites")))
            check(f"map {name} has both team spawns", fields.get("spawns") == "2", str(fields.get("spawns")))
        orders = sorted(int(f["order"]) for f in maps_seen.values() if f.get("order", "").isdigit())
        check("map orders are distinct", len(orders) == len(set(orders)) == 2, str(orders))
        check("the two maps do not overlap", value("MAPS_APART") == "yes", str(value("MAPS_APART")))

        # The overlay's own behaviour cannot be run outside Roblox, so the parts
        # of it that are wiring -- which module the client requires, which
        # attribute the panel writes -- are asserted against the shipped source
        # instead. These are the mistakes that produced a scope button that did
        # nothing and a settings panel that changed nothing.
        def overlay(path: str) -> str:
            f = OVERLAY / path
            return f.read_text(encoding="utf-8") if f.is_file() else ""

        def overlay_src(path: str) -> str:
            """A file the overlay replaces, read from the overlay if present and
            from the recovered source otherwise -- the same order the build
            applies them in, so this reads what the place will actually run."""
            f = OVERLAY / path
            if f.is_file():
                return f.read_text(encoding="utf-8")
            f = SRC / path
            return f.read_text(encoding="utf-8") if f.is_file() else ""

        client_input = overlay("StarterPack/TrainingCarbine/ClientModules/ClientInput.luau")
        weapon_controls = overlay("ReplicatedStorage/FourD/Architects/Firearm2/Common/WeaponControls.luau")
        mobile = overlay("ReplicatedStorage/FourD/Common/MobileControls.luau")
        hud = overlay("StarterPlayer/StarterPlayerScripts/MatchHud.client.luau")

        check("weapon controls module is shipped", bool(weapon_controls), "overlay copy missing")
        check(
            "client input requires the weapon controls module",
            "WeaponControls" in client_input and "require" in client_input,
            "scope gating has no module to call",
        )
        check(
            "the scope gate reads the optic decision",
            "WeaponControls.available(" in client_input and "SetAvailable(" in client_input,
            "SCOPE is not gated on the weapon having an optic",
        )
        check(
            "the cluster follows its own settings",
            "GetAttributeChangedSignal" in mobile and "STORAGE_PREFIX" in mobile,
            "a change made in the panel would not reach a live cluster",
        )
        check(
            "the cluster clamps its stored settings",
            "clampNumber" in mobile,
            "a stale attribute could scale the cluster to nothing",
        )
        check(
            "the settings panel writes the cluster's attributes",
            "MobileControls.STORAGE_PREFIX" in hud and "SetAttribute" in hud,
            "the panel and the cluster disagree on the attribute names",
        )
        check(
            "the settings panel is reachable from the menu",
            "settings.Activated" in hud and "panel.Visible = true" in hud,
            "CONTROLS opens nothing",
        )

        # The server side of the rotation. MapRegistry being shipped is not
        # enough -- a server that never requires it, or that still names one map
        # directly, has a rotation that exists and is never used.
        match_manager = overlay_src("ServerScriptService/MatchManager.server.luau")
        check(
            "the match layer requires the map registry",
            "MapRegistry" in match_manager and "require" in match_manager,
            "the rotation has no registry to read",
        )
        check(
            "the match layer no longer names one map directly",
            "workspace.PrototypeRange" not in match_manager,
            "a hardcoded map would ignore the rotation",
        )
        check(
            "the match layer selects and rotates maps",
            "MapRegistry.collect(" in match_manager and "advanceMap(" in match_manager,
            "the rotation is never driven",
        )
        check(
            "the match layer spawns on the active map",
            "activeMap.model:FindFirstChild(" in match_manager,
            "a round would spawn on a map the match is not playing on",
        )
        maps_lua = (ROOT / "breachline/maps.lua").read_text(encoding="utf-8")
        check(
            "the map pass stamps the registry's attributes",
            all(attr in maps_lua for attr in ("MapId", "MapName", "MapOrder")),
            "the build and the registry disagree on the attribute names",
        )

        # The fallback above reads src when the overlay has no copy, which is
        # what makes the recovered source reviewable -- and is also how a fix
        # landed in src and never reached the place: the check read the fixed
        # src, passed, and the published MatchManager kept its old rules. The
        # match layer and its rules are shipped as overlay copies, so assert the
        # copies exist rather than trusting the fallback.
        for shipped in (
            "ServerScriptService/MatchManager.server.luau",
            "ReplicatedStorage/MatchModules/RoundRules.luau",
        ):
            check(
                f"the overlay ships {shipped}",
                (OVERLAY / shipped).is_file(),
                "a fix in src alone would never be published",
            )
        shipped_rules_path = OVERLAY / "ReplicatedStorage/MatchModules/RoundRules.luau"
        shipped_match_path = OVERLAY / "ServerScriptService/MatchManager.server.luau"
        shipped_rules = shipped_rules_path.read_text(encoding="utf-8") if shipped_rules_path.is_file() else ""
        shipped_match = shipped_match_path.read_text(encoding="utf-8") if shipped_match_path.is_file() else ""
        check(
            "the shipped rules can start a round with one player",
            "requiredPlayers" in shipped_rules,
            "a lone player would wait on 'Waiting for Players' forever",
        )
        check(
            "the shipped match layer gates on the practice rule",
            "requiredPlayers(" in shipped_match,
            "the server would still demand two players",
        )
    finally:
        shutil.rmtree(work, ignore_errors=True)

    print(f"\n{checks - len(failures)}/{checks} checks passed")
    for name in failures:
        print(f"  FAILED: {name}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
