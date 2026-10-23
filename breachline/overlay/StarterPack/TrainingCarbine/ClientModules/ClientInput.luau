--[[
	File: ClientInput.luau

	Input for a firearm, from keyboard, gamepad, and touch.

	The keyboard and gamepad path is unchanged: Keybinds owns the three
	actions the rig already understood. The touch path is where this differs
	from what shipped before. Rather than reveal the vehicle cluster's single
	FIRE face and hang a lone ADS toggle off the side, a shooter on foot now
	gets a full cluster from MobileControls, and every button on it maps to a
	verb this module owns.

	Two verbs are new to the rig: crouch, which the camera reads off a player
	attribute so nothing else has to be told about it, and swap, which equips
	the next tool in the backpack. Scope is reported separately from aim, so a
	weapon can distinguish a shoulder aim from a scoped one.
]]--

-- Root

local ClientInput = {}
ClientInput.__index = ClientInput

-- Roblox Services

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

-- Dependencies

local FourD = ReplicatedStorage:WaitForChild("FourD")
local Constants = require(FourD.Architects.Firearm2.Common.Constants)
local WeaponControls = require(FourD.Architects.Firearm2.Common.WeaponControls)
local Dumpster = require(FourD.Libs.Dumpster)
local Keybinds = require(FourD.Common.Keybinds)
local MobileControls = require(FourD.Common.MobileControls)
local TouchButtons = require(FourD.Common.TouchButtons)

-- Constants

local KEYBINDS_SET_ID = "Firearm2"

local CROUCH_ATTRIBUTE = Constants.CROUCH_ATTRIBUTE
local SCOPE_ATTRIBUTE = "AXScope"
local CROUCH_WALK_SPEED = Constants.CROUCH_WALK_SPEED
local INTERACT_RANGE = 12

-- Roblox's own touch controls. Its jump button shares the bottom-right
-- corner with our cluster, so it is hidden for as long as ours is up.
local JUMP_FRAME_NAME = "TouchControlFrame"
local JUMP_BUTTON_NAME = "JumpButton"

-- Local Functions

local function defaultJumpButton(): GuiObject?
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then return nil end

	for _, child in ipairs(playerGui:GetChildren()) do
		if child:IsA("ScreenGui") then
			local frame = child:FindFirstChild(JUMP_FRAME_NAME)
			local button = if frame then frame:FindFirstChild(JUMP_BUTTON_NAME) else nil
			if button and button:IsA("GuiObject") then
				return button
			end
		end
	end

	return nil
end

local function humanoid(): Humanoid?
	local character = player.Character
	if not character then return nil end
	return character:FindFirstChildOfClass("Humanoid")
end

---The Tool this module was shipped inside. ClientInput is a child of the tool's
---ClientModules folder, so the weapon's own attributes are one ancestor away.
---Walking rather than indexing `script.Parent.Parent` keeps it correct for both
---the starting copy and the shop copy, which are the same rig at two paths.
local function weaponTool(): Tool?
	local node = script.Parent
	while node do
		if node:IsA("Tool") then return node end
		node = node.Parent
	end
	return nil
end

---The params the cluster's availability is decided from, read off the Tool the
---same way the controller reads them.
local function weaponParams(): { [string]: any }
	local tool = weaponTool()
	if not tool then return {} end

	local params = {}
	for _, key in Constants.PARAM_KEYS do
		params[key] = tool:GetAttribute(key)
	end
	return params
end

-- Public Methods

function ClientInput:IsFireHeld(): boolean
	return self._fireHeld
end

function ClientInput:IsAimHeld(): boolean
	return self._aimHeld
end

function ClientInput:IsCrouching(): boolean
	return self._crouching
end

function ClientInput:_setFire(held: boolean)
	if self._fireHeld == held then return end
	self._fireHeld = held
	if held then
		self.FireBegan:Fire()
	else
		self.FireEnded:Fire()
	end
end

function ClientInput:_setAim(held: boolean)
	if self._aimHeld == held then return end
	self._aimHeld = held
	if held then
		self.AimBegan:Fire()
	else
		self.AimEnded:Fire()
	end
end

