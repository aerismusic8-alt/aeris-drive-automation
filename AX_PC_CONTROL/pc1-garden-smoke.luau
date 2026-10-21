-- AX Garden Legends: Studio edit-mode smoke test.
--
-- Roblox Studio runs this through `--task RunScript`, so it executes against the
-- freshly built local place file. Nothing here touches a published experience.
--
-- What this proves: the place opens in real Studio, every shared module loads,
-- both entry points exist, and World.build produces the garden with its scenery
-- and its twelve plots. That last one is the check that would have caught the
-- "green slab with grey boxes" build: it counts the trees and the fence posts,
-- not just the containers.
--
-- What it cannot prove: that the server loop and the HUD run, because Edit mode
-- does not execute Script or LocalScript instances. Play mode covers that.
--
-- Output is one `SMOKE_PASS|label|detail` or `SMOKE_FAIL|label|detail` line per
-- check, so the caller can parse the log without guessing.

local function report(ok: boolean, label: string, detail: string)
        print(string.format("%s|%s|%s", ok and "SMOKE_PASS" or "SMOKE_FAIL", label, detail or ""))
end

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local StarterPlayer = game:GetService("StarterPlayer")

local shared = ReplicatedStorage:FindFirstChild("Shared")
if not shared then
        report(false, "shared-folder", "ReplicatedStorage.Shared is missing")
        return
end

local names = {}
for _, child in ipairs(shared:GetChildren()) do
        if child:IsA("ModuleScript") then
                table.insert(names, child.Name)
        end
end
table.sort(names)
report(#names > 0, "module-count", tostring(#names))

local failures = {}
for _, name in ipairs(names) do
        local ok, err = pcall(function()
                return require(shared:FindFirstChild(name))
        end)
        if not ok then
                table.insert(failures, string.format("%s (%s)", name, tostring(err)))
        end
end
report(#failures == 0, "modules-require", table.concat(failures, " ~ "))

local serverScript = ServerScriptService:FindFirstChild("AXGardenServer")
report(serverScript ~= nil, "server-script", serverScript and serverScript.ClassName or "missing")

local starterScripts = StarterPlayer:FindFirstChild("StarterPlayerScripts")
local clientScript = starterScripts and starterScripts:FindFirstChild("AXGardenClient")
report(clientScript ~= nil, "client-script", clientScript and clientScript.ClassName or "missing")

-- The world is built by the server at runtime, so in Edit mode it must be
-- absent. A world already in the place file would mean the build captured
-- runtime state, which is a sign the file was saved from a running session.
local prebuilt = workspace:FindFirstChild("GardenWorld")
report(prebuilt == nil, "world-not-baked", prebuilt and "GardenWorld is baked into the file" or "clean")

if not serverScript then
        report(false, "world-build", "no server script, cannot build")
        return
end

-- Build the world for real. This runs the same code the server runs on start,
-- so a broken scenery palette or a missing plot surfaces here rather than in
-- front of a player.
local Config = require(shared:FindFirstChild("Config"))
local world = nil
local ok, err = pcall(function()
        local World = require(serverScript:FindFirstChild("World"))
        local root, plots = World.build(Config.Garden.StartingPlots or 3)
        root.Parent = workspace
        world = root
        report(#plots == Config.Garden.TotalPlots, "plot-handles",
                string.format("%d handles for %d plots", #plots, Config.Garden.TotalPlots))
end)
if not ok then
        report(false, "world-build", tostring(err))
        return
end
report(world ~= nil, "world-present", world and "World.build returned a root" or "no root returned")
if not world then
        return
end

local kinds = {}
local parts = 0
local balls, cylinders = 0, 0
local materials = {}
for _, node in ipairs(world:GetDescendants()) do
        if node:IsA("BasePart") then
                parts += 1
                kinds[node.Name] = (kinds[node.Name] or 0) + 1
                if node:IsA("Part") then
                        if node.Shape == Enum.PartType.Ball then
                                balls += 1
                        elseif node.Shape == Enum.PartType.Cylinder then
                                cylinders += 1
                        end
                end
                if node.Material then
                        materials[node.Material.Name] = true
                end
        end
end
report(parts > 200, "world-parts", tostring(parts))

-- K's report was that the garden is "only square blocks". These count the shape
-- work, so a run that ships boxes again is caught here rather than by K.
report(balls > 40, "world-balls", tostring(balls))
report(cylinders > 10, "world-cylinders", tostring(cylinders))
local materialCount = 0
for _ in pairs(materials) do
        materialCount += 1
end
report(materialCount > 5, "world-materials", tostring(materialCount))

-- The scenery check. A bare slab has ground and plots and nothing else; this
-- fails if the trees, the bushes or the fence are gone.
for _, kind in ipairs({ "Trunk", "Leaves", "Bush", "FencePost", "PathSlab", "Soil", "Pond", "Lantern" }) do
        report((kinds[kind] or 0) > 0, "scenery-" .. kind, tostring(kinds[kind] or 0))
end

-- The sky and the atmosphere are what the first build had none of, and the
-- low-end settings are what keep it visible on this machine's Intel HD adapter.
local Lighting = game:GetService("Lighting")
report(Lighting:FindFirstChild("GardenSky") ~= nil, "lighting-sky", "GardenSky")
report(Lighting:FindFirstChild("GardenAtmosphere") ~= nil, "lighting-atmosphere", "GardenAtmosphere")
report(Lighting.GlobalShadows == false, "lighting-shadows-off", tostring(Lighting.GlobalShadows))

-- Edit mode runs without the RobloxScript capability, so `Technology` is not
-- readable there: reading it throws "lacking capability RobloxScript" and the
-- uncaught error ended this script at the line, silently skipping every check
-- below it. The read is wrapped so the rest of the smoke always runs, and the
-- check reports what edit mode can actually see instead of a false failure.
local okTech, tech = pcall(function()
        return Lighting.Technology
end)
report(okTech and tech == Enum.Technology.Voxel, "lighting-voxel",
        okTech and tostring(tech) or "unreadable in edit mode")

-- The ground has to collide, or the player spawns and falls out of the world.
local ground = world:FindFirstChild("Ground")
report(ground ~= nil, "ground-present", ground and ground.ClassName or "missing")
if ground then
        report(ground.CanCollide == true, "ground-collides", tostring(ground.CanCollide))
end

local spawn = world:FindFirstChild("GardenSpawn")
report(spawn ~= nil, "spawn-present", spawn and spawn.ClassName or "missing")

report(true, "smoke-complete", string.format("%d modules, %d parts", #names, parts))
