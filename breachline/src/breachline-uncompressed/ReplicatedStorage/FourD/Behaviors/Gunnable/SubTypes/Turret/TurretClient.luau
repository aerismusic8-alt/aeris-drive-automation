-- GENERATED WRAPPER around upstream TurretClient.
-- Only the enclosing function is added. Started by StarterPlayerScripts.Client.FourDClientRuntime.
return function(root: Instance, manifest: Instance)
if not script.Parent:IsA("Model") then return end

local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FourD = ReplicatedStorage:WaitForChild("FourD")
local Common = FourD:WaitForChild("Behaviors"):WaitForChild("Gunnable"):WaitForChild("Common")
local Controller = require(Common:WaitForChild("Controller"))
local ReplicationReady = require(Common:WaitForChild("ReplicationReady"))
local Keybinds = require(FourD:WaitForChild("Common"):WaitForChild("Keybinds"))
local HelpUI = require(FourD:WaitForChild("Common"):WaitForChild("HelpUI"))
local TouchFire = require(FourD:WaitForChild("Common"):WaitForChild("TouchFire"))

local TURRET_KEYBINDS_SET_ID = "Gunnable.Turret"

local model = script.Parent
local player = Players.LocalPlayer

local function findChassisPart(root: Instance): BasePart?
	for _, desc in ipairs(root:GetDescendants()) do
		if desc.Name == "Chassis" and desc:IsA("BasePart") then
			return desc
		end
	end

	return nil
end

local hasDriverSeat = ReplicationReady.waitForAttribute(model, "Gunnable_HasDriverSeat")
local hasGunnerSeat = ReplicationReady.waitForAttribute(model, "Gunnable_HasGunnerSeat")
local hasYawMotor = ReplicationReady.waitForAttribute(model, "Gunnable_HasYawMotor")
local pitchUpDeg = ReplicationReady.waitForAttribute(model, "gunnerPitchUp")
local pitchDownDeg = ReplicationReady.waitForAttribute(model, "gunnerPitchDown")
local firstPersonMode = ReplicationReady.waitForAttribute(model, "Gunnable_FirstPerson")
local disablePitch = ReplicationReady.waitForAttribute(model, "Gunnable_DisablePitch")
local disableYaw = ReplicationReady.waitForAttribute(model, "Gunnable_DisableYaw")
local disableCrosshair = ReplicationReady.waitForAttribute(model, "Gunnable_DisableCrosshair")
local turretSpeedDeg = ReplicationReady.waitForAttribute(model, "Gunnable_TurretSpeed")
local updateTurretEvent = ReplicationReady.waitForChild(model, "UpdateTurret", "RemoteEvent")
local turretFireEvent = ReplicationReady.waitForChild(model, "TurretFire", "RemoteEvent")
local turretMount = ReplicationReady.waitForChild(model, "TurretMount", "BasePart")
local turretMotor = ReplicationReady.waitForDescendant(model, "TurretMotor", "Motor6D")
local turretYawMotor = if hasYawMotor == true
	then ReplicationReady.waitForDescendant(model, "TurretYawMotor", "Motor6D")
	else nil
local swapRoleEvent: RemoteEvent? = if hasGunnerSeat == true
	then ReplicationReady.waitForChild(model, "SwapRole", "RemoteEvent")
	else nil
local driverSeat: VehicleSeat? = if hasDriverSeat == true
	then ReplicationReady.waitForObjectValue(model, "Gunnable_DriverSeatRef", "VehicleSeat")
	else nil
local gunnerSeat: Seat? = if hasGunnerSeat == true
	then ReplicationReady.waitForObjectValue(model, "Gunnable_GunnerSeatRef", "Seat")
	else nil

