--[[
	File: HelpUI/init.luau

	Context-aware facade for the HelpUI system: a single, self-managed keybind
	overlay driven by named states. States are registered (and serialized onto
	a model) by the server; either the server or the client can choose which
	state a given client sees.

	Server API (capability bind / server scripts):
		HelpUI.registerState(model, stateName, definition)
		HelpUI.setStateFor(model, player, stateName?)   -- nil hides

	Client API (cloned behavior controllers):
		HelpUI.showSet(model, setId, opts?)             -- ephemeral single Set
		HelpUI.setState(model, stateName?)              -- nil hides
		HelpUI.clearState(model)
]]--

-- Root

local HelpUI = {}

-- Roblox Services

local RunService = game:GetService("RunService")

-- Dependencies

local Types = require(script.Types)

-- Types

export type StateDefinition = Types.StateDefinition
export type Source = Types.Source

-- Implementation

if RunService:IsServer() then
	local CollectionService = game:GetService("CollectionService")
	local Constants = require(script.Constants)
	local Serialize = require(script.Serialize)

	---Serializes a state definition onto the model so any client can render it.
	function HelpUI.registerState(model: Instance, stateName: string, definition: Types.StateDefinition)
		Serialize.write(model, stateName, definition)
		Serialize.ensureRemote(model)
		CollectionService:AddTag(model, Constants.Tag)
	end

	---Tells one client which state to show for this model. nil hides it.
	function HelpUI.setStateFor(model: Instance, player: Player, stateName: string?)
		local remote = Serialize.ensureRemote(model)
		remote:FireClient(player, stateName or false)
	end
else
	local Client = require(script.Client)

	HelpUI.showSet = Client.showSet
	HelpUI.setState = Client.setState
	HelpUI.clearState = Client.clearState
	HelpUI.applyRole = Client.applyRole
	HelpUI.clearRole = Client.clearRole
end

-- Return

return HelpUI
