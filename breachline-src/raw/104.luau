-- GENERATED WRAPPER around upstream HardpointClient.
-- Only the enclosing function is added. Started by StarterPlayerScripts.Client.FourDClientRuntime.
return function(root: Instance, manifest: Instance)
if not script.Parent:IsA("Model") then return end

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Common = ReplicatedStorage:WaitForChild("FourD"):WaitForChild("Behaviors"):WaitForChild("Gunnable"):WaitForChild("Common")
local FireClient = require(Common:WaitForChild("FireClient"))
local Controller = require(Common:WaitForChild("Controller"))
local TracerRender = require(Common:WaitForChild("TracerRender"))
local ReplicationReady = require(Common:WaitForChild("ReplicationReady"))

local model = script.Parent

local fireTurretEvent = ReplicationReady.waitForChild(model, "GunnerFire", "RemoteEvent")
local attsFolder = ReplicationReady.waitForChild(model, "Gunnable_HardpointAttachments", "Folder")
local expectedAttachmentCount = ReplicationReady.waitForAttribute(model, "Gunnable_HardpointAttachmentCount")
local hasSeat = ReplicationReady.waitForAttribute(model, "Gunnable_HasSeat")
local fireSequence = ReplicationReady.waitForAttribute(model, "Gunnable_FireSequence")
local attachments: { Attachment } = if attsFolder and typeof(expectedAttachmentCount) == "number"
	then ReplicationReady.waitForObjectValues(attsFolder, expectedAttachmentCount, "Attachment")
	else {}
local seat: (Seat | VehicleSeat)? = if hasSeat == true
	then ReplicationReady.waitForObjectValue(model, "Gunnable_SeatRef", { "Seat", "VehicleSeat" }) :: any
	else nil

if not fireTurretEvent
	or not attsFolder
	or typeof(expectedAttachmentCount) ~= "number"
	or #attachments ~= expectedAttachmentCount
	or hasSeat == nil
	or typeof(fireSequence) ~= "string"
	or (hasSeat == true and not seat)
then
	warn("[HardpointClient] Replicated rig was not ready, aborting")
	return false
end

local function isLocalAuthorized(): boolean
	return Controller.localIsAuthorized(model, Controller.seatOptsFor(model, seat))
end

local rateMultiplier = if fireSequence == "Cycled" then math.max(1, #attachments) else 1

FireClient.bind(model, {
	FireEvent = fireTurretEvent,
	MuzzleAttachments = attachments,
	FireSequence = fireSequence,
	IsActive = isLocalAuthorized,
	GetAimRay = function()
		local primary = attachments[1]
		if not primary then return nil end

		local worldCFrame = primary.WorldCFrame
		return {
			Origin = worldCFrame.Position,
			Direction = worldCFrame.LookVector,
		}
	end,
	RateMultiplier = rateMultiplier,
})

local tracerEvent = model:WaitForChild("TracerShot")
local templateRef = model:WaitForChild("Gunnable_BulletProjectile")
TracerRender.bind(model, tracerEvent, templateRef)

end
;