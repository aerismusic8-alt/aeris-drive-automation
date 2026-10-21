-- Earned-round-currency shop. Server owns prices, phase checks, and item grants.
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local state = game:GetService("ReplicatedStorage"):WaitForChild("MatchState")
local prices = {CompactSMG = 700, Armor = 600}

state.BuyItem.OnServerEvent:Connect(function(player, itemName)
    if typeof(itemName) ~= "string" then return end
    local cost = prices[itemName]
    if not cost then return end
    if state:GetAttribute("Phase") ~= "Buy Phase" then return end
    if player.Parent ~= Players or not player.Team or player:GetAttribute("Alive") ~= true then return end
    local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
    if not humanoid or humanoid.Health <= 0 then return end
    local ownedAttribute = if itemName == "Armor" then "Armor" else "HasSMG"
    if player:GetAttribute(ownedAttribute) == true then return end
    local money = player:GetAttribute("Money")
    if typeof(money) ~= "number" or money < cost then return end
    local template = nil
    if itemName == "CompactSMG" then
        template = ServerStorage.WeaponTemplates:FindFirstChild("CompactSMG")
        if not template or not player:FindFirstChildOfClass("Backpack") then return end
    end
    player:SetAttribute("Money", money - cost)
    player:SetAttribute(ownedAttribute, true)
    if template then
        local gun = template:Clone()
        gun.Parent = player.Backpack
    else
        local torso = player.Character:FindFirstChild("UpperTorso") or player.Character:FindFirstChild("Torso")
        if torso then
            local vest = Instance.new("Part")
            vest.Name = "ProtectiveVest"
            vest.Size = Vector3.new(2.1, 1.6, .32)
            vest.Color = Color3.fromRGB(85, 96, 77)
            vest.Material = Enum.Material.Fabric
            vest.CanCollide = false
            vest.Massless = true
            vest.CFrame = torso.CFrame * CFrame.new(0, 0, -.72)
            vest.Parent = player.Character
            local weld = Instance.new("WeldConstraint")
            weld.Part0 = vest
            weld.Part1 = torso
            weld.Parent = vest
        end
    end
end)