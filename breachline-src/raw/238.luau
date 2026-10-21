local cycleCameraModeEvent = script.Parent.Parent.Camera.CycleCameraMode

local function cycleCameraModeHandler(_, inputState: Enum.UserInputState)
	if inputState == Enum.UserInputState.Begin then
		cycleCameraModeEvent:Fire()
	end
end

return cycleCameraModeHandler
