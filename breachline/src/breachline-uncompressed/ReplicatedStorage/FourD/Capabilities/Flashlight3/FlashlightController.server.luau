-- Persisted authoritative Flashlight3 state machine.

local tool = script.Parent
assert(tool and tool:IsA("Tool"), "FourDFlashlightServer must be parented to a Tool")

local lightRef = script:WaitForChild("LightRef") :: ObjectValue
local light = lightRef.Value
local activate = tool:WaitForChild("FourDActivate") :: BindableEvent
assert(light and light:IsA("Light"), "Flashlight3 LightRef is invalid")
local typedLight = light :: Light

local lastActivation = 0

local function toggle()
	local now = os.clock()
	if now - lastActivation < 0.1 then return end
	lastActivation = now
	typedLight.Enabled = not typedLight.Enabled
end

tool.Activated:Connect(toggle)
tool.Equipped:Connect(function()
	typedLight.Enabled = true
end)
tool.Unequipped:Connect(function()
	typedLight.Enabled = false
end)
activate.Event:Connect(toggle)

script:SetAttribute("RuntimeVersion", 1)
script:SetAttribute("RuntimeReady", true)
