-- GENERATED WRAPPER around upstream HardpointHud.
-- Only the enclosing function is added. Started by StarterPlayerScripts.Client.FourDClientRuntime.
return function(root: Instance, manifest: Instance)
--[[
	File: SubTypes/Hardpoint/HardpointHud.server.luau

	Client-side aiming HUD for Hardpoints. Casts forward from the barrel centroid
	(mirror of HardpointServer convergence math) and snaps the reticle to the
	nearest surface within the convergence/gun range, falling back to the
	convergence point when nothing is in front. Sizes the spread outline to the
	estimated dispersion at the reticle distance. Visible to the authorized firer
	and to any opt-in viewer (e.g. an aircraft pilot identified by HudViewerAttribute).

	Screen projection and ScreenGui lifecycle live in Common/AimReticle, shared
	with the Launcher SubType.
]]

if not script.Parent:IsA("Model") then return end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Common = ReplicatedStorage:WaitForChild("FourD"):WaitForChild("Behaviors"):WaitForChild("Gunnable"):WaitForChild("Common")
local Controller = require(Common:WaitForChild("Controller"))
local AimReticle = require(Common:WaitForChild("AimReticle"))
local ReplicationReady = require(Common:WaitForChild("ReplicationReady"))

local model = script.Parent
local localPlayer = Players.LocalPlayer

local attsFolder = ReplicationReady.waitForChild(model, "Gunnable_HardpointAttachments", "Folder")
local configFolder = ReplicationReady.waitForChild(model, "GunnableHardpointConfig", "Configuration")
local expectedAttachmentCount = ReplicationReady.waitForAttribute(model, "Gunnable_HardpointAttachmentCount")
local hasSeat = ReplicationReady.waitForAttribute(model, "Gunnable_HasSeat")
if not attsFolder or not configFolder or typeof(expectedAttachmentCount) ~= "number" or hasSeat == nil then
	warn("[HardpointHud] Replicated rig was not ready, aborting")
	return false
end

local function readConfig(name: string, default: any): any
	if not configFolder then return default end

	local valueObj = ReplicationReady.waitForChild(configFolder, name)
	if valueObj and valueObj:IsA("ValueBase") then
		return (valueObj :: any).Value
	end

	return default
end

local aimHudEnabled = readConfig("aimHudEnabled", true)
if aimHudEnabled == false then return end

local convergenceRange = readConfig("convergenceRange", 0)
local gunRange = readConfig("gunRange", 800)
local spreadDegrees = readConfig("spread", 0)
local hudViewerAttribute = readConfig("hudViewerAttribute", "")
local reticleLerp = readConfig("reticleLerp", false) == true

local convergenceActive = convergenceRange > 0 and convergenceRange <= gunRange
local spreadRad = math.rad(spreadDegrees)

local attachments: { Attachment } =
	ReplicationReady.waitForObjectValues(attsFolder, expectedAttachmentCount, "Attachment")
local seat: (Seat | VehicleSeat)? = if hasSeat == true
	then ReplicationReady.waitForObjectValue(model, "Gunnable_SeatRef", { "Seat", "VehicleSeat" }) :: any
	else nil

if #attachments ~= expectedAttachmentCount or (hasSeat == true and not seat) then
	warn("[HardpointHud] Replicated references were not ready, aborting")
	return false
end

local function isLocalViewer(): boolean
	if Controller.localIsAuthorized(model, Controller.seatOptsFor(model, seat)) then
		return true
	end

	if hudViewerAttribute == "" then
		return false
	end

	local localUserId = localPlayer.UserId
	if model:GetAttribute(hudViewerAttribute) == localUserId then
		return true
	end

	local root = model.PrimaryPart
	if root and root:GetAttribute(hudViewerAttribute) == localUserId then
		return true
	end

	return false
end

local function computeGunRay(): (Vector3, Vector3)
	local centroid = Vector3.zero
	local forwardSum = Vector3.zero
	for _, barrel in ipairs(attachments) do
		local barrelCFrame = barrel.WorldCFrame
		centroid += barrelCFrame.Position
		forwardSum += barrelCFrame.LookVector
	end

	centroid /= #attachments
	local forward = if forwardSum.Magnitude > 1e-5 then forwardSum.Unit else attachments[1].WorldCFrame.LookVector
	return centroid, forward
end

local reticle = AimReticle.new({ Lerp = reticleLerp })

local raycastParams = RaycastParams.new()
raycastParams.FilterType = Enum.RaycastFilterType.Exclude
raycastParams.IgnoreWater = true

local function computeSpreadRadius(centroid: Vector3, forward: Vector3, aimPoint: Vector3, reticleDist: number): number
	local maxOffset = 0
	if convergenceActive then
		local convergencePoint = centroid + forward * convergenceRange
		for _, barrel in ipairs(attachments) do
			local barrelPos = barrel.WorldCFrame.Position
			local toConverge = convergencePoint - barrelPos
			local barrelDir = if toConverge.Magnitude > 1e-5 then toConverge.Unit else barrel.WorldCFrame.LookVector
			local barrelHit = barrelPos + barrelDir * reticleDist
			local offset = (barrelHit - aimPoint).Magnitude
			if offset > maxOffset then maxOffset = offset end
		end
	end

	return maxOffset + reticleDist * math.tan(spreadRad)
end

local function onRender(deltaTime: number)
	if not isLocalViewer() then
		reticle:ReleaseGui()
		return
	end

	local centroid, forward = computeGunRay()
	local projectDist = if convergenceActive then convergenceRange else gunRange
	raycastParams.FilterDescendantsInstances = { model, localPlayer.Character }
	local hit = Workspace:Raycast(centroid, forward * projectDist, raycastParams)
	local reticleDist = if hit then hit.Distance else projectDist
	local aimPoint = centroid + forward * reticleDist

	if not reticle:Update(aimPoint, deltaTime) then return end

	reticle:SetSpreadRadius(computeSpreadRadius(centroid, forward, aimPoint, reticleDist))
end

local renderConnection = RunService.RenderStepped:Connect(onRender)

model.Destroying:Connect(function()
	renderConnection:Disconnect()
	reticle:Destroy()
end)

end
bH