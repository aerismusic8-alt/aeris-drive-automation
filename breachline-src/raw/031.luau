--[[
	File: Common/MuzzleFlashFx.luau

	Client-side muzzle-flash VFX: ephemeral BillboardGui clone of Assets/UI/Flash
	plus a one-shot Lightable.flash PointLight. Owns a shared UnreliableRemoteEvent
	so server callers can broadcast a flash without per-system networking
	boilerplate. Used by Architects/Firearm2 and Behaviors/Gunnable.
]]--

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FourD = ReplicatedStorage:WaitForChild("FourD")
local Lightable = require(FourD.Behaviors.Lightable)

local DURATION = 0.05
local BILLBOARD_NAME = "MuzzleFlash"
local TEXTURE_NAME = "Texture"
local LIGHT_BRIGHTNESS = 1
local LIGHT_RANGE = 10
local LIGHT_COLOR = Color3.fromRGB(252, 244, 141)
local FLASH_TEMPLATE_PATH = { "Assets", "UI", "Flash" }
local REMOTE_NAME = "MuzzleFlashFx_Play"
local MAX_CACHED_FX = 16

type FxEntry = {
	Billboard: BillboardGui,
	GenToken: number,
}

local MuzzleFlashFx = {}

local cachedFlashTemplate: BillboardGui? = nil
local fxByAttachment: { [Attachment]: FxEntry } = {}
local lruOrder: { Attachment } = {}
local muzzleFlashRemote: UnreliableRemoteEvent

local function resolveRemote(): UnreliableRemoteEvent
	if RunService:IsServer() then
		local existing = script:FindFirstChild(REMOTE_NAME)
		if existing and existing:IsA("UnreliableRemoteEvent") then
			return existing
		end

		local remote = Instance.new("UnreliableRemoteEvent")
		remote.Name = REMOTE_NAME
		remote.Parent = script
		return remote
	end

	return script:WaitForChild(REMOTE_NAME) :: UnreliableRemoteEvent
end

local function resolveFlashTemplate(): BillboardGui?
	if cachedFlashTemplate and cachedFlashTemplate.Parent then
		return cachedFlashTemplate
	end

	local current: Instance = ReplicatedStorage
	for _, segment in FLASH_TEMPLATE_PATH do
		local nextChild = current:FindFirstChild(segment)
		if not nextChild then return nil end
		current = nextChild
	end

	if not current:IsA("BillboardGui") then return nil end

	cachedFlashTemplate = current
	return current
end

local function destroyEntry(attachment: Attachment)
	local entry = fxByAttachment[attachment]
	fxByAttachment[attachment] = nil
	if entry and entry.Billboard then
		entry.Billboard:Destroy()
	end
end

local function touchLru(attachment: Attachment)
	for i = #lruOrder, 1, -1 do
		if lruOrder[i] == attachment then
			table.remove(lruOrder, i)
			break
		end
	end

	table.insert(lruOrder, attachment)

	while #lruOrder > MAX_CACHED_FX do
		local evicted = table.remove(lruOrder, 1)
		if not evicted then break end
		destroyEntry(evicted)
	end
end

local function acquireBillboard(attachment: Attachment): BillboardGui?
	local entry = fxByAttachment[attachment]
	if entry and entry.Billboard.Parent == attachment then
		return entry.Billboard
	end

	if entry then
		destroyEntry(attachment)
	end

	local template = resolveFlashTemplate()
	if not template then return nil end

	local billboard = template:Clone()
	billboard.Name = BILLBOARD_NAME
	billboard.Enabled = false
	billboard.Parent = attachment

	fxByAttachment[attachment] = { Billboard = billboard, GenToken = 0 }
	return billboard
end

function MuzzleFlashFx.play(attachment: Attachment, color: Color3?)
	if not attachment or not attachment.Parent then return end

	local billboard = acquireBillboard(attachment)
	if billboard then
		local entry = fxByAttachment[attachment]
		local texture = billboard:FindFirstChild(TEXTURE_NAME)
		if texture and texture:IsA("ImageLabel") then
			texture.Rotation = math.random() * 360 - 180
		end

		billboard.Enabled = true

		entry.GenToken += 1
		local gen = entry.GenToken
		task.delay(DURATION, function()
			local current = fxByAttachment[attachment]
			if not current then return end
			if current.GenToken ~= gen then return end
			if current.Billboard and current.Billboard.Parent then
				current.Billboard.Enabled = false
			end
		end)

		touchLru(attachment)
	end

	Lightable.flash(attachment, {
		Type = "point",
		Brightness = LIGHT_BRIGHTNESS,
		Color = color or LIGHT_COLOR,
		Range = LIGHT_RANGE,
		Shadows = true,
		Flash = { Count = 1, OnLength = DURATION, OffLength = 0 },
	})
end

function MuzzleFlashFx.fire(attachment: Attachment, firingPlayer: Player?, color: Color3?)
	if not attachment then return end

	if RunService:IsServer() then
		muzzleFlashRemote:FireAllClients(firingPlayer, attachment, color)
		return
	end

	MuzzleFlashFx.play(attachment, color)
end

muzzleFlashRemote = resolveRemote()

if RunService:IsClient() then
	muzzleFlashRemote.OnClientEvent:Connect(function(firingPlayer: Player?, attachment: Attachment, color: Color3?)
		if firingPlayer == Players.LocalPlayer then return end
		if not attachment or not attachment:IsA("Attachment") then return end

		MuzzleFlashFx.play(attachment, color)
	end)
end

return MuzzleFlashFx
p