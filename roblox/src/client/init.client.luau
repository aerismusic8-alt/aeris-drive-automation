--!strict
-- Client entry point: renders server state and sends upgrade intent.
--
-- The client never computes authoritative values; it displays what the server
-- sent and asks permission before changing anything.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RequestUpgrade = Remotes:WaitForChild("RequestUpgrade") :: RemoteFunction
local WaveState = Remotes:WaitForChild("WaveState") :: RemoteEvent
local PlayerState = Remotes:WaitForChild("PlayerState") :: RemoteEvent

local player = Players.LocalPlayer

local state = {
	coins = 0,
	upgrades = {},
	inventory = {},
	stats = { kills = 0, wavesCleared = 0, deaths = 0 },
	derived = nil,
	health = 0,
	maxHealth = 0,
	wave = { phase = "INTERMISSION", wave = 0, timeRemaining = 0, aliveEnemies = 0 },
}

local function formatCoins(value: number): string
	local text = tostring(math.floor(value))
	local out = text:reverse():gsub("(%d%d%d)", "%1,")
	out = out:reverse()
	return (out:gsub("^,", ""))
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

	local coins = gui:FindFirstChild("Coins")
	if coins and coins:IsA("TextLabel") then
		coins.Text = "Coins: " .. formatCoins(state.coins)
	end

	local waveLabel = gui:FindFirstChild("Wave")
	if waveLabel and waveLabel:IsA("TextLabel") then
		local w = state.wave
		if w.phase == "INTERMISSION" then
			waveLabel.Text = string.format("Wave %d starts in %ds", w.wave + 1, math.ceil(w.timeRemaining))
		else
			waveLabel.Text = string.format("Wave %d - %d enemies", w.wave, w.aliveEnemies)
		end
	end

	local healthLabel = gui:FindFirstChild("Health")
	if healthLabel and healthLabel:IsA("TextLabel") then
		healthLabel.Text = string.format("HP %d/%d", math.floor(state.health), math.floor(state.maxHealth))
	end
end

PlayerState.OnClientEvent:Connect(function(payload)
	state.coins = payload.coins
	state.upgrades = payload.upgrades
	state.inventory = payload.inventory
	state.stats = payload.stats
	state.derived = payload.derived
	state.health = payload.health
	state.maxHealth = payload.maxHealth
	render()
end)

WaveState.OnClientEvent:Connect(function(snapshot)
	state.wave = snapshot
	render()
end)

-- Public intent API used by UI buttons.
local function requestUpgrade(upgradeId: string): (boolean, string?)
	local ok, allowed, reason = pcall(function()
		return RequestUpgrade:InvokeServer(upgradeId)
	end)
	if not ok then
		warn("[AX Arena] upgrade request failed: " .. tostring(allowed))
		return false, "REQUEST_FAILED"
	end
	return allowed, reason
end

_G.AXArena = {
	state = state,
	requestUpgrade = requestUpgrade,
	Config = Config,
}

render()
print("[AX Arena] client ready")
