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
local Text = require(Shared.Text)
local Classes = require(Shared.Classes)
local Skills = require(Shared.Skills)
local Items = require(Shared.Items)

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
local AttackFx = Remotes:WaitForChild("AttackFx") :: RemoteEvent
local RaiseAttribute = Remotes:WaitForChild("RaiseAttribute") :: RemoteFunction
local LearnSkill = Remotes:WaitForChild("LearnSkill") :: RemoteFunction
local AdvanceJob = Remotes:WaitForChild("AdvanceJob") :: RemoteFunction
local CastSkill = Remotes:WaitForChild("CastSkill") :: RemoteFunction
local EquipItem = Remotes:WaitForChild("EquipItem") :: RemoteFunction
local UnequipItem = Remotes:WaitForChild("UnequipItem") :: RemoteFunction
local UseItem = Remotes:WaitForChild("UseItem") :: RemoteFunction
local PickUpDrop = Remotes:WaitForChild("PickUpDrop") :: RemoteFunction
local ManualAttack = Remotes:WaitForChild("ManualAttack") :: RemoteFunction
local SetAuto = Remotes:WaitForChild("SetAuto") :: RemoteFunction
local OpenPanel = Remotes:WaitForChild("OpenPanel") :: RemoteEvent

local Hud = require(script.Hud)
local HudLayout = Hud.Layout
local AttackAnim = require(script.AttackAnim)
local ItemView = require(script.ItemView)

local player = Players.LocalPlayer

local state = {
	coins = 0,
	upgrades = {},
	stats = { kills = 0, wavesCleared = 0, deaths = 0 },
	-- The active story objective, straight from the server. The tracker
	-- below draws it; it used to be read without ever being written, so the
	-- one panel that tells a new player what to do stayed empty forever.
	quest = nil,
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

	-- Character build, mirrored from the server. The client only displays
	-- these; it never derives them.
	attributes = {},
	attributeSheet = nil,
	attributePoints = 0,
	attributeNames = { "STR", "AGI", "VIT", "INT", "DEX", "LUK" },
	class = Config.Classes.StartingClass,
	className = "",
	classTagline = "",
	classDef = nil,
	jobLevel = 1,
	jobXp = 0,
	jobXpForNext = 1,
	skillPoints = 0,
	skills = {},
	hotbar = {},
	sp = 0,
	maxSp = 0,
	equipment = {},
	bag = {},
	bagCapacity = Config.Items.DefaultCapacity,
	autoAttack = Config.Combat.AutoAttack,
	autoPickup = true,
	buffs = {},
	-- Which character tab is open, and whether the panel is up at all.
	charTab = "Stats",
	charOpen = false,
	-- The shop tab shares the character panel; the villager opens it directly.
	shopOpen = false,
	-- The last RequestShop payload, so the shop tab renders without a
	-- network call on every frame.
	shop = nil,
	shopError = nil,
	-- Whether the rewards overlay (daily, code) is up.
	rewardsOpen = false,
	-- Which standing panels are folded down to a bar. Keyed by panel name,
	-- so a panel remembers whether the player put it away.
        --
	-- Actions starts folded. It is a menu of six buttons and 412 pixels tall,
	-- and with it open a phone held five panels at once and looked like a
	-- spreadsheet. The panels that stay open are the ones a player reads or
	-- presses while fighting: the wave banner, the quest tracker, the stats,
	-- and the attack buttons.
	folded = { Actions = true },
	-- True while the player stands in the first field, which cannot kill
	-- them. The server is the authority on this, not the client.
	fieldLethal = true,
}

-- Declared here, filled in below. render() and the tab builders connect button
-- handlers that call Intent.castSkill; those closures run on tap, but they are
-- compiled before the table exists, so without this forward declaration they
-- would capture the global Intent -- nil -- and every skill button would
-- throw "attempt to index nil with 'castSkill'" when pressed.
local Intent

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

-- Declared ahead of render so render can call them; both are defined further
-- down, next to the panels they draw.
local renderCombat, renderCharacter

