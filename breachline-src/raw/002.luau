--[[
	File: StarterPlayerScripts/Client/LightableClient.client.luau

	Single shared client controller for the Lightable behavior. Discovers
	strobe + flash wrappers via CollectionService tags and renders their
	time-varying effects locally using `workspace:GetServerTimeNow()` so
	all clients (including late-joiners) stay in phase without per-frame
	server traffic.

	Server tags wrapper folders with `Lightable_Strobe` or `Lightable_Flash`.
	Each wrapper carries:
		- LightRef ObjectValue -> the Light instance to drive
		- BaseBrightness, BaseColor, BaseRange, BaseShadows, BaseAngle?,
		  BaseFace? attributes (the static "base" values)
		- Strobe-specific: StrobeEnabled, StrobeStartTime, Keyframes folder
		- Flash-specific:  FlashCount, FlashOnLength, FlashOffLength,
		                   FlashStartTime, FlashTotalDuration
]]--

-- Roblox Services

local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Dependencies

local FourD = ReplicatedStorage:WaitForChild("FourD")
local Behaviors = FourD:FindFirstChild("Behaviors")
local BehaviorRoot = Behaviors and Behaviors:FindFirstChild("Lightable")
if BehaviorRoot == nil then
	return
end
local Constants = require(BehaviorRoot.Common.Constants)

-- Constants

local VERBOSE_LOGGING = false
local STROBE_TAG = Constants.STROBE_TAG
local FLASH_TAG = Constants.FLASH_TAG
local LIGHT_REF_NAME = Constants.LIGHT_REF_VALUE_NAME
local KEYFRAMES_ATTRIBUTE_NAME = Constants.KEYFRAMES_ATTRIBUTE_NAME

-- Local Functions

local function vprint(...: any)
	if not VERBOSE_LOGGING then return end
	print(`[{script.Name}]`, ...)
end

local function vwarn(...: any)
	warn(`[{script.Name}]`, ...)
end

-- State

local entries: { [Folder]: Entry } = {}

-- Helpers

local function resolveLight(wrapper: Folder): Light?
	local ref = wrapper:FindFirstChild(LIGHT_REF_NAME)
	if not ref or not ref:IsA("ObjectValue") then
		return nil
	end

	local value = ref.Value
	if value and value:IsA("Light") then
		return value
	end

	return nil
end

local function readKeyframes(wrapper: Folder): ({ StrobeKeyframeCache }, number)
	local encoded = wrapper:GetAttribute(KEYFRAMES_ATTRIBUTE_NAME)
	if typeof(encoded) ~= "string" or encoded == "" then
		return {}, 0
	end

	local ok, decoded = pcall(function()
		return HttpService:JSONDecode(encoded)
	end)
	if not ok or typeof(decoded) ~= "table" then
		return {}, 0
	end

	local total = 0
	local keyframes: { StrobeKeyframeCache } = {}
	for _, raw in ipairs(decoded) do
		local rawColor = raw.C
		local color = if typeof(rawColor) == "table"
			then Color3.new(rawColor[1] or 1, rawColor[2] or 1, rawColor[3] or 1)
			else Color3.new(1, 1, 1)
		local time = math.max(raw.T or 0, 0)
		total += time
		table.insert(keyframes, {
			Brightness = raw.B or 0,
			Color = color,
			Enabled = if raw.E ~= nil then raw.E else true,
			Range = raw.R or 0,
			Time = time,
		})
	end

	return keyframes, total
end

local function applyKeyframe(light: LightObject, kf: StrobeKeyframeCache)
	if not kf.Enabled then
		light.Enabled = false
		return
	end

	light.Brightness = kf.Brightness
	light.Color = kf.Color
	light.Range = kf.Range
	light.Enabled = true
end

-- Entry Registration

