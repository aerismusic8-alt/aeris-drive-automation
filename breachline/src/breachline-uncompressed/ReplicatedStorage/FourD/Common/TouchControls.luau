--!strict

--[[
	Shared mounted-vehicle touch HUD.

	Roblox owns movement on the left through Humanoid.MoveDirection. FourD owns
	only Exit plus four action faces on the right. Multiple vehicle systems may
	register at once (for example a car controller plus a mounted gun); the most
	recent registration that supplies a face owns that face until destroyed.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Icons = require(script.Icons)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local FACE_NAMES = { "Up", "Right", "Down", "Left" }
local IGNORE_INPUT_TAG = "IgnoreInput"

export type InputHandler = (state: Enum.UserInputState, input: InputObject?) -> ()

export type Action = {
	--- Shown when the action has no icon, and used as the accessibility name.
	--- Keep it a plain English phrase so experience translations can pick it up.
	Label: string,
	Icon: Icons.IconName?,
	Handler: InputHandler,
	--- Optional gate. The face stays hidden while this returns false, so an
	--- action whose subject went away cannot leave a dead button behind.
	Available: (() -> boolean)?,
}

export type Config = {
	Priority: number?,
	Exit: Action?,
	Up: Action?,
	Right: Action?,
	Down: Action?,
	Left: Action?,
	HideJump: boolean?,
	--- Unequips Tools and prevents re-equipping while this control is active.
	BlockTools: boolean?,
	--- A Tool that implements the mount itself, such as a skateboard.
	AllowedTool: Tool?,
}

export type Handle = {
	Destroy: (self: Handle) -> (),
}

type Registration = {
	Id: number,
	Config: Config,
}

type ButtonState = {
	Button: TextButton,
	Action: Action?,
	Input: InputObject?,
	PressedAction: Action?,
}

local registrations: { Registration } = {}
local nextRegistrationId = 0
local gui: ScreenGui? = nil
local buttonStates: { [string]: ButtonState } = {}
local savedJumpVisibility: { [GuiObject]: boolean } = {}
local jumpVisibilityConnections: { [GuiObject]: RBXScriptConnection } = {}
local inputEndedConnection: RBXScriptConnection? = nil
local preferredInputConnection: RBXScriptConnection? = nil
local descendantAddedConnection: RBXScriptConnection? = nil
local viewportConnection: RBXScriptConnection? = nil
local characterAddedConnection: RBXScriptConnection? = nil
local characterChildAddedConnection: RBXScriptConnection? = nil
local humanoidSeatedConnection: RBXScriptConnection? = nil
local humanoidDiedConnection: RBXScriptConnection? = nil
local dropRemote: RemoteEvent? = nil
local shouldHideJump: () -> boolean
local shouldBlockTools: () -> boolean
local refresh: () -> ()

local function isTouchPreferred(): boolean
	return UserInputService.PreferredInput == Enum.PreferredInput.Touch
end

local function isLocalCharacterAlive(): boolean
	local character = player.Character
	local humanoid = character and character:FindFirstChildWhichIsA("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

---Resolved per press rather than cached at load, since the authority script
---creates the remote at runtime and it may replicate after this module loads.
local function getDropRemote(): RemoteEvent?
	if dropRemote and dropRemote.Parent then return dropRemote end
	local found = script.Parent:FindFirstChild("DropToolRequest")
	dropRemote = if found and found:IsA("RemoteEvent") then found else nil
	return dropRemote
end

local function styleButton(button: TextButton)
	button.AutoButtonColor = true
	button.AutoLocalize = true
	button.BackgroundColor3 = Color3.fromRGB(30, 37, 48)
	button.BackgroundTransparency = 0.18
	button.BorderSizePixel = 0
	button.FontFace = Font.new(
		"rbxasset://fonts/families/Oswald.json",
		Enum.FontWeight.Regular,
		Enum.FontStyle.Normal
	)
	button.TextColor3 = Color3.new(1, 1, 1)
	button.TextScaled = true
	button.TextWrapped = true

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = button

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(10, 13, 18)
	stroke.Transparency = 0.1
	stroke.Thickness = 1
	stroke.Parent = button

	local textConstraint = Instance.new("UITextSizeConstraint")
	textConstraint.MinTextSize = 12
	textConstraint.MaxTextSize = 20
	textConstraint.Parent = button
end

local function finishPress(state: ButtonState, inputState: Enum.UserInputState)
	local input = state.Input
	local action = state.PressedAction
	state.Input = nil
	state.PressedAction = nil
	if input then
		input:RemoveTag(IGNORE_INPUT_TAG)
	end
	if action then
		action.Handler(inputState, input)
	end
end

local function wireButton(name: string, button: TextButton)
	local state: ButtonState = {
		Button = button,
		Action = nil,
		Input = nil,
		PressedAction = nil,
	}
	buttonStates[name] = state

	button.InputBegan:Connect(function(input: InputObject)
		if state.Input or not state.Action then return end
		if input.UserInputType ~= Enum.UserInputType.Touch
			and input.UserInputType ~= Enum.UserInputType.MouseButton1
		then
			return
		end

		input:AddTag(IGNORE_INPUT_TAG)
		state.Input = input
		state.PressedAction = state.Action
		state.PressedAction.Handler(Enum.UserInputState.Begin, input)
	end)

	-- Also released here so a finger that slides off the button cannot leave the
	-- action latched on if the UserInputService event is missed.
	button.InputEnded:Connect(function(input: InputObject)
		if state.Input == input then
			finishPress(state, Enum.UserInputState.End)
		end
	end)
end

---Draws an action's glyph, falling back to its text label when it has no icon.
local function applyActionAppearance(state: ButtonState, action: Action?)
	local button = state.Button
	local iconName = if action then action.Icon else nil

	if button:GetAttribute("Icon") ~= iconName then
		Icons.apply(button, iconName, button.TextColor3)
		button:SetAttribute("Icon", iconName)
	end

	-- Text is only drawn for actions without a glyph. Glyphs need no
	-- translation; any text that does show is left to the experience's
	-- localization to translate.
	button.Text = if action and not iconName then action.Label else ""
	-- Kept regardless so diagnostics and tests can identify a face by action.
	button:SetAttribute("Action", if action then action.Label else nil)
end

local function finishAllPresses(inputState: Enum.UserInputState)
	for _, state in buttonStates do
		if state.PressedAction then
			finishPress(state, inputState)
		end
	end
end

local function createGui(): ScreenGui
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "FourDTouchControls"
	screenGui.ResetOnSpawn = false
	screenGui.DisplayOrder = 1000
	-- Respect the device cutout, but not CoreUI's top-bar exclusion: Exit belongs
	-- on the same row as Roblox's menu controls.
	screenGui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local exit = Instance.new("TextButton")
	exit.Name = "Exit"
	exit.AnchorPoint = Vector2.new(1, 0)
	exit.Position = UDim2.new(1, -18, 0, 18)
	exit.Size = UDim2.fromOffset(104, 46)
	exit.ZIndex = 3
	styleButton(exit)
	exit.Parent = screenGui
	wireButton("Exit", exit)

	local diamond = Instance.new("Frame")
	diamond.Name = "Diamond"
	diamond.AnchorPoint = Vector2.new(1, 1)
	diamond.Position = UDim2.new(1, -18, 1, -18)
	diamond.Size = UDim2.fromOffset(190, 190)
	diamond.BackgroundTransparency = 1
	diamond.Parent = screenGui

	local positions = {
		Up = UDim2.fromOffset(64, 0),
		Right = UDim2.fromOffset(128, 64),
		Down = UDim2.fromOffset(64, 128),
		Left = UDim2.fromOffset(0, 64),
	}
	for _, name in FACE_NAMES do
		local button = Instance.new("TextButton")
		button.Name = name
		button.Position = positions[name]
		button.Size = UDim2.fromOffset(62, 62)
		button.ZIndex = 3
		styleButton(button)
		button.Parent = diamond
		wireButton(name, button)
	end

	screenGui.Parent = playerGui
	return screenGui
end

local function restoreJumpButton()
	for jumpButton, connection in jumpVisibilityConnections do
		connection:Disconnect()
	end
	table.clear(jumpVisibilityConnections)
	for jumpButton, wasVisible in savedJumpVisibility do
		if jumpButton.Parent then
			jumpButton.Visible = wasVisible
		end
	end
	table.clear(savedJumpVisibility)
end

local function hideJumpButton()
	for _, descendant in playerGui:GetDescendants() do
		if descendant:IsA("GuiObject") and descendant.Name == "JumpButton" then
			if savedJumpVisibility[descendant] == nil then
				savedJumpVisibility[descendant] = descendant.Visible
				jumpVisibilityConnections[descendant] = descendant:GetPropertyChangedSignal("Visible"):Connect(function()
					if isTouchPreferred() and shouldHideJump() and descendant.Visible then
						descendant.Visible = false
					end
				end)
			end
			descendant.Visible = false
		end
	end
end

local function resolveAction(name: string): Action?
	local resolved: Action? = nil
	local resolvedPriority = -math.huge
	for _, registration in registrations do
		local config = registration.Config :: any
		local action = config[name]
		local priority = registration.Config.Priority or 0
		if action and action.Available and not action.Available() then
			action = nil
		end
		if action and priority >= resolvedPriority then
			resolved = action
			resolvedPriority = priority
		end
	end
	return resolved
end

local function updateLayout()
	if not gui then return end
	local camera = Workspace.CurrentCamera
	local minDimension = if camera then math.min(camera.ViewportSize.X, camera.ViewportSize.Y) else 600
	local scale = if minDimension < 500 then 0.82 else 1

	local exit = gui:FindFirstChild("Exit")
	if exit and exit:IsA("TextButton") then
		exit.Position = UDim2.new(1, -18 * scale, 0, 18 * scale)
		exit.Size = UDim2.fromOffset(104 * scale, 46 * scale)
	end

	local diamond = gui:FindFirstChild("Diamond")
	if not diamond or not diamond:IsA("Frame") then return end
	diamond.Position = UDim2.new(1, -18 * scale, 1, -18 * scale)
	diamond.Size = UDim2.fromOffset(190 * scale, 190 * scale)
	local positions = {
		Up = Vector2.new(64, 0),
		Right = Vector2.new(128, 64),
		Down = Vector2.new(64, 128),
		Left = Vector2.new(0, 64),
	}
	for name, position in positions do
		local button = diamond:FindFirstChild(name)
		if button and button:IsA("TextButton") then
			button.Position = UDim2.fromOffset(position.X * scale, position.Y * scale)
			button.Size = UDim2.fromOffset(62 * scale, 62 * scale)
		end
	end
end

shouldHideJump = function(): boolean
	for _, registration in registrations do
		if registration.Config.HideJump == true then return true end
	end
	return false
end

shouldBlockTools = function(): boolean
	for _, registration in registrations do
		if registration.Config.BlockTools == true then return true end
	end

	-- Driving anything counts even if its controller never registered. Plain
	-- Seats do not, or sitting on scenery would silently confiscate a tool.
	local character = player.Character
	local humanoid = character and character:FindFirstChildWhichIsA("Humanoid")
	local seat = humanoid and humanoid.SeatPart
	return seat ~= nil and seat:IsA("VehicleSeat")
end

local function unequipToolsIfBlocked()
	if not shouldBlockTools() then return end
	local character = player.Character
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not character or not backpack then return end

	for _, child in character:GetChildren() do
		if not child:IsA("Tool") then continue end
		local allowed = false
		for _, registration in registrations do
			if registration.Config.BlockTools and registration.Config.AllowedTool == child then
				allowed = true
				break
			end
		end
		if not allowed then
			child.Parent = backpack
		end
	end
end

local function watchCharacter(character: Model)
	if characterChildAddedConnection then characterChildAddedConnection:Disconnect() end
	if humanoidSeatedConnection then humanoidSeatedConnection:Disconnect() end
	if humanoidDiedConnection then humanoidDiedConnection:Disconnect() end

	characterChildAddedConnection = character.ChildAdded:Connect(function(child: Instance)
		if child:IsA("Tool") then task.defer(unequipToolsIfBlocked) end
	end)

	local humanoid = character:FindFirstChildWhichIsA("Humanoid")
	if humanoid then
		humanoidSeatedConnection = humanoid.Seated:Connect(function(active: boolean)
			if active then task.defer(unequipToolsIfBlocked) end
		end)
		humanoidDiedConnection = humanoid.Died:Connect(refresh)
	end
	refresh()
end

refresh = function()
	unequipToolsIfBlocked()
	if #registrations == 0 then
		finishAllPresses(Enum.UserInputState.Cancel)
		restoreJumpButton()
		if gui then
			gui:Destroy()
			gui = nil
		end
		table.clear(buttonStates)
		return
	end

	if not gui then
		gui = createGui()
	end
	gui.Enabled = isTouchPreferred() and isLocalCharacterAlive()
	if not gui.Enabled then
		finishAllPresses(Enum.UserInputState.Cancel)
	end
	updateLayout()

	for name, state in buttonStates do
		local action = resolveAction(name)
		if state.PressedAction and state.PressedAction ~= action then
			finishPress(state, Enum.UserInputState.Cancel)
		end
		state.Action = action
		applyActionAppearance(state, action)
		state.Button.Visible = action ~= nil
	end

	if gui.Enabled and shouldHideJump() then
		hideJumpButton()
	else
		restoreJumpButton()
	end
end

local function ensureConnections()
	if not inputEndedConnection then
		inputEndedConnection = UserInputService.InputEnded:Connect(function(input: InputObject)
			for _, state in buttonStates do
				if state.Input == input then
					finishPress(state, Enum.UserInputState.End)
				end
			end
		end)
	end
	if not preferredInputConnection then
		preferredInputConnection = UserInputService:GetPropertyChangedSignal("PreferredInput"):Connect(refresh)
	end
	if not descendantAddedConnection then
		descendantAddedConnection = playerGui.DescendantAdded:Connect(function(descendant: Instance)
			if descendant:IsA("GuiObject")
				and descendant.Name == "JumpButton"
				and isTouchPreferred()
				and shouldHideJump()
			then
				task.defer(hideJumpButton)
			end
		end)
	end
	if not viewportConnection and Workspace.CurrentCamera then
		viewportConnection = Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateLayout)
	end
	if not characterAddedConnection then
		characterAddedConnection = player.CharacterAdded:Connect(watchCharacter)
		if player.Character then watchCharacter(player.Character) end
	end
end

local TouchControls = {}

---Adds the standard tool Jump action on Right and hides Roblox's duplicate
---Jump button while the registration is active.
function TouchControls.withJump(config: Config, tool: Tool?): Config
	-- Preserve a caller's explicit Right action instead of crashing older
	-- SimpleTool configurations. New tool mappings reserve this face for Jump.
	if config.Right == nil then
		config.HideJump = true
		config.Right = {
			Label = "Jump",
			Icon = "Jump",
			Handler = function(state)
				if state ~= Enum.UserInputState.Begin then return end
				local character = player.Character
				local humanoid = character and character:FindFirstChildWhichIsA("Humanoid")
				if humanoid then
					humanoid.Jump = true
					humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
				end
			end,
		}
	end
	if tool and tool.CanBeDropped then
		local heldTool = tool
		config.Exit = {
			Label = "Drop",
			Icon = "Drop",
			Available = function()
				return heldTool.Parent == player.Character
			end,
			Handler = function(state)
				if state ~= Enum.UserInputState.Begin then return end
				if heldTool.Parent ~= player.Character then return end
				local remote = getDropRemote()
				if remote then
					remote:FireServer(heldTool)
				else
					warn("[TouchControls] Drop unavailable: FourD.Common.DropToolRequest is missing")
				end
			end,
		}
	end
	return config
end

function TouchControls.bind(config: Config): Handle
	ensureConnections()
	nextRegistrationId += 1
	local id = nextRegistrationId
	table.insert(registrations, {
		Id = id,
		Config = config,
	})
	refresh()

	local destroyed = false
	local handle = {} :: Handle
	function handle:Destroy()
		if destroyed then return end
		destroyed = true
		for index, registration in registrations do
			if registration.Id == id then
				table.remove(registrations, index)
				break
			end
		end
		refresh()
	end
	return handle
end

return TouchControls
