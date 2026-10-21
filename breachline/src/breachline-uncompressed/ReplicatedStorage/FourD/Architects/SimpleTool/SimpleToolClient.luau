-- GENERATED WRAPPER around upstream SimpleToolClient.
-- Only the enclosing function is added. Started by StarterPlayerScripts.Client.FourDClientRuntime.
return function(root: Instance, manifest: Instance)
--[[
	File: SimpleToolClient.server.luau
]]--

if not script.Parent:IsA("Tool") then return end

-- Roblox Services

local ContextActionService = game:GetService("ContextActionService")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")

-- Object References

local toolInstance: Tool = script.Parent

-- Constants

local KEY_DELIMITER = ";"
local BIND_ATTRIBUTE_PREFIX = "Bind_"
local BIND_BUTTON_PREFIX = "BindBtn_"
local BUTTON_DELIMITER = "|"
local CAS_PREFIX = "SimpleToolBind_" .. string.gsub(HttpService:GenerateGUID(false), "-", "") .. "_"

-- Module State

local idleTrack: AnimationTrack? = nil
local idleHumanoid: Humanoid? = nil
local idleAnimId: string? = nil

local activateTrack: AnimationTrack? = nil
local activateHumanoid: Humanoid? = nil
local activateAnimId: string? = nil

local customBindsRemote: RemoteEvent? = nil
local customBindMap: { [any]: { string } } = {}
local customBindUisConnection: RBXScriptConnection? = nil
local equippedNow = false
local warnedKeys: { [string]: boolean } = {}

type ButtonBindInfo = {
	Inputs: { EnumItem },
	Title: string?,
	Image: string?,
	Position: UDim2?,
}

local buttonBinds: { [string]: ButtonBindInfo } = {}
local casBoundIds: { [string]: boolean } = {}

-- Forward Declarations

local syncCasBindings: () -> ()
local casHandler: (string, Enum.UserInputState, InputObject) -> Enum.ContextActionResult

-- Local Functions

local function lookupEnum(enumType: Enum, name: string): EnumItem?
	for _, item in enumType:GetEnumItems() do
		if item.Name == name then return item end
	end
	return nil
end

local function parseBindValue(value: string): { EnumItem }
	local tokens = string.split(value, KEY_DELIMITER)
	local keys: { EnumItem } = {}
	for i = 2, #tokens do
		local token = tokens[i]
		if token == "" then continue end
		local segments = string.split(token, ".")
		if #segments ~= 2 then
			if not warnedKeys[token] then
				warnedKeys[token] = true
				warn(`[SimpleToolClient] unparseable bind key "{token}"`)
			end
			continue
		end

		local enumTypeName, enumName = segments[1], segments[2]
		local enumItem: EnumItem? = nil
		if enumTypeName == "KeyCode" then
			enumItem = lookupEnum(Enum.KeyCode, enumName)
		elseif enumTypeName == "UserInputType" then
			enumItem = lookupEnum(Enum.UserInputType, enumName)
		end

		if enumItem then
			table.insert(keys, enumItem)
		elseif not warnedKeys[token] then
			warnedKeys[token] = true
			warn(`[SimpleToolClient] unknown bind key "{token}"`)
		end
	end

	return keys
end

local function parseButtonValue(value: string): ButtonBindInfo
	local segs = string.split(value, BUTTON_DELIMITER)
	local title = segs[1]
	local image = segs[2]
	local posStr = segs[3]

	local position: UDim2? = nil
	if posStr and posStr ~= "" then
		local parts = string.split(posStr, ",")
		if #parts == 4 then
			position = UDim2.new(
				tonumber(parts[1]) or 0,
				tonumber(parts[2]) or 0,
				tonumber(parts[3]) or 0,
				tonumber(parts[4]) or 0
			)
		end
	end

	return {
		Inputs = {},
		Title = (title and title ~= "") and title or nil,
		Image = (image and image ~= "") and image or nil,
		Position = position,
	}
end

local function rebuildBindMap()
	table.clear(customBindMap)
	table.clear(buttonBinds)

	local bindEntries: { [string]: { EnumItem } } = {}
	local buttonEntries: { [string]: string } = {}

	for name, value in script:GetAttributes() do
		if typeof(value) ~= "string" then continue end

		local bindId = string.match(name, `^{BIND_ATTRIBUTE_PREFIX}(.+)`)
		if bindId then
			bindEntries[bindId] = parseBindValue(value)
			continue
		end

		local buttonId = string.match(name, `^{BIND_BUTTON_PREFIX}(.+)`)
		if buttonId then
			buttonEntries[buttonId] = value
		end
	end

	for id, keys in bindEntries do
		local buttonValue = buttonEntries[id]
		if buttonValue then
			local info = parseButtonValue(buttonValue)
			info.Inputs = keys
			buttonBinds[id] = info
		else
			for _, enumItem in keys do
				local bucket = customBindMap[enumItem]
				if not bucket then
					bucket = {}
					customBindMap[enumItem] = bucket
				end
				table.insert(bucket, id)
			end
		end
	end

	syncCasBindings()
end

