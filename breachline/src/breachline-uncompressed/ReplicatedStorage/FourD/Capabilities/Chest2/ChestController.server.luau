-- Persisted authoritative Chest2 state machine.

local chest = script.Parent
assert(chest and chest:IsA("Model"), "FourDChestServer must be parented to a Model")

local prompt = chest:FindFirstChild("OpenChestPrompt", true)
local wrapper = chest:FindFirstChild("Hingeable_Wrapper", true)
local lid = chest:FindFirstChild("lid")
local activate = chest:FindFirstChild("FourDActivate")

assert(prompt and prompt:IsA("ProximityPrompt"), "Chest2 is missing OpenChestPrompt")
assert(wrapper and wrapper:IsA("Folder"), "Chest2 is missing Hingeable_Wrapper")
assert(lid and lid:IsA("PVInstance"), "Chest2 is missing lid")
assert(activate and activate:IsA("BindableEvent"), "Chest2 is missing FourDActivate")

local busy = false

local function setCollidable(enabled: boolean)
	local parts = {}
	if lid:IsA("BasePart") then table.insert(parts, lid) end
	for _, descendant in lid:GetDescendants() do
		if descendant:IsA("BasePart") then table.insert(parts, descendant) end
	end
	for _, part in parts do
		part.CanCollide = if enabled
			then part:GetAttribute("FourDOriginalCanCollide") ~= false
			else false
	end
end

local function runCycle()
	if busy then return end
	busy = true
	prompt.Enabled = false
	setCollidable(false)

	wrapper:SetAttribute("MaxSpeed", 8)
	wrapper:SetAttribute("Damping", 1)
	wrapper:SetAttribute("Stiffness", 4)
	wrapper:SetAttribute("TargetAngle", math.rad(chest:GetAttribute("openAngleDegrees") or 110))

	task.wait(chest:GetAttribute("holdSeconds") or 3)

	wrapper:SetAttribute("MaxSpeed", 6)
	wrapper:SetAttribute("Damping", 1)
	wrapper:SetAttribute("Stiffness", 3)
	wrapper:SetAttribute("TargetAngle", 0)
	task.wait(0.85)

	setCollidable(true)
	prompt.Enabled = true
	busy = false
end

prompt.Triggered:Connect(runCycle)
activate.Event:Connect(runCycle)
script:SetAttribute("RuntimeVersion", 1)
script:SetAttribute("RuntimeReady", true)
