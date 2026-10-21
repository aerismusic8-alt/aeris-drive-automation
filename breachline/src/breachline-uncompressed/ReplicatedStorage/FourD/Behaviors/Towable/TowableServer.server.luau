if not script.Parent:IsA("Model") then return end

local CollectionService = game:GetService("CollectionService")

local RECEIVER_TAG = "TowHitchReceiver"
local MAX_ATTACH_DISTANCE = 7.5
local TOGGLE_COOLDOWN = 0.5
local RECEIVER_IN_USE_ATTRIBUTE = "HitchInUse"
local FIXED_ALIGNMENT_ATTRIBUTE = "FixedAlignment"
local UNHITCH_CLEAR_TIMEOUT = 5
local TOWED_MASS_ATTRIBUTE = "HitchTowedMass"

local model = script.Parent

local maxAttachDistance = model:GetAttribute("HitchMaxAttachDistance") or MAX_ATTACH_DISTANCE

local hitchAttachment = model:FindFirstChild("HitchAttachment", true)
if not hitchAttachment then return end

local hitchPrompt = model:FindFirstChild("HitchPrompt", true)
local toggleEvent = model:FindFirstChild("HitchToggleEvent")
local seatRef = model:FindFirstChild("Towable_DriverSeatRef")

local activeConstraint = nil
local savedHitchCFrame = nil
local coupledReceiver: Attachment? = nil
local noCollisionConstraints: { NoCollisionConstraint } = {}
local lastToggleTime = 0

local function computeTowedMass(towableModel: Instance): number
	local total = 0
	for _, descendant in ipairs(towableModel:GetDescendants()) do
		if descendant:IsA("BasePart") and not descendant.Massless then
			total += descendant:GetMass()
		end
	end
	return total
end

local function findNearbyReceiver(position: Vector3, maxDist: number?): Attachment?
	local searchDist = maxDist or MAX_ATTACH_DISTANCE
	local best, bestDist = nil, searchDist
	for _, receiverAtt in ipairs(CollectionService:GetTagged(RECEIVER_TAG)) do
		if not receiverAtt:IsA("Attachment") then continue end
		if receiverAtt:IsDescendantOf(model) then continue end
		if not receiverAtt:IsDescendantOf(workspace) then continue end
		if receiverAtt:GetAttribute(RECEIVER_IN_USE_ATTRIBUTE) then continue end

		local dist = (receiverAtt.WorldCFrame.Position - position).Magnitude
		if dist < bestDist then
			best = receiverAtt
			bestDist = dist
		end
	end
	return best
end

local function setPromptText(connected: boolean)
	if hitchPrompt then
		hitchPrompt.ActionText = if connected then "Disconnect" else "Connect"
	end
end

local function getTowableModel(receiver: Attachment): Instance?
	local ownerRef = receiver:FindFirstChild("Towable_OwnerModel")
	if ownerRef and ownerRef:IsA("ObjectValue") then
		return ownerRef.Value
	end
	return nil
end

local function applyNoCollisions(towableModel: Instance)
	local towerParts: { BasePart } = {}
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant.CanCollide then
			table.insert(towerParts, descendant)
		end
	end

	for _, towablePart in ipairs(towableModel:GetDescendants()) do
		if not (towablePart:IsA("BasePart") and towablePart.CanCollide) then continue end
		for _, towerPart in ipairs(towerParts) do
			local noCollision = Instance.new("NoCollisionConstraint")
			noCollision.Part0 = towerPart
			noCollision.Part1 = towablePart
			noCollision.Parent = towerPart
			table.insert(noCollisionConstraints, noCollision)
		end
	end
end

