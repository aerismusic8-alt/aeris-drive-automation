-- Shooting-range targets take server-authoritative damage from the firearm rig.
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local range = workspace:WaitForChild("PrototypeRange")

for _, target in ipairs(range:GetChildren()) do
    if target.Name ~= "Target" then continue end
    local damageEvent = Instance.new("BindableEvent")
    damageEvent.Name = "TakeDamage"
    damageEvent.Parent = target
    CollectionService:AddTag(target, "WeaponsSystemDamageable")
    local fullCFrame = target.CFrame
    local label = target.TargetLabel.TextLabel
    local health = 100
    local down = false
    damageEvent.Event:Connect(function(amount)
        if down or typeof(amount) ~= "number" or amount <= 0 then return end
        health = math.max(0, health - math.min(amount, 100))
        target:SetAttribute("TargetHealth", health)
        label.Text = tostring(math.ceil(health)) .. " HP"
        target.Color = Color3.fromRGB(191, 156, 116)
        task.delay(0.12, function()
            if target.Parent and not down then target.Color = Color3.fromRGB(164, 111, 84) end
        end)
        if health > 0 then return end
        down = true
        label.Text = "DOWN"
        target.CanQuery = false
        TweenService:Create(target, TweenInfo.new(0.24, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {CFrame = fullCFrame * CFrame.Angles(math.rad(85), 0, 0), Transparency = 0.55}):Play()
        task.delay(3, function()
            if not target.Parent then return end
            health = 100
            target:SetAttribute("TargetHealth", health)
            target.CFrame = fullCFrame
            target.Transparency = 0
            target.CanQuery = true
            target.Color = Color3.fromRGB(164, 111, 84)
            label.Text = "100 HP"
            down = false
        end)
    end)
end