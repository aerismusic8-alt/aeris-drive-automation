--[[
	File: HelpUI/Serialize.luau

	Reads and writes HelpUI state definitions onto a model as Instances, plus
	the per-model push RemoteEvent. The server writes; the client reads. The
	serialized tree lets a state survive replication so any client can resolve
	and render it without server traffic per row.

	Layout:
		model
		├─ HelpUI_States (Folder)
		│   └─ <StateName> (Folder)
		│       ├─ "1" (Configuration)  Type="Set",    SetId, Filter? (csv)
		│       └─ "2" (Configuration)  Type="Manual", Id, Description, Keyboard?, Gamepad?
		└─ HelpUI_SetState (RemoteEvent)
]]--

-- Root

local Serialize = {}

-- Dependencies

local Constants = require(script.Parent.Constants)
local Types = require(script.Parent.Types)

-- Local Functions

local function getStatesFolder(model: Instance, create: boolean): Folder?
	local existing = model:FindFirstChild(Constants.StatesFolderName)
	if existing and existing:IsA("Folder") then
		return existing
	end

	if not create then
		return nil
	end

	local folder = Instance.new("Folder")
	folder.Name = Constants.StatesFolderName
	folder.Parent = model

	return folder
end

-- Public Methods

---Writes (or overwrites) a single state definition onto the model.
function Serialize.write(model: Instance, stateName: string, definition: Types.StateDefinition)
	local statesFolder = getStatesFolder(model, true)

	local previous = statesFolder:FindFirstChild(stateName)
	if previous then
		previous:Destroy()
	end

	local stateFolder = Instance.new("Folder")
	stateFolder.Name = stateName

	for index, source in definition.Sources do
		local node = Instance.new("Configuration")
		node.Name = tostring(index)
		node:SetAttribute("Type", source.Type)

		if source.Type == "Set" then
			node:SetAttribute("SetId", source.SetId)
			if source.Filter and #source.Filter > 0 then
				node:SetAttribute("Filter", table.concat(source.Filter, ","))
			end
		else
			node:SetAttribute("Id", source.Id)
			node:SetAttribute("Description", source.Description)
			if source.Keyboard then
				node:SetAttribute("Keyboard", source.Keyboard)
			end

			if source.Gamepad then
				node:SetAttribute("Gamepad", source.Gamepad)
			end
		end

		node.Parent = stateFolder
	end

	stateFolder.Parent = statesFolder
end

---Reads a state definition back from the model, or nil if absent.
function Serialize.read(model: Instance, stateName: string): Types.StateDefinition?
	local statesFolder = getStatesFolder(model, false)
	if not statesFolder then
		return nil
	end

	local stateFolder = statesFolder:FindFirstChild(stateName)
	if not stateFolder then
		return nil
	end

	local nodes = stateFolder:GetChildren()
	table.sort(nodes, function(a: Instance, b: Instance): boolean
		return (tonumber(a.Name) or 0) < (tonumber(b.Name) or 0)
	end)

	local sources: { Types.Source } = {}
	for _, node in nodes do
		local sourceType = node:GetAttribute("Type")
		if sourceType == "Set" then
			local setId = node:GetAttribute("SetId")
			if typeof(setId) == "string" then
				local filterCsv = node:GetAttribute("Filter")
				local filter = nil
				if typeof(filterCsv) == "string" and filterCsv ~= "" then
					filter = string.split(filterCsv, ",")
				end

				table.insert(sources, {
					Type = "Set",
					SetId = setId,
					Filter = filter,
				})
			end
		elseif sourceType == "Manual" then
			local description = node:GetAttribute("Description")
			local id = node:GetAttribute("Id")
			if typeof(id) == "string" and typeof(description) == "string" then
				table.insert(sources, {
					Type = "Manual",
					Id = id,
					Description = description,
					Keyboard = node:GetAttribute("Keyboard"),
					Gamepad = node:GetAttribute("Gamepad"),
				})
			end
		end
	end

	return { Sources = sources }
end

---Returns the per-model push RemoteEvent, creating it if missing.
function Serialize.ensureRemote(model: Instance): RemoteEvent
	local existing = model:FindFirstChild(Constants.RemoteName)
	if existing and existing:IsA("RemoteEvent") then
		return existing
	end

	local remote = Instance.new("RemoteEvent")
	remote.Name = Constants.RemoteName
	remote.Parent = model

	return remote
end

-- Return

return Serialize
