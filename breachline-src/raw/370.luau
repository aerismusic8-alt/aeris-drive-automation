-- Utility class to get instances from the workspace

local WorkspaceManager = {}

function WorkspaceManager.getMainSpawnPoint()
	return workspace:WaitForChild("Regions"):WaitForChild("MainSpawnPoint")
end

function WorkspaceManager.getUpDirection()
	return WorkspaceManager.getMainSpawnPoint():WaitForChild("UpDirection")
end

return WorkspaceManager
.