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
local PlantCrop = Remotes:WaitForChild("PlantCrop") :: RemoteFunction
local HarvestCrop = Remotes:WaitForChild("HarvestCrop") :: RemoteFunction
local UseAxe = Remotes:WaitForChild("UseAxe") :: RemoteFunction
local FarmState = Remotes:WaitForChild("FarmState") :: RemoteEvent
local WaveState = Remotes:WaitForChild("WaveState") :: RemoteEvent
local PlayerState = Remotes:WaitForChild("PlayerState") :: RemoteEvent
local Notify = Remotes:WaitForChild("Notify") :: RemoteEvent
local CombatFx = Remotes:WaitForChild("CombatFx") :: RemoteEvent

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
	field = nil,
	fields = {},
	killStreak = 0,
	pets = { pets = {}, equipped = {} },
	maxEquipped = Config.Pets.MaxEquipped,
	coinMultiplier = 1,
	dailyReady = false,
	dailyStreak = 0,
	dailySecondsLeft = 0,
	plots = {},
	axe = { charges = 0, maxCharges = 5 },
	crops = {},
	cropIndex = 1,
	wave = { phase = "TOWN", wave = 0, timeRemaining = 0, aliveEnemies = 0 },
	-- The most recent kill, shown for a moment so a boss kill reads as a
	-- moment rather than a number change.
	lastKill = nil,
	lastKillAt = 0,
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
	setLabel(gui, "Field", "Field: " .. (state.field or "Town"))
	setLabel(gui, "Zone", string.format("Zone: %s  (x%.1f)", state.zone, state.coinMultiplier))
	setLabel(gui, "Rebirth", string.format("Rebirth %d  Combo x%d", state.rebirths, state.killStreak))

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

	-- The axe button is only useful when charged, so it says how many
	-- charges are banked and greys out when a swing would do nothing.
	local actions = gui:FindFirstChild("Actions")
	if actions then
		local chargeLabel = actions:FindFirstChild("AxeCharges")
		if chargeLabel and chargeLabel:IsA("TextLabel") then
			chargeLabel.Text = string.format("Axe: %d/%d", state.axe.charges, state.axe.maxCharges)
			chargeLabel.TextColor3 = state.axe.charges > 0 and Color3.fromRGB(140, 255, 170) or Color3.fromRGB(150, 158, 176)
		end
		local axeButton = actions:FindFirstChild("Axe")
		if axeButton and axeButton:IsA("TextButton") then
			axeButton.Active = state.axe.charges > 0
			axeButton.Text = state.axe.charges > 0 and string.format("AXE  x%d", state.axe.charges) or "AXE (empty)"
		end
		local cropButton = actions:FindFirstChild("Crop")
		local crop = state.crops[state.cropIndex]
		if cropButton and cropButton:IsA("TextButton") and crop then
			cropButton.Text = string.format("%s (%ds)", crop.id, crop.growSeconds)
		end
		-- A count of ripe crops, so the player knows a harvest is waiting.
		local ready = 0
		for _, plot in ipairs(state.plots) do
			if plot.ready then
				ready += 1
			end
		end
		local farmButton = actions:FindFirstChild("Farm")
		if farmButton and farmButton:IsA("TextButton") then
			farmButton.Text = ready > 0 and string.format("FARM (%d ready)", ready) or "FARM"
		end
	end

	local w = state.wave
	if w.phase == "TOWN" then
		setLabel(gui, "Wave", "Town - pick a field with MAP")
	elseif w.phase == "INTERMISSION" then
		setLabel(gui, "Wave", string.format("%s: wave %d in %ds", w.field or "Field", w.wave + 1, math.ceil(w.timeRemaining)))
	else
		setLabel(gui, "Wave", string.format("%s: wave %d - %d enemies", w.field or "Field", w.wave, w.aliveEnemies))
	end

	-- The boss bar is the only element that appears and disappears on its own.
	local bossPanel = gui:FindFirstChild("BossPanel")
	if bossPanel and bossPanel:IsA("Frame") then
		local boss = w.boss
		if boss then
			bossPanel.Visible = true
			setLabel(gui, "BossName", string.format("%s  %d/%d", boss.name, math.floor(boss.health), boss.maxHealth))
			local track = bossPanel:FindFirstChild("BossTrack")
			local fill = track and track:FindFirstChild("BossFill")
			if fill and fill:IsA("Frame") then
				fill.Size = UDim2.new(math.clamp(boss.fraction, 0, 1), 0, 1, 0)
			end
		else
			bossPanel.Visible = false
		end
	end

	-- Kill flash: brief, centred under the boss bar, gone on its own.
	local killLabel = gui:FindFirstChild("KillFlash")
	if killLabel and killLabel:IsA("TextLabel") then
		if state.lastKill and os.clock() - state.lastKillAt < 1.2 then
			killLabel.Visible = true
			local text = string.format("+%d  %s", state.lastKill.coins, state.lastKill.name)
			if state.lastKill.boss then
				text = "BOSS DOWN  " .. text
			end
			if state.killStreak > 1 then
				text = text .. string.format("   combo x%d", state.killStreak)
			end
			killLabel.Text = text
		else
			killLabel.Visible = false
		end
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
	state.field = payload.field
	state.fields = payload.fields or {}
	state.killStreak = payload.killStreak or 0
	state.pets = payload.pets
	state.maxEquipped = payload.maxEquipped
	state.coinMultiplier = payload.coinMultiplier
	state.dailyReady = payload.dailyReady == true
	state.dailyStreak = payload.dailyStreak or 0
	state.dailySecondsLeft = payload.dailySecondsLeft or 0
	state.crops = payload.crops or state.crops
	render()
