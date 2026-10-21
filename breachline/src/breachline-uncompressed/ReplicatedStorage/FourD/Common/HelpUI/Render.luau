--[[
	File: HelpUI/Render.luau

	The view layer for the HelpUI system. Owns a single ScreenGui (cloned from
	the shared HelpScreen asset) and renders keybind rows. Swaps row visuals
	between keyboard text and gamepad icons based on the player's last input
	type; touch input hides the overlay entirely.

	`AddBind` is intentionally signature-compatible with
	`Keybinds.applyToHelpScreen`, which drives rows by calling
	`view:AddBind(id, key, description)`.
]]--

-- Root

local Render = {}
Render.__index = Render

-- Roblox Services

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

-- Dependencies

local FourD = ReplicatedStorage:WaitForChild("FourD")
local Dumpster = require(FourD.Libs.Dumpster)

-- Constants

local TEMPLATE_PATH = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("UI"):WaitForChild("HelpScreen")
local KEY_CODE_REPLACEMENTS: { [Enum.KeyCode]: string } = {
	[Enum.KeyCode.Space] = "Spacebar",
	[Enum.KeyCode.LeftShift] = "LShift",
	[Enum.KeyCode.RightShift] = "RShift",
	[Enum.KeyCode.LeftControl] = "LCtrl",
	[Enum.KeyCode.RightControl] = "RCtrl",
	[Enum.KeyCode.LeftAlt] = "LAlt",
	[Enum.KeyCode.RightAlt] = "RAlt",
}

-- Local Functions

local function getStringForKeyCode(keyCode: Enum.KeyCode): string
	if KEY_CODE_REPLACEMENTS[keyCode] then
		return KEY_CODE_REPLACEMENTS[keyCode]
	end

	local str = UserInputService:GetStringForKeyCode(keyCode)
	if str == "" then
		return keyCode.Name
	end

	return str
end

local function resolveBindKey(key: BindKey): (Enum.KeyCode?, Enum.KeyCode?)
	if typeof(key) == "EnumItem" then
		return key, key
	end

	return key.Keyboard, key.Gamepad
end

local function categorizeInputType(inputType: Enum.UserInputType): InputDevice
	local name = inputType.Name
	if string.find(name, "Gamepad") then
		return "Gamepad"
	end

	if name == "Touch" then
		return "Touch"
	end

	return "Keyboard"
end

-- Public Methods

---Adds a keybind row. The newest bind renders at the top of the list.
function Render:AddBind(id: string, key: BindKey, description: string)
	assert(self._binds[id] == nil, `bind '{id}' already exists`)

	local keyboardKey, gamepadKey = resolveBindKey(key)
	assert(keyboardKey ~= nil or gamepadKey ~= nil, `bind '{id}' must declare Keyboard or Gamepad`)

	local row = self._templateRow:Clone()
	local gamepadLabel = row.GamepadLabel
	local keyboardLabel = row.KeyboardLabel
	local controlLabel = row.ControlLabel
	local keyboardText = keyboardLabel.TextLabel

	controlLabel.Text = description
	if gamepadKey ~= nil then
		gamepadLabel.Image = UserInputService:GetImageForKeyCode(gamepadKey)
	end

	if keyboardKey ~= nil then
		keyboardText.Text = string.upper(getStringForKeyCode(keyboardKey))
	end

	self._orderCounter -= 1
	row.LayoutOrder = self._orderCounter

	local entry: BindEntry = {
		Row = row,
		GamepadLabel = gamepadLabel,
		KeyboardLabel = keyboardLabel,
		HasKeyboard = keyboardKey ~= nil,
		HasGamepad = gamepadKey ~= nil,
	}

	self:_applyDeviceVisibilityToEntry(entry)

	row.Parent = self._controlsFrame
	self._binds[id] = entry
end

---Removes a previously-added row by id. No-op if it does not exist.
function Render:RemoveBind(id: string)
	local entry = self._binds[id]
	if not entry then return end

	entry.Row:Destroy()
	self._binds[id] = nil
end

---Removes every row and resets ordering.
function Render:Clear()
	for id, entry in self._binds do
		entry.Row:Destroy()
		self._binds[id] = nil
	end

	self._orderCounter = 0
end

---Sets whether the overlay is visible. Touch input always hides it.
function Render:SetVisible(visible: boolean)
	self._visible = visible
	self:_refreshScreenEnabled()
end

---Destroys class data, cleans up connections, and destroys tracked objects.
function Render:Destroy()
	assert(table.isfrozen(self) == false, "cannot destroy an already-destroyed Render")
	self._mainDump:Destroy()
	for k in self do rawset(self, k, nil) end

	table.freeze(self)
end

-- Private Methods

function Render:_applyDeviceVisibilityToEntry(entry: BindEntry)
	local device = self._inputDevice
	local hasKeyForDevice = (device == "Gamepad" and entry.HasGamepad)
		or (device == "Keyboard" and entry.HasKeyboard)
	entry.Row.Visible = hasKeyForDevice
	entry.GamepadLabel.Visible = device == "Gamepad" and entry.HasGamepad
	entry.KeyboardLabel.Visible = device == "Keyboard" and entry.HasKeyboard
end

function Render:_refreshScreenEnabled()
	self._screenGui.Enabled = self._visible and self._inputDevice ~= "Touch"
end

function Render:_refreshInputDevice()
	self._inputDevice = categorizeInputType(UserInputService:GetLastInputType())

	for _, entry in self._binds do
		self:_applyDeviceVisibilityToEntry(entry)
	end

	self:_refreshScreenEnabled()
end

-- Constructor

function Render.new(): RenderInstance
	local localPlayer = Players.LocalPlayer
	assert(localPlayer ~= nil, "HelpUI.Render.new() must be called on the client")

	local playerGui = localPlayer:WaitForChild("PlayerGui")
	local screenGui = TEMPLATE_PATH:Clone()
	screenGui.ResetOnSpawn = false
	local controlsFrame = screenGui.Controls
	local templateRow = controlsFrame.Template
	templateRow.Parent = screenGui
	templateRow.Visible = false

	local self = setmetatable({}, Render)

	self._mainDump = Dumpster.new()
	self._screenGui = screenGui
	self._controlsFrame = controlsFrame
	self._templateRow = templateRow
	self._binds = {}
	self._orderCounter = 0
	self._visible = false
	self._inputDevice = categorizeInputType(UserInputService:GetLastInputType())

	self._mainDump:Add(screenGui)
	self._mainDump:Connect(UserInputService.LastInputTypeChanged, function()
		self:_refreshInputDevice()
	end)

	self:_refreshScreenEnabled()
	screenGui.Parent = playerGui

	return self
end

-- Types

export type InputDevice = "Gamepad" | "Keyboard" | "Touch"

export type BindKey = Enum.KeyCode | { Keyboard: Enum.KeyCode?, Gamepad: Enum.KeyCode? }

export type BindEntry = {
	Row: Frame,
	GamepadLabel: ImageLabel,
	KeyboardLabel: Frame,
	HasKeyboard: boolean,
	HasGamepad: boolean,
}

export type RenderInstance = typeof(setmetatable(
	{} :: {
		_mainDump: typeof(Dumpster.new()),
		_screenGui: ScreenGui,
		_controlsFrame: Frame,
		_templateRow: Frame,
		_binds: { [string]: BindEntry },
		_orderCounter: number,
		_visible: boolean,
		_inputDevice: InputDevice,
	},
	Render
))

-- Return

return Render
