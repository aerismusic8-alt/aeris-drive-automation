local Constants = require(script.Parent.Parent.Parent.Constants)

local car = script.Parent.Parent.Parent.Parent
local inputs = car.Inputs

local function nitroHandler(_, inputState: Enum.UserInputState)
	if inputState == Enum.UserInputState.Begin then
		inputs:SetAttribute(Constants.NITRO_INPUT_ATTRIBUTE, true)
	else
		inputs:SetAttribute(Constants.NITRO_INPUT_ATTRIBUTE, false)
	end
end

return nitroHandler
