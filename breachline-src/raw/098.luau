--[[
	File: Common/Reload.luau

	Magazine + auto-reload state machine. Stores state on model attributes so
	the server fire path and any UI listeners can read it. gunAmmo = -1 opts
	out (infinite ammo, no reload).
]]--

local MAGAZINE_ATTR = "Gunnable_Magazine"
local RELOADING_ATTR = "Gunnable_Reloading"
local INFINITE_AMMO = -1

local Reload = {}

Reload.MAGAZINE_ATTR = MAGAZINE_ATTR
Reload.RELOADING_ATTR = RELOADING_ATTR
Reload.INFINITE_AMMO = INFINITE_AMMO

local function getCfgNumber(model: Model, name: string, default: number): number
	local cfg = model:FindFirstChild("GunnableHardpointConfig")
	if cfg then
		local v = cfg:FindFirstChild(name)
		if v and typeof(v.Value) == "number" then return v.Value end
	end

	return default
end

function Reload.setup(model: Model)
	local ammo = getCfgNumber(model, "gunAmmo", 100)
	model:SetAttribute(MAGAZINE_ATTR, ammo)
	model:SetAttribute(RELOADING_ATTR, false)

	if not model:FindFirstChild("ReloadGun") then
		local reloadEvent = Instance.new("RemoteEvent")
		reloadEvent.Name = "ReloadGun"
		reloadEvent.Parent = model
	end
end

function Reload.triggerReload(model: Model)
	if model:GetAttribute(RELOADING_ATTR) then return end

	local mag = model:GetAttribute(MAGAZINE_ATTR)
	if mag == INFINITE_AMMO then return end

	local capacity = getCfgNumber(model, "gunAmmo", 100)
	if capacity == INFINITE_AMMO then return end

	local reloadTime = getCfgNumber(model, "gunReloadTime", 3)

	model:SetAttribute(RELOADING_ATTR, true)

	local reloadEvent = model:FindFirstChild("ReloadGun")
	if reloadEvent and reloadEvent:IsA("RemoteEvent") then
		reloadEvent:FireAllClients("Started", reloadTime)
	end

	task.delay(reloadTime, function()
		if not model.Parent then return end
		model:SetAttribute(MAGAZINE_ATTR, capacity)
		model:SetAttribute(RELOADING_ATTR, false)

		if reloadEvent and reloadEvent:IsA("RemoteEvent") and reloadEvent.Parent then
			reloadEvent:FireAllClients("Completed")
		end
	end)
end

function Reload.tryConsume(model: Model): boolean
	local mag = model:GetAttribute(MAGAZINE_ATTR)
	if typeof(mag) ~= "number" then return false end
	if mag == INFINITE_AMMO then return true end
	if model:GetAttribute(RELOADING_ATTR) then return false end

	if mag > 0 then
		local nextMag = mag - 1
		model:SetAttribute(MAGAZINE_ATTR, nextMag)
		if nextMag == 0 then
			Reload.triggerReload(model)
		end

		return true
	end

	Reload.triggerReload(model)
	return false
end

return Reload
6