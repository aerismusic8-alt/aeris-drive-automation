local car = script.Parent.Parent.Parent.Parent
local chassis = car.Chassis
local rightNitroEmitterAttachment = chassis.RightNitroEmitterAttachment
local leftNitroEmitterAttachment = chassis.LeftNitroEmitterAttachment

local nitroEnabled = false

local Particles = {}

function Particles.startNitro()
	if nitroEnabled then
		return
	end

	nitroEnabled = true

	-- Enable the particle emitters and lights inside the nitro emitter attachments
	for _, emitter in rightNitroEmitterAttachment:GetChildren() do
		emitter.Enabled = true
	end
	for _, emitter in leftNitroEmitterAttachment:GetChildren() do
		emitter.Enabled = true
	end
end

function Particles.stopNitro()
	if not nitroEnabled then
		return
	end

	nitroEnabled = false

	-- Disable the particle emitters and lights inside the nitro emitter attachments
	for _, emitter in rightNitroEmitterAttachment:GetChildren() do
		emitter.Enabled = false
	end
	for _, emitter in leftNitroEmitterAttachment:GetChildren() do
		emitter.Enabled = false
	end
end

return Particles
