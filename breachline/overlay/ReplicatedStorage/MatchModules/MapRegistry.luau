--[[
        File: MapRegistry.luau

        Which maps exist, and which one a match plays on.

        A map is a Model in Workspace that carries three attributes -- MapId,
        MapName and MapOrder -- plus the things a round needs: a BombSites folder
        holding two sites with a PlantPrompt each, and an Attackers Spawn and a
        Defenders Spawn.

        The registry reads the maps out of the place rather than holding a list of
        its own. That is deliberate: a list here would be a second copy of the
        truth, and the two would drift the first time a map was added to the build
        and not to the list. The build pass that creates a map is the same pass
        that stamps its attributes, so the place is the source of truth and this
        module is only the reader.

        Pure: it reads instances it is handed and does no engine work of its own,
        so the whole selection rule runs under the plain Luau CLI.
]]--

local MapRegistry = {}

-- The attribute a Model must carry to be considered a map. Kept as constants so
-- the build pass and this module cannot disagree about the spelling.
MapRegistry.ID_ATTRIBUTE = "MapId"
MapRegistry.NAME_ATTRIBUTE = "MapName"
MapRegistry.ORDER_ATTRIBUTE = "MapOrder"

---Everything a map must have for a round to run on it. Returns a list of the
---problems found, empty when the map is complete. Returning the reasons rather
---than a boolean is what makes a build failure readable.
function MapRegistry.problems(model): { string }
        local problems = {}

        if typeof(model) ~= "Instance" or not model:IsA("Model") then
                return { "not a Model" }
        end

        local id = model:GetAttribute(MapRegistry.ID_ATTRIBUTE)
        if typeof(id) ~= "string" or id == "" then
                table.insert(problems, "no " .. MapRegistry.ID_ATTRIBUTE .. " attribute")
        end
        if typeof(model:GetAttribute(MapRegistry.NAME_ATTRIBUTE)) ~= "string" then
                table.insert(problems, "no " .. MapRegistry.NAME_ATTRIBUTE .. " attribute")
        end

        local sites = model:FindFirstChild("BombSites")
        if not sites then
                table.insert(problems, "no BombSites folder")
        else
                local count = 0
                for _, site in ipairs(sites:GetChildren()) do
                        if site:IsA("BasePart") and site:FindFirstChild("PlantPrompt") then
                                count += 1
                        end
                end
                if count < 2 then
                        table.insert(problems, "needs two bomb sites with a PlantPrompt, found " .. count)
                end
        end

        for _, spawnName in ipairs({ "Attackers Spawn", "Defenders Spawn" }) do
                local spawn = model:FindFirstChild(spawnName)
                if not spawn or not spawn:IsA("SpawnLocation") then
                        table.insert(problems, "no " .. spawnName .. " SpawnLocation")
                end
        end

        return problems
end

function MapRegistry.isMap(model): boolean
        return #MapRegistry.problems(model) == 0
end

---Every complete map under `container`, sorted by MapOrder then name. A Model
---that is missing part of the contract is skipped rather than returned, because
---a half-built map that reaches the match layer is a crash in the round loop
---instead of a build error.
function MapRegistry.collect(container): { [string]: any }
        local maps = {}
        if not container then return maps end

        for _, child in ipairs(container:GetChildren()) do
                if child:IsA("Model") and child:GetAttribute(MapRegistry.ID_ATTRIBUTE) and MapRegistry.isMap(child) then
                        local order = child:GetAttribute(MapRegistry.ORDER_ATTRIBUTE)
                        table.insert(maps, {
                                id = child:GetAttribute(MapRegistry.ID_ATTRIBUTE),
                                name = child:GetAttribute(MapRegistry.NAME_ATTRIBUTE),
                                order = if typeof(order) == "number" then order else math.huge,
                                model = child,
                        })
                end
        end

        table.sort(maps, function(a, b)
                if a.order ~= b.order then return a.order < b.order end
                return a.id < b.id
        end)
        return maps
end

function MapRegistry.find(maps, id)
        for _, map in ipairs(maps) do
                if map.id == id then return map end
        end
        return nil
end

---The map after `currentId` in rotation order, wrapping at the end. A match that
---has never run -- or one whose map was removed from the build -- starts at the
---first map rather than failing, so a bad saved value cannot stop the game.
function MapRegistry.next(maps, currentId)
        if #maps == 0 then return nil end
        local index = nil
        for i, map in ipairs(maps) do
                if map.id == currentId then
                        index = i
                        break
                end
        end
        if not index then return maps[1] end
        return maps[index % #maps + 1]
end

---Turn off everything that lets a round run on a map: its spawns and its plant
---prompts. Used on the maps a match is not playing on, so a player cannot spawn
---into or plant on the wrong one. The geometry stays where it is; only the
---round-carrying parts are switched off.
function MapRegistry.deactivate(model)
        for _, descendant in ipairs(model:GetDescendants()) do
                if descendant:IsA("SpawnLocation") then
                        descendant.Enabled = false
                elseif descendant:IsA("ProximityPrompt") then
                        descendant.Enabled = false
                end
        end
        model:SetAttribute("MapActive", false)
end

function MapRegistry.activate(model)
        for _, descendant in ipairs(model:GetDescendants()) do
                if descendant:IsA("SpawnLocation") then
                        -- The range spawn is a practice pad, not a round spawn, so
                        -- it stays off even on the active map.
                        descendant.Enabled = descendant.Name ~= "Range Spawn"
                elseif descendant:IsA("ProximityPrompt") then
                        descendant.Enabled = true
                end
        end
        model:SetAttribute("MapActive", true)
end

return MapRegistry
