--[[
TankSimple5 Capability - Tracked vehicle with rotating turret and pitching cannon

Composes: WheeledVehicle Architect (treads as wheels) + Gunnable (newTurret)
Schema: TankSimple5 (hull + turret + turret cannon + 2 tread assemblies)

NOTE: Treads use the same Drivable rig but with tread assemblies mapped to wheels.
The turret yaws on Gunnable's split-axis mount and the cannon pitches on top of it;
the driver aims both with the camera.
]]

local FourD = script:FindFirstAncestor("FourD")
local Capabilities = FourD:FindFirstChild("Capabilities")
local CapabilityBase = require(Capabilities.CapabilityBase)
local SchemaBuilder = require(Capabilities.SchemaBuilder)
local Beh = FourD:FindFirstChild("Behaviors")
local WheeledVehicleArchitect = require(FourD.Architects.WheeledVehicle)
local Gunnable = require(Beh.Gunnable)
local GeometryUtils = require(FourD.Common.GeometryUtils)

local REACH_EPSILON = 0.1
local CAMERA_AIM_HEIGHT_OFFSET = 8

local function detectTankForward(hull: Model, turret: Model, cannon: Model): Vector3
	local hullCFrame = GeometryUtils.getInstanceCFrame(hull)
	local hullSize = GeometryUtils.getInstanceSize(hull)
	local axis = if hullSize.Z >= hullSize.X then hullCFrame.LookVector else hullCFrame.RightVector

	-- Cannon juts out of the turret toward the front, so it disambiguates the hull axis sign
	local cannonPosition = GeometryUtils.getInstanceCFrame(cannon).Position
	local reach = cannonPosition - GeometryUtils.getInstanceCFrame(turret).Position
	if math.abs(reach:Dot(axis)) < REACH_EPSILON then
		reach = cannonPosition - hullCFrame.Position
	end

	if reach:Dot(axis) < 0 then
		axis = -axis
	end

	return axis
end

local function createTrackProxyWheels(track: Model, forwardHint: Vector3): (BasePart, BasePart)
	local trackCFrame = GeometryUtils.getInstanceCFrame(track)
	local trackSize = GeometryUtils.getInstanceSize(track)

	local axis = if trackSize.Z >= trackSize.X then trackCFrame.LookVector else trackCFrame.RightVector
	if axis:Dot(forwardHint) < 0 then
		axis = -axis
	end

	local length = math.max(trackSize.X, trackSize.Z)
	local width = math.min(trackSize.X, trackSize.Z)
	local diameter = trackSize.Y
	local axleOffset = math.max(length * 0.5 - diameter * 0.5, length * 0.25)

	local function createProxy(sign: number): BasePart
		local proxy = Instance.new("Part")
		proxy.Name = "TrackWheelProxy"
		proxy.Size = Vector3.new(width, diameter, diameter)
		proxy.CFrame = CFrame.lookAlong(trackCFrame.Position + axis * (sign * axleOffset), axis)
		proxy.Transparency = 1
		proxy.CanCollide = false
		proxy.CanQuery = false
		proxy.CanTouch = false
		proxy.Massless = true
		proxy.Anchored = true
		proxy.Parent = track.Parent
		return proxy
	end

	return createProxy(1), createProxy(-1)
end

local function makeShellTemplate(projectileName: string): PVInstance
	if projectileName ~= "" then
		local projectiles = FourD:FindFirstChild("Projectiles")
		local template = projectiles and projectiles:FindFirstChild(projectileName)
		if template and (template:IsA("BasePart") or template:IsA("Model")) then
			return template:Clone()
		end
	end

	local shell = Instance.new("Part")
	shell.Name = "TankShell"
	shell.Shape = Enum.PartType.Ball
	shell.Size = Vector3.new(0.8, 0.8, 0.8)
	shell.Color = Color3.fromRGB(45, 45, 45)
	shell.Material = Enum.Material.Metal
	return shell
end