if hasDriverSeat == nil
	or hasGunnerSeat == nil
	or hasYawMotor == nil
	or typeof(pitchUpDeg) ~= "number"
	or typeof(pitchDownDeg) ~= "number"
	or typeof(firstPersonMode) ~= "boolean"
	or typeof(disablePitch) ~= "boolean"
	or typeof(disableYaw) ~= "boolean"
	or typeof(disableCrosshair) ~= "boolean"
	or typeof(turretSpeedDeg) ~= "number"
	or not updateTurretEvent
	or not turretFireEvent
	or not turretMount
	or not turretMotor
	or (hasYawMotor == true and not turretYawMotor)
	or (hasGunnerSeat == true and not swapRoleEvent)
	or (hasDriverSeat == true and not driverSeat)
	or (hasGunnerSeat == true and not gunnerSeat)
then
	warn("[TurretClient] Replicated rig was not ready, aborting")
	return false
end

local pitchUpRad = math.rad(pitchUpDeg)
local pitchDownRad = math.rad(pitchDownDeg)
local turretSpeedRad = math.rad(turretSpeedDeg)

local crosshairGui = nil
local injectedFrame: Instance? = nil
local gunnerControlsGui = nil
local isGunner = false
local isDriver = false
local cameraWasModified = false
local wasInVehicle = false

local gunnerYaw = 0
local gunnerPitch = 0
local savedMouseBehavior: EnumItem? = nil
local savedMouseIcon: boolean? = nil
local cameraUpOffset = 1.5

local TURRET_UPDATE_RATE = 1 / 20
local GUNNER_CAMERA_BIND = "GunnableGunnerCamera"
local MOUSE_SENSITIVITY = 0.003
local MIN_AIM_HORIZONTAL_RANGE = 30

local CROSSHAIR_GAP = 6
local CROSSHAIR_LEN = 12
local CROSSHAIR_THICKNESS = 2
local CROSSHAIR_COLOR = Color3.new(1, 1, 1)
local CROSSHAIR_DOT_SIZE = 4

local function makeLine(parent: Instance, sizeX: number, sizeY: number, posX: number, posY: number): Frame
	local line = Instance.new("Frame")
	line.Size = UDim2.fromOffset(sizeX, sizeY)
	line.Position = UDim2.new(0.5, posX, 0.5, posY)
	line.AnchorPoint = Vector2.new(0.5, 0.5)
	line.BackgroundColor3 = CROSSHAIR_COLOR
	line.BorderSizePixel = 0
	line.Parent = parent
	return line
end

local function hardpointHudActive(): boolean
	if not model:GetAttribute(Controller.TURRET_BOUND_ATTR) then return false end

	local hardpointConfig = model:FindFirstChild("GunnableHardpointConfig")
	local enabledValue = hardpointConfig and hardpointConfig:FindFirstChild("aimHudEnabled")
	return enabledValue ~= nil and enabledValue.Value == true
end

local function launcherReticleActive(): boolean
	local launcherConfig = model:FindFirstChild("GunnableLauncherConfig")
	local enabledValue = launcherConfig and launcherConfig:FindFirstChild("reticleEnabled")
	return enabledValue ~= nil and enabledValue.Value == true
end

local function createCrosshair()
	if crosshairGui then return end
	if disableCrosshair then return end
	if hardpointHudActive() then return end
	if launcherReticleActive() then return end
	crosshairGui = Instance.new("ScreenGui")
	crosshairGui.Name = "GunnerCrosshair"
	crosshairGui.ResetOnSpawn = false
	crosshairGui.IgnoreGuiInset = true
	crosshairGui.DisplayOrder = 20

	local dot = Instance.new("Frame")
	dot.Name = "Dot"
	dot.Size = UDim2.fromOffset(CROSSHAIR_DOT_SIZE, CROSSHAIR_DOT_SIZE)
	dot.Position = UDim2.new(0.5, 0, 0.5, 0)
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.BackgroundColor3 = CROSSHAIR_COLOR
	dot.BorderSizePixel = 0
	dot.Parent = crosshairGui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = dot

	makeLine(crosshairGui, CROSSHAIR_THICKNESS, CROSSHAIR_LEN, 0, -(CROSSHAIR_GAP + CROSSHAIR_LEN / 2))
	makeLine(crosshairGui, CROSSHAIR_THICKNESS, CROSSHAIR_LEN, 0, CROSSHAIR_GAP + CROSSHAIR_LEN / 2)
	makeLine(crosshairGui, CROSSHAIR_LEN, CROSSHAIR_THICKNESS, -(CROSSHAIR_GAP + CROSSHAIR_LEN / 2), 0)
	makeLine(crosshairGui, CROSSHAIR_LEN, CROSSHAIR_THICKNESS, CROSSHAIR_GAP + CROSSHAIR_LEN / 2, 0)

	crosshairGui.Parent = player.PlayerGui