local function scheduleNoCollisionClear(receiver: Attachment?)
	local constraints = noCollisionConstraints
	noCollisionConstraints = {}
	if #constraints == 0 then return end

	task.spawn(function()
		local elapsed = 0
		while elapsed < UNHITCH_CLEAR_TIMEOUT do
			if not receiver or not receiver.Parent then break end
			local separation = (hitchAttachment.WorldCFrame.Position - receiver.WorldCFrame.Position).Magnitude
			if separation >= maxAttachDistance then break end
			elapsed += task.wait()
		end

		for _, noCollision in ipairs(constraints) do
			noCollision:Destroy()
		end
	end)
end

local function disconnect()
	if not activeConstraint then return end

	activeConstraint:Destroy()
	activeConstraint = nil

	local receiver = coupledReceiver
	if receiver then
		receiver:SetAttribute(RECEIVER_IN_USE_ATTRIBUTE, nil)
		local towerRef = receiver:FindFirstChild("Towable_TowerModel")
		if towerRef then towerRef:Destroy() end
		coupledReceiver = nil
	end

	scheduleNoCollisionClear(receiver)

	if savedHitchCFrame then
		hitchAttachment.CFrame = savedHitchCFrame
		savedHitchCFrame = nil
	end

	model:SetAttribute(TOWED_MASS_ATTRIBUTE, 0)
	model:SetAttribute("hitchConnected", false)
	setPromptText(false)
end

local function connect()
	local receiver = findNearbyReceiver(hitchAttachment.WorldCFrame.Position, maxAttachDistance)
	if not receiver then
		warn("[Towable] No nearby receiver found")
		return
	end

	local towableModel = getTowableModel(receiver)

	if not receiver:GetAttribute(FIXED_ALIGNMENT_ATTRIBUTE) then
		savedHitchCFrame = hitchAttachment.CFrame
		local hitchWorld = hitchAttachment.WorldPosition
		hitchAttachment.WorldPosition = Vector3.new(hitchWorld.X, receiver.WorldCFrame.Position.Y, hitchWorld.Z)
	end

	if towableModel and towableModel:IsA("Model") and not towableModel:GetAttribute("trackActive") then
		local gap = hitchAttachment.WorldCFrame.Position - receiver.WorldCFrame.Position
		towableModel:PivotTo(CFrame.new(gap) * towableModel:GetPivot())
	end

	local constraint = Instance.new("BallSocketConstraint")
	constraint.Name = "HitchConstraint"
	constraint.Attachment0 = hitchAttachment
	constraint.Attachment1 = receiver
	constraint.Parent = hitchAttachment.Parent
	activeConstraint = constraint

	receiver:SetAttribute(RECEIVER_IN_USE_ATTRIBUTE, true)
	coupledReceiver = receiver

	local towerRef = Instance.new("ObjectValue")
	towerRef.Name = "Towable_TowerModel"
	towerRef.Value = model
	towerRef.Parent = receiver

	if towableModel then
		applyNoCollisions(towableModel)
	end

	model:SetAttribute(TOWED_MASS_ATTRIBUTE, if towableModel then computeTowedMass(towableModel) else 0)
	model:SetAttribute("hitchConnected", true)
	setPromptText(true)
end

local function toggle()
	if activeConstraint then
		disconnect()
	else
		connect()
	end
end

if hitchPrompt then
	hitchPrompt.Triggered:Connect(toggle)
end

if toggleEvent and toggleEvent:IsA("RemoteEvent") then
	local function isDriver(firingPlayer: Player): boolean
		local seat = if seatRef and seatRef:IsA("ObjectValue") then seatRef.Value else nil
		seat = seat or model:FindFirstChildWhichIsA("VehicleSeat", true)
		if not seat then return false end

		local occupant = seat.Occupant
		if not occupant then return false end

		local character = firingPlayer.Character
		return character ~= nil and occupant.Parent == character
	end

	toggleEvent.OnServerEvent:Connect(function(firingPlayer: Player)
		if not isDriver(firingPlayer) then return end

		local now = os.clock()
		if now - lastToggleTime < TOGGLE_COOLDOWN then return end
		lastToggleTime = now

		toggle()
	end)
end
