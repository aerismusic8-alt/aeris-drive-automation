if not script.Parent:IsA("Model") then return end

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Common = ReplicatedStorage:WaitForChild("FourD"):WaitForChild("Behaviors"):WaitForChild("Gunnable"):WaitForChild("Common")
local FireServer = require(Common:WaitForChild("FireServer"))
local Controller = require(Common:WaitForChild("Controller"))

local model = script.Parent

local fireTurretEvent = model:FindFirstChild("GunnerFire")
local tracerEvent = model:FindFirstChild("TracerShot")
local attsFolder = model:FindFirstChild("Gunnable_HardpointAttachments")
local seatRef = model:FindFirstChild("Gunnable_SeatRef")
local seat: Seat? = if seatRef and seatRef:IsA("ObjectValue") then seatRef.Value else nil

if not fireTurretEvent or not tracerEvent or not attsFolder then
	warn("[HardpointServer] Missing required instances, aborting")
	return
end

local attachments: { Attachment } = {}
for _, objectValue in ipairs(attsFolder:GetChildren()) do
	if objectValue:IsA("ObjectValue") and objectValue.Value and objectValue.Value:IsA("Attachment") then
		table.insert(attachments, objectValue.Value)
	end
end

if #attachments == 0 then
	warn("[HardpointServer] No muzzle attachments resolved, aborting")
	return
end

Controller.setOverride(model, nil)

local function isAuthorizedFirer(player: Player): boolean
	return Controller.resolve(model, Controller.seatOptsFor(model, seat)) == player
end

local fireSequence = model:GetAttribute("Gunnable_FireSequence") or "Simultaneous"
local rateMultiplier = if fireSequence == "Cycled" then math.max(1, #attachments) else 1

local configFolder = model:FindFirstChild("GunnableHardpointConfig")
local convergenceRange = 0
local gunRange = 800
if configFolder then
	local convergenceValue = configFolder:FindFirstChild("convergenceRange")
	if convergenceValue then convergenceRange = convergenceValue.Value end

	local gunRangeValue = configFolder:FindFirstChild("gunRange")
	if gunRangeValue then gunRange = gunRangeValue.Value end
end

local convergenceActive = convergenceRange > 0 and convergenceRange <= gunRange

local function getConvergenceDirection(att: Attachment): Vector3
	local centroid = Vector3.zero
	local forwardSum = Vector3.zero
	for _, barrel in ipairs(attachments) do
		local barrelCFrame = barrel.WorldCFrame
		centroid += barrelCFrame.Position
		forwardSum += barrelCFrame.LookVector
	end

	centroid /= #attachments

	local forward = if forwardSum.Magnitude > 1e-5 then forwardSum.Unit else att.WorldCFrame.LookVector
	local convergencePoint = centroid + forward * convergenceRange
	local toPoint = convergencePoint - att.WorldCFrame.Position
	if toPoint.Magnitude < 1e-5 then
		return att.WorldCFrame.LookVector
	end

	return toPoint.Unit
end

FireServer.bind(model, {
	FireEvent = fireTurretEvent,
	TracerEvent = tracerEvent,
	MuzzleAttachments = attachments,
	GetDirection = if convergenceActive then getConvergenceDirection else nil,
	IsAuthorizedPlayer = isAuthorizedFirer,
	UseClientHints = function()
		return model:GetAttribute(Controller.TURRET_BOUND_ATTR) == true
	end,
	FireSequence = fireSequence,
	RateMultiplier = rateMultiplier,
})
