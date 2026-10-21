-- Lightweight range HUD; the firearm rig draws its own ammo and crosshair.
local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")
local player = Players.LocalPlayer
local gui = Instance.new("ScreenGui")
gui.Name = "RangeHud"
gui.ResetOnSpawn = false
gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
gui.Parent = player:WaitForChild("PlayerGui")
local function text(name, value, size, pos, anchor)
    local item = Instance.new("TextLabel")
    item.Name = name
    item.Text = value
    item.Size = size
    item.Position = pos
    item.AnchorPoint = anchor
    item.BackgroundColor3 = Color3.fromRGB(31, 33, 32)
    item.BackgroundTransparency = 0.16
    item.TextColor3 = Color3.fromRGB(239, 237, 226)
    item.Font = Enum.Font.GothamMedium
    item.TextScaled = true
    item.Parent = gui
    local padding = Instance.new("UIPadding")
    padding.PaddingLeft = UDim.new(0, 10)
    padding.PaddingRight = UDim.new(0, 10)
    padding.Parent = item
    return item
end
local title = text("Title", "TACTICAL RANGE  /  SHOOT THE TARGETS", UDim2.new(0.62, 0, 0, 38), UDim2.fromScale(0.5, 0.04), Vector2.new(0.5, 0))
local health = text("Health", "HEALTH  100", UDim2.new(.26, 0, 0, 30), UDim2.new(0, 8, 0, 98), Vector2.new(0, 0))
local healthSize = Instance.new("UISizeConstraint")
healthSize.MaxSize = Vector2.new(160, 32)
healthSize.Parent = health
local hint = text("Hint", "FIRE: CLICK / TAP     RELOAD: R     MOVE: WASD / THUMBSTICK", UDim2.new(0.64, 0, 0, 34), UDim2.fromScale(0.5, 0.92), Vector2.new(0.5, 1))
title.Visible = false
hint.Visible = false
local function bindCharacter(character)
    local humanoid = character:WaitForChild("Humanoid")
    local function update() health.Text = "HEALTH  " .. tostring(math.ceil(humanoid.Health)) end
    humanoid.HealthChanged:Connect(update)
    update()
end
player.CharacterAdded:Connect(bindCharacter)
if player.Character then bindCharacter(player.Character) end
local connected = {}
local reloadButton = Instance.new("TextButton")
reloadButton.Name = "TouchReload"
reloadButton.Text = "RELOAD"
reloadButton.Font = Enum.Font.GothamBold
reloadButton.TextScaled = true
reloadButton.TextColor3 = Color3.fromRGB(239, 237, 226)
reloadButton.BackgroundColor3 = Color3.fromRGB(65, 69, 63)
reloadButton.Size = UDim2.fromOffset(100, 52)
reloadButton.Position = UDim2.new(1, -122, 1, -178)
reloadButton.Visible = game:GetService("UserInputService").TouchEnabled
reloadButton.Parent = gui
reloadButton.Activated:Connect(function()
    local character = player.Character
    local tool = character and (character:FindFirstChild("CompactSMG") or character:FindFirstChild("TrainingCarbine"))
    local remotes = tool and tool:FindFirstChild("Remotes")
    local reload = remotes and remotes:FindFirstChild("Reload")
    if reload then reload:FireServer() end
end)
local function bindGun(tool)
    if not tool:IsA("Tool") or (tool.Name ~= "TrainingCarbine" and tool.Name ~= "CompactSMG") or connected[tool] then return end
    connected[tool] = true
    local remote = tool:WaitForChild("Remotes"):WaitForChild("ShotReplicate")
    remote.OnClientEvent:Connect(function()
        if tool.Parent ~= player.Character then return end
        local source = SoundService:FindFirstChild("ShotSfx")
        if source then
            local shot = source:Clone()
            shot.Volume = 0.45
            shot.Parent = SoundService
            shot:Play()
            shot.Ended:Once(function() shot:Destroy() end)
        end
    end)
end
local backpack = player:WaitForChild("Backpack")
backpack.ChildAdded:Connect(bindGun)
for _, tool in ipairs(backpack:GetChildren()) do bindGun(tool) end
player.CharacterAdded:Connect(function(char)
    char.ChildAdded:Connect(bindGun)
    for _, tool in ipairs(char:GetChildren()) do bindGun(tool) end
end)
if player.Character then
    player.Character.ChildAdded:Connect(bindGun)
    for _, tool in ipairs(player.Character:GetChildren()) do bindGun(tool) end
end