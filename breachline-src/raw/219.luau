local UserInputService = game:GetService("UserInputService")
local UserGameSettings = UserSettings():GetService("UserGameSettings")
local Workspace = game:GetService("Workspace")

local disconnectAndClear = require(script.Parent.Parent.Parent.disconnectAndClear)

-- These variables have been pulled from the default camera scripts
local MIN_TOUCH_SENSITIVITY_FRACTION = 0.25 -- 25% sensitivity at 90