--[[
	File: ReplicatedStorage/FourD/Common/TouchButtons.luau

	GENERATED -- not part of upstream FourD.

	Press handling for the buttons a vehicle's touch cluster draws.

	Two rules come from the wheeled cluster, which got here first and is the
	one players already know. A finger lifted after sliding off a button never
	fires InputEnded on that button, so releases are watched service-wide
	instead. And a finger dragged across a neighbour must not press it too, so
	an InputObject is claimed once by tag and ignored everywhere after.
]]--

local UserInputService = game:GetService("UserInputService")

-- Matches WheeledVehicle Constants.TOUCH_INPUT_OBJECT_IGNORE_TAG. A gunner's
-- Fire button shares a cluster with the driving buttons, so the two have to
-- agree on which drag has already been claimed.
local IGNORE_TAG = "IgnoreInput"

local IDLE_TRANSPARENCY = 0.75
local HELD_TRANSPARENCY = 0.5

-- The breakpoint the default touch controls and the wheeled cluster use.
local SMALL_SCREEN_THRESHOLD = 500
local SMALL_SCREEN_SCALE = 0.8

local TouchButtons = {}

TouchButtons.IGNORE_TAG = IGNORE_TAG
TouchButtons.IDLE_TRANSPARENCY = IDLE_TRANSPARENCY
TouchButtons.HELD_TRANSPARENCY = HELD_TRANSPARENCY

local function isPress(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.Touch
		or input.UserInputType == Enum.UserInputType.MouseButton1
end

---Runs `onPress` once per tap.
function TouchButtons.bindTap(button: GuiButton, onPress: () -> ()): RBXScriptConnection
	return button.InputBegan:Connect(function(input)
		if input:HasTag(IGNORE_TAG) or not isPress(input) then return end
		input:AddTag(IGNORE_TAG)
		onPress()
	end)
end

---Runs `onPress` on touch down and `onRelease` when that same finger lifts,
---wherever on screen it has wandered to by then.
function TouchButtons.bindHold(
	button: GuiButton,
	onPress: () -> (),
	onRelease: () -> ()
): { RBXScriptConnection }
	local held: InputObject? = nil

	local began = button.InputBegan:Connect(function(input)
		if input:HasTag(IGNORE_TAG) or not isPress(input) then return end
		input:AddTag(IGNORE_TAG)
		held = input
		button.BackgroundTransparency = HELD_TRANSPARENCY
		onPress()
	end)

	local ended = UserInputService.InputEnded:Connect(function(input)
		if input ~= held then return end
		input:RemoveTag(IGNORE_TAG)
		held = nil
		button.BackgroundTransparency = IDLE_TRANSPARENCY
		onRelease()
	end)

	return { began, ended }
end

---Keeps a cluster legible on a phone, on the same breakpoint the default
---touch controls use.
function TouchButtons.watchScale(screen: ScreenGui): RBXScriptConnection
	local scale = screen:FindFirstChildOfClass("UIScale")

	local function update()
		if not scale then return end
		local minSide = math.min(screen.AbsoluteSize.X, screen.AbsoluteSize.Y)
		scale.Scale = if minSide < SMALL_SCREEN_THRESHOLD then SMALL_SCREEN_SCALE else 1
	end

	update()
	return screen:GetPropertyChangedSignal("AbsoluteSize"):Connect(update)
end

return TouchButtons