local function render()
	local hud = player:FindFirstChild("PlayerGui")
	if not hud then
		return
	end
	local gui = hud:FindFirstChild("AXArenaHUD")
	if not gui then
		return
	end

	setLabel(gui, "Coins", Text.get("coins") .. ": " .. formatCoins(state.coins))
	local xpNext = state.xpForNext == math.huge and Text.get("max") or tostring(math.floor(state.xpForNext))
	setLabel(gui, "Level", string.format("%s %d  (%d/%s XP)", Text.get("level"), state.level,
		math.floor(state.xp), xpNext))
	setLabel(gui, "Health", string.format("%s %d/%d", Text.get("health"), math.floor(state.health),
		math.floor(state.maxHealth)))
	setLabel(gui, "Field", Text.get("field") .. ": " .. Text.placeName(state.field or "Town"))
	setLabel(gui, "Zone", string.format("%s: %s  (x%.1f)", Text.get("zone"), Text.placeName(state.zone),
		state.coinMultiplier))
	setLabel(gui, "Rebirth", string.format("%s %d  %s x%d", Text.get("rebirth"), state.rebirths,
		Text.get("combo"), state.killStreak))

	-- The quest tracker. The server sends a snapshot of the active objective, so
	-- the client only has to draw it. A finished story says so rather than showing
	-- a stale objective forever.
	local quest = state.quest
	if type(quest) == "table" then
		if quest.complete then
			setLabel(gui, "QuestTitle", Text.get("quest"))
			setLabel(gui, "QuestBody", Text.get("questAllDone"))
		else
			setLabel(gui, "QuestTitle", string.format("%d/%d  %s", quest.done or 0, quest.total or 0,
				Text.get(quest.titleKey)))
			-- The objective line carries its own progress, so the count is visible
			-- without a second label.
			local body = Text.get(quest.bodyKey)
			if (quest.count or 1) > 1 then
				body = Text.get("questProgress", body, quest.progress or 0, quest.count)
			end
			setLabel(gui, "QuestBody", body)
		end
	end

	-- The badge only shows in the first field, where a monster cannot land the
	-- last hit. Without it a player at 1 HP wonders why they are still alive.
	local safeBadge = gui:FindFirstChild("SafeBadge")
	if safeBadge and safeBadge:IsA("TextLabel") then
		-- Guarded on the fold: this runs before applyFolds, so without the
		-- check the badge would reappear on the collapsed stats bar.
		safeBadge.Visible = state.field ~= nil and not state.fieldLethal
			and not Hud.isFolded(state.folded, "Stats")
	end

	-- The skill bar. It is rebuilt from the server's hotbar every render, so
	-- what is on the bar is exactly what the server will let the player cast:
	-- the same list the character sheet shows, moved to where a thumb can
	-- reach it mid-fight. Rebuilding rather than diffing keeps it honest; the
	-- bar only changes when the hotbar does, which is a level-up, not a tick.
	local skillBar = gui:FindFirstChild("SkillBar")
	if skillBar and skillBar:IsA("Frame") then
		local row = skillBar:FindFirstChild("SkillRow")
		local hotbar = state.hotbar
		local signature = #hotbar
		for _, skill in ipairs(hotbar) do
			signature = signature .. ":" .. skill.id
		end
		if skillBar:GetAttribute("Signature") ~= signature then
			skillBar:SetAttribute("Signature", signature)
			if row then
				row:ClearAllChildren()
				local shown = math.min(#hotbar, HudLayout.SKILL_SLOTS)
				for i = 1, shown do
					local skill = hotbar[i]
					local cell = Hud.button(row, "Skill_" .. skill.id, Text.skillName(skill.id),
						UDim2.new(0, HudLayout.SKILL_BUTTON, 0, HudLayout.SKILL_BUTTON),
						UDim2.new(0, (i - 1) * (HudLayout.SKILL_BUTTON + HudLayout.SKILL_GAP), 0, 0),
						Hud.COLORS.gold)
					cell.TextSize = 12
					cell.Activated:Connect(function()
						local ok, reason = Intent.castSkill(skill.id)
						if not ok and reason and reason ~= "COOLDOWN" and reason ~= "NO_SP" then
							warn("[AX Arena] cast rejected: " .. tostring(reason))
						end
					end)
				end
			end
		end
		-- The bar is only as wide as the skills it holds, and it only exists when
		-- there is something to cast. An empty bar is a row of nothing over the
		-- attack button.
		local slots = math.max(1, math.min(#hotbar, HudLayout.SKILL_SLOTS))
		skillBar.Size = UDim2.new(0, HudLayout.skillBarWidth(slots), 0, HudLayout.skillBarHeight())
		skillBar.Visible = #hotbar > 0 and not state.charOpen
	end

	-- Folding is applied last, because it walks each panel's children and hides
	-- them; anything set visible above would be undone if this ran first.
	Hud.applyFolds(state.folded)

	-- The daily button says what will happen before the tap, so a tap is
	-- never a surprise and a disabled button is obviously disabled.
	local rewardsFolder = gui:FindFirstChild("Rewards")
	if rewardsFolder and rewardsFolder:IsA("Frame") then
		-- The overlay is shown from state, so opening the character sheet or
		-- travelling cannot leave it stuck on screen.
		rewardsFolder.Visible = state.rewardsOpen and not state.charOpen
	end
	local daily = rewardsFolder and rewardsFolder:FindFirstChild("Daily")
	if daily and daily:IsA("TextButton") then
		if state.dailyReady then
			daily.Text = Text.get("dailyClaim", state.dailyStreak + 1)
			daily.BackgroundColor3 = Color3.fromRGB(255, 206, 84)
			daily.Active = true
		else
			local hours = math.floor(state.dailySecondsLeft / 3600)
			local minutes = math.floor((state.dailySecondsLeft % 3600) / 60)
			daily.Text = Text.get("dailyWait", hours, minutes)
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
			chargeLabel.Text = string.format("%s: %d/%d", Text.get("axe"), state.axe.charges,
				state.axe.maxCharges)
			chargeLabel.TextColor3 = state.axe.charges > 0 and Color3.fromRGB(140, 255, 170) or Color3.fromRGB(150, 158, 176)
		end
		local axeButton = actions:FindFirstChild("Axe")
		if axeButton and axeButton:IsA("TextButton") then
			axeButton.Active = state.axe.charges > 0
			axeButton.Text = state.axe.charges > 0
				and string.format("%s  x%d", Text.get("axe"), state.axe.charges)
				or Text.get("axeEmpty")
		end
		local cropButton = actions:FindFirstChild("Crop")
		local crop = state.crops[state.cropIndex]
		if cropButton and cropButton:IsA("TextButton") and crop then
			cropButton.Text = string.format("%s (%ds)", Text.cropName(crop.id), crop.growSeconds)
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
			farmButton.Text = ready > 0 and Text.get("farmReady", ready) or Text.get("farm")
		end
	end

	local w = state.wave
	if w.phase == "TOWN" then
		setLabel(gui, "Wave", Text.get("townPickField"))
	elseif w.phase == "INTERMISSION" then
		setLabel(gui, "Wave", Text.get("waveNext", Text.placeName(w.field), w.wave + 1,
			math.ceil(w.timeRemaining)))
	else
		setLabel(gui, "Wave", Text.get("waveFighting", Text.placeName(w.field), w.wave, w.aliveEnemies))
	end

	-- The boss bar is the only element that appears and disappears on its own.
	local bossPanel = gui:FindFirstChild("BossPanel")
	if bossPanel and bossPanel:IsA("Frame") then
		local boss = w.boss
		if boss then
			bossPanel.Visible = true
			setLabel(gui, "BossName", string.format("%s  %d/%d", Text.enemyName(boss.name),
				math.floor(boss.health), boss.maxHealth))
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
			local text = string.format("+%d  %s", state.lastKill.coins,
				Text.enemyName(state.lastKill.name))
			if state.lastKill.boss then
				text = Text.get("bossDown") .. "  " .. text
			end
			if state.killStreak > 1 then
				text = text .. string.format("   %s x%d", Text.get("combo"), state.killStreak)
			end
			killLabel.Text = text
		else
			killLabel.Visible = false
		end
	end

	renderCombat(gui)
	renderCharacter(gui)
end

-- The combat panel: attack button, the two auto toggles, and the manual pickup.
-- Auto state is shown by colour and by the word, so it reads at a glance.
function renderCombat(gui: Instance)
	local combat = gui:FindFirstChild("Combat")
	if not combat then
		return
	end

	local attack = combat:FindFirstChild("Attack")
	if attack and attack:IsA("TextButton") then
		attack.Text = Text.get("attackButton")
		-- In town there is nothing to hit, so the button reads as unusable
		-- rather than silently doing nothing.
		attack.Active = state.field ~= nil
		attack.BackgroundColor3 = state.field and Hud.COLORS.gold or Hud.COLORS.disabled
	end

	local autoAttack = combat:FindFirstChild("AutoAttack")
	if autoAttack and autoAttack:IsA("TextButton") then
		autoAttack.Text = state.autoAttack and Text.get("autoAttackOn") or Text.get("autoAttackOff")
		autoAttack.BackgroundColor3 = state.autoAttack and Hud.COLORS.green or Hud.COLORS.disabled
	end

	local autoPickup = combat:FindFirstChild("AutoPickup")
	if autoPickup and autoPickup:IsA("TextButton") then
		autoPickup.Text = state.autoPickup and Text.get("autoPickupOn") or Text.get("autoPickupOff")
		autoPickup.BackgroundColor3 = state.autoPickup and Hud.COLORS.green or Hud.COLORS.disabled
	end
end

-- One row of the character list. Rows are rebuilt per tab, because each tab
-- shows a different kind of thing and a shared row factory would be a bigger
-- abstraction than the screen needs.
local function charRow(list: Instance, name: string, index: number, height: number)
	local row = Hud.button(list, name, "", UDim2.new(1, -8, 0, height), UDim2.new(0, 4, 0, (index - 1) * (height + 6)), Hud.COLORS.disabled)
	row.ZIndex = 22
	row.TextSize = 15
	row.TextXAlignment = Enum.TextXAlignment.Left
	row.AutoButtonColor = false
	return row
end

-- Stats tab: the six attributes, with a +1 and a +10 button when points remain,
-- then the derived numbers so the effect of a point is visible immediately.
local function renderStatsTab(list: Instance)
	list:ClearAllChildren()
	local row = 0
	local sheet = state.attributeSheet or {}

	local header = charRow(list, "Header", row + 1, 30)
	header.Text = Text.get("pointsLeft", state.attributePoints)
	header.TextColor3 = state.attributePoints > 0 and Hud.COLORS.gold or Hud.COLORS.muted
	row += 1

	for _, stat in ipairs(state.attributeNames) do
		local value = state.attributes[stat] or 1
		local line = charRow(list, "Attr_" .. stat, row + 1, 34)
		line.Text = string.format("%s   %d", Text.statName(stat), value)
		line.TextColor3 = Hud.COLORS.text
		row += 1

		if state.attributePoints > 0 then
			local plusOne = Hud.button(list, "Plus1_" .. stat, Text.get("addPoint"), UDim2.new(0, 46, 0, 30),
				UDim2.new(1, -108, 0, row * 40 + 2), Hud.COLORS.green)
			plusOne.ZIndex = 23
			plusOne.Activated:Connect(function()
				Intent.raiseAttribute(stat, 1)
			end)

			local plusTen = Hud.button(list, "Plus10_" .. stat, Text.get("addTen"), UDim2.new(0, 46, 0, 30),
				UDim2.new(1, -56, 0, row * 40 + 2), Hud.COLORS.blue)
			plusTen.ZIndex = 23
			plusTen.Activated:Connect(function()
				Intent.raiseAttribute(stat, 10)
			end)
		end
	end

	local derived = {
		{ Text.get("attack"), sheet.attack },
		{ Text.get("magicAttack"), sheet.magicAttack },
		{ Text.get("defense"), sheet.defense },
		{ Text.get("magicDefense"), sheet.magicDefense },
		{ Text.get("hit"), sheet.hit },
		{ Text.get("flee"), sheet.flee },
		{ Text.get("maxHealth"), sheet.maxHealth },
		{ Text.get("maxSp"), sheet.maxSp },
	}
	for _, entry in ipairs(derived) do
		local line = charRow(list, "Derived_" .. tostring(entry[1]), row + 1, 28)
		line.Text = string.format("%s: %d", entry[1], math.floor(entry[2] or 0))
		line.TextColor3 = Hud.COLORS.muted
		row += 1
	end

	list.CanvasSize = UDim2.new(0, 0, 0, row * 40 + 20)
end

-- Skills tab: everything the class can learn, with a LEARN button, then cast
-- buttons for what is already learned.
local function renderSkillsTab(list: Instance)
	list:ClearAllChildren()
	local row = 0
	local header = charRow(list, "Header", row + 1, 30)
	header.Text = Text.get("skillPoints", state.skillPoints)
	header.TextColor3 = state.skillPoints > 0 and Hud.COLORS.gold or Hud.COLORS.muted
	row += 1

	for _, def in ipairs(Skills.forClass(state.class)) do
		local level = math.floor(state.skills[def.id] or 0)
		local line = charRow(list, "Skill_" .. def.id, row + 1, 44)
		line.Text = string.format("%s  %d/%d", Text.skillName(def.id), level, def.maxLevel)
		line.TextColor3 = level > 0 and Hud.COLORS.green or Hud.COLORS.muted
		row += 1

		if level < def.maxLevel and state.skillPoints > 0 then
			local learn = Hud.button(list, "Learn_" .. def.id, Text.get("learn"), UDim2.new(0, 74, 0, 34),
				UDim2.new(1, -86, 0, row * 50 - 42), Hud.COLORS.blue)
			learn.ZIndex = 23
			learn.Activated:Connect(function()
				Intent.learnSkill(def.id)
			end)
		end
	end

	local hotbar = state.hotbar
	if #hotbar > 0 then
		local castHeader = charRow(list, "CastHeader", row + 1, 30)
		castHeader.Text = Text.get("cast")
		castHeader.TextColor3 = Hud.COLORS.muted
		row += 1

		for _, skill in ipairs(hotbar) do
			local cast = Hud.button(list, "Cast_" .. skill.id,
				string.format("%s  (%d)", Text.skillName(skill.id), skill.spCost),
				UDim2.new(1, -8, 0, 40), UDim2.new(0, 4, 0, row * 50), Hud.COLORS.gold)
			cast.ZIndex = 23
			cast.TextSize = 15
			cast.Activated:Connect(function()
				Intent.castSkill(skill.id)
			end)
			row += 1
		end
	end

	list.CanvasSize = UDim2.new(0, 0, 0, row * 50 + 20)
end

-- Job tab: the current class, its job level and XP, then every class it can
-- advance into with the requirement spelled out.
local function renderJobTab(list: Instance)
	list:ClearAllChildren()
	local row = 0

	local current = charRow(list, "Current", row + 1, 34)
	current.Text = string.format("%s  (%s %d)", state.className, Text.get("jobLevel"), state.jobLevel)
	current.TextColor3 = Hud.COLORS.gold
	row += 1

	local xpLine = charRow(list, "JobXp", row + 1, 30)
	local xpNext = state.jobXpForNext == math.huge and Text.get("max") or tostring(math.floor(state.jobXpForNext))
	xpLine.Text = string.format("%s: %d/%s", Text.get("jobXp"), math.floor(state.jobXp), xpNext)
	xpLine.TextColor3 = Hud.COLORS.muted
	row += 1

	if state.classTagline and #state.classTagline > 0 then
		local tagline = charRow(list, "Tagline", row + 1, 28)
		tagline.Text = state.classTagline
		tagline.TextColor3 = Hud.COLORS.muted
		row += 1
	end

	-- The class tree comes from the shared module, so the panel can never offer
	-- an advancement the server would refuse.
	local header = charRow(list, "Branches", row + 1, 30)
	header.Text = Text.get("branchOf")
	header.TextColor3 = Hud.COLORS.muted
	row += 1

	for _, def in ipairs(Classes.list()) do
		if def.id ~= state.class then
			local line = charRow(list, "Class_" .. def.id, row + 1, 48)
			line.Text = string.format("%s  -  %s", Text.className(def.id), Text.classTagline(def.id))
			line.TextColor3 = Hud.COLORS.text
			row += 1

			local ok, reason = Classes.canAdvance(state.class, def.id, state.level, state.jobLevel)
			local advance = Hud.button(list, "Advance_" .. def.id, Text.get("jobAdvance"), UDim2.new(0, 84, 0, 34),
				UDim2.new(1, -96, 0, row * 54 - 44), ok and Hud.COLORS.green or Hud.COLORS.disabled)
			advance.ZIndex = 23
			advance.TextSize = 15
			advance.Active = ok
			if not ok then
				advance.Text = reason == "LEVEL_TOO_LOW"
					and string.format(Text.get("jobRequirements"), def.levelRequirement or 1, def.jobLevelRequirement or 1)
					or Text.get("maxSkill")
			else
				advance.Activated:Connect(function()
					Intent.advanceJob(def.id)
				end)
			end
		end
	end

	list.CanvasSize = UDim2.new(0, 0, 0, row * 54 + 20)
end

-- Shop tab: the Robux catalogue, straight from the server. Prices come from
-- Monetization.list() and a product with no assetId is refused by the server,
-- so this only renders what can actually be bought. Tapping one hands the
-- purchase to Roblox; the server grants it on the receipt.
local function renderShopTab(list: Instance)
	list:ClearAllChildren()
	local shop = state.shop
	local row = 0

	local header = charRow(list, "ShopHeader", row + 1, 30)
	header.Text = Text.get("shop")
	header.TextColor3 = Hud.COLORS.gold
	row += 1

	if not shop then
		local loading = charRow(list, "ShopLoading", row + 1, 30)
		loading.Text = Text.get("shopLoading")
		loading.TextColor3 = Hud.COLORS.muted
		list.CanvasSize = UDim2.new(0, 0, 0, 60)
		return
	end

	if state.shopError then
		local reason = state.shopError
		local label = reason == "NOT_CONFIGURED" and Text.get("notConfigured")
			or reason == "SHOP_UNAVAILABLE" and Text.get("shopUnavailable")
			or tostring(reason)
		local banner = charRow(list, "ShopError", row + 1, 30)
		banner.Text = Text.get("shopFailed", label)
		banner.TextColor3 = Hud.COLORS.red
		row += 1
	end

	local products = shop.products or {}
	if #products == 0 then
		local empty = charRow(list, "ShopEmpty", row + 1, 30)
		empty.Text = Text.get("shopEmpty")
		empty.TextColor3 = Hud.COLORS.muted
		list.CanvasSize = UDim2.new(0, 0, 0, 60)
		return
	end

	for _, product in ipairs(products) do
		local owned = shop.owned and shop.owned[product.id] == true
		local line = charRow(list, "Product_" .. product.id, row + 1, 52)
		line.Text = string.format("%s  -  %d R$\n%s", product.name, product.robux, product.description)
		line.TextColor3 = Hud.COLORS.text
		row += 1

		local label = owned and Text.get("owned") or Text.get("buy")
		local buy = Hud.button(list, "Buy_" .. product.id, label, UDim2.new(0, 96, 0, 40),
			UDim2.new(1, -108, 0, row * 58 - 52), owned and Hud.COLORS.disabled or Hud.COLORS.green)
		buy.ZIndex = 23
		buy.TextSize = 16
		buy.Active = not owned
		if not owned then
			buy.Activated:Connect(function()
				local ok, reason = Intent.buyProduct(product.id)
				if not ok then
					state.shopError = reason
					render()
				end
			end)
		end
	end

	list.CanvasSize = UDim2.new(0, 0, 0, row * 58 + 20)
end

-- Bag tab: worn gear as icon tiles, then the bag as a grid of icon tiles. A
-- tile shows the object itself, and a tap does the one thing that item can do
-- -- equip a weapon, use a potion -- so the grid needs no per-row buttons and a
-- phone gets its screen back.
--
-- Both boards wrap at four columns: there are eight equipment slots and the
-- character panel is 340px wide, so a single row of tiles would run off the
-- edge of the screen.
local TILE = 68
local GAP = 8
local COLUMNS = 4
local CELL_HEIGHT = TILE + 16 + GAP

local function gridPosition(index: number): UDim2
        local column = (index - 1) % COLUMNS
        local rowIndex = math.floor((index - 1) / COLUMNS)
        return UDim2.new(0, 6 + column * (TILE + GAP), 0, 6 + rowIndex * CELL_HEIGHT)
end

local function gridHeight(count: number): number
        local rows = math.max(1, math.ceil(count / COLUMNS))
        return rows * CELL_HEIGHT + 12
end

-- One labelled board of icon tiles. `entries` is a list of { itemId, count },
-- with itemId nil for an empty slot.
local function renderGrid(list: Instance, name: string, top: number, entries: { any }, onTap: (any) -> ())
        local board = Instance.new("Frame")
        board.Name = name
        board.Size = UDim2.new(1, -8, 0, gridHeight(#entries))
        board.Position = UDim2.new(0, 4, 0, top)
        board.BackgroundTransparency = 1
        board.ZIndex = 22
        board.Parent = list

        for index, entry in ipairs(entries) do
                if entry.itemId then
                        local def = Items.getDef(entry.itemId)
                        local cell = ItemView.cell(board, name .. "_" .. tostring(index), gridPosition(index), TILE,
                                entry.itemId, def, entry.caption)
                        ItemView.badge(cell, entry.count)
                        cell.Activated:Connect(function()
                                onTap(entry)
                        end)
                else
                        ItemView.emptyTile(board, name .. "_" .. tostring(index), gridPosition(index), TILE)
                        local caption = Instance.new("TextLabel")
                        caption.Name = "Caption"
                        caption.Size = UDim2.new(0, TILE, 0, 14)
                        caption.Position = UDim2.new(gridPosition(index).X, 0, gridPosition(index).Y, TILE + 2)
                        caption.BackgroundTransparency = 1
                        caption.Font = Enum.Font.GothamBold
                        caption.TextSize = 12
                        caption.TextColor3 = Hud.COLORS.muted
                        caption.Text = entry.caption
                        caption.ZIndex = 23
                        caption.Parent = board
                end
        end

        return gridHeight(#entries)
end

local function renderBagTab(list: Instance)
        list:ClearAllChildren()

        -- Worn gear first, so the player sees what is on before what is carried.
        local equipHeader = charRow(list, "EquipHeader", 1, 26)
        equipHeader.Text = Text.get("equipment")
        equipHeader.TextColor3 = Hud.COLORS.muted

        local worn = {}
        for _, slot in ipairs(Items.slots()) do
                table.insert(worn, {
                        itemId = state.equipment[slot],
                        slot = slot,
                        caption = Text.slotName(slot),
                })
        end
        local equipHeight = renderGrid(list, "EquipBoard", 32, worn, function(entry)
                Intent.unequipItem(entry.slot)
        end)

        local bagTop = 32 + equipHeight + 12

        local bagHeader = charRow(list, "BagHeader", 2, 26)
        bagHeader.Text = string.format("%s  %d/%d", Text.get("inventory"), #state.bag, state.bagCapacity)
        bagHeader.TextColor3 = Hud.COLORS.muted
        bagHeader.Position = UDim2.new(0, 4, 0, bagTop)

        if #state.bag == 0 then
                local empty = charRow(list, "EmptyBag", 3, 26)
                empty.Text = Text.get("empty")
                empty.TextColor3 = Hud.COLORS.muted
                empty.Position = UDim2.new(0, 4, 0, bagTop + 30)
                list.CanvasSize = UDim2.new(0, 0, 0, bagTop + 70)
                return
        end

        local carried = {}
        for _, slot in ipairs(state.bag) do
                table.insert(carried, {
                        itemId = slot.itemId,
                        count = slot.count,
                        caption = Text.itemName(slot.itemId),
                })
        end
        local bagHeight = renderGrid(list, "BagBoard", bagTop + 30, carried, function(entry)
                local def = Items.getDef(entry.itemId)
                if def and def.kind == "equipment" then
                        Intent.equipItem(entry.itemId)
                elseif def and def.kind == "consumable" then
                        Intent.useItem(entry.itemId)
                end
        end)

        list.CanvasSize = UDim2.new(0, 0, 0, bagTop + 40 + bagHeight)
end

-- The character panel. Tabs are rebuilt on open and after every state change,
-- so a row's buttons always match the state they were built from.
function renderCharacter(gui: Instance)
	local panel = gui:FindFirstChild("CharPanel")
	if not panel or not panel:IsA("Frame") then
		return
	end
	panel.Visible = state.charOpen
	if not state.charOpen then
		return
	end

	local list = panel:FindFirstChild("CharList")
	if not list or not list:IsA("ScrollingFrame") then
		return
	end

	local tabs = panel:FindFirstChild("Tabs")
	if tabs then
		for _, id in ipairs({ "Stats", "Skills", "Job", "Bag", "Shop" }) do
			local tab = tabs:FindFirstChild("Tab_" .. id)
			if tab and tab:IsA("TextButton") then
				tab.BackgroundColor3 = (state.charTab == id) and Hud.COLORS.gold or Hud.COLORS.disabled
			end
		end
	end

	local title = panel:FindFirstChild("CharTitle")
	if title and title:IsA("TextLabel") then
		title.Text = string.format("%s  -  %s  (%s %d)", Text.get("character"), state.className,
			Text.get("jobLevel"), state.jobLevel)
	end

	if state.charTab == "Stats" then
		renderStatsTab(list)
	elseif state.charTab == "Skills" then
		renderSkillsTab(list)
	elseif state.charTab == "Job" then
		renderJobTab(list)
	elseif state.charTab == "Shop" then
		renderShopTab(list)
	else
		renderBagTab(list)
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
	state.fieldLethal = payload.fieldLethal ~= false
	state.fields = payload.fields or {}
	state.killStreak = payload.killStreak or 0
	state.pets = payload.pets
	state.maxEquipped = payload.maxEquipped
	state.coinMultiplier = payload.coinMultiplier
	state.dailyReady = payload.dailyReady == true
	state.dailyStreak = payload.dailyStreak or 0
	state.dailySecondsLeft = payload.dailySecondsLeft or 0
	state.crops = payload.crops or state.crops

	-- Character sheet.
	state.attributes = payload.attributes or state.attributes
	state.attributeSheet = payload.attributeSheet or state.attributeSheet
	state.attributePoints = payload.attributePoints or 0
	state.attributeNames = payload.attributeNames or state.attributeNames
	state.class = payload.class or state.class
	state.className = payload.className or Text.className(state.class)
	state.classTagline = payload.classTagline or ""
	state.classDef = payload.classDef or Classes.getDef(state.class)
	state.jobLevel = payload.jobLevel or 1
	state.jobXp = payload.jobXp or 0
	state.jobXpForNext = payload.jobXpForNext or 1
	state.skillPoints = payload.skillPoints or 0
	state.skills = payload.skills or {}
	state.hotbar = payload.hotbar or {}
	state.sp = payload.sp or 0
	state.maxSp = payload.maxSp or 0
	state.equipment = payload.equipment or {}
	state.bag = payload.bag or {}
	state.bagCapacity = payload.bagCapacity or state.bagCapacity
	state.autoAttack = payload.autoAttack == true
	state.autoPickup = payload.autoPickup ~= false
	state.buffs = payload.buffs or {}
	state.quest = payload.quest or state.quest

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

-- Every swing is broadcast, so a monster taking damage is visible to the
-- whole field rather than only to the player who tapped.
AttackFx.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" or payload.kind ~= "attack" then
		return
	end
	AttackAnim.playForUserId(payload.userId, payload.style)
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

Intent = {}

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

-- The attack button. One tap, one swing; the server decides whether it lands.
-- The swing itself is drawn from the server broadcast, so a manual tap and
-- an auto-attack animate through exactly the same path.
function Intent.attack(): (boolean, string?)
	return invoke(ManualAttack)
end

function Intent.setAuto(mode: string, value: boolean): (boolean, string?)
	return invoke(SetAuto, mode, value)
end

function Intent.raiseAttribute(stat: string, times: number): (boolean, any, string?)
	return invoke(RaiseAttribute, stat, times)
end

function Intent.learnSkill(skillId: string): (boolean, any, string?)
	return invoke(LearnSkill, skillId)
end

function Intent.advanceJob(target: string): (boolean, string?)
	return invoke(AdvanceJob, target)
end

function Intent.castSkill(skillId: string): (boolean, any, string?)
	return invoke(CastSkill, skillId)
end

function Intent.equipItem(itemId: string): (boolean, string?)
	return invoke(EquipItem, itemId)
end

function Intent.unequipItem(slot: string): (boolean, string?)
	return invoke(UnequipItem, slot)
end

function Intent.useItem(itemId: string): (boolean, any, string?)
	return invoke(UseItem, itemId)
end

function Intent.pickUp(dropId: number?): (boolean, any, string?)
	return invoke(PickUpDrop, dropId, false)
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
	box.Size = UDim2.new(0, 300, 0, 190)
	box.Position = UDim2.new(0.5, 0, 0.5, 0)
	box.AnchorPoint = Vector2.new(0.5, 0.5)
	box.BackgroundColor3 = Color3.fromRGB(18, 20, 28)
	box.BorderSizePixel = 0
	box.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 14)
	corner.Parent = box

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -24, 0, 34)
	title.Position = UDim2.new(0, 12, 0, 8)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextSize = 18
	title.TextColor3 = Color3.fromRGB(236, 240, 248)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = Text.get("enterCode")
	title.Parent = box

	local entry = Instance.new("TextBox")
	entry.Name = "Entry"
	entry.Size = UDim2.new(1, -24, 0, 46)
	entry.Position = UDim2.new(0, 12, 0, 46)
	entry.BackgroundColor3 = Color3.fromRGB(32, 36, 48)
	entry.BorderSizePixel = 0
	entry.Font = Enum.Font.GothamBold
	entry.TextSize = 22
	entry.TextColor3 = Color3.fromRGB(255, 255, 255)
	entry.PlaceholderText = Text.get("codePlaceholder")
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
	submit.Text = Text.get("redeem")
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
	cancel.Text = Text.get("cancel")
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

	local places = { { id = "Town", unlocked = true, levelRequirement = 0 } }
	for _, field in ipairs(state.fields) do
		table.insert(places, field)
	end

	for index, place in ipairs(places) do
		local current = (state.field == place.id) or (not state.field and place.id == "Town")
		local label = Text.placeName(place.id)
		if not place.unlocked then
			label = string.format("%s (%s %d)", label, Text.get("level"), place.levelRequirement or 1)
		end
		if current then
			label = label .. "  " .. Text.get("here")
		end
		local color = place.unlocked and (current and Hud.COLORS.disabled or Hud.COLORS.blue) or Hud.COLORS.disabled
		local row = Hud.button(list, "Place_" .. place.id, label, UDim2.new(1, 0, 0, 56), UDim2.new(0, 0, 0, (index - 1) * 62), color)
		row.ZIndex = 12
		row.TextSize = 16
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
	list.CanvasSize = UDim2.new(0, 0, 0, #places * 62)
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

	-- The combat panel and the character sheet.
	local combatPanel = gui:WaitForChild("Combat")
	local attackButton = combatPanel:WaitForChild("Attack") :: TextButton
	local autoAttackButton = combatPanel:WaitForChild("AutoAttack") :: TextButton
	local autoPickupButton = combatPanel:WaitForChild("AutoPickup") :: TextButton
	local pickupButton = combatPanel:WaitForChild("Pickup") :: TextButton

	-- Every panel with a fold caret: a tap puts it away or brings it back.
	-- The caret is a child of the panel, so this must be wired before any
	-- handler that reads the panel's contents.
	for _, panelName in ipairs({ "Stats", "WavePanel", "Actions", "Combat" }) do
		local panelFrame = gui:FindFirstChild(panelName)
		local caret = panelFrame and panelFrame:FindFirstChild("Fold")
		if caret and caret:IsA("TextButton") then
			local name = panelName
			caret.Activated:Connect(function()
				state.folded[name] = not state.folded[name]
				render()
			end)
		end
	end

	local charPanel = gui:WaitForChild("CharPanel") :: Frame
	local charClose = charPanel:WaitForChild("CloseChar") :: TextButton
	local charButton = actions:WaitForChild("Character") :: TextButton
	local tabs = charPanel:WaitForChild("Tabs")

	-- Every panel opens through one named function, so a villager prompt and
	-- a HUD button cannot end up showing different things.
	local function openTravel()
		buildTravelList(travel)
		state.rewardsOpen = false
		state.charOpen = false
		travel.Visible = true
		render()
	end

	local function openRewards()
		travel.Visible = false
		state.charOpen = false
		state.rewardsOpen = true
		render()
	end

	local function openCharacter()
		travel.Visible = false
		state.rewardsOpen = false
		state.charOpen = true
		render()
	end

	-- The catalogue changes rarely but the owned flags change on a purchase,
	-- so the shop is refreshed when its surface opens rather than kept live.
	local function refreshShop()
		state.shop = Intent.fetchShop()
		state.shopError = nil
	end

	local function openShop()
		travel.Visible = false
		state.rewardsOpen = false
		state.charTab = "Shop"
		state.charOpen = true
		refreshShop()
		render()
	end

	mapButton.Activated:Connect(openTravel)

	closeTravel.Activated:Connect(function()
		travel.Visible = false
	end)

	-- Rewards: open from the action panel, close from the overlay itself.
	local rewardsButton = actions:WaitForChild("RewardsButton") :: TextButton
	local rewardsPanel = gui:WaitForChild("Rewards") :: Frame
	local closeRewards = rewardsPanel:WaitForChild("CloseRewards") :: TextButton
	rewardsButton.Activated:Connect(function()
		if state.rewardsOpen then
			state.rewardsOpen = false
			render()
		else
			openRewards()
		end
	end)
	closeRewards.Activated:Connect(function()
		state.rewardsOpen = false
		render()
	end)

	axeButton.Activated:Connect(function()
		Intent.useAxe()
	end)

	-- Attack: one tap, one swing. The server decides if it lands.
	attackButton.Activated:Connect(function()
		local ok, reason = Intent.attack()
		if not ok and reason and reason ~= "COOLDOWN" and reason ~= "NO_TARGET" then
			warn("[AX Arena] attack rejected: " .. tostring(reason))
		end
	end)

	-- The auto toggles flip a server flag, so the button reflects real state.
	autoAttackButton.Activated:Connect(function()
		Intent.setAuto("attack", not state.autoAttack)
	end)

	autoPickupButton.Activated:Connect(function()
		Intent.setAuto("pickup", not state.autoPickup)
	end)

	-- Manual pickup: collects everything in range right now, whatever the auto
	-- setting says.
	pickupButton.Activated:Connect(function()
		local ok, taken, reason = invoke(PickUpDrop, nil, true)
		if not ok and reason and reason ~= "NOTHING_IN_RANGE" then
			warn("[AX Arena] pickup rejected: " .. tostring(reason))
		end
		if ok and type(taken) == "table" then
			for _, entry in ipairs(taken) do
				print(string.format("[AX Arena] %s x%d", Text.itemName(entry.itemId), entry.count))
			end
		end
	end)

	-- The character sheet: open, close, and switch tabs.
	charButton.Activated:Connect(function()
		if state.charOpen then
			state.charOpen = false
			render()
		else
			openCharacter()
		end
	end)

	charClose.Activated:Connect(function()
		state.charOpen = false
		render()
	end)

	for _, id in ipairs({ "Stats", "Skills", "Job", "Bag", "Shop" }) do
		local tab = tabs:FindFirstChild("Tab_" .. id)
		if tab and tab:IsA("TextButton") then
			tab.Activated:Connect(function()
				state.charTab = id
				if id == "Shop" then
					refreshShop()
				end
				render()
			end)
		end
	end

	-- A villager in town was used. The server already checked that the player
	-- is in town and that the villager exists; this only opens the panel the
	-- server named, through the same opener the matching button uses.
	OpenPanel.OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" then
			return
		end
		local panel = payload.panel
		if panel == "travel" then
			openTravel()
		elseif panel == "rewards" then
			openRewards()
		elseif panel == "character" then
			openCharacter()
		elseif panel == "shop" then
			openShop()
		elseif panel == "quests" then
			-- Quests are the tracker in the corner; a tap brings it back if
			-- the player folded it away.
			state.folded.QuestPanel = false
			render()
		end
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
