--[[
	File: Replication.luau
]]--

-- Root

local Replication = {}

-- Constants

local REMOTE_NAMES = {
	"Fire",
	"Reload",
	"ReloadCancel",
	"ShotReplicate",
	"ReloadStarted",
	"ReloadAck",
	"AmmoChanged",
}

-- Public Functions

local function attachRemotes(tool: Tool): Folder
	local folder = Instance.new("Folder")
	folder.Name = "Remotes"

	for _, remoteName in REMOTE_NAMES do
		local remote = Instance.new("RemoteEvent")
		remote.Name = remoteName
		remote.Parent = folder
	end

	folder.Parent = tool
	return folder
end

Replication.attachRemotes = attachRemotes

-- Return

return Replication
