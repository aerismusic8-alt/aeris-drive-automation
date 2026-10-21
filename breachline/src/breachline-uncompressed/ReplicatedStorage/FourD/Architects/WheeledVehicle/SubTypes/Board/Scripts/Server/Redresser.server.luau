--[[
	File: Redresser.server.luau
]]--

-- Dependencies

local Constants = require(script.Parent.Parent.Constants)

-- Object References

local boardRig = script.Parent.Parent.Parent
local board = boardRig.Parent
local chassis = boardRig:WaitForChild("Chassis")
local redressOrientation = chassis:WaitForChild("RedressOrientation")
local redressAttachment = chassis:WaitForChild("RedressAttachment")
local config = board:WaitForChild("BoardConfig")
local remotes = boardRig:WaitForChild("Remotes")
local redressRemote = remotes:WaitForChild(Constants.REDRESS_REMOTE_NAME)
local ownerValue = boardRig:WaitForChild(Constants.OWNER_VALUE_NAME)

-- Constants

local REDRESS_DURATION = 0.5
local REDRESS_LIFT_HEIGHT = 4

-- State

local redressing = false

-- Local Functions

local function startRedress()
	if redressing then return end

	local now = os.clock()
	local lastRedress = boardRig:GetAttribute(Constants.LAST_REDRESS_ATTRIBUTE) or 0
	local cooldownValue = config:FindFirstChild("RedressCooldown")
	local cooldown = if cooldownValue and cooldownValue:IsA("NumberValue") then cooldownValue.Value else 2.0
	if now - lastRedress < cooldown then return end

	boardRig:SetAttribute(Constants.LAST_REDRESS_ATTRIBUTE, now)
	redressing = true

	local forwardWorld = chassis.CFrame.LookVector
	local flatForward = Vector3.new(forwardWorld.X, 0, forwardWorld.Z)
	if flatForward.Magnitude < 1e-3 then
		flatForward = Vector3.new(0, 0, -1)
	else
		flatForward = flatForward.Unit
	end

	local targetPos = chassis.Position + Vector3.new(0, REDRESS_LIFT_HEIGHT, 0)
	redressAttachment.WorldCFrame = CFrame.lookAt(targetPos, targetPos + flatForward)
	redressOrientation.Enabled = true

	task.delay(REDRESS_DURATION, function()
		redressOrientation.Enabled = false
		redressing = false
	end)
end

local function onRedressRemote(player: Player)
	if ownerValue.Value ~= player then return end

	startRedress()
end

local function initialize()
	redressRemote.OnServerEvent:Connect(onRedressRemote)
end

initialize()
