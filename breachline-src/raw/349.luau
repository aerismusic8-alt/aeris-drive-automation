--[[
SchoolBus6 Capability - Drivable school bus with a deployable stop sign arm.

Composes: WheeledVehicle.FourWheel Architect + Hingeable Behavior.
Schema: SchoolBus6 (body + 4 wheels + stop sign arm).
]]

local FourD = script:FindFirstAncestor("FourD")
local Capabilities = FourD:FindFirstChild("Capabilities")
local CapabilityBase = require(Capabilities.CapabilityBase)
local SchemaBuilder = require(Capabilities.SchemaBuilder)
local WheeledVehicleArchitect = require(FourD.Architects.WheeledVehicle)
local Hingeable = require(FourD.Behaviors.Hingeable)
local GeometryUtils = require(FourD.Common.GeometryUtils)
local recenterModelPivot = require(FourD.Common.recenterModelPivot)
local HelpUI = require(FourD.Common.HelpUI)

local STOP_SIGN_EXTENDED_ATTRIBUTE = "stopSignExtended"
local STOP_SIGN_TOGGLE_KEY_ATTRIBUTE = "stopSignToggleKey"
local STOP_SIGN_TOGGLE_EVENT_NAME = "StopSignToggleEvent"
local DEFAULT_TOGGLE_KEY = "T"
local HELP_STATE_DRIVER = "SchoolBus6_Driver"
local DEG_90 = math.pi / 2
local SWING_OPTS = { MaxSpeed = 1.5 }

type StopSignPlan = {
	PivotWorldCFrame: CFrame,
	SpawnedDeployed: boolean,
	DeployedAngle: number,
	RetractedAngle: number,
}

local function flattenToPlane(vector: Vector3, planeNormal: Vector3): Vector3
	return vector - planeNormal * vector:Dot(planeNormal)
end

local function signedAngleAbout(axis: Vector3, from: Vector3, to: Vector3): number
	local a = flattenToPlane(from, axis)
	local b = flattenToPlane(to, axis)
	if a.Magnitude < 1e-4 or b.Magnitude < 1e-4 then return 0 end
	a = a.Unit
	b = b.Unit
	return math.atan2(axis:Dot(a:Cross(b)), a:Dot(b))
end

local function projectedHalfExtent(cframe: CFrame, size: Vector3, direction: Vector3): number
	return 0.5 * (math.abs(cframe.RightVector:Dot(direction)) * size.X
		+ math.abs(cframe.UpVector:Dot(direction)) * size.Y
		+ math.abs(cframe.LookVector:Dot(direction)) * size.Z)
end

local function bounds(instance: PVInstance): (CFrame, Vector3)
	if instance:IsA("BasePart") then return instance.CFrame, instance.Size end
	return (instance :: Model):GetBoundingBox()
end

