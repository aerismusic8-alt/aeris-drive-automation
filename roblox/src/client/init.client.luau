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
local ClaimDaily = Remotes:WaitForChild("ClaimDaily") :: RemoteFunction
local RedeemCode = Remotes:WaitForChild("RedeemCode") :: RemoteFunction
local WaveState = Remotes:WaitForChild("WaveState") :: RemoteEvent
local PlayerState = Remotes:WaitForChild("PlayerState") :: RemoteEvent
local Notify = Remotes:WaitForChild("Notify") :: RemoteEvent

local Hud = require(script.Hud)

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
	dailyReady = false,
	dailyStreak = 0,
	dailySecondsLeft = 0,
	wave = { phase = "INTERMISSION", wave = 0, timeRemaining = 0, aliveEnemies = 0 },
}

local function formatCoins(value: number): string
	local text = tostring(math.floor(value))
	local out = text:reverse():gsub("(%d%d%d)", "%1,")
	out = out:reverse()
	return (out:gsub("^,", ""))
end

local function setLabel(gui: Instance, name: string, text: string)
	-- The labels live inside panels, not directly under the ScreenGui, so the
	-- search has to recurse or every stat silently keeps its placeholder text.
	local label = gui:FindFirstChild(name, true)
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

	-- The daily button says what will happen before the tap, so a tap is
	-- never a surprise and a disabled button is obviously disabled.
	local rewardsFolder = gui:FindFirstChild("Rewards")
	local daily = rewardsFolder and rewardsFolder:FindFirstChild("Daily")
	if daily and daily:IsA("TextButton") then
		if state.dailyReady then
			daily.Text = string.format("Claim Daily (day %d)", state.dailyStreak + 1)
			daily.BackgroundColor3 = Color3.fromRGB(255, 206, 84)
			daily.Active = true
		else
			local hours = math.floor(state.dailySecondsLeft / 3600)
			local minutes = math.floor((state.dailySecondsLeft % 3600) / 60)
			daily.Text = string.format("Daily in %dh %dm", hours, minutes)
			daily.BackgroundColor3 = Color3.fromRGB(70, 74, 88)
			daily.Active = false
		end
	end

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
	state.dailyReady = payload.dailyReady == true
	state.dailyStreak = payload.dailyStreak or 0
	state.dailySecondsLeft = payload.dailySecondsLeft or 0
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

function Intent.claimDaily(): (boolean, any, string?)
	return invoke(ClaimDaily)
end

function Intent.redeemCode(code: string): (boolean, any, string?)
	if type(code) ~= "string" or #code == 0 then
		return false, nil, "EMPTY_CODE"
	end
	return invoke(RedeemCode, code)
end

-- Roblox has no native text prompt, so this is the smallest screen that can
-- accept a code and confirm it. One field, two big buttons.
local function promptForCode(onSubmit: (string) -> ())
	local playerGui = player:WaitForChild("PlayerGui")
	local existing = playerGui:FindFirstChild("AXCodePrompt")
	if existing then
		existing:Destroy()
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "AXCodePrompt"
	gui.ResetOnSpawn = false
	gui.Parent = playerGui

	local shade = Instance.new("TextButton")
	shade.Size = UDim2.new(1, 0, 1, 0)
	shade.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	shade.BackgroundTransparency = 0.45
	shade.Text = ""
	shade.AutoButtonColor = false
	shade.Parent = gui

	local box = Instance.new("Frame")
	box.Size = UDim2.new(0, 300, 0, 180)
	box.Position = UDim2.new(0.5, 0, 0.5, 0)
	box.AnchorPoint = Vector2.new(0.5, 0.5)
	box.BackgroundColor3 = Color3.fromRGB(18, 20, 28)
	box.BorderSizePixel = 0
	box.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 14)
	corner.Parent = box

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -24, 0, 30)
	title.Position = UDim2.new(0, 12, 0, 8)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextSize = 18
	title.TextColor3 = Color3.fromRGB(236, 240, 248)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = "Enter a promo code"
	title.Parent = box

	local entry = Instance.new("TextBox")
	entry.Name = "Entry"
	entry.Size = UDim2.new(1, -24, 0, 46)
	entry.Position = UDim2.new(0, 12, 0, 42)
	entry.BackgroundColor3 = Color3.fromRGB(32, 36, 48)
	entry.BorderSizePixel = 0
	entry.Font = Enum.Font.GothamBold
	entry.TextSize = 22
	entry.TextColor3 = Color3.fromRGB(255, 255, 255)
	entry.PlaceholderText = "CODE"
	entry.Text = ""
	entry.ClearTextOnFocus = false
	entry.Parent = box

	local entryCorner = Instance.new("UICorner")
	entryCorner.CornerRadius = UDim.new(0, 10)
	entryCorner.Parent = entry

	local function close()
		gui:Destroy()
	end

	local submit = Instance.new("TextButton")
	submit.Size = UDim2.new(0.5, -18, 0, 50)
	submit.Position = UDim2.new(0, 12, 1, -62)
	submit.BackgroundColor3 = Color3.fromRGB(96, 170, 255)
	submit.Font = Enum.Font.GothamBold
	submit.TextSize = 20
	submit.TextColor3 = Color3.fromRGB(12, 14, 20)
	submit.Text = "Redeem"
	submit.Parent = box
	local submitCorner = Instance.new("UICorner")
	submitCorner.CornerRadius = UDim.new(0, 10)
	submitCorner.Parent = submit

	local cancel = Instance.new("TextButton")
	cancel.Size = UDim2.new(0.5, -18, 0, 50)
	cancel.Position = UDim2.new(0.5, 6, 1, -62)
	cancel.BackgroundColor3 = Color3.fromRGB(70, 74, 88)
	cancel.Font = Enum.Font.GothamBold
	cancel.TextSize = 20
	cancel.TextColor3 = Color3.fromRGB(236, 240, 248)
	cancel.Text = "Cancel"
	cancel.Parent = box
	local cancelCorner = Instance.new("UICorner")
	cancelCorner.CornerRadius = UDim.new(0, 10)
	cancelCorner.Parent = cancel

	cancel.Activated:Connect(close)
	shade.Activated:Connect(close)
	submit.Activated:Connect(function()
		local value = entry.Text
		close()
		onSubmit(value)
	end)
	entry:CaptureFocus()
end

-- Wire the reward buttons. Each tap calls the same Intent the rest of the
-- client uses, so the button and the API cannot drift apart.
local function wireButtons()
	local gui = Hud.build()

	local rewards = gui:WaitForChild("Rewards")
	local daily = rewards:WaitForChild("Daily") :: TextButton
	local code = rewards:WaitForChild("Code") :: TextButton

	daily.Activated:Connect(function()
		-- The server confirms and pushes new state back, so the button updates
		-- from PlayerState rather than from this response.
		local ok, _, reason = Intent.claimDaily()
		if not ok and reason then
			warn("[AX Arena] daily rejected: " .. tostring(reason))
		end
	end)

	code.Activated:Connect(function()
		promptForCode(function(value)
			local ok, _, reason = Intent.redeemCode(value)
			if not ok and reason then
				warn("[AX Arena] code rejected: " .. tostring(reason))
			end
		end)
	end)
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

-- Build the screen, then wire the buttons.
Hud.build()
wireButtons()

_G.AXArena = {
	state = state,
	Intent = Intent,
	Config = Config,
}

render()
print("[AX Arena] client ready")
