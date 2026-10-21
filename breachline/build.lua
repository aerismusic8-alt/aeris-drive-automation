--[[
	Rebuild the Breachline place from the recovered source plus an overlay.

	The base place is the byte-for-byte download from the published experience,
	repacked so rbxmk can read it (see scripts/unpack-breachline.sh). The overlay
	is a directory tree that mirrors instance paths; every .luau file in it
	replaces the Source of the script at that path, and a path with no script
	already there creates one.

	Keeping the base place separate means an edit is one small file in the
	overlay, reviewable on its own, and the build is the same every time.

	Usage:
	  rbxmk run --allow-insecure-paths breachline/build.lua <base.rbxl> <overlay-dir> <out.rbxl>
]]

local basePath, overlayDir, outPath = ...

assert(basePath, "usage: build.lua <base.rbxl> <overlay-dir> <out.rbxl>")
assert(overlayDir, "usage: build.lua <base.rbxl> <overlay-dir> <out.rbxl>")
assert(outPath, "usage: build.lua <base.rbxl> <overlay-dir> <out.rbxl>")

-- The same weapon ships twice: once in StarterPack as the starting gun, and
-- once in ServerStorage as the shop template the server clones. A fix to one
-- is a fix to both, so an overlay path under a source prefix is applied to
-- each of its mirrors as well.
local MIRRORS = {
	["StarterPack/TrainingCarbine"] = { "ServerStorage/WeaponTemplates/CompactSMG" },
}

local place = fs.read(basePath)
assert(place and place.ClassName == "DataModel", "base place did not decode to a DataModel")

local replaced, created, failures = 0, 0, {}

local function classForName(name)
	if name:match("%.server%.luau$") then return "Script" end
	if name:match("%.client%.luau$") then return "LocalScript" end
	if name:match("%.luau$") then return "ModuleScript" end
	return nil
end

local function scriptNameForFile(name)
	return (name:gsub("%.server%.luau$", ""):gsub("%.client%.luau$", ""):gsub("%.luau$", ""))
end

---Resolve a slash-joined path to the instance it names, or nil with the
---segment that went missing.
local function resolve(segments)
	local parent = place
	for _, segment in ipairs(segments) do
		local next = parent:FindFirstChild(segment)
		if not next then return nil, segment end
		parent = next
	end
	return parent
end

local function apply(targetSegments, fileName, source, reportPath)
	local parent, missing = resolve(targetSegments)
	if not parent then
		table.insert(failures, reportPath .. " (missing " .. missing .. ")")
		return
	end

	local leaf = scriptNameForFile(fileName)
	local existing = parent:FindFirstChild(leaf)
	if existing then
		existing.Source = source
		replaced = replaced + 1
	else
		local class = classForName(fileName)
		local inst = Instance.new(class)
		inst.Name = leaf
		inst.Source = source
		inst.Parent = parent
		created = created + 1
	end
end

---Every target path a source path maps to: itself, plus any mirror.
local function targetsFor(segments)
	local targets = { segments }
	local joined = table.concat(segments, "/")
	for source, mirrors in pairs(MIRRORS) do
		if joined:sub(1, #source + 1) == source .. "/" then
			local rest = joined:sub(#source + 2)
			for _, mirror in ipairs(mirrors) do
				table.insert(targets, string.split(mirror .. "/" .. rest, "/"))
			end
		end
	end
	return targets
end

-- Walk the overlay. Each file's path under overlayDir is the instance path,
-- minus the extension.
local function walk(dir, segments)
	local entries = fs.dir(dir)
	if not entries then return end

	for _, entry in ipairs(entries) do
		if entry.Name:sub(1, 1) ~= "." then
			local full = dir .. "/" .. entry.Name
			if entry.IsDir then
				table.insert(segments, entry.Name)
				walk(full, segments)
				table.remove(segments)
			elseif classForName(entry.Name) then
				local source = fs.read(full, "txt")
				local reportPath = table.concat(segments, "/") .. "/" .. entry.Name
				for _, target in ipairs(targetsFor(segments)) do
					apply(target, entry.Name, source, reportPath)
				end
			end
		end
	end
end

walk(overlayDir, {})

if #failures > 0 then
	io.stderr:write("BUILD_FAILED: overlay paths with no parent instance:\n")
	for _, f in ipairs(failures) do io.stderr:write("  " .. f .. "\n") end
	os.exit(1)
end

fs.write(outPath, place, "rbxl")
print(string.format("BUILD_OK replaced=%d created=%d out=%s", replaced, created, outPath))
