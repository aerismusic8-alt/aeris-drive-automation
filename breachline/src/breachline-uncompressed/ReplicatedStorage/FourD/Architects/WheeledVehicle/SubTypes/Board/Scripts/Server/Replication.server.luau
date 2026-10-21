--[[
	File: Replication.server.luau
]]--

-- Dependencies

local Constants = require(script.Parent.Parent.Constants)

-- Object References

local boardRig = script.Parent.Parent.Parent
local board = boardRig.Parent
local config = board:WaitForChild("BoardConfig")
local remotes = boardRig:WaitForChild("Remotes")
local ollieRemote = remotes:WaitForChild(Constants.OLLIE_REMOTE_NAME)
local ownerValue = boardRig:WaitForChild(Constants.OWNER_VALUE_NAME)

-- Local Functions

local function onOllieRemote(player: Player)
	if ownerValue.Value ~= player then return end

	local now = os.clock()
	local lastOllie = boardRig:GetAttribute(Constants.LAST_OLLIE_ATTRIBUTE) or 0
	local cooldownValue = config:FindFirstChild("OllieCooldown")
	local cooldown = if cooldownValue and cooldownValue:IsA("NumberValue") then cooldownValue.Value else 0.4
	if now - lastOllie < cooldown then return end

	boardRig:SetAttribute(Constants.LAST_OLLIE_ATTRIBUTE, now)
end

local function initialize()
	ollieRemote.OnServerEvent:Connect(onOllieRemote)
end

initialize()