local function planStopSignHinge(sign: PVInstance, body: PVInstance, fl: PVInstance, fr: PVInstance, rl: PVInstance, rr: PVInstance): StopSignPlan
	local frontCenter = (fl:GetPivot().Position + fr:GetPivot().Position) / 2
	local rearCenter = (rl:GetPivot().Position + rr:GetPivot().Position) / 2

	local forward = frontCenter - rearCenter
	forward = if forward.Magnitude < 1e-3 then Vector3.new(0, 0, -1) else forward.Unit

	local up = flattenToPlane(Vector3.yAxis, forward)
	up = if up.Magnitude < 1e-3 then Vector3.yAxis else up.Unit

	local right = forward:Cross(up)
	right = if right.Magnitude < 1e-3 then Vector3.xAxis else right.Unit

	local bodyCFrame, bodySize = bounds(body)
	local busCenter = bodyCFrame.Position
	local bodyHalfWidth = projectedHalfExtent(bodyCFrame, bodySize, right)

	local signCFrame, signSize = bounds(sign)
	local signCenter = signCFrame.Position

	local flatLocal = GeometryUtils.getFlattestAxis(signSize)
	local plateNormal = signCFrame:VectorToWorldSpace(flatLocal).Unit

	local axes = {
		{ Dir = signCFrame.RightVector, Extent = signSize.X },
		{ Dir = signCFrame.UpVector, Extent = signSize.Y },
		{ Dir = signCFrame.LookVector, Extent = signSize.Z },
	}
	local verticalIndex = 1
	for index = 2, 3 do
		if math.abs(axes[index].Dir:Dot(up)) > math.abs(axes[verticalIndex].Dir:Dot(up)) then
			verticalIndex = index
		end
	end
	local armAxis = nil
	for index = 1, 3 do
		if index ~= verticalIndex and (not armAxis or axes[index].Extent > armAxis.Extent) then
			armAxis = axes[index]
		end
	end
	local armDir = armAxis.Dir.Unit
	local armExtent = armAxis.Extent

	local deployedByPlate = math.abs(plateNormal:Dot(forward)) > math.abs(plateNormal:Dot(right))
	local lateralReach = math.abs((signCenter - busCenter):Dot(right)) + projectedHalfExtent(signCFrame, signSize, right)
	local deployedByProtrusion = lateralReach > bodyHalfWidth + armExtent * 0.25
	if deployedByPlate ~= deployedByProtrusion then
		warn(`[SchoolBus6] stop sign deploy-state heuristics disagree (plate={deployedByPlate}, protrusion={deployedByProtrusion}); trusting plate-normal`)
	end
	local spawnedDeployed = deployedByPlate

	local endA = signCenter + armDir * (armExtent / 2)
	local endB = signCenter - armDir * (armExtent / 2)
	local pivotPosition
	if spawnedDeployed then
		pivotPosition = if (endA - busCenter).Magnitude <= (endB - busCenter).Magnitude then endA else endB
	else
		pivotPosition = if (endA - busCenter):Dot(forward) >= (endB - busCenter):Dot(forward) then endA else endB
	end
	pivotPosition = pivotPosition - up * (pivotPosition - signCenter):Dot(up)

	local pivotY = up
	local pivotX = flattenToPlane(forward, up).Unit
	local pivotWorldCFrame = CFrame.fromMatrix(pivotPosition, pivotY, pivotX)

	local sideSign = if (signCenter - busCenter):Dot(right) >= 0 then 1 else -1
	local deployedDir = right * sideSign
	local retractedDir = -forward
	local currentDir = signCenter - pivotPosition
	local otherDir = if spawnedDeployed then retractedDir else deployedDir
	local foldAngle = signedAngleAbout(up, currentDir, otherDir)
	if math.abs(foldAngle) < 1e-3 then
		foldAngle = if spawnedDeployed then -DEG_90 else DEG_90
	end

	return {
		PivotWorldCFrame = pivotWorldCFrame,
		SpawnedDeployed = spawnedDeployed,
		DeployedAngle = if spawnedDeployed then 0 else foldAngle,
		RetractedAngle = if spawnedDeployed then foldAngle else 0,
	}
end