local function makeFunctional(root: Model, config: { [string]: any }): Model
	local hull = root:FindFirstChild("hull")
	local turret = root:FindFirstChild("turret")
	local cannon = root:FindFirstChild("turret cannon")
	local leftTrack = root:FindFirstChild("left track")
	local rightTrack = root:FindFirstChild("right track")

	if not hull then error("Missing 'hull'") end
	if not turret then error("Missing 'turret'") end
	if not cannon then error("Missing 'turret cannon'") end
	if not leftTrack then error("Missing 'left track'") end
	if not rightTrack then error("Missing 'right track'") end

	local hullAnchor = GeometryUtils.getOrSetPrimaryPart(hull)
	local forwardHint = detectTankForward(hull, turret, cannon)

	local gunRelCFs = {}
	for _, gunPiece in ipairs({ turret, cannon }) do
		for _, part in ipairs(GeometryUtils.getInstanceParts(gunPiece)) do
			gunRelCFs[part] = hullAnchor.CFrame:ToObjectSpace(part.CFrame)
		end
	end

	turret.Parent = nil
	cannon.Parent = nil

	-- Tracks can't fill wheel slots directly (front/rear would coincide); invisible
	-- proxy wheels at each track's ends define the wheelbase, tracks weld on as ExtraParts
	local leftFront, leftRear = createTrackProxyWheels(leftTrack, forwardHint)
	local rightFront, rightRear = createTrackProxyWheels(rightTrack, forwardHint)

	for _, track in ipairs({ leftTrack, rightTrack }) do
		for _, part in ipairs(GeometryUtils.getInstanceParts(track)) do
			part.CanCollide = false
		end
	end

	local vehicle = WheeledVehicleArchitect.build4Wheel(hull, {
		Schema = {
			WheelFL = leftFront,
			WheelFR = rightFront,
			WheelRL = leftRear,
			WheelRR = rightRear,
		},
		SeatPosition = config.seatPosition,
		Performance = { HasNitro = true },
		ExtraParts = { leftTrack, rightTrack },
		Camera = { AimHeightOffset = CAMERA_AIM_HEIGHT_OFFSET },
	})
	local assembledTank = vehicle.vehicleModel

	turret.Parent = assembledTank
	cannon.Parent = assembledTank
	for part, relCF in pairs(gunRelCFs) do
		part.CFrame = hullAnchor.CFrame:ToWorldSpace(relCF)
	end

	local driverSeat = assembledTank:FindFirstChildWhichIsA("VehicleSeat", true)

	local turretHandle = Gunnable.newTurret(assembledTank, cannon, {
		DriverSeat = driverSeat,
		YawModel = turret,
		GunnerPitchUp = config.gunPitchUp,
		GunnerPitchDown = config.gunPitchDown,
		DisableCrosshair = true,
	})

	if turretHandle then
		local muzzle = Gunnable.detectMuzzle(assembledTank, cannon)
		if muzzle then
			local shellTemplate = makeShellTemplate(config.projectileName or "")
			local launcher = Gunnable.newLauncher(assembledTank, muzzle, shellTemplate, {
				ImpactDamage = config.gunDamage,
				FireRate = config.gunFireRate / 60,
				Smoke = {
					AssetName = "CannonSmoke",
					ParticleCount = 30,
				},
				Explosion = {
					Radius = 8,
					Damage = config.gunDamage * 0.5,
				},
				Projectile = {
					Speed = config.projectileSpeed,
					Range = config.gunRange,
					Gravity = config.projectileGravity,
				},
				AimVisual = "Hud",
			})
			shellTemplate:Destroy()
			turretHandle:BindWeapon(launcher)
		else
			warn("[TankSimple5] Could not detect cannon muzzle; gun will not fire")
		end
	end

	return assembledTank
end

local TankSimple5 = CapabilityBase.createChild()

function TankSimple5:getCapabilityDocumentation()
	return [[
The TankSimple5Capability creates a tracked combat vehicle with a rotating turret and a
pitching cannon barrel. Treads provide drive physics. The driver aims with the camera; the
turret yaws to follow while the cannon elevates, and it fires arcing shells with mouse click.
Use for tanks, APCs, or any tracked combat vehicle.
]]
end

function TankSimple5:getModelSpecs()
	return {
		{
			name = "car",
			modelSchema = "TankSimple5",
			description = "a tank with hull, turret, turret cannon barrel, and two tread assemblies",
		},
	}
end

function TankSimple5:getBindParametersDefinition()
	return SchemaBuilder.define()
		:addOptionalArgument("seatPosition", { type = "string", enum = { "inside", "ontop" }, default = "inside", description = "Driver seat position" })
		:addOptionalArgument("gunDamage", { type = "number", default = 80, description = "Damage per shell" })
		:addOptionalArgument("gunFireRate", { type = "number", default = 30, description = "RPM (slow for tank)" })
		:addOptionalArgument("gunRange", { type = "number", default = 800, description = "Max shell travel distance in studs" })
		:addOptionalArgument("gunPitchUp", { type = "number", default = 20, minimum = 0, description = "Max cannon elevation in degrees" })
		:addOptionalArgument("gunPitchDown", { type = "number", default = 8, minimum = 0, description = "Max cannon depression in degrees" })
		:addOptionalArgument("projectileSpeed", { type = "number", default = 500, description = "Shell speed studs/s" })
		:addOptionalArgument("projectileGravity", { type = "number", default = 20, minimum = 0, description = "Downward shell acceleration studs/s^2; higher = more arc" })
		:addOptionalArgument("projectileName", { type = "string", default = "", description = "Projectile template" })
		:build()
end

function TankSimple5:getCapabilitySelectionExamples()
	return {
		{
			user = "a battle tank",
			assistant = {
				capability_reasoning = 'A tracked combat vehicle with a turret gun. TankSimple5Capability handles this.',
				capability_selection = "TankSimple5Capability",
				overall_size_reasoning = "A tank is about 7m long, 3.5m wide, 2.5m tall.",
				overall_size_selection = { x = 3.5, y = 2.5, z = 7 },
			},
		},
	}
end

function TankSimple5:bind(generatedModels, parameters)
	local isValid, errorMsg = self:validateConfig(parameters)
	if not isValid then error("TankSimple5Capability configuration error: " .. errorMsg) end

	local carModel = generatedModels["car"]
	if not carModel then error("Could not find 'car' model") end

	return makeFunctional(carModel, parameters)
end

return TankSimple5