end

local function destroyCrosshair()
	if crosshairGui then
		crosshairGui:Destroy()
		crosshairGui = nil
	end
end

local function createControlFrame(keyText: string, labelText: string, layoutOrder: number): Frame
	local frame = Instance.new("Frame")
	frame.Name = keyText .. "Frame"
	frame.Size = UDim2.new(0, 0, 0, 0)
	frame.AutomaticSize = Enum.AutomaticSize.XY
	frame.BackgroundColor3 = Color3.new(0, 0, 0)
	frame.BackgroundTransparency = 0.75
	frame.BorderSizePixel = 0
	frame.LayoutOrder = layoutOrder

	local uiCorner = Instance.new("UICorner")
	uiCorner.CornerRadius = UDim.new(0, 8)
	uiCorner.Parent = frame

	local uiPadding = Instance.new("UIPadding")
	uiPadding.PaddingLeft = UDim.new(0, 4)
	uiPadding.PaddingRight = UDim.new(0, 4)
	uiPadding.Parent = frame

	local innerLayout = Instance.new("UIListLayout")
	innerLayout.Padding = UDim.new(0, 8)
	innerLayout.FillDirection = Enum.FillDirection.Horizontal
	innerLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	innerLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	innerLayout.SortOrder = Enum.SortOrder.LayoutOrder
	innerLayout.Parent = frame

	local gradient = Instance.new("UIGradient")
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	gradient.Parent = frame

	local keyFrame = Instance.new("Frame")
	keyFrame.Name = "KeyboardLabel"
	keyFrame.Size = UDim2.fromOffset(24, 24)
	keyFrame.AutomaticSize = Enum.AutomaticSize.X
	keyFrame.BackgroundColor3 = Color3.new(1, 1, 1)
	keyFrame.BackgroundTransparency = 0
	keyFrame.BorderSizePixel = 0
	keyFrame.LayoutOrder = 0
	keyFrame.Parent = frame

	local keyPad = Instance.new("UIPadding")
	keyPad.PaddingLeft = UDim.new(0, 8)
	keyPad.PaddingRight = UDim.new(0, 8)
	keyPad.Parent = keyFrame

	local keyCorner = Instance.new("UICorner")
	keyCorner.CornerRadius = UDim.new(0, 4)
	keyCorner.Parent = keyFrame

	local keyLabel = Instance.new("TextLabel")
	keyLabel.Size = UDim2.fromOffset(0, 24)
	keyLabel.AutomaticSize = Enum.AutomaticSize.X
	keyLabel.BackgroundTransparency = 1
	keyLabel.Text = keyText
	keyLabel.TextColor3 = Color3.new(0, 0, 0)
	keyLabel.TextSize = 20
	keyLabel.Font = Enum.Font.Oswald
	keyLabel.Parent = keyFrame

	local controlLabel = Instance.new("TextLabel")
	controlLabel.Name = "ControlLabel"
	controlLabel.Size = UDim2.fromOffset(0, 24)
	controlLabel.AutomaticSize = Enum.AutomaticSize.X
	controlLabel.BackgroundTransparency = 1
	controlLabel.Text = labelText
	controlLabel.TextColor3 = Color3.new(1, 1, 1)
	controlLabel.TextSize = 24
	controlLabel.Font = Enum.Font.Oswald
	controlLabel.LayoutOrder = 1
	controlLabel.Parent = frame

	return frame
end

