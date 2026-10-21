--[[
	FourDServerComponent -- started at Play by ServerScriptService.FourDServerRuntime.

	Restores the stop-sign toggle. The relay StopSignToggleEvent -> retarget the
	stop-sign hinge, gated by the driver, was an in-memory connection made inside
	the edit-time bind() (SchoolBus6's wireStopSignToggle) and did not survive to
	Play: a compiled bus received the event with nothing listening, so pressing T
	did nothing.

	The hinge itself is fully client-rendered from the persisted Hingeable_Wrapper
	folder (see HingeableClient): in Servo mode the client springs toward the
	wrapper's TargetAngle attribute. So this component holds no Hingeable object --
	it just re-acquires the wrapper (via the persisted ref) and the two swing
	angles (persisted attributes) and writes TargetAngle on toggle, exactly as the
	edit-time closure did through Hingeable:SetTargetAngle.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local FourD = ReplicatedStorage:WaitForChild("FourD")
local HingeConstants = require(FourD:WaitForChild("Behaviors"):WaitForChild("Hingeable"):WaitForChild("Common"):WaitForChild("Constants"))

local STOP_SIGN_EXTENDED_ATTRIBUTE = "stopSignExtended"
local DEPLOYED_ANGLE_ATTRIBUTE = "SchoolBus6_DeployedAngle"
local RETRACTED_ANGLE_ATTRIBUTE = "SchoolBus6_RetractedAngle"
local WRAPPER_REF_NAME = "SchoolBus6_HingeWrapperRef"

local function refValue(model: Instance, name: string): Instance?
	local ref = model:FindFirstChild(name)
	if ref and ref:IsA("ObjectValue") then
		return ref.Value
	end
	return nil
end

return function(root: Instance, _manifest: Instance)
	assert(root:IsA("Model"), "[StopSignServer] root must be a Model")

	local toggleEvent = root:WaitForChild("StopSignToggleEvent", 10)
	assert(toggleEvent and toggleEvent:IsA("RemoteEvent"), "[StopSignServer] missing StopSignToggleEvent RemoteEvent")

	local wrapper = refValue(root, WRAPPER_REF_NAME)
	assert(wrapper and wrapper:IsA("Folder"), "[StopSignServer] missing " .. WRAPPER_REF_NAME .. " -> Hingeable_Wrapper folder")

	local deployedAngle = root:GetAttribute(DEPLOYED_ANGLE_ATTRIBUTE)
	local retractedAngle = root:GetAttribute(RETRACTED_ANGLE_ATTRIBUTE)
	assert(typeof(deployedAngle) == "number", "[StopSignServer] missing " .. DEPLOYED_ANGLE_ATTRIBUTE)
	assert(typeof(retractedAngle) == "number", "[StopSignServer] missing " .. RETRACTED_ANGLE_ATTRIBUTE)

	local extended = root:GetAttribute(STOP_SIGN_EXTENDED_ATTRIBUTE) == true

	local connections: { RBXScriptConnection } = {}
	table.insert(
		connections,
		toggleEvent.OnServerEvent:Connect(function(firingPlayer: Player)
			local seat = root:FindFirstChildWhichIsA("VehicleSeat", true)
			if not seat then return end
			local occupant = seat.Occupant
			if not occupant or occupant.Parent ~= firingPlayer.Character then return end

			extended = not extended
			root:SetAttribute(STOP_SIGN_EXTENDED_ATTRIBUTE, extended)
			wrapper:SetAttribute(HingeConstants.ATTR_TARGET_ANGLE, if extended then deployedAngle else retractedAngle)
		end)
	)

	return function()
		for _, connection in connections do
			connection:Disconnect()
		end
	end
end
