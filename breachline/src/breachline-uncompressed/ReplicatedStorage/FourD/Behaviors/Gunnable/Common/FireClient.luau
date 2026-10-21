--[[
	File: Common/FireClient.luau

	Shared client-side firing input: Mouse1, or the Fire button in the
	gunner's on-screen control cluster, held to fire with rate-limit, fires
	RemoteEvent with caller-supplied (origin, direction). Variants supply the
	aim ray and an isActive predicate. Plays muzzle flash locally on fire and
	mirrors server broadcast for non-firing clients.
]]--

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local FourD = script:FindFirstAncestor("FourD")
local MuzzleFlashFx = require(FourD.Common.MuzzleFlashFx)
local TouchFire = require(FourD.Common.TouchFire)

export type AimRay = {
	Origin: Vector3,
	Direction: Vector3,
}

export type FireSequence = "Simultaneous" | "Cycled"

export type BindOptions = {
	FireEvent: RemoteEvent,
	MuzzleAttachments: { Attachment },
	IsActive: () -> boolean,
	GetAimRay: () -> AimRay?,
	RateMultiplier: number?,
	FireSequence: FireSequence?,
}

local FireClient = {}

local function playLocalFlash(atts: { Attachment }, fireSequence: FireSequence, cycleIdx: number, color: Color3?): number
	if fireSequence == "Cycled" then
		local att = atts[cycleIdx]
		if att then MuzzleFlashFx.play(att, color) end

		return (cycleIdx % math.max(1, #atts)) + 1
	end

	for _, att in ipairs(atts) do
		MuzzleFlashFx.play(att, color)
	end

	return cycleIdx
end

function FireClient.bind(model: Model, opts: BindOptions): () -> ()
	local configFolder = model:FindFirstChild("GunnableHardpointConfig")
	local fireRateRPM = 600
	local tracerColorValue = if configFolder then configFolder:FindFirstChild("tracerColor") else nil
	local muzzleColor: Color3? = if tracerColorValue then tracerColorValue.Value else nil
	if configFolder then
		local fr = configFolder:FindFirstChild("gunFireRate")
		if fr then fireRateRPM = fr.Value end
	end
	local rateMultiplier = math.max(1, opts.RateMultiplier or 1)
	local fireInterval = 60 / (fireRateRPM * rateMultiplier)
	local fireSequence: FireSequence = opts.FireSequence or "Simultaneous"
	local muzzleAttachments = opts.MuzzleAttachments
	local localCycleIdx = 1

	local isFiring = false
	local lastFireTick = 0

	-- Touch has no mouse button to hold down, so firing rides on a button in
	-- whatever control cluster the gunner already has on screen.
	local touchFire = if UserInputService.TouchEnabled then TouchFire.new() else nil

	if touchFire then
		touchFire.Began = function()
			if opts.IsActive() then
				isFiring = true
			end
		end
		touchFire.Ended = function()
			isFiring = false
		end
	end

	local inputBeganConn = UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1 and opts.IsActive() then
			isFiring = true
		end
	end)

	local inputEndedConn = UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			isFiring = false
		end
	end)

	local heartbeatConn = RunService.Heartbeat:Connect(function()
		if touchFire then
			touchFire:sync(opts.IsActive())
		end

		if not isFiring then return end
		if not opts.IsActive() then
			isFiring = false
			return
		end

		local now = tick()
		if now - lastFireTick < fireInterval then return end
		lastFireTick = now

		local ray = opts.GetAimRay()
		if not ray then return end

		localCycleIdx = playLocalFlash(muzzleAttachments, fireSequence, localCycleIdx, muzzleColor)
		opts.FireEvent:FireServer(ray.Origin, ray.Direction)
	end)

	return function()
		inputBeganConn:Disconnect()
		inputEndedConn:Disconnect()
		heartbeatConn:Disconnect()

		if touchFire then
			touchFire:destroy()
		end

		isFiring = false
	end
end

return FireClient
