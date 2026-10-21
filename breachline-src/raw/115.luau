--[[
	File: Firearm2.luau
]]--

-- Root

local Firearm2 = {}

-- Dependencies

local Pistol = require(script.SubTypes.Pistol)
local Sniper = require(script.SubTypes.Sniper)
local Types = require(script.Common.Types)

-- Object References

local ScriptsFolder = script:FindFirstChild("Scripts")

-- Local Functions

local function CloneScripts(tool: Tool, sourceFolder: Folder)
	local scriptsClone = sourceFolder:Clone()
	scriptsClone.Name = "ClientModules"

	local controller = scriptsClone:FindFirstChild("Firearm2Controller")
	local serverScript = scriptsClone:FindFirstChild("Firearm2Server")
	local ikHand = scriptsClone:FindFirstChild("Firearm2IKHand")

	if controller then
		controller.Parent = tool
		-- Client logic is a ClientComponent ModuleScript (no Disabled); the
		-- runtime requires it. Only a real (server) BaseScript needs enabling.
		if controller:IsA("BaseScript") then
			controller.Disabled = false
		end
	end

	if serverScript then
		serverScript.Parent = tool
		serverScript.Disabled = false
	end

	if ikHand then
		ikHand.Parent = tool
		if ikHand:IsA("BaseScript") then
			ikHand.Disabled = false
		end
	end

	for _, child in scriptsClone:GetChildren() do
		if not child:IsA("ModuleScript") then
			child:Destroy()
		end
	end

	scriptsClone.Parent = tool
end

-- Public Functions

function Firearm2.buildPistol(bodyModel: Model, params: Types.PistolSetupParams): any
	local originalParent = bodyModel.Parent
	local instance = Pistol.new(bodyModel, params)

	if ScriptsFolder then
		CloneScripts(instance.Tool, ScriptsFolder)
	end

	instance.Tool.Parent = originalParent
	return instance
end

function Firearm2.buildSniper(bodyModel: Model, params: Types.SniperSetupParams): any
	local originalParent = bodyModel.Parent
	local instance = Sniper.new(bodyModel, params)

	if ScriptsFolder then
		CloneScripts(instance.Tool, ScriptsFolder)
	end

	instance.Tool.Parent = originalParent
	return instance
end

-- Types

export type PistolSetupParams = Types.PistolSetupParams
export type PistolSchema = Types.PistolSchema
export type PistolInstance = Types.PistolInstance
export type SniperSetupParams = Types.SniperSetupParams
export type SniperSchema = Types.SniperSchema
export type SniperInstance = Types.SniperInstance

-- Return

return Firearm2
s