--!strict

-- Server-side ownership policy shared by every FourD world-tool pickup path.

local Players = game:GetService("Players")

local MAX_OWNED_TOOLS = 3

local ToolInventoryPolicy = {}

function ToolInventoryPolicy.countOwnedTools(player: Player, except: Tool?): number
	local count = 0
	local backpack = player:FindFirstChildOfClass("Backpack")
	local character = player.Character

	if backpack then
		for _, child in backpack:GetChildren() do
			if child:IsA("Tool") and child ~= except then
				count += 1
			end
		end
	end

	if character then
		for _, child in character:GetChildren() do
			if child:IsA("Tool") and child ~= except then
				count += 1
			end
		end
	end

	return count
end

function ToolInventoryPolicy.canPickup(player: Player, tool: Tool?): boolean
	return ToolInventoryPolicy.countOwnedTools(player, tool) < MAX_OWNED_TOOLS
end

---Checks and reparents without yielding, so simultaneous touches cannot exceed
---the cap between the capacity check and ownership transfer.
function ToolInventoryPolicy.tryPickup(player: Player, tool: Tool): boolean
	if not tool:IsDescendantOf(workspace) then return false end
	local parent = tool.Parent
	if parent and parent:IsA("Model") and Players:GetPlayerFromCharacter(parent) then
		return false
	end
	if not ToolInventoryPolicy.canPickup(player, tool) then return false end

	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then return false end

	tool.Parent = backpack
	return true
end

ToolInventoryPolicy.MAX_OWNED_TOOLS = MAX_OWNED_TOOLS

return table.freeze(ToolInventoryPolicy)
