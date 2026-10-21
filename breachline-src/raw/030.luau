--!strict

local ContextActionService = game:GetService("ContextActionService")
local RunService = game:GetService("RunService")

local Types = require(script.Types)

export type BindKey = Types.BindKey
export type TouchFace = Types.TouchFace
export type TouchSpec = Types.TouchSpec
export type BindSpec = Types.BindSpec
export type BindSet = Types.BindSet
export type ResolvedBind = Types.ResolvedBind
export type ResolvedBindSet = Types.ResolvedBindSet
export type ActionHandler = Types.ActionHandler
export type BindActionsOpts = Types.BindActionsOpts
export type ApplyToHelpScreenOpts = Types.ApplyToHelpScreenOpts
export type BindActionsHandle = Types.BindActionsHandle

local Keybinds = {}

local registry: { [string]: BindSet } = {}
local actionNameOwners: { [string]: string } = {}
local frozen = false
local warnedAttributes: { [string]: boolean } = {}

local function vwarn(message: string, ...: any)
	warn(string.format("[Keybinds] " .. message, ...))
end

local function validateBindSet(set: BindSet)
	assert(type(set) == "table", "BindSet must be a table")
	assert(type(set.Id) == "string" and set.Id ~= "", "BindSet.Id must be a non-empty string")
	assert(type(set.ActionPrefix) == "string" and set.ActionPrefix ~= "", "BindSet.ActionPrefix must be a non-empty string")
	assert(type(set.Binds) == "table", "BindSet.Binds must be a table")

	if registry[set.Id] then
		error(string.format("[Keybinds] duplicate set id '%s'", set.Id), 0)
	end

	local seenBindIds: { [string]: boolean } = {}
	local seenTouchFaces: { [string]: string } = {}
	for _, spec in set.Binds do
		assert(type(spec.Id) == "string" and spec.Id ~= "", "BindSpec.Id must be a non-empty string")
		assert(type(spec.Description) == "string", "BindSpec.Description must be a string")
		if spec.Touch then
			assert(
				table.find({ "Up", "Right", "Down", "Left", "Exit" }, spec.Touch.Face) ~= nil,
				string.format("BindSpec.Touch.Face is invalid for '%s/%s'", set.Id, spec.Id)
			)
			assert(
				spec.Touch.Icon == nil or type(spec.Touch.Icon) == "string",
				string.format("BindSpec.Touch.Icon must be a string for '%s/%s'", set.Id, spec.Id)
			)
			local existingBindId = seenTouchFaces[spec.Touch.Face]
			assert(
				existingBindId == nil,
				string.format(
					"touch face '%s' is used by both '%s' and '%s' in set '%s'",
					spec.Touch.Face,
					existingBindId or "",
					spec.Id,
					set.Id
				)
			)
			seenTouchFaces[spec.Touch.Face] = spec.Id
		end
		if seenBindIds[spec.Id] then
			error(string.format("[Keybinds] duplicate bind id '%s' in set '%s'", spec.Id, set.Id), 0)
		end

		seenBindIds[spec.Id] = true

		if spec.Keyboard == nil and spec.Gamepad == nil then
			error(string.format("[Keybinds] bind '%s/%s' must declare Keyboard or Gamepad", set.Id, spec.Id), 0)
		end

		local actionName = set.ActionPrefix .. spec.Id
		local existing = actionNameOwners[actionName]
		if existing then
			error(string.format(
				"[Keybinds] action name collision '%s' between set '%s' and set '%s'",
				actionName, existing, set.Id
			), 0)
		end

		actionNameOwners[actionName] = set.Id
	end
end

local function register(set: BindSet)
	if frozen then
		error("[Keybinds] cannot register after freeze", 0)
	end

	validateBindSet(set)
	registry[set.Id] = set
end

local function autoDiscover()
	local setsFolder = script:FindFirstChild("Sets")
	if not setsFolder then
		return
	end

	for _, child in setsFolder:GetChildren() do
		if child:IsA("ModuleScript") then
			local ok, result = pcall(require :: (Instance) -> any, child)
			if not ok then
				vwarn("failed to require Set '%s': %s", child.Name, tostring(result))
				continue
			end

			local okReg, errReg = pcall(register :: (any) -> any, result)
			if not okReg then
				vwarn("failed to register Set '%s': %s", child.Name, tostring(errReg))
			end
		end
	end