local function registerStrobe(wrapper: Folder)
	if entries[wrapper] then return end

	local light = resolveLight(wrapper)
	if not light then
		vwarn("Strobe wrapper missing Light reference:", wrapper:GetFullName())
		return
	end

	local keyframes, totalCycle = readKeyframes(wrapper)
	local entry: StrobeEntry = {
		Kind = "strobe",
		Wrapper = wrapper,
		Light = light,
		Connections = {},
		Keyframes = keyframes,
		TotalCycle = totalCycle,
		Enabled = wrapper:GetAttribute("StrobeEnabled") == true,
		StartTime = (wrapper:GetAttribute("StrobeStartTime") or 0) :: number,
		CurrentIndex = -1,
	}

	table.insert(entry.Connections, wrapper:GetAttributeChangedSignal("StrobeEnabled"):Connect(function()
		entry.Enabled = wrapper:GetAttribute("StrobeEnabled") == true
		entry.CurrentIndex = -1
	end))

	table.insert(entry.Connections, wrapper:GetAttributeChangedSignal("StrobeStartTime"):Connect(function()
		entry.StartTime = wrapper:GetAttribute("StrobeStartTime") or 0
		entry.CurrentIndex = -1
	end))

	entries[wrapper] = entry

	vprint("Registered strobe:", wrapper:GetFullName(), "keyframes:", #keyframes, "cycle:", totalCycle)
end

local function registerFlash(wrapper: Folder)
	if entries[wrapper] then return end

	local light = resolveLight(wrapper)
	if not light then
		vwarn("Flash wrapper missing Light reference:", wrapper:GetFullName())
		return
	end

	local entry: FlashEntry = {
		Kind = "flash",
		Wrapper = wrapper,
		Light = light,
		Count = wrapper:GetAttribute("FlashCount") or Constants.DEFAULTS.FlashCount,
		OnLength = wrapper:GetAttribute("FlashOnLength") or Constants.DEFAULTS.FlashOnLength,
		OffLength = wrapper:GetAttribute("FlashOffLength") or Constants.DEFAULTS.FlashOffLength,
		StartTime = wrapper:GetAttribute("FlashStartTime") or workspace:GetServerTimeNow(),
		TotalDuration = wrapper:GetAttribute("FlashTotalDuration") or 0,
		Finished = false,
		LastEnabled = nil,
	}

	entries[wrapper] = entry

	vprint("Registered flash:", wrapper:GetFullName(), "duration:", entry.TotalDuration)
end

local function unregister(wrapper: Folder)
	local entry = entries[wrapper]
	if not entry then return end

	if entry.Kind == "strobe" then
		for _, conn in ipairs(entry.Connections) do
			conn:Disconnect()
		end
	end

	if entry.Light and entry.Light.Parent then
		entry.Light.Enabled = false
	end

	entries[wrapper] = nil
	vprint("Unregistered:", wrapper:GetFullName())
end

-- Per-frame Tick

local function tickStrobe(entry: StrobeEntry, now: number)
	local light = entry.Light
	if not light or not light.Parent then return end

	if not entry.Enabled or entry.TotalCycle <= 0 or #entry.Keyframes == 0 then
		if entry.CurrentIndex ~= 0 then
			light.Enabled = false
			entry.CurrentIndex = 0
		end

		return
	end

	local elapsed = (now - entry.StartTime) % entry.TotalCycle
	local accum = 0
	local targetIndex = #entry.Keyframes

	for index, kf in ipairs(entry.Keyframes) do
		accum += kf.Time
		if elapsed < accum then
			targetIndex = index
			break
		end
	end

	if entry.CurrentIndex == targetIndex then return end

	entry.CurrentIndex = targetIndex
	applyKeyframe(light, entry.Keyframes[targetIndex])
end

local function tickFlash(entry: FlashEntry, now: number)
	local light = entry.Light
	if not light or not light.Parent then return end
	if entry.Finished then return end

	local elapsed = now - entry.StartTime
	if elapsed < 0 then
		if entry.LastEnabled ~= false then
			light.Enabled = false
			entry.LastEnabled = false
		end

		return
	end

	if elapsed >= entry.TotalDuration then
		entry.Finished = true
		unregister(entry.Wrapper)
		return
	end

	local cycleLength = entry.OnLength + entry.OffLength
	local cycleIndex = if cycleLength > 0 then math.floor(elapsed / cycleLength) else 0
	if cycleIndex >= entry.Count then
		entry.Finished = true
		unregister(entry.Wrapper)
		return
	end

	local intra = elapsed - cycleIndex * cycleLength
	local nowEnabled = intra < entry.OnLength
	if entry.LastEnabled ~= nowEnabled then
		light.Enabled = nowEnabled
		entry.LastEnabled = nowEnabled
	end
end

-- Bootstrap

CollectionService:GetInstanceAddedSignal(STROBE_TAG):Connect(function(instance: Instance)
	if instance:IsA("Folder") then
		registerStrobe(instance)
	end
end)

CollectionService:GetInstanceRemovedSignal(STROBE_TAG):Connect(function(instance: Instance)
	if instance:IsA("Folder") then
		unregister(instance)
	end
end)

CollectionService:GetInstanceAddedSignal(FLASH_TAG):Connect(function(instance: Instance)
	if instance:IsA("Folder") then
		registerFlash(instance)
	end
end)

CollectionService:GetInstanceRemovedSignal(FLASH_TAG):Connect(function(instance: Instance)
	if instance:IsA("Folder") then
		unregister(instance)
	end
end)

for _, wrapper in ipairs(CollectionService:GetTagged(STROBE_TAG)) do
	if wrapper:IsA("Folder") then
		registerStrobe(wrapper)
	end
end

for _, wrapper in ipairs(CollectionService:GetTagged(FLASH_TAG)) do
	if wrapper:IsA("Folder") then
		registerFlash(wrapper)
	end
end

RunService.Heartbeat:Connect(function()
	local now = workspace:GetServerTimeNow()
	for _, entry in pairs(entries) do
		if entry.Kind == "strobe" then
			tickStrobe(entry, now)
		else
			tickFlash(entry, now)
		end
	end
end)

-- Types

type LightObject = Light & PointLight & SurfaceLight & SpotLight

type StrobeKeyframeCache = {
	Brightness: number,
	Color: Color3,
	Enabled: boolean,
	Range: number,
	Time: number,
}

type StrobeEntry = {
	Kind: "strobe",
	Wrapper: Folder,
	Light: Light?,
	Connections: { RBXScriptConnection },
	Keyframes: { StrobeKeyframeCache },
	TotalCycle: number,
	Enabled: boolean,
	StartTime: number|any,
	CurrentIndex: number,
}

type FlashEntry = {
	Kind: "flash",
	Wrapper: Folder,
	Light: Light?,
	Count: number,
	OnLength: number,
	OffLength: number,
	StartTime: number,
	TotalDuration: number,
	Finished: boolean,
	LastEnabled: boolean?,
}

type Entry = StrobeEntry | FlashEntry

vprint("LightableClient online")