local function removeInjectedFrame()
	if injectedFrame then
		injectedFrame:Destroy()
		injectedFrame = nil
	end
end

local function injectSwapIntoControlsGui()
	removeInjectedFrame()
	if not isDriver or not gunnerSeat then return end

	task.spawn(function()
		local gui = player.PlayerGui:WaitForChild("ControlsGui", 3)
		if not gui or not isDriver then return end

		local controls = gui:FindFirstChild("Controls")
		if not controls then return end

		local templateFrame = controls:FindFirstChild("ExitFrame") or controls:FindFirstChild("CameraFrame")
		if templateFrame then
			local newFrame = templateFrame:Clone()
			newFrame.Name = "SwapRoleFrame"
			newFrame.LayoutOrder = -1

			local kl = newFrame:FindFirstChild("KeyboardLabel")
			if kl then
				kl.Visible = true
				local tl = kl:FindFirstChild("TextLabel")
				if tl then tl.Text = "F" end
			end

			local gl = newFrame:FindFirstChild("GamepadLabel")
			if gl then gl.Visible = false end

			local cl = newFrame:FindFirstChild("ControlLabel")
			if cl then cl.Text = "Gunner" end

			newFrame.Parent = controls
			injectedFrame = newFrame
		else
			local newFrame = createControlFrame("F", "Gunner", -1)
			newFrame.Parent = controls
			injectedFrame = newFrame
		end
	end)
end

local function destroyGunnerControls()
	if gunnerControlsGui then
		gunnerControlsGui:Destroy()
		gunnerControlsGui = nil
	end
end

local function createGunnerControls()
	destroyGunnerControls()

	gunnerControlsGui = Instance.new("ScreenGui")
	gunnerControlsGui.Name = "GunnerControlsGui"
	gunnerControlsGui.ResetOnSpawn = false
	gunnerControlsGui.IgnoreGuiInset = false
	gunnerControlsGui.DisplayOrder = 0

	local guiPad = Instance.new("UIPadding")
	guiPad.PaddingLeft = UDim.new(0, 30)
	guiPad.PaddingRight = UDim.new(0, 30)
	guiPad.PaddingBottom = UDim.new(0, 30)
	guiPad.PaddingTop = UDim.new(0, 30)
	guiPad.Parent = gunnerControlsGui

	local controls = Instance.new("Frame")
	controls.Name = "Controls"
	controls.Size = UDim2.new(0, 0, 0, 0)
	controls.AutomaticSize = Enum.AutomaticSize.XY
	controls.Position = UDim2.new(0, 0, 1, 0)
	controls.AnchorPoint = Vector2.new(0, 1)
	controls.BackgroundTransparency = 1
	controls.Parent = gunnerControlsGui

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	layout.VerticalAlignment = Enum.VerticalAlignment.Top
	layout.Parent = controls

	if gunnerSeat then
		createControlFrame("F", "Driver", 0).Parent = controls
	end
	createControlFrame("E", "Exit", 1).Parent = controls

	gunnerControlsGui.Parent = player.PlayerGui
end

local function updateGunnerCamera()
	local delta = UserInputService:GetMouseDelta()
	gunnerYaw = gunnerYaw - delta.X * MOUSE_SENSITIVITY
	gunnerPitch = math.clamp(gunnerPitch - delta.Y * MOUSE_SENSITIVITY, -pitchDownRad, pitchUpRad)

	local chassis = findChassisPart(model)
	if not chassis or not turretMount then return end

	local cameraPos = turretMount.Position + chassis.CFrame.UpVector * cameraUpOffset
	local rotCF = CFrame.Angles(0, gunnerYaw, 0) * CFrame.Angles(gunnerPitch, 0, 0)
	local localForward = rotCF.LookVector
	local worldForward = chassis.CFrame:VectorToWorldSpace(localForward)

	local cam = workspace.CurrentCamera
	if cam then
		cam.CFrame = CFrame.lookAt(cameraPos, cameraPos + worldForward)
		cam.Focus = CFrame.new(cameraPos + worldForward * 100)
	end
