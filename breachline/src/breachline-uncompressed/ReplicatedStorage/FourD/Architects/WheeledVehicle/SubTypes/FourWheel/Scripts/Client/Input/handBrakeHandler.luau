local Constants = require(script.Parent.Parent.Parent.Constants)

local car = script.Parent.Parent.Parent.Parent
local inputs = car.Inputs

local function handBrakeHandler(_, inputState: Enum.UserInputState)
	if inputState == Enum.UserInputState.Begin then
		inputs:SetAttribute(Constants.HAND_BRAKE_INPUT_ATTRIBUTE, true)
	else
		inputs:SetAttribute(Constants.HAND_BRAKE_INPUT_ATTRIBUTE, false)
	end
end

return handBrakeHandler
