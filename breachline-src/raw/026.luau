--[[
	File: HelpUI/Client.luau

	Client-side singleton for the HelpUI system. Owns one Render (overlay) for
	the LocalPlayer and shows the binds of the single currently-active state.

	Two ways a state becomes active:
		- Local: a cloned behavior controller calls `setState`/`showSet`.
		- Remote: the server pushes a state via the per-model RemoteEvent
		  (discovered by CollectionService tag).

	Only one state is visible at a time (last writer wins). `clearState` hides
	the overlay only if the calling model currently owns it.
]]--

-- Root

local Client = {}

-- Roblox Services

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Dependencies

local FourD = ReplicatedStorage:WaitForChild("FourD")
local Dumpster = require(FourD.Libs.Dumpster)
local Keybinds = require(FourD.Common.Keybinds)
local Constants = require(script.Parent.Constants)
local Render = require(script.Parent.Render)
local Serialize = require(script.Parent.Serialize)
local Types = require(script.Parent.Types)

-- Module State

local render: Render.RenderInstance = nil
local activeModel: Instance? = nil
local modelDumps: { [Instance]: any } = {}

-- Local Functions

local function getRender(): Render.RenderInstance
	if not render then
		render = Render.new()
	end

	return render
end

local function keyCodeFromName(name: string?): Enum.KeyCode?
	if typeof(name) ~= "string" or name == "" then
		return nil
	end

	for _, keyCode in Enum.KeyCode:GetEnumItems() do
		if keyCode.Name == name then
			return keyCode
		end
	end

	return nil
end

local function renderDefinition(model: Instance, definition: Types.StateDefinition, keyPrefix: string)
	local view = getRender()
	view:Clear()

	for index, source in definition.Sources do
		if source.Type == "Set" then
			local ok, err = pcall(function()
				Keybinds.applyToHelpScreen(source.SetId, view, model, {
					Filter = source.Filter,
					IdPrefix = `{keyPrefix}{index}/`,
				})
			end)
			if not ok then
				warn(`[HelpUI] failed to apply set '{source.SetId}': {err}`)
			end
		else
			local keyboardKey = keyCodeFromName(source.Keyboard)
			local gamepadKey = keyCodeFromName(source.Gamepad)
			if keyboardKey or gamepadKey then
				local ok, err = pcall(function()
					view:AddBind(`{keyPrefix}manual/{source.Id}`, {
						Keyboard = keyboardKey,
						Gamepad = gamepadKey,
					}, source.Description)
				end)
				if not ok then
					warn(`[HelpUI] failed to add manual bind '{source.Id}': {err}`)
				end
			end
		end
	end

	view:SetVisible(true)
end

-- Public Methods

---Shows a registered (serialized) state by name. nil hides this model's state.
function Client.setState(model: Instance, stateName: string?)
	if stateName == nil then
		Client.clearState(model)
		return
	end

	local definition = Serialize.read(model, stateName)
	if not definition then
		warn(`[HelpUI] no serialized state '{stateName}' on {model:GetFullName()}`)
		return
	end

	activeModel = model
	renderDefinition(model, definition, `{stateName}/`)
end

---Shows an ephemeral single-Set overlay (standalone behaviors).
function Client.showSet(model: Instance, setId: string, opts: { Filter: { string }? }?)
	local filter = opts and opts.Filter
	activeModel = model
	renderDefinition(model, {
		Sources = { { Type = "Set", SetId = setId, Filter = filter } },
	}, "set/")
end

---Hides the overlay if this model currently owns the active state.
function Client.clearState(model: Instance)
	if activeModel ~= model then return end

	activeModel = nil
	if render then
		render:Clear()
		render:SetVisible(false)
	end
end

---Applies a behavior's default help state for a role it just entered.
---Stands down if a capability suppresses defaults; otherwise honors an
---injected state name (capability composite), falling back to the behavior's
---own Set.
function Client.applyRole(model: Instance, ownSetId: string, roleAttribute: string, opts: { Filter: { string }? }?)
	if model:GetAttribute(Constants.SuppressDefaultAttribute) then return end

	local injected = model:GetAttribute(roleAttribute)
	if typeof(injected) == "string" then
		Client.setState(model, injected)
	else
		Client.showSet(model, ownSetId, opts)
	end
end

---Clears a behavior's default help state on role exit. No-op when the
---capability suppresses defaults (it owns the overlay via server push).
function Client.clearRole(model: Instance)
	if model:GetAttribute(Constants.SuppressDefaultAttribute) then return end

	Client.clearState(model)
end

-- Discovery (server push listener)

local function onServerPush(model: Instance, payload: any)
	if payload == nil or payload == false then
		Client.clearState(model)
	elseif typeof(payload) == "string" then
		Client.setState(model, payload)
	end
end

local function registerModel(model: Instance)
	if modelDumps[model] then return end

	local remote = model:WaitForChild(Constants.RemoteName, 5)
	if not remote or not remote:IsA("RemoteEvent") then return end

	local dump = Dumpster.new()
	dump:Connect(remote.OnClientEvent, function(payload: any)
		onServerPush(model, payload)
	end)
	modelDumps[model] = dump
end

local function unregisterModel(model: Instance)
	local dump = modelDumps[model]
	if dump then
		dump:Destroy()
		modelDumps[model] = nil
	end

	Client.clearState(model)
end

local function resetOnRespawn()
	activeModel = nil
	if render then
		render:Clear()
		render:SetVisible(false)
	end
end

Players.LocalPlayer.CharacterAdded:Connect(resetOnRespawn)

for _, model in CollectionService:GetTagged(Constants.Tag) do
	task.spawn(registerModel, model)
end

CollectionService:GetInstanceAddedSignal(Constants.Tag):Connect(function(model: Instance)
	task.spawn(registerModel, model)
end)

CollectionService:GetInstanceRemovedSignal(Constants.Tag):Connect(unregisterModel)

-- Return

return Client
/