end

local function beginScriptableCamera(upOffset: number)
	cameraUpOffset = upOffset
	local cam = workspace.CurrentCamera
	if cam then
		cam.CameraType = Enum.CameraType.Scriptable
	end

	savedMouseBehavior = UserInputService.MouseBehavior
	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	savedMouseIcon = UserInputService.MouseIconEnabled
	UserInputService.MouseIconEnabled = false
	gunnerYaw = 0
	gunnerPitch = 0
	cameraWasModified = true
	RunService:BindToRenderStep(GUNNER_CAMERA_BIND, Enum.RenderPriority.Camera.Value, updateGunnerCamera)
end

local function enterGunnerCamera()
	beginScriptableCamera(1.5)
end

local function enterFirstPersonCamera()
	beginScriptableCamera(0)
end

local function restoreCamera()
	if not cameraWasModified then return end
	cameraWasModified = false

	RunService:UnbindFromRenderStep(GUNNER_CAMERA_BIND)
	UserInputService.MouseBehavior = savedMouseBehavior or Enum.MouseBehavior.Default
	savedMouseBehavior = nil
	UserInputService.MouseIconEnabled = if savedMouseIcon ~= nil then savedMouseIcon else true
	savedMouseIcon = nil

	local cam = workspace.CurrentCamera
	if cam then
		cam.CameraType = Enum.CameraType.Custom
		local humanoid = player.Character and player.Character:FindFirstChildWhichIsA("Humanoid")
		if humanoid then
			cam.CameraSubject = humanoid
		end
	end
end

local function gunnerExitHandler(_, inputState: Enum.UserInputState)
	if inputState ~= Enum.UserInputState.Begin then return end
	if not isGunner then return end

	local character = player.Character
	if not character then return end
	local humanoid = character:FindFirstChildWhichIsA("Humanoid")
	if not humanoid then return end

	humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)

	local primaryPart = character.PrimaryPart
	if primaryPart then
		local joints = primaryPart:GetJoints()
		for _, joint in joints do
			if joint.Name == "SeatWeld" then
				repeat
					joint.AncestryChanged:Wait()
				until not joint:IsDescendantOf(game)
				break
			end
		end
	end

	local chassis = findChassisPart(model)
	local exitAtt = chassis and chassis:FindFirstChild("ExitLocationAttachment")
	if exitAtt then
		task.defer(function()
			character:PivotTo(exitAtt.WorldCFrame)
		end)
	end

	humanoid.PlatformStand = true
	task.wait()
	humanoid.PlatformStand = false
end

local gunnerExitBindHandle: Keybinds.BindActionsHandle? = nil

local function bindGunnerExit()
	if gunnerExitBindHandle then return end
	gunnerExitBindHandle = Keybinds.bindActions(TURRET_KEYBINDS_SET_ID, {
		ExitGunner = function(state: Enum.UserInputState, _)
			return gunnerExitHandler(nil, state)
		end,
	})
end

local function unbindGunnerExit()
	if gunnerExitBindHandle then
		gunnerExitBindHandle:Destroy()
		gunnerExitBindHandle = nil
	end
end

local function checkRoles()
	local gunnerOccupant = if gunnerSeat then gunnerSeat.Occupant else nil
	local seatedAsGunner = gunnerOccupant ~= nil and gunnerOccupant.Parent == player.Character
	local overrideLocal = Controller.localIsOverride(model)

	isGunner = seatedAsGunner or (overrideLocal and not seatedAsGunner)

	if driverSeat and driverSeat.Occupant then
		isDriver = driverSeat.Occupant.Parent == player.Character
	else
		isDriver = false
	end
end

local gunnerPrompt = model:FindFirstChild("GunnerPrompt", true)
local promptSuppressConn: RBXScriptConnection? = nil

