--[[
	File: ClientRecoilModel.luau
]]--

-- Root

local ClientRecoilModel = {}
ClientRecoilModel.__index = ClientRecoilModel

-- Public Methods

function ClientRecoilModel:Step(deltaTime: number): (number, number)
	local recovery = math.rad(self._params.RecoilRecovery) * deltaTime

	if self._pitchOffset > 0 then
		self._pitchOffset = math.max(0, self._pitchOffset - recovery)
	end

	if self._yawOffset > 0 then
		self._yawOffset = math.max(0, self._yawOffset - recovery)
	elseif self._yawOffset < 0 then
		self._yawOffset = math.min(0, self._yawOffset + recovery)
	end

	return self._pitchOffset, self._yawOffset
end

function ClientRecoilModel:OnShot()
	local kickPitch = math.rad(self._params.RecoilVertical)
	local kickYaw = math.rad(self._params.RecoilHorizontal) * (math.random() * 2 - 1)
	local maxAccum = math.rad(self._params.RecoilMaxAccum)
	self._pitchOffset = math.min(self._pitchOffset + kickPitch, maxAccum)
	self._yawOffset += kickYaw
end

function ClientRecoilModel:Reset()
	self._pitchOffset = 0
	self._yawOffset = 0
end

function ClientRecoilModel:Destroy()
	for key in self do rawset(self, key, nil) end
	table.freeze(self)
end

-- Constructor

function ClientRecoilModel.new(params: { [string]: any }): any
	local self = setmetatable({}, ClientRecoilModel)
	self._params = params
	self._pitchOffset = 0
	self._yawOffset = 0
	return self
end

-- Return

return ClientRecoilModel