end)

WaveState.OnClientEvent:Connect(function(snapshot)
	state.wave = snapshot
	render()
end)

-- Plot timers and axe charges arrive on their own channel, because they
-- change every second and would otherwise drag the whole stat panel along.
FarmState.OnClientEvent:Connect(function(payload)
	state.plots = payload.plots or {}
	state.axe = payload.axe or state.axe
	render()
end)

Notify.OnClientEvent:Connect(function(message)
	print("[AX Arena] " .. tostring(message))
end)

-- Kills arrive on their own channel: they are per-player and far too
-- frequent to ride along with the whole player state.
CombatFx.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then
		return
	end
	state.lastKill = payload
	state.lastKillAt = os.clock()
	render()
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

function Intent.travelZone(placeId: string): (boolean, string?)
	return invoke(TravelZone, placeId)
end

-- Travel to town or a field. The server validates the level lock and moves
-- the character; the client only asks.
function Intent.travelTo(placeId: string): (boolean, string?)
	return invoke(TravelZone, placeId)
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

function Intent.plantCrop(plotIndex: number, cropId: string): (boolean, string?)
	return invoke(PlantCrop, plotIndex, cropId)
end

function Intent.harvestCrop(plotIndex: number): (boolean, any, string?)
	return invoke(HarvestCrop, plotIndex)
end

function Intent.useAxe(): (boolean, any, string?)
	return invoke(UseAxe)
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
-- The player should never have to walk to a plot and tap it. One tap on
-- FARM does the obvious thing: harvest a ripe plot if there is one,
-- otherwise plant the selected crop in the nearest free plot.
local function onFarmTap()
	local ripe: number? = nil
	local free: number? = nil
	for _, plot in ipairs(state.plots) do
		if plot.ready and not ripe then
			ripe = plot.index
		end
		if not plot.cropId and not free then
			free = plot.index
		end
	end

	if ripe then
		Intent.harvestCrop(ripe)
		return
	end
	if free then
		local crop = state.crops[state.cropIndex]
		if crop then
			Intent.plantCrop(free, crop.id)
		end
	end
end

-- One button per place: town plus every field the player can see. The lock
-- state comes from the server snapshot, so the button never promises a trip
-- the server will refuse.
local function buildTravelList(travel: Frame)
	local list = travel:FindFirstChild("FieldList")
	if not list then
		return
	end
	list:ClearAllChildren()

	local places = { { id = "Town", name = "Town", unlocked = true, levelRequirement = 0 } }
	for _, field in ipairs(state.fields) do
		table.insert(places, field)
	end

	for index, place in ipairs(places) do
		local current = (state.field == place.id) or (not state.field and place.id == "Town")
		local label = place.name
		if not place.unlocked then
			label = string.format("%s (Lv %d)", place.name, place.levelRequirement or 1)
		end
		if current then
			label = label .. "  <- here"
		end
		local color = place.unlocked and (current and Hud.COLORS.disabled or Hud.COLORS.blue) or Hud.COLORS.disabled
		local row = Hud.button(list, "Place_" .. place.id, label, UDim2.new(1, 0, 0, 46), UDim2.new(0, 0, 0, (index - 1) * 52), color)
		row.ZIndex = 12
		row.TextSize = 18
		row.Active = place.unlocked and not current
		if row.Active then
			row.Activated:Connect(function()
				local ok, reason = Intent.travelTo(place.id)
				if ok then
					travel.Visible = false
				elseif reason then
					warn("[AX Arena] travel rejected: " .. tostring(reason))
				end
			end)
		end
	end
	list.CanvasSize = UDim2.new(0, 0, 0, #places * 52)
end

local function wireButtons()
	local gui = Hud.build()

	local rewards = gui:WaitForChild("Rewards")
	local daily = rewards:WaitForChild("Daily") :: TextButton
	local code = rewards:WaitForChild("Code") :: TextButton

	local actions = gui:WaitForChild("Actions")
	local axeButton = actions:WaitForChild("Axe") :: TextButton
	local farmButton = actions:WaitForChild("Farm") :: TextButton
	local cropButton = actions:WaitForChild("Crop") :: TextButton
	local mapButton = actions:WaitForChild("Map") :: TextButton

	local travel = gui:WaitForChild("TravelPanel") :: Frame
	local closeTravel = travel:WaitForChild("CloseTravel") :: TextButton

	mapButton.Activated:Connect(function()
		buildTravelList(travel)
		travel.Visible = not travel.Visible
	end)

	closeTravel.Activated:Connect(function()
		travel.Visible = false
	end)

	axeButton.Activated:Connect(function()
		Intent.useAxe()
	end)

	farmButton.Activated:Connect(onFarmTap)

	-- Cycling the crop is local: it only changes what FARM will plant next.
	cropButton.Activated:Connect(function()
		if #state.crops == 0 then
			return
		end
		state.cropIndex = state.cropIndex % #state.crops + 1
		render()
	end)

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
