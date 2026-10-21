--[[
	File: ReplicatedStorage/FourD/Common/PromptSuppression.luau

	GENERATED -- not part of upstream FourD.

	`ProximityPromptService.Enabled` is one switch for the entire client, but
	upstream toggles it from each mounted controller, and each one remembers
	the value it happened to find before suppressing. Two controllers holding
	it at once is enough to lose the original: the second reads the `false` the
	first just wrote, and restores that on the way out. Every prompt in the
	game then stays dead, with no way back short of a respawn -- which is what
	StarterPlayerScripts.Client.CameraReset is there to paper over.

	Counting holders makes the order irrelevant. The switch drops on the first
	acquire and is only restored once the last holder has let go.
]]

local ProximityPromptService = game:GetService("ProximityPromptService")

local holders = 0
local restore: boolean? = nil

local PromptSuppression = {}

function PromptSuppression.acquire()
	holders += 1
	if holders == 1 then
		restore = ProximityPromptService.Enabled
		ProximityPromptService.Enabled = false
	end
end

function PromptSuppression.release()
	-- Releasing without a matching acquire would hand the next caller's claim
	-- away. Callers each track their own, but they run in separate threads and
	-- destruction paths fire more than once.
	if holders == 0 then
		return
	end
	holders -= 1
	if holders == 0 then
		ProximityPromptService.Enabled = if restore == nil then true else restore
		restore = nil
	end
end

return PromptSuppression
