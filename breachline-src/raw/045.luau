--[[
	File: ReplicatedStorage/FourD/Common/TouchFire.luau

	GENERATED -- not part of upstream FourD.

	The Fire control for a gunner on a touchscreen.

	Every FourD vehicle that draws a touch cluster ships a hidden
	`Controls.FireButton`, and this reveals whichever one is already on
	screen. A gunner who is also the driver then ends up with one set of
	buttons rather than a second overlay dropped over the first. Crewing
	something with no cluster of its own -- a passenger turret, a fixed
	emplacement -- draws the bundled single-button cluster instead, in the
	same chrome.

	`ClearJumpButton` is for a shooter on foot rather than in a seat. A
	vehicle hides Roblox's own touch controls, so its cluster can have the
	bottom-right corner; a player carrying a gun still has the jump button
	there, and ours has to sit above it.
]]--

local Players = game:GetService("Players")

local TouchButtons = require(script.Parent.TouchButtons)

local CONTROLS_NAME = "Controls"
local BUTTON_NAME = "FireButton"

-- Roblox's touch controls, which we move out of the way of rather than touch.
local JUMP_FRAME_NAME = "TouchControlFrame"
local JUMP_BUTTON_NAME = "JumpButton"
local JUMP_GAP = 20
-- Used until the jump button exists to be measured, and if it never does.
local JUMP_CLEARANCE_FALLBACK = 150

-- A vehicle parents its cluster while mounting, which can land a frame or
-- two after the seat is taken. Waiting before drawing our own keeps the
-- common case -- the driver is the gunner -- from flashing a second button.
local ADOPT_GRACE_SYNCS = 3

local template = script:WaitForChild("FireTouchGui")

local TouchFire = {}
TouchFire.__index = TouchFire

export type Options = {
	ClearJumpButton: boolean?,
}

export type Handle = {
	Began: (() -> ())?,
	Ended: (() -> ())?,
	sync: (Handle, active: boolean) -> (),
	destroy: (Handle) -> (),
}

local function localPlayerGui(): Instance?
	local player = Players.LocalPlayer
	if not player then return nil end
	return player:FindFirstChildOfClass("PlayerGui")
end

-- Roblox parents its touch controls under a ScreenGui of its own, named the
-- same as the vehicle clusters. The TouchControlFrame child is what tells
-- them apart.
local function jumpButton(): GuiObject?
	local gui = localPlayerGui()
	if not gui then return nil end

	for _, child in ipairs(gui:GetChildren()) do
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

function TouchFire.new(options: Options?): Handle
	local self = setmetatable({
		Began = nil,
		Ended = nil,
		_button = nil,
		_own = nil,
		_connections = {},
		_syncs = 0,
		_clearJump = if options then options.ClearJumpButton == true else false,
	}, TouchFire)

	return (self :: any) :: Handle
end

-- The cluster some other script already has on screen, ours excepted.
function TouchFire:_adoptable(): TextButton?
	local gui = localPlayerGui()
	if not gui then return nil end

	for _, child in ipairs(gui:GetChildren()) do
		if child:IsA("ScreenGui") and child ~= self._own then
			local controls = child:FindFirstChild(CONTROLS_NAME)
			local button = if controls then controls:FindFirstChild(BUTTON_NAME) else nil
			if button and button:IsA("TextButton") then
				return button
			end
		end
	end

	return nil
end

function TouchFire:_bind(button: TextButton)
	self._button = button
	button.BackgroundTransparency = TouchButtons.IDLE_TRANSPARENCY
	button.Visible = true

	local held = TouchButtons.bindHold(button, function()
		if self.Began then self.Began() end
	end, function()
		if self.Ended then self.Ended() end
	end)

	for _, connection in ipairs(held) do
		table.insert(self._connections, connection)
	end
end

function TouchFire:_unbind()
	for _, connection in ipairs(self._connections) do
		connection:Disconnect()
	end
	table.clear(self._connections)

	local button = self._button
	self._button = nil

	if self.Ended then self.Ended() end

	if self._own then
		self._own:Destroy()
		self._own = nil
	elseif button and button.Parent then
		button.Visible = false
		button.BackgroundTransparency = TouchButtons.IDLE_TRANSPARENCY
	end
end

-- Lift our cluster clear of the jump button. The button is measured rather
-- than assumed because its size tracks the screen, and re-measured because it
-- is often not on screen yet the frame a gun is equipped.
function TouchFire:_liftAboveJump(controls: GuiObject)
	local function place()
		local jump = jumpButton()
		local clearance = if jump and jump.AbsoluteSize.Y > 0
			then jump.AbsoluteSize.Y + JUMP_GAP
			else JUMP_CLEARANCE_FALLBACK
		controls.Position = UDim2.new(1, 0, 1, -clearance)
	end

	place()

	local jump = jumpButton()
	if jump then
		table.insert(self._connections, jump:GetPropertyChangedSignal("AbsoluteSize"):Connect(place))
	else
		local gui = controls.Parent :: ScreenGui
		table.insert(self._connections, gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(place))
	end
end

function TouchFire:_drawOwn(): TextButton?
	local gui = localPlayerGui()
	if not gui then return nil end

	local screen = template:Clone()
	screen.Parent = gui
	self._own = screen
	table.insert(self._connections, TouchButtons.watchScale(screen))

	if self._clearJump then
		self:_liftAboveJump(screen.Controls)
	end

	return screen.Controls.FireButton
end

---Call every frame with whether the local player is crewing this gun.
function TouchFire:sync(active: boolean)
	if not active then
		self._syncs = 0
		if self._button then
			self:_unbind()
		end
		return
	end

	self._syncs += 1

	local adoptable = self:_adoptable()
	if adoptable then
		if self._button ~= adoptable then
			self:_unbind()
			self:_bind(adoptable)
		end
		return
	end

	-- Ours is already up and there is still nothing better to adopt.
	if self._own then return end

	-- Whatever cluster we had adopted left with its vehicle.
	if self._button then
		self:_unbind()
	end

	if self._syncs >= ADOPT_GRACE_SYNCS then
		local own = self:_drawOwn()
		if own then
			self:_bind(own)
		end
	end
end

function TouchFire:destroy()
	if self._button or self._own then
		self:_unbind()
	end
	self._syncs = 0
end

return TouchFire
