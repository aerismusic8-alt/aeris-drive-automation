--[[
	File: BuildController.luau
]]--

-- Root

local BuildController = {}

-- Constants

local UNMOUNT_REMOTE_NAME = "UnmountRequest"
local SWAP_REMOTE_NAME = "SwapSeatRequest"

-- Local Functions

local function vwarn(...: any)
	warn(`[{script.Name}]`, ...)
end

local function enableScripts(container: Instance)
	for _, descendant in container:GetDescendants() do
		if descendant:IsA("BaseScript") then
			descendant.Disabled = false
		end
	end
end

-- Public Functions

function BuildController.writeAttributes(root: BasePart, attributes: { [string]: any })
	for key, value in attributes do
		root:SetAttribute(key, value)
	end
	root:SetAttribute("PilotUserId", 0)
end

function BuildController.createUnmountRemote(wrapperModel: Model): RemoteEvent
	local remote = Instance.new("RemoteEvent")
	remote.Name = UNMOUNT_REMOTE_NAME
	remote.Parent = wrapperModel
	return remote
end

function BuildController.createSwapRemote(wrapperModel: Model): RemoteEvent
	local remote = Instance.new("RemoteEvent")
	remote.Name = SWAP_REMOTE_NAME
	remote.Parent = wrapperModel
	return remote
end

function BuildController.cloneScripts(wrapperModel: Model, scriptsFolder: Instance)
	local clonedScripts = scriptsFolder:Clone()
	clonedScripts.Parent = wrapperModel
	enableScripts(clonedScripts)
end

function BuildController.rig(config: ControllerRigConfig): RemoteEvent
	BuildController.writeAttributes(config.Root, config.Attributes)

	local remote = BuildController.createUnmountRemote(config.WrapperModel)

	if not config.ScriptsFolder then
		vwarn("ScriptsFolder not provided; client controller will not be installed")
		return remote
	end

	BuildController.cloneScripts(config.WrapperModel, config.ScriptsFolder)
	return remote
end

-- Types

export type ControllerRigConfig = {
	WrapperModel: Model,
	Root: BasePart,
	Attributes: { [string]: any },
	ScriptsFolder: Instance?,
}

-- Return

return BuildController
