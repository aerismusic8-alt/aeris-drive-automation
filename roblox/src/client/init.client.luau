--!strict
-- Client entry point: renders server state and sends intent.
--
-- The client never computes authoritative values. It displays what the server
-- sent and asks permission before changing anything. All the farm UI (eggs,
-- pets, rebirth, zones, shop) goes through the remotes created by the server.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RequestUpgrade = Remotes:WaitForChild("RequestUpgrade") :: RemoteFunction
local RequestShop = Remotes:WaitForChild("RequestShop") :: RemoteFunction
local HatchEgg = Remotes:WaitForChild("HatchEgg") :: RemoteFunction
local EquipPet = Remotes:WaitForChild("EquipPet") :: RemoteFunction
local UnequipPet = Remotes:WaitForChild("UnequipPet") :: RemoteFunction
local DoRebirth = Remotes:WaitForChild("Rebirth") :: RemoteFunction
local TravelZone = Remotes:WaitForChild("TravelZone") :: RemoteFunction
local WaveState = Remotes:WaitForChild("WaveState") :: RemoteEvent
local PlayerState = Remotes:WaitForChild("PlayerState") :: RemoteEvent
local Notify = Remotes:WaitForChild("Notify") :: RemoteEvent

local player = Players.LocalPlayer

local state = {
	coins = 0,
	upgrades = {},
	stats = { kills = 0, wavesCleared = 0, deaths = 0 },
	derived = nil,
	health = 0,
	maxHealth = 0,
	level = 1,
	xp = 0,
	xpForNext = 1,
	rebirths = 0,
	rebirthRequirement = 0,
	zone = Config.Zones.Default,
	pets = { pets = {}, equipped = {} },
	maxEquipped = Config.Pets.MaxEquipped,
	coinMultiplier = 1,
	wave = { phase = "INTERMISSION", wave = 0, timeRemaining = 0, aliveEnemies = 0 },
}

local function formatCoins(value: number): string
	local text = tostring(math.floor(value))
	local out = text:reverse():gsub("(%d%d%d)", "%1,")
	out = out:reverse()
	return (out:gsub("^,", ""))
end

local function setLabel(gui: Instance, name: string, text: string)
	local label = gui:FindFirstChild(name)
	if label and label:IsA("TextLabel") then
		label.Text = text
	end
end

local function render()
	local hud = player:FindFirstChild("PlayerGui")
	if not hud then
		return
	end
	local gui = hud:FindFirstChild("AXArenaHUD")
	if not gui then
		return
	end

	setLabel(gui, "Coins", "Coins: " .. formatCoins(state.coins))
	setLabel(gui, "Level", string.format("Lv %d  (%d/%s XP)", state.level, math.floor(state.xp),
		state.xpForNext == math.huge and "MAX" or tostring(math.floor(state.xpForNext))))
	setLabel(gui, "Health", string.format("HP %d/%d", math.floor(state.health), math.floor(state.maxHealth)))
	setLabel(gui, "Zone", "Zone: " .. state.zone)
	setLabel(gui, "Rebirth", string.format("Rebirth %d (x%.2f)", state.rebirths, state.coinMultiplier))

	local w = state.wave
	if w.phase == "INTERMISSION" then
		setLabel(gui, "Wave", string.format("Wave %d starts in %ds", w.wave + 1, math.ceil(w.timeRemaining)))
	else
		setLabel(gui, "Wave", string.format("Wave %d - %d enemies", w.wave, w.aliveEnemies))
	end
end

PlayerState.OnClientEvent:Connect(function(payload)
	state.coins = payload.coins
	state.upgrades = payload.upgrades
	state.stats = payload.stats
	state.derived = payload.derived
	state.health = payload.health
	state.maxHealth = payload.maxHealth
	state.level = payload.level
	state.xp = payload.xp
	state.xpForNext = payload.xpForNext
	state.rebirths = payload.rebirths
	state.rebirthRequirement = payload.rebirthRequirement
	state.zone = payload.zone
	state.pets = payload.pets
	state.maxEquipped = payload.maxEquipped
	state.coinMultiplier = payload.coinMultiplier
	render()
end)

WaveState.OnClientEvent:Connect(function(snapshot)
	state.wave = snapshot
	render()
end)

Notify.OnClientEvent:Connect(function(message)
	print("[AX Arena] " .. tostring(message))
end)

-- Every call is wrapped so a server-side rejection surfaces as a reason
-- instead of an error the UI has to guess at.
local function invoke(remote: RemoteFunction, ...): (boolean, any, any)
	local ok, allowed, extra = pcall(function(...)
		return remote:InvokeServer(...)
	end, ...)
	if not ok then
		warn("[AX Arena] remote failed: " .. tostring(allowed))
		return false, "REQUEST_FAILED", nil
	end
	return allowed, extra, nil
end

local Intent = {}

function Intent.requestUpgrade(upgradeId: string): (boolean, string?)
	return invoke(RequestUpgrade, upgradeId)
end

function Intent.fetchShop(): any
	local ok, data = invoke(RequestShop)
	return ok and data or nil
end

function Intent.hatchEgg(eggId: string): (boolean, any, string?)
	return invoke(HatchEgg, eggId)
end

function Intent.equipPet(uid: number): (boolean, string?)
	return invoke(EquipPet, uid)
end

function Intent.unequipPet(uid: number): (boolean, string?)
	return invoke(UnequipPet, uid)
end

function Intent.rebirth(): (boolean, string?)
	return invoke(DoRebirth)
end

function Intent.travelZone(zoneId: string): (boolean, string?)
	return invoke(TravelZone, zoneId)
end

-- Robux purchases go straight to Roblox. The prompt needs the *numeric* asset
-- id, which is configured per product; the server grants on receipt.
function Intent.buyProduct(productId: string): (boolean, string?)
	local shop = Intent.fetchShop()
	if not shop then
		return false, "SHOP_UNAVAILABLE"
	end

	for _, product in ipairs(shop.products or {}) do
		if product.id == productId then
			if not product.assetId then
				return false, "NOT_CONFIGURED"
			end
			local ok = pcall(function()
				if product.kind == "gamepass" then
					MarketplaceService:PromptGamePassPurchase(player, product.assetId)
				else
					MarketplaceService:PromptProductPurchase(player, product.assetId)
				end
			end)
			if not ok then
				return false, "PROMPT_FAILED"
			end
			return true, nil
		end
	end
	return false, "UNKNOWN_PRODUCT"
end

_G.AXArena = {
	state = state,
	Intent = Intent,
	Config = Config,
}

render()
print("[AX Arena] client ready")