local function suppressGunnerPrompt()
	if not gunnerPrompt then return end
	gunnerPrompt.Enabled = false
	if not promptSuppressConn then
		promptSuppressConn = gunnerPrompt:GetPropertyChangedSignal("Enabled"):Connect(function()
			if (isDriver or isGunner) and gunnerPrompt.Enabled then
				gunnerPrompt.Enabled = false
			end
		end)
	end
end

local function unsuppressGunnerPrompt()
	if promptSuppressConn then
		promptSuppressConn:Disconnect()
		promptSuppressConn = nil
	end
end

local gunHiddenLocally = false

local function hideGunForLocalPlayer()
	if gunHiddenLocally then return end
	gunHiddenLocally = true
	local gunModel = model:FindFirstChild("gun")
	if gunModel then
		for _, part in ipairs(gunModel:GetDescendants()) do
			if part:IsA("BasePart") then
				part.LocalTransparencyModifier = 1
			end
		end
	end

	if turretMount then
		turretMount.LocalTransparencyModifier = 1
	end
end

local function showGunForLocalPlayer()
	if not gunHiddenLocally then return end
	gunHiddenLocally = false
	local gunModel = model:FindFirstChild("gun")
	if gunModel then
		for _, part in ipairs(gunModel:GetDescendants()) do
			if part:IsA("BasePart") then
				part.LocalTransparencyModifier = 0
			end
		end
	end

	if turretMount then
		turretMount.LocalTransparencyModifier = 0
	end
end

local turretHiddenLocally = false

local function hideTurretForLocalPlayer()
	if turretHiddenLocally then return end
	turretHiddenLocally = true
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.LocalTransparencyModifier = 1
		end
	end
end

local function showTurretForLocalPlayer()
	if not turretHiddenLocally then return end
	turretHiddenLocally = false
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.LocalTransparencyModifier = 0
		end
	end
end

local function onRoleChanged()
	local inVehicle = isGunner or isDriver

	if isGunner then
		createCrosshair()
		enterGunnerCamera()
		bindGunnerExit()
		createGunnerControls()
		removeInjectedFrame()
		hideGunForLocalPlayer()
		suppressGunnerPrompt()
	elseif isDriver then
		if not model:GetAttribute("gunnerActive") then
			createCrosshair()
		end

		if firstPersonMode then
			enterFirstPersonCamera()
			hideTurretForLocalPlayer()
		else
			restoreCamera()
			showGunForLocalPlayer()
		end

		unbindGunnerExit()
		destroyGunnerControls()
		injectSwapIntoControlsGui()
		suppressGunnerPrompt()
	end

	if wasInVehicle and not inVehicle then
		destroyCrosshair()
		destroyGunnerControls()
		removeInjectedFrame()
		unbindGunnerExit()
		showGunForLocalPlayer()
		showTurretForLocalPlayer()
		unsuppressGunnerPrompt()
		restoreCamera()
	end

	if isGunner then
		HelpUI.applyRole(model, "Gunnable.Turret", "HelpUI_GunnerState")
	else
		HelpUI.clearRole(model)
	end

	wasInVehicle = inVehicle
end

if gunnerSeat then
	gunnerSeat:GetPropertyChangedSignal("Occupant"):Connect(function()
		checkRoles()
		onRoleChanged()
	end)
end

if driverSeat then
	driverSeat:GetPropertyChangedSignal("Occupant"):Connect(function()
		checkRoles()
		onRoleChanged()
	end)
end

model:GetAttributeChangedSignal(Controller.OVERRIDE_ATTR):Connect(function()
	checkRoles()
	onRoleChanged()
end)

model:GetAttributeChangedSignal("gunnerActive"):Connect(function()
	if isDriver then
		if model:GetAttribute("gunnerActive") then
			destroyCrosshair()
		else
			createCrosshair()
		end
	end
end)

local roleSwapKey = Keybinds.getKeyboardKey(TURRET_KEYBINDS_SET_ID, "RoleSwap")
local roleSwapGamepadKey = Keybinds.getGamepadKey(TURRET_KEYBINDS_SET_ID, "RoleSwap")

UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if processed then return end

	if input.KeyCode == roleSwapKey or input.KeyCode == roleSwapGamepadKey then
		if (isDriver or isGunner) and swapRoleEvent then
			swapRoleEvent:FireServer()
		end
	end
end)

local function getScreenCenterTarget(): Vector3?
	local camera = workspace.CurrentCamera
	if not camera then return nil end

	local vs = camera.ViewportSize
	local ray = camera:ViewportPointToRay(vs.X / 2, vs.Y / 2)

	local params = RaycastParams.new()
	params.FilterDescendantsInstances = { model, player.Character }
	params.FilterType = Enum.RaycastFilterType.Exclude

	local result = workspace:Raycast(ray.Origin, ray.Direction * 1000, params)
	local targetPoint = if result then result.Position else ray.Origin + ray.Direction * 1000
	if not turretMount then return targetPoint end

	local chassis = findChassisPart(model)
	local up = if chassis then chassis.CFrame.UpVector else Vector3.yAxis
	local offset = targetPoint - turretMount.Position
	local verticalReach = offset:Dot(up)
	if (offset - up * verticalReach).Magnitude >= MIN_AIM_HORIZONTAL_RANGE then return targetPoint end

	local forward = ray.Direction.Unit
	local flatForward = forward - up * forward:Dot(up)
	if flatForward.Magnitude < 0.001 then return nil end

	return turretMount.Position + flatForward.Unit * MIN_AIM_HORIZONTAL_RANGE + up * verticalReach
end

local function calcTurretAngles(targetPoint: Vector3): (number?, number?)
	local chassis = findChassisPart(model)
	if not chassis or not turretMount then return nil, nil end

	local turretWorldPos = turretMount.Position
	local dirToTarget = targetPoint - turretWorldPos
	if dirToTarget.Magnitude < 0.01 then return nil, nil end
	dirToTarget = dirToTarget.Unit

	local cf = chassis.CFrame
	local horizontalDir = dirToTarget - cf.UpVector * dirToTarget:Dot(cf.UpVector)
	if horizontalDir.Magnitude < 0.001 then return nil, nil end
	horizontalDir = horizontalDir.Unit

	local yaw = math.atan2(-horizontalDir:Dot(cf.RightVector), horizontalDir:Dot(cf.LookVector))
	local pitch = math.asin(math.clamp(dirToTarget:Dot(cf.UpVector), -1, 1))
	pitch = math.clamp(pitch, -pitchDownRad, pitchUpRad)

	return yaw, pitch
end

local lastTurretUpdate = 0
local driverAimYaw = 0
local driverAimPitch = 0

local function isLocalControlling(): boolean
	if isGunner then return true end
	if isDriver and not model:GetAttribute("gunnerActive") then return true end

	return false
end

local function lockAxes(yaw: number, pitch: number): (number, number)
	return if disableYaw then 0 else yaw, if disablePitch then 0 else pitch
end

RunService.Heartbeat:Connect(function()
	local now = tick()
	if now - lastTurretUpdate < TURRET_UPDATE_RATE then return end

	if isGunner then
		lastTurretUpdate = now
		updateTurretEvent:FireServer(lockAxes(gunnerYaw, gunnerPitch))
	elseif isDriver and not model:GetAttribute("gunnerActive") then
		lastTurretUpdate = now
		updateTurretEvent:FireServer(lockAxes(driverAimYaw, driverAimPitch))
	end
end)

local baseC0Value = ReplicationReady.waitForChild(model, "TurretBaseC0", "CFrameValue")
local turretBaseC0: CFrame? = if baseC0Value and baseC0Value:IsA("CFrameValue")
	then baseC0Value.Value
	elseif turretMotor then turretMotor.C0
	else nil

local yawBaseC0Value = if hasYawMotor == true
	then ReplicationReady.waitForChild(model, "TurretYawBaseC0", "CFrameValue")
	else nil
