--[[
	File: ClientInput.luau
]]--

-- Root

local ClientInput = {}
ClientInput.__index = ClientInput

-- Roblox Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

-- Dependencies

local FourD = ReplicatedStorage:WaitForChild("FourD")
local Dumpster = require(FourD.Libs.Dumpster)
local Keybinds = require(FourD.Common.Keybinds)
local TouchFire = require(FourD.Common.TouchFire)

-- Constants

local KEYBINDS_SET_ID = "Firearm2"

-- Public Methods

function ClientInput:IsFireHeld(): boolean
	return self._fireHeld
end

function ClientInput:IsAimHeld(): boolean
	return self._aimHeld
end

function ClientInput:Enable()
	if self._dumpster then return end

	local dumpster = Dumpster.new()
	self._dumpster = dumpster

	local handle = Keybinds.bindActions(KEYBINDS_SET_ID, {
		Fire = function(state)
			if state == Enum.UserInputState.Begin then
				self._fireHeld = true
				self.FireBegan:Fire()
			elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
				self._fireHeld = false
				self.FireEnded:Fire()
			end
			return nil
		end,
		Aim = function(state)
			if state == Enum.UserInputState.Begin then
				self._aimHeld = true
				self.AimBegan:Fire()
			elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
				self._aimHeld = false
				self.AimEnded:Fire()
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

	-- Keybinds reaches keyboard and gamepad only. The touch trigger is drawn
	-- clear of the jump button, which a player on foot still has, and only
	-- Fire is offered: reloading already happens on its own when the magazine
	-- runs dry.
	if UserInputService.TouchEnabled then
		local touchFire = TouchFire.new({ ClearJumpButton = true })
		touchFire.Began = function()
			self._fireHeld = true
			self.FireBegan:Fire()
		end
		touchFire.Ended = function()
			self._fireHeld = false
			self.FireEnded:Fire()
		end

		local connection = RunService.Heartbeat:Connect(function()
			touchFire:sync(true)
		end)

		dumpster:Add(function()
			connection:Disconnect()
			touchFire:destroy()
		end)
	end
end

function ClientInput:Disable()
	if not self._dumpster then return end

	local dumpster = self._dumpster
	self._dumpster = nil
	dumpster:Destroy()

	self._fireHeld = false
	self._aimHeld = false
end

function ClientInput:Destroy()
	self:Disable()

	self.FireBegan:Destroy()
	self.FireEnded:Destroy()
	self.AimBegan:Destroy()
	self.AimEnded:Destroy()
	self.ReloadTriggered:Destroy()

	for key in self do rawset(self, key, nil) end
	table.freeze(self)
end

-- Constructor

function ClientInput.new(): any
	local self = setmetatable({}, ClientInput)
	self._dumpster = nil
	self._fireHeld = false
	self._aimHeld = false
	self.FireBegan = Instance.new("BindableEvent")
	self.FireEnded = Instance.new("BindableEvent")
	self.AimBegan = Instance.new("BindableEvent")
	self.AimEnded = Instance.new("BindableEvent")
	self.ReloadTriggered = Instance.new("BindableEvent")
	return self
end

-- Return

return ClientInput
w