local function wireStopSignToggle(scriptParent: Instance, assembledCar: Model, hinge, plan: StopSignPlan)
	assembledCar:SetAttribute(STOP_SIGN_EXTENDED_ATTRIBUTE, false)
	assembledCar:SetAttribute(STOP_SIGN_TOGGLE_KEY_ATTRIBUTE, DEFAULT_TOGGLE_KEY)
	hinge:SetTargetAngle(plan.RetractedAngle, SWING_OPTS)

	local toggleEvent = Instance.new("RemoteEvent")
	toggleEvent.Name = STOP_SIGN_TOGGLE_EVENT_NAME
	toggleEvent.Parent = assembledCar

	-- The toggle relay (StopSignToggleEvent -> retarget the hinge, gated by the
	-- driver) must run at Play, not here in the edit-time bind(): a connection
	-- made now is discarded when the compiler's RigExec session ends, so a
	-- compiled bus received the event with nothing listening. The hinge is
	-- client-rendered from its persisted Hingeable_Wrapper (Servo springs toward
	-- the wrapper's TargetAngle), so persist a pointer to that folder plus the two
	-- swing angles and clone the durable StopSignServer component into the rig. It
	-- is stamped FourDServerComponent, registered in the runtime manifest, and
	-- started by ServerScriptService.FourDServerRuntime at Play, where it rewrites
	-- TargetAngle on toggle.
	assembledCar:SetAttribute("SchoolBus6_DeployedAngle", plan.DeployedAngle)
	assembledCar:SetAttribute("SchoolBus6_RetractedAngle", plan.RetractedAngle)

	local wrapperRef = Instance.new("ObjectValue")
	wrapperRef.Name = "SchoolBus6_HingeWrapperRef"
	wrapperRef.Value = hinge:GetWrapper()
	wrapperRef.Parent = assembledCar

	local serverComponent = scriptParent:FindFirstChild("StopSignServer")
	if serverComponent then
		serverComponent:Clone().Parent = assembledCar
	end
end

local function MakeFunctional(root: Model, config): Model
	recenterModelPivot(root)

	local fl = root:FindFirstChild("left front wheel")
	local fr = root:FindFirstChild("right front wheel")
	local rl = root:FindFirstChild("left rear wheel")
	local rr = root:FindFirstChild("right rear wheel")
	local body = root:FindFirstChild("body")
	local stopSign = root:FindFirstChild("stop sign arm")

	if not fl then error("Missing 'left front wheel'") end
	if not fr then error("Missing 'right front wheel'") end
	if not rl then error("Missing 'left rear wheel'") end
	if not rr then error("Missing 'right rear wheel'") end
	if not body then error("Missing 'body'") end

	for _, wheel in { fl, fr, rl, rr } do
		if wheel:IsA("Model") then recenterModelPivot(wheel) end
	end
	if body:IsA("Model") then recenterModelPivot(body) end

	local plan = nil
	local stopSignRelCFrames = {}
	local bodyAnchor = GeometryUtils.getOrSetPrimaryPart(body)
	if stopSign and stopSign:IsA("Model") and bodyAnchor then
		recenterModelPivot(stopSign, true)
		plan = planStopSignHinge(stopSign, body, fl, fr, rl, rr)
		for _, part in GeometryUtils.getInstanceParts(stopSign) do
			stopSignRelCFrames[part] = bodyAnchor.CFrame:ToObjectSpace(part.CFrame)
		end
		stopSign.Parent = nil
	end
	local pivotLocalToBody = if plan then bodyAnchor.CFrame:ToObjectSpace(plan.PivotWorldCFrame) else nil

	local vehicle = WheeledVehicleArchitect.build4Wheel(body, {
		Schema = {
			WheelFL = fl,
			WheelFR = fr,
			WheelRL = rl,
			WheelRR = rr,
		},
		SeatPosition = config.seatPosition,
		Performance = { HasNitro = true },
	})
	local assembledCar = vehicle.vehicleModel

	if plan and next(stopSignRelCFrames) then
		bodyAnchor = GeometryUtils.getOrSetPrimaryPart(body)
		stopSign.Parent = assembledCar
		for part, relativeCFrame in pairs(stopSignRelCFrames) do
			part.CFrame = bodyAnchor.CFrame:ToWorldSpace(relativeCFrame)
			part.Anchored = false
			part.CanCollide = false
			part.Massless = true
		end
		recenterModelPivot(stopSign, true)

		local chassis = GeometryUtils.findRigChassis(assembledCar)
		local pivotWorld = bodyAnchor.CFrame:ToWorldSpace(pivotLocalToBody)
		local pivotLocal = stopSign:GetPivot():ToObjectSpace(pivotWorld)
		local hinge = Hingeable.new(stopSign, {
			PivotCFrame = pivotLocal,
			Mode = "Servo",
			RelativeTo = chassis or bodyAnchor,
			TargetAngle = 0,
		})

		wireStopSignToggle(script.Parent, assembledCar, hinge, plan)

		HelpUI.registerState(assembledCar, HELP_STATE_DRIVER, {
			Sources = {
				{ Type = "Set", SetId = "WheeledVehicle.FourWheel" },
				{ Type = "Set", SetId = "SchoolBus6" },
			},
		})
		assembledCar:SetAttribute("HelpUI_DriverState", HELP_STATE_DRIVER)

		local clientScript = script.Parent:FindFirstChild("SchoolBusClient")
		if clientScript then
			local clone = clientScript:Clone()
			if clone:IsA("BaseScript") then
				clone.Enabled = true
			end
			clone.Parent = assembledCar
		end
	end

	return assembledCar
end

local SchoolBus6 = CapabilityBase.createChild()

function SchoolBus6:getCapabilityDocumentation()
	return [[
The SchoolBus6Capability creates a drivable school bus with a stop sign arm that the driver can extend or retract.
Press T (or DPadLeft / the on-screen button) to deploy or fold the stop sign arm while driving.
]]
end

function SchoolBus6:getModelSpecs()
	return {
		{
			name = "car",
			modelSchema = "SchoolBus6",
			description = "a school bus with four wheels, body, and a flip-out stop sign arm",
		},
	}
end

function SchoolBus6:getBindParametersDefinition()
	return SchemaBuilder.define()
		:addOptionalArgument("seatPosition", {
			type = "string",
			enum = { "inside", "ontop" },
			default = "inside",
			description = "Position of the driver seat",
		})
		:build()
end

function SchoolBus6:getCapabilitySelectionExamples()
	return {
		{
			user = "a school bus",
			assistant = {
				capability_reasoning = 'A school bus with a stop sign arm. SchoolBus6Capability is the right choice.',
				capability_selection = "SchoolBus6Capability",
				overall_size_reasoning = "A school bus is about 10m long, 2.4m wide, 3m tall.",
				overall_size_selection = { x = 2.4, y = 3, z = 10 },
			},
		},
	}
end

function SchoolBus6:bind(generatedModels, parameters)
	local isValid, errorMsg = self:validateConfig(parameters)
	if not isValid then error("SchoolBus6Capability configuration error: " .. errorMsg) end

	local carModel = generatedModels["car"]
	if not carModel then error("Could not find 'car' model") end

	return MakeFunctional(carModel, parameters)
end

return SchoolBus6
[