local yawMotor: Motor6D? = if turretYawMotor and turretYawMotor:IsA("Motor6D") then turretYawMotor else nil
local turretYawBaseC0: CFrame? = if yawBaseC0Value and yawBaseC0Value:IsA("CFrameValue")
	then yawBaseC0Value.Value
	elseif yawMotor then yawMotor.C0
	else nil

local smoothedYaw = model:GetAttribute("turretYaw") or 0
local smoothedPitch = model:GetAttribute("turretPitch") or 0

local function approachAngle(current: number, target: number, maxStep: number): number
	local delta = math.atan2(math.sin(target - current), math.cos(target - current))
	return current + math.clamp(delta, -maxStep, maxStep)
end

if turretMotor and turretMotor:IsA("Motor6D") and turretBaseC0 then
	RunService.RenderStepped:Connect(function(deltaTime: number)
		local targetYaw: number
		local targetPitch: number
		if isGunner then
			targetYaw, targetPitch = gunnerYaw, gunnerPitch
		elseif isDriver and not model:GetAttribute("gunnerActive") then
			local targetPoint = getScreenCenterTarget()
			if targetPoint then
				local aimYaw, aimPitch = calcTurretAngles(targetPoint)
				if aimYaw and aimPitch then
					driverAimYaw, driverAimPitch = aimYaw, aimPitch
				end
			end

			targetYaw, targetPitch = driverAimYaw, driverAimPitch
		else
			targetYaw = model:GetAttribute("turretYaw") or 0
			targetPitch = model:GetAttribute("turretPitch") or 0
		end

		targetPitch = math.clamp(targetPitch, -pitchDownRad, pitchUpRad)
		targetYaw, targetPitch = lockAxes(targetYaw, targetPitch)

		local maxStep = turretSpeedRad * deltaTime
		smoothedYaw = approachAngle(smoothedYaw, targetYaw, maxStep)
		smoothedPitch = approachAngle(smoothedPitch, targetPitch, maxStep)

		local appliedYaw, appliedPitch = lockAxes(smoothedYaw, smoothedPitch)
		if yawMotor and turretYawBaseC0 then
			yawMotor.C0 = turretYawBaseC0 * CFrame.Angles(0, appliedYaw, 0)
			turretMotor.C0 = turretBaseC0 * CFrame.Angles(appliedPitch, 0, 0)
		else
			turretMotor.C0 = turretBaseC0 * CFrame.Angles(0, appliedYaw, 0) * CFrame.Angles(appliedPitch, 0, 0)
		end
	end)
end

if turretFireEvent then
	local function getLauncherAimHints(): (Vector3?, Vector3?)
		local originRef = model:FindFirstChild("Gunnable_LauncherOrigin")
		local attachment = if originRef and originRef:IsA("ObjectValue") then originRef.Value else nil
		if not attachment or not attachment:IsA("Attachment") then return nil, nil end

		local worldCFrame = attachment.WorldCFrame

		return worldCFrame.Position, worldCFrame.LookVector
	end

	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed then return end
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
		if not isLocalControlling() then return end

		turretFireEvent:FireServer(getLauncherAimHints())
	end)

	-- Touch has no mouse button, so the shot rides on the Fire button in
	-- whatever cluster the gunner already has on screen -- for a tank, the
	-- driving cluster, since the driver aims the turret. One shell per press,
	-- matching the click, so only the press edge is wired.
	if UserInputService.TouchEnabled then
		local touchFire = TouchFire.new()
		touchFire.Began = function()
			if not isLocalControlling() then return end

			turretFireEvent:FireServer(getLauncherAimHints())
		end

		RunService.Heartbeat:Connect(function()
			touchFire:sync(isLocalControlling())
		end)
	end
end

checkRoles()
onRoleChanged()

player.CharacterRemoving:Connect(function()
	destroyCrosshair()
	destroyGunnerControls()
	removeInjectedFrame()
	unbindGunnerExit()
	showGunForLocalPlayer()
	showTurretForLocalPlayer()
	unsuppressGunnerPrompt()
	isGunner = false
	isDriver = false
	wasInVehicle = false
	restoreCamera()
end)

end
