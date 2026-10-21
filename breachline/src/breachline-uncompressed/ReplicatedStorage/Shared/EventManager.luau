local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Events = ReplicatedStorage:WaitForChild("Events")

local function createRemoteEvent(name: string): RemoteEvent
	-- Idempotent: if an event with this name already exists (e.g. another server
	-- script already called init()), return the existing one instead of creating
	-- a duplicate. Duplicates would silently break consumers, since
	-- Events:WaitForChild(name) only returns one of the matching children.
	local existing = Events:FindFirstChild(name)
	if existing and existing:IsA("RemoteEvent") then
		return existing
	end
	local event = Instance.new("RemoteEvent")
	event.Name = name
	event.Parent = Events
	return event
end

local function getEvent(name: string): RemoteEvent
	return Events:WaitForChild(name) :: RemoteEvent
end

local ServerEventManager = {}
local ClientEventManager = {}

-- Safe to call from multiple server scripts: createRemoteEvent() reuses any
-- existing RemoteEvent of the same name instead of creating duplicates.
function ServerEventManager.init()
	print("Initializing EventManager")
	createRemoteEvent("AddBbox") -- client -> server
	createRemoteEvent("CloneBbox") -- client -> server
	createRemoteEvent("UpdateBbox") -- client -> server
	createRemoteEvent("RemoveBbox") -- client -> server
	createRemoteEvent("TeleportToSpawn") -- client -> server
end

-- AddBbox
function ClientEventManager.addBbox()
	getEvent("AddBbox"):FireServer()
end

function ServerEventManager.registerAddBbox(callback: (player: Player) -> ())
	getEvent("AddBbox").OnServerEvent:Connect(callback)
end

-- CloneBbox
function ClientEventManager.cloneBbox(originalPart: BasePart, finalCFrame: CFrame)
	getEvent("CloneBbox"):FireServer(originalPart, finalCFrame)
end

function ServerEventManager.registerCloneBbox(
	callback: (player: Player, originalPart: BasePart, finalCFrame: CFrame) -> ()
)
	getEvent("CloneBbox").OnServerEvent:Connect(callback)
end

-- RemoveBbox
function ClientEventManager.removeBbox(selectedBlock: BasePart)
	getEvent("RemoveBbox"):FireServer(selectedBlock)
end

function ServerEventManager.registerRemoveBbox(callback: (player: Player, selectedBlock: BasePart) -> ())
	getEvent("RemoveBbox").OnServerEvent:Connect(callback)
end

-- UpdateBbox
function ClientEventManager.updateBbox(partToUpdate: BasePart, newSize: Vector3, newCFrame: CFrame)
	getEvent("UpdateBbox"):FireServer(partToUpdate, newSize, newCFrame)
end

function ServerEventManager.registerUpdateBbox(callback: (
	player: Player,
	partToUpdate: BasePart,
	newSize: Vector3,
	newCFrame: CFrame
) -> ())
	getEvent("UpdateBbox").OnServerEvent:Connect(callback)
end

-- TeleportToSpawn
function ClientEventManager.teleportToSpawn()
	getEvent("TeleportToSpawn"):FireServer()
end

function ServerEventManager.registerTeleportToSpawn(callback: (player: Player) -> ())
	getEvent("TeleportToSpawn").OnServerEvent:Connect(callback)
end

if RunService:IsServer() then
	return ServerEventManager
elseif RunService:IsClient() then
	return ClientEventManager
else
	error("EventManager can only be used on the server or client")
end