function ClientInput:_setCrouch(crouching: boolean)
	self._crouching = crouching
	player:SetAttribute(CROUCH_ATTRIBUTE, crouching and 1 or 0)

	local hum = humanoid()
	if hum then
		if crouching then
			self._standWalkSpeed = hum.WalkSpeed
			hum.WalkSpeed = CROUCH_WALK_SPEED
		else
			hum.WalkSpeed = self._standWalkSpeed or hum.WalkSpeed
		end
	end
end

---Equips the next tool in the backpack, wrapping at the end.
function ClientInput:_swap()
	local character = player.Character
	local hum = humanoid()
	if not character or not hum then return end

	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then return end

	local candidates = {}
	for _, item in ipairs(backpack:GetChildren()) do
		if item:IsA("Tool") then
			table.insert(candidates, item)
		end
	end
	for _, item in ipairs(character:GetChildren()) do
		if item:IsA("Tool") then
			table.insert(candidates, item)
		end
	end

	if #candidates < 2 then return end

	local current = character:FindFirstChildOfClass("Tool")
	local index = 1
	for i, item in ipairs(candidates) do
		if item == current then
			index = i % #candidates + 1
			break
		end
	end

	hum:EquipTool(candidates[index])
end

---Holds the nearest enabled proximity prompt, which is how this game plants,
---defuses, and picks things up.
function ClientInput:_interact()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then return end

	local origin = root.Position
	local best, bestDistance = nil, INTERACT_RANGE

	for _, descendant in ipairs(Workspace:GetDescendants()) do
		if descendant:IsA("ProximityPrompt") and descendant.Enabled then
			local parent = descendant.Parent
			if parent and parent:IsA("BasePart") then
				local distance = (parent.Position - origin).Magnitude
				if distance < bestDistance then
					best, bestDistance = descendant, distance
				end
			end
		end
	end

	if best then
		best:InputHoldBegin()
		task.delay(best.HoldDuration + 0.05, function()
			if best.Parent then
				best:InputHoldEnd()
			end
		end)
	end
end

function ClientInput:_enableTouch(dumpster: any)
	local controls = MobileControls.new()
	controls:Enable()
	dumpster:Add(controls)

	-- A weapon with iron sights has nothing for SCOPE to do, so its button is
	-- hidden rather than left on screen doing nothing when tapped.
	controls:SetAvailable(WeaponControls.available(weaponParams()))

	local function button(name: string): TextButton?
		return controls:GetButton(name)
	end

	-- bindHold returns its connections as a list; Dumpster only knows how to
	-- clean one connection at a time, so each is handed over on its own.
	local function hold(btn: GuiButton, onPress: () -> (), onRelease: () -> ())
		for _, connection in ipairs(TouchButtons.bindHold(btn, onPress, onRelease)) do
			dumpster:Add(connection)
		end
	end

	local fire = button("Fire")
	if fire then
		hold(fire, function()
			self:_setFire(true)
		end, function()
			self:_setFire(false)
		end)
	end

	local aim = button("Aim")
	if aim then
		dumpster:Add(TouchButtons.bindTap(aim, function()
			self:_setAim(not self._aimHeld)
			aim.BackgroundColor3 = if self._aimHeld
				then Color3.fromRGB(112, 138, 96)
				else Color3.fromRGB(58, 66, 58)
		end))
	end

	local scope = button("Scope")
	if scope then
		dumpster:Add(TouchButtons.bindTap(scope, function()
			self._scopeHeld = not self._scopeHeld
			player:SetAttribute(SCOPE_ATTRIBUTE, self._scopeHeld and 1 or 0)
			scope.BackgroundColor3 = if self._scopeHeld
				then Color3.fromRGB(112, 138, 96)
				else Color3.fromRGB(58, 66, 58)

			-- Scoping is aiming through a magnified optic, so it holds the aim
			-- on for as long as it is up.
			self:_setAim(self._scopeHeld)
			self.ScopeToggled:Fire(self._scopeHeld)
		end))
	end

	local reload = button("Reload")
	if reload then
		dumpster:Add(TouchButtons.bindTap(reload, function()
			self.ReloadTriggered:Fire()
		end))
	end

	local swap = button("Switch")
	if swap then
		dumpster:Add(TouchButtons.bindTap(swap, function()
			self:_swap()
		end))
	end

	local jump = button("Jump")
	if jump then
		dumpster:Add(TouchButtons.bindTap(jump, function()
			local hum = humanoid()
			if hum then hum.Jump = true end
		end))
	end

	local crouch = button("Crouch")
	if crouch then
		dumpster:Add(TouchButtons.bindTap(crouch, function()
			self:_setCrouch(not self._crouching)
			crouch.BackgroundColor3 = if self._crouching
				then Color3.fromRGB(112, 138, 96)
				else Color3.fromRGB(58, 66, 58)
		end))
	end

	local interact = button("Interact")
	if interact then
		dumpster:Add(TouchButtons.bindTap(interact, function()
			self:_interact()
		end))
	end

	-- Our cluster owns the corner, so Roblox's jump button steps aside while
	-- it is up and comes back when the tool is put away.
	local jumpButton = defaultJumpButton()
	if jumpButton then
		local wasVisible = jumpButton.Visible
		jumpButton.Visible = false
		dumpster:Add(function()
			if jumpButton.Parent then
				jumpButton.Visible = wasVisible
			end
		end)
	end

	-- The vehicle cluster's FIRE face is for a gunner in a seat; a shooter on
	-- foot must not leave a dead button on screen.
	local touchFire = require(FourD.Common.TouchFire).new({ ClearJumpButton = true })
	local connection = RunService.Heartbeat:Connect(function()
		touchFire:sync(false)
	end)
	dumpster:Add(function()
		connection:Disconnect()
		touchFire:destroy()
	end)
