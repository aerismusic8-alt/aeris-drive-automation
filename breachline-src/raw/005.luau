local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local player = Players.LocalPlayer
local state = game:GetService("ReplicatedStorage"):WaitForChild("MatchState")
local gui = Instance.new("ScreenGui")
gui.Name = "BuyHud"
gui.ResetOnSpawn = false
gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
gui.DisplayOrder = 15
gui.Parent = player:WaitForChild("PlayerGui")
local function button(parent, name, label, size, position)
    local b = Instance.new("TextButton")
    b.Name = name
    b.Text = label
    b.Size = size
    b.Position = position
    b.AnchorPoint = Vector2.new(.5, 0)
    b.Font = Enum.Font.GothamBold
    b.TextScaled = true
    b.TextColor3 = Color3.fromRGB(246, 239, 216)
    b.BackgroundColor3 = Color3.fromRGB(78, 91, 75)
    b.Selectable = true
    b.Parent = parent
    return b
end
local openButton = button(gui, "OpenShop", "BUY", UDim2.fromOffset(94, 50), UDim2.new(.5, 0, .55, 0))
local loadout = Instance.new("TextLabel")
loadout.Name = "Loadout"
loadout.Size = UDim2.new(.5, 0, 0, 28)
loadout.Position = UDim2.new(1, -10, 0, 98)
loadout.AnchorPoint = Vector2.new(1, 0)
loadout.BackgroundColor3 = Color3.fromRGB(41, 45, 41)
loadout.BackgroundTransparency = .2
loadout.TextColor3 = Color3.fromRGB(239, 237, 226)
loadout.Font = Enum.Font.GothamMedium
loadout.TextScaled = true
loadout.Parent = gui
local panel = Instance.new("Frame")
panel.Name = "ShopPanel"
panel.Size = UDim2.new(.8, 0, 0, 280)
panel.Position = UDim2.fromScale(.5, .5)
panel.AnchorPoint = Vector2.new(.5, .5)
panel.BackgroundColor3 = Color3.fromRGB(41, 45, 41)
panel.Visible = false
panel.Parent = gui
local limit = Instance.new("UISizeConstraint")
limit.MaxSize = Vector2.new(390, 300)
limit.Parent = panel
local balance = Instance.new("TextLabel")
balance.Name = "Balance"
balance.Size = UDim2.new(1, 0, 0, 48)
balance.BackgroundTransparency = 1
balance.Font = Enum.Font.GothamBold
balance.TextColor3 = Color3.new(1, 1, 1)
balance.TextScaled = true
balance.Parent = panel
local smg = button(panel, "SMG", "Compact SMG  $700", UDim2.new(1, -36, 0, 55), UDim2.new(.5, 0, 0, 57))
local armor = button(panel, "Armor", "Protective armor  $600", UDim2.new(1, -36, 0, 55), UDim2.new(.5, 0, 0, 119))
local close = button(panel, "Close", "CLOSE", UDim2.new(1, -36, 0, 50), UDim2.new(.5, 0, 0, 203))
local function setOpen(on)
    panel.Visible = on and state:GetAttribute("Phase") == "Buy Phase"
    if panel.Visible then player.CameraMode = Enum.CameraMode.Classic
    elseif player:GetAttribute("Alive") == true then player.CameraMode = Enum.CameraMode.LockFirstPerson end
end
local function refresh()
    openButton.Visible = state:GetAttribute("Phase") == "Buy Phase" and player:GetAttribute("Alive") == true
    if not openButton.Visible then setOpen(false) end
    balance.Text = "BUY PHASE  |  $" .. tostring(player:GetAttribute("Money") or 0)
    loadout.Text = "LOADOUT: CARBINE" .. (if player:GetAttribute("HasSMG") then " + SMG" else "") .. (if player:GetAttribute("Armor") then " + ARMOR" else "")
    smg.Text = if player:GetAttribute("HasSMG") then "Compact SMG  - OWNED" else "Compact SMG  $700"
    armor.Text = if player:GetAttribute("Armor") then "Protective armor  - OWNED" else "Protective armor  $600"
end
openButton.Activated:Connect(function() setOpen(not panel.Visible) end)
close.Activated:Connect(function() setOpen(false) end)
smg.Activated:Connect(function() state.BuyItem:FireServer("CompactSMG") end)
armor.Activated:Connect(function() state.BuyItem:FireServer("Armor") end)
UserInputService.InputBegan:Connect(function(input, processed)
    if not processed and input.KeyCode == Enum.KeyCode.B and openButton.Visible then setOpen(not panel.Visible) end
end)
state:GetAttributeChangedSignal("Phase"):Connect(refresh)
for _,attr in ipairs({"Money", "Armor", "HasSMG", "Alive"}) do player:GetAttributeChangedSignal(attr):Connect(refresh) end
refresh()