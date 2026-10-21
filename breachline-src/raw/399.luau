if not script.Parent:IsA("Tool") then return end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FourD = ReplicatedStorage:WaitForChild("FourD")
local Common = FourD.Common
local GetCharacterFromPart = require(Common.getCharacterFromPart)
local IsDamageable = require(Common.isDamageable)

local Tool: Tool = script.Parent
local Handle: BasePart = Tool:WaitForChild("Handle") :: BasePart
local SwingAction = Tool:WaitForChild("SwingAction") :: RemoteEvent
local HitRequest = Tool:WaitForChild("HitRequest") :: RemoteEvent
local SwingSignal = Tool:WaitForChild("SwingSignal") :: BindableEvent
local HitSignal = Tool:WaitForChild("HitSignal") :: BindableEvent

local DAMAGE_DEALT = Tool:GetAttribute("DamageDealt") or 35
local SWING_SPEED = Tool:GetAttribute("SwingSpeed") or 1
local SWING_ACTIVE_DURATION = 0.4
local REACH_MULTIPLIER = 2.0
local HANDLE_LONGEST_AXIS = math.max(Handle.Size.X, Handle.Size.Y, Handle.Size.Z)
local REACH_BUDGET = HANDLE_LONGEST_AXIS * REACH_MULTIPLIER

local swingActive = false
local hitThisSwing: { [Humanoid]: boolean } = {}

local function getOwnerPlayer(): Player?
	local parent = Tool.Parent
	if not parent then return nil end

	local player = Players:GetPlayerFromCharacter(parent)
	if player then return player end

	if parent:IsA("Backpack") then
		return parent.Parent :: Player
	end

	return nil
end

local function hasLineOfSight(attackerChar: Model, victimChar: Model, attackerHRP: BasePart, targetPart: BasePart): boolean
	local direction = targetPart.Position - attackerHRP.Position
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { attackerChar, victimChar }
	rayParams.IgnoreWater = true

	local result = workspace:Raycast(attackerHRP.Position, direction, rayParams)
	return result == nil
end

SwingAction.OnServerEvent:Connect(function(player: Player, swingType: string)
	if getOwnerPlayer() ~= player then return end
	if swingActive then return end

	swingActive = true
	hitThisSwing = {}

	SwingSignal:Fire(swingType)

	task.delay(SWING_ACTIVE_DURATION / SWING_SPEED, function()
		swingActive = false
	end)
end)

HitRequest.OnServerEvent:Connect(function(player: Player, victimHumanoid: Humanoid, hitPart: BasePart)
	if not swingActive then return end
	if getOwnerPlayer() ~= player then return end

	if typeof(victimHumanoid) ~= "Instance" then return end
	if not victimHumanoid:IsA("Humanoid") then return end

	if typeof(hitPart) ~= "Instance" then return end
	if not hitPart:IsA("BasePart") then return end
	if not hitPart.Parent then return end

	local victimChar = victimHumanoid.Parent
	if not victimChar or not victimChar:IsA("Model") then return end
	if hitThisSwing[victimHumanoid] then return end

	if GetCharacterFromPart(hitPart) ~= victimChar then return end

	local victimHRP = victimChar:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not victimHRP then return end
	if not IsDamageable(hitPart) then return end

	local attackerChar = player.Character
	if not attackerChar then return end
	if attackerChar == victimChar then return end

	local attackerHRP = attackerChar:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not attackerHRP then return end

	local distance = (attackerHRP.Position - victimHRP.Position).Magnitude
	if distance > REACH_BUDGET then return end

	if not hasLineOfSight(attackerChar, victimChar, attackerHRP, hitPart) then return end

	hitThisSwing[victimHumanoid] = true
	victimHumanoid:TakeDamage(DAMAGE_DEALT)
	HitSignal:Fire(victimHumanoid, DAMAGE_DEALT)
end)

Tool.Equipped:Connect(function()
	if not Tool.PrimaryPart then return end
	Tool.PrimaryPart.CanCollide = false
end)

Tool.Unequipped:Connect(function()
	if not Tool.PrimaryPart then return end
	Tool.PrimaryPart.CanCollide = true
end)