end

function ClientInput:Enable()
	if self._dumpster then return end

	local dumpster = Dumpster.new()
	self._dumpster = dumpster

	local handle = Keybinds.bindActions(KEYBINDS_SET_ID, {
		Fire = function(state)
			if state == Enum.UserInputState.Begin then
				self:_setFire(true)
			elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
				self:_setFire(false)
			end
			return nil
		end,
		Aim = function(state)
			if state == Enum.UserInputState.Begin then
				self:_setAim(true)
			elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
				self:_setAim(false)
			end
			return nil
		end,
		Reload = function(state)
			if state == Enum.UserInputState.Begin then
				self.ReloadTriggered:Fire()
			end
			return nil
		end,
	})
	dumpster:Add(function() handle:Destroy() end)

	if UserInputService.TouchEnabled then
		self:_enableTouch(dumpster)
	end
end

function ClientInput:Disable()
	if not self._dumpster then return end

	local dumpster = self._dumpster
	self._dumpster = nil
	dumpster:Destroy()

	self._fireHeld = false
	self._aimHeld = false
	self._scopeHeld = false
	self._crouching = false
	player:SetAttribute(CROUCH_ATTRIBUTE, 0)

	-- The camera reads the scope state off a player attribute, not off this
	-- module, so putting the tool away has to clear it here or the next weapon
	-- is drawn still zoomed. This is the one piece of state that outlives the
	-- tool and therefore cannot be left to the dumpster.
	player:SetAttribute(SCOPE_ATTRIBUTE, 0)
end

function ClientInput:Destroy()
	self:Disable()

	self.FireBegan:Destroy()
	self.FireEnded:Destroy()
	self.AimBegan:Destroy()
	self.AimEnded:Destroy()
	self.ReloadTriggered:Destroy()
	self.ScopeToggled:Destroy()

	for key in self do rawset(self, key, nil) end
	table.freeze(self)
end

-- Constructor

function ClientInput.new(): any
	local self = setmetatable({}, ClientInput)
	self._dumpster = nil
	self._fireHeld = false
	self._aimHeld = false
	self._scopeHeld = false
	self._crouching = false
	self._standWalkSpeed = nil
	self.FireBegan = Instance.new("BindableEvent")
	self.FireEnded = Instance.new("BindableEvent")
	self.AimBegan = Instance.new("BindableEvent")
	self.AimEnded = Instance.new("BindableEvent")
	self.ReloadTriggered = Instance.new("BindableEvent")
	self.ScopeToggled = Instance.new("BindableEvent")
	return self
end

ClientInput.CROUCH_ATTRIBUTE = CROUCH_ATTRIBUTE

-- Return

return ClientInput