end

local function resolveAttrSource(instance: Instance): Instance
	local inputs = instance:FindFirstChild("Inputs")
	if inputs then
		return inputs
	end

	return instance
end

local function resolveAttrKey(instance: Instance, attrName: string?, fallback: BindKey?): BindKey?
	if attrName == nil then
		return fallback
	end

	local source = resolveAttrSource(instance)
	local raw = source:GetAttribute(attrName)
	if raw == nil then
		return fallback
	end

	if typeof(raw) == "EnumItem" then
		return raw :: any
	end

	if type(raw) == "string" then
		local resolved = (Enum.KeyCode :: any)[raw]
		if resolved then
			return resolved
		end

		local warnKey = source:GetFullName() .. "/" .. attrName
		if not warnedAttributes[warnKey] then
			warnedAttributes[warnKey] = true
			vwarn("attribute '%s' on %s has invalid KeyCode name '%s', using fallback", attrName, source:GetFullName(), raw)
		end
	end

	return fallback
end

function Keybinds.getSet(setId: string): BindSet
	local set = registry[setId]
	if not set then
		error(string.format("[Keybinds] unknown set '%s'", setId), 2)
	end

	return set
end

function Keybinds.getBind(setId: string, bindId: string): BindSpec
	local set = Keybinds.getSet(setId)
	for _, spec in set.Binds do
		if spec.Id == bindId then
			return spec
		end
	end

	error(string.format("[Keybinds] unknown bind '%s' in set '%s'", bindId, setId), 2)
end

function Keybinds.getAllSetIds(): { string }
	local ids: { string } = {}
	for id in registry do
		table.insert(ids, id)
	end

	table.sort(ids)
	return ids
end

function Keybinds.resolve(setId: string, instance: Instance?): ResolvedBindSet
	local set = Keybinds.getSet(setId)
	local resolved: ResolvedBindSet = {
		Id = set.Id,
		ActionPrefix = set.ActionPrefix,
		Binds = {},
	}
	for _, spec in set.Binds do
		local kbKey: BindKey? = spec.Keyboard
		local gpKey: Enum.KeyCode? = spec.Gamepad
		if instance and spec.OverrideAttribute then
			kbKey = resolveAttrKey(instance, spec.OverrideAttribute.Keyboard, kbKey)
			local resolvedGp = resolveAttrKey(instance, spec.OverrideAttribute.Gamepad, gpKey)
			if resolvedGp == nil then
				gpKey = nil
			elseif typeof(resolvedGp) == "EnumItem" and (resolvedGp :: any).EnumType == Enum.KeyCode then
				gpKey = resolvedGp :: Enum.KeyCode
			end
		end

		table.insert(resolved.Binds, {
			Id = spec.Id,
			Description = spec.Description,
			Category = spec.Category,
			Keyboard = kbKey,
			Gamepad = gpKey,
			Touch = spec.Touch,
		})
	end

	return resolved
end

function Keybinds.getKeyboardKey(setId: string, bindId: string, instance: Instance?): BindKey?
	local spec = Keybinds.getBind(setId, bindId)
	if instance and spec.OverrideAttribute then
		return resolveAttrKey(instance, spec.OverrideAttribute.Keyboard, spec.Keyboard)
	end

	return spec.Keyboard
end

function Keybinds.getGamepadKey(setId: string, bindId: string, instance: Instance?): Enum.KeyCode?
	local spec = Keybinds.getBind(setId, bindId)
	if instance and spec.OverrideAttribute then
		local resolved = resolveAttrKey(instance, spec.OverrideAttribute.Gamepad, spec.Gamepad)
		if resolved == nil or typeof(resolved) == "EnumItem" then
			return resolved :: any
		end
	end

	return spec.Gamepad
end

local function filterContains(filter: { string }?, id: string): boolean
	if filter == nil then
		return true
	end

	for _, candidate in filter do
		if candidate == id then
			return true
		end
	end

	return false
end

local function toHelpScreenKey(kbKey: BindKey?, gpKey: Enum.KeyCode?): any?
	local kbIsKeyCode = typeof(kbKey) == "EnumItem" and (kbKey :: any).EnumType == Enum.KeyCode
	if not kbIsKeyCode then
		kbKey = nil
	end

	if kbKey and gpKey then
		return { Keyboard = kbKey, Gamepad = gpKey }
	elseif kbKey then
		return { Keyboard = kbKey }
	elseif gpKey then
		return { Gamepad = gpKey }
	end

	return nil