local function loadTrack(humanoid: Humanoid, animationId: string): AnimationTrack
	local anim = Instance.new("Animation")
	anim.AnimationId = animationId
	local track = humanoid:LoadAnimation(anim)
	anim:Destroy()
	return track
end

local function stopAndClear(trackRef: AnimationTrack?): AnimationTrack?
	if trackRef then
		trackRef:Stop()
		trackRef:Destroy()
	end

	return nil
end

local function resolveBindsRemote(): RemoteEvent?
	if customBindsRemote then return customBindsRemote end
	local found = toolInstance:FindFirstChild("CustomBindsRemote")
	if found and found:IsA("RemoteEvent") then
		customBindsRemote = found
		return found
	end
	return nil
end

casHandler = function(actionName: string, inputState: Enum.UserInputState, _: InputObject): Enum.ContextActionResult
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end

	if not equippedNow then
		return Enum.ContextActionResult.Pass
	end

	local remote = resolveBindsRemote()
	if not remote then
		return Enum.ContextActionResult.Pass
	end

	local id = string.sub(actionName, #CAS_PREFIX + 1)
	remote:FireServer(id)
	return Enum.ContextActionResult.Pass
end

syncCasBindings = function()
	for id in casBoundIds do
		if not buttonBinds[id] then
			ContextActionService:UnbindAction(CAS_PREFIX .. id)
			casBoundIds[id] = nil
		end
	end

	if not equippedNow then return end

	for id, info in buttonBinds do
		local actionName = CAS_PREFIX .. id
		if casBoundIds[id] then
			ContextActionService:UnbindAction(actionName)
		end

		ContextActionService:BindAction(actionName, casHandler, true, table.unpack(info.Inputs))
		if info.Title then ContextActionService:SetTitle(actionName, info.Title) end
		if info.Image then ContextActionService:SetImage(actionName, info.Image) end
		if info.Position then ContextActionService:SetPosition(actionName, info.Position) end
		casBoundIds[id] = true
	end
end

local function onInputBegan(input: InputObject, gameProcessed: boolean)
	if gameProcessed then return end
	if not equippedNow then return end

	local remote = resolveBindsRemote()
	if not remote then return end

	local key: any
	if input.KeyCode ~= Enum.KeyCode.Unknown then
		key = input.KeyCode
	else
		key = input.UserInputType
	end

	local ids = customBindMap[key]
	if not ids then return end
	for _, id in ids do
		remote:FireServer(id)
	end
end

local function onEquipped()
	equippedNow = true
	resolveBindsRemote()
	syncCasBindings()

	if customBindUisConnection then customBindUisConnection:Disconnect() end
	customBindUisConnection = UserInputService.InputBegan:Connect(onInputBegan)

	local character = toolInstance.Parent
	if not character or not character:IsA("Model") then return end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	local idleId = toolInstance:GetAttribute("IdleAnimationId")
	if typeof(idleId) ~= "string" or idleId == "" then return end

	if idleTrack and (idleHumanoid ~= humanoid or idleAnimId ~= idleId) then
		idleTrack = stopAndClear(idleTrack)
	end

	local track: AnimationTrack
	if idleTrack then
		track = idleTrack
	else
		track = loadTrack(humanoid, idleId)
		track.Priority = Enum.AnimationPriority.Idle
		track.Looped = true
		idleTrack = track
		idleHumanoid = humanoid
		idleAnimId = idleId
	end

	track:Play()
end

local function onUnequipped()
	equippedNow = false
	if customBindUisConnection then
		customBindUisConnection:Disconnect()
		customBindUisConnection = nil
	end

	for id in casBoundIds do
		ContextActionService:UnbindAction(CAS_PREFIX .. id)
		casBoundIds[id] = nil
	end

	if idleTrack then idleTrack:Stop() end
	if activateTrack then activateTrack:Stop() end
end

local function onActivated()
	local character = toolInstance.Parent
	if not character or not character:IsA("Model") then return end

	local activateId = toolInstance:GetAttribute("ActivateAnimationId")
	if typeof(activateId) ~= "string" or activateId == "" then return end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	if activateTrack and (activateHumanoid ~= humanoid or activateAnimId ~= activateId) then
		activateTrack = stopAndClear(activateTrack)
	end

	local track: AnimationTrack
	if activateTrack then
		track = activateTrack
	else
		track = loadTrack(humanoid, activateId)
		track.Priority = Enum.AnimationPriority.Action
		track.Looped = false
		activateTrack = track
		activateHumanoid = humanoid
		activateAnimId = activateId
	end

	track:Stop()
	track:Play()
end

local function onAttributeChanged(name: string)
	if string.match(name, `^{BIND_ATTRIBUTE_PREFIX}(.+)`)
		or string.match(name, `^{BIND_BUTTON_PREFIX}(.+)`) then
		rebuildBindMap()
	end
end

script.AttributeChanged:Connect(onAttributeChanged)
toolInstance.Equipped:Connect(onEquipped)
toolInstance.Unequipped:Connect(onUnequipped)
toolInstance.Activated:Connect(onActivated)

script.Destroying:Connect(function()
	for id in casBoundIds do
		ContextActionService:UnbindAction(CAS_PREFIX .. id)
		casBoundIds[id] = nil
	end
end)

rebuildBindMap()

end
