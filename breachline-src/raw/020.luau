--[[
	File: ClientSpreadModel.luau
]]--

-- Root

local ClientSpreadModel = {}
ClientSpreadModel.__index = ClientSpreadModel

-- Roblox Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Dependencies

local FourD = ReplicatedStorage:WaitForChild("FourD")
local Architects = FourD:WaitForChild("Architects")
local Firearm2 = Architects:WaitForChild("Firearm2")
local Constants = require(Firearm2.Common.Constants)

-- Constants

local MOVE_LERP_RATE = Constants.SPREAD_MOVE_LERP_RATE

-- Public Methods

function ClientSpreadModel:Step(deltaTime: number, isMoving: boolean): number
	local moveTarget = if isMoving then 1 else 0
	local moveBlendStep = math.clamp(deltaTime * MOVE_LERP_RATE, 0, 1)
	self._moveBlend = math.lerp(self._moveBlend, moveTarget, moveBlendStep)

	self._accumShot = math.max(0, self._accumShot - self._params.SpreadRecovery * deltaTime)

	local moveContribution = self._params.BaseSpread * (self._params.MoveSpreadMult - 1) * self._moveBlend
	local total = self._params.BaseSpread + moveContribution + self._accumShot
	return math.clamp(total, 0, self._params.MaxSpread)
end

function ClientSpreadModel:OnShot()
	local headroom = math.max(0, self._params.MaxSpread - self._params.BaseSpread)
	self._accumShot = math.min(self._accumShot + self._params.SpreadPerShot, headroom)
end

function ClientSpreadModel:Reset()
	self._accumShot = 0
	self._moveBlend = 0
end

function ClientSpreadModel:Destroy()
	for key in self do rawset(self, key, nil) end
	table.freeze(self)
end

-- Constructor

function ClientSpreadModel.new(params: { [string]: any }): any
	local self = setmetatable({}, ClientSpreadModel)
	self._params = params
	self._accumShot = 0
	self._moveBlend = 0
	return self
end

-- Return

return ClientSpreadModel
$