end

function Keybinds.applyToHelpScreen(setId: string, helpScreen: any, instance: Instance?, opts: ApplyToHelpScreenOpts?): { string }
	assert(RunService:IsClient(), "[Keybinds] applyToHelpScreen requires client context")
	local resolved = Keybinds.resolve(setId, instance)
	local filter = opts and opts.Filter
	local prefix = (opts and opts.IdPrefix) or ""
	local addedIds: { string } = {}
	for _, bind in resolved.Binds do
		if not filterContains(filter, bind.Id) then
			continue
		end

		local key = toHelpScreenKey(bind.Keyboard, bind.Gamepad)
		if key == nil then
			continue
		end

		local rowId = prefix .. resolved.Id .. "/" .. bind.Id
		helpScreen:AddBind(rowId, key, bind.Description)
		table.insert(addedIds, rowId)
	end

	return addedIds
end

local function asCasArg(key: BindKey?): any?
	if key == nil then
		return nil
	end

	return key
end

function Keybinds.bindActions(setId: string, handlers: { [string]: ActionHandler }, instance: Instance?, opts: BindActionsOpts?): BindActionsHandle
	assert(RunService:IsClient(), "[Keybinds] bindActions requires client context")
	local resolved = Keybinds.resolve(setId, instance)
	local priority = opts and opts.Priority
	local createTouch = (opts and opts.CreateTouchButton) or false
	for _, bind in resolved.Binds do
		if handlers[bind.Id] and bind.Touch then
			createTouch = false
			break
		end
	end
	local nameSuffix = (opts and opts.ActionNameSuffix) or ""
	local boundActionNames: { string } = {}
	local touchConfig: any = {
		Priority = opts and opts.TouchPriority,
		HideJump = opts and opts.HideJump,
		BlockTools = opts and opts.BlockTools,
	}
	local hasTouchActions = false

	for _, bind in resolved.Binds do
		local handler = handlers[bind.Id]
		if handler == nil then
			continue
		end

		local kbArg = asCasArg(bind.Keyboard)
		local gpArg = asCasArg(bind.Gamepad)
		if kbArg == nil and gpArg == nil then
			continue
		end

		local keys: { BindKey } = {}
		if kbArg ~= nil then
			table.insert(keys, kbArg)
		end

		if gpArg ~= nil then
			table.insert(keys, gpArg)
		end

		local actionName = resolved.ActionPrefix .. bind.Id .. nameSuffix
		local wrapped = function(_: string, state: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
			local result = handler(state, input)
			if result == nil then
				return Enum.ContextActionResult.Pass
			end

			return result
		end

		if not (opts and opts.TouchOnly) then
			if priority ~= nil then
				ContextActionService:BindActionAtPriority(actionName, wrapped, createTouch, priority, table.unpack(keys))
			else
				ContextActionService:BindAction(actionName, wrapped, createTouch, table.unpack(keys))
			end

			table.insert(boundActionNames, actionName)
		end

		if bind.Touch then
			local face = bind.Touch.Face
			if touchConfig[face] ~= nil then
				vwarn("touch face '%s' is declared more than once in active set '%s'; later bind wins", face, setId)
			end
			touchConfig[face] = {
				Label = bind.Description,
				Icon = bind.Touch.Icon,
				Handler = function(state: Enum.UserInputState, input: InputObject?)
					handler(state, input :: InputObject)
				end,
			}
			hasTouchActions = true
		end
	end

	local touchHandle: any = nil
	if hasTouchActions then
		local TouchControls = require(script.Parent.TouchControls)
		if opts and opts.TouchJump then
			TouchControls.withJump(touchConfig, if instance and instance:IsA("Tool") then instance else nil)
		end
		touchHandle = TouchControls.bind(touchConfig)
	end

	local handle = {} :: BindActionsHandle
	function handle:Destroy()
		if touchHandle then
			touchHandle:Destroy()
			touchHandle = nil
		end
		for _, actionName in boundActionNames do
			ContextActionService:UnbindAction(actionName)
		end

		table.clear(boundActionNames)
	end

	return handle
end

autoDiscover()
frozen = true
table.freeze(registry)
table.freeze(Keybinds)

return Keybinds
