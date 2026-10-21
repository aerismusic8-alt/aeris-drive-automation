local UserInputService = game:GetService("UserInputService")

local KEY_CODE_REPLACEMENTS = {
	[Enum.KeyCode.Space] = "Spacebar",
	[Enum.KeyCode.LeftShift] = "LShift",
	[Enum.KeyCode.RightShift] = "RShift",
	[Enum.KeyCode.LeftControl] = "LCtrl",
	[Enum.KeyCode.RightControl] = "RCtrl",
	[Enum.KeyCode.LeftAlt] = "LAlt",
	[Enum.KeyCode.RightAlt] = "RAlt",
}

local function getStringForKeyCode(keyCode: Enum.KeyCode): string
	-- Use shortened/modified version for a few of the keycodes, this is simply artistic preference
	if KEY_CODE_REPLACEMENTS[keyCode] then
		return KEY_CODE_REPLACEMENTS[keyCode]
	end

	-- Get the correct string to display for the keycode. This allows us to display the
	-- correct key for non-QWERTY keyboard layouts.
	local str = UserInputService:GetStringForKeyCode(keyCode)
	-- If there is no defined string for the keycode, simply return the keycode name
	if str == "" then
		return keyCode.Name
	else
		return str
	end
end

return getStringForKeyCode
