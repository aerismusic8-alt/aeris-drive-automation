--!strict
-- Attack animation, done in code.
--
-- A tap used to change a number and nothing else, so the character stood still
-- while the monster lost health. There is no rigged animation asset to play
-- here, so the swing is procedural: the right shoulder's Motor6D is rotated
-- through a short arc and a slash is drawn in front of the character.
--
-- Motor6D is used rather than the newer AnimationTrack because a Motor6D exists
-- on both the R6 and the R15 avatar, so one code path animates either rig.
--
-- Every swing is short and self-cancelling: a new tap restarts the arc instead
-- of queueing behind the last one, which is what a fast auto-attack needs.

local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local player = Players.LocalPlayer

local AttackAnim = {}

-- How long one swing takes. Kept near the fastest attack interval so the
-- animation never becomes the thing that limits the attack rate.
local SWING_TIME = 0.22

-- Rotation keyframes per swing style, in degrees around the shoulder. `back` is
-- the wind-up, `through` is the strike, and the arc is tweened between them.
type Keyframes = {
        back: { number },
        through: { number },
        -- Where the slash effect appears, relative to the character's facing.
        arcYaw: number,
        arcPitch: number,
        -- How wide the drawn slash is, in studs.
        reach: number,
}

local STYLES: { [string]: Keyframes } = {
        -- A wide horizontal cut.
        slash = { back = { -35, 20, -25 }, through = { 30, -55, 15 }, arcYaw = -70, arcPitch = 0, reach = 6.5 },
        -- A straight push forward, like drawing a bow.
        thrust = { back = { -20, 25, 0 }, through = { 10, -20, 0 }, arcYaw = -20, arcPitch = 0, reach = 7.5 },
        -- Raise the staff, then point it forward.
        cast = { back = { -70, 0, 0 }, through = { -25, -30, 0 }, arcYaw = -30, arcPitch = -18, reach = 6.0 },
        -- Two short jabs.
        stab = { back = { -15, 30, -10 }, through = { 5, -35, 10 }, arcYaw = -45, arcPitch = 0, reach = 4.5 },
        -- An overhead blow straight down.
        smite = { back = { -95, 0, 0 }, through = { 45, -10, 0 }, arcYaw = 0, arcPitch = -55, reach = 6.0 },
}

local function keyframesFor(style: string?): Keyframes
        return STYLES[style or "slash"] or STYLES.slash
end

-- The joint that moves the right arm, whichever rig the avatar is using.
local function rightShoulder(character: Model): Motor6D?
        local upper = character:FindFirstChild("RightUpperArm") or character:FindFirstChild("Right Arm")
        if not upper then
                return nil
        end
        local joint = upper:FindFirstChild("RightShoulder")
        if joint and joint:IsA("Motor6D") then
                return joint
        end
        -- R6 keeps the joint inside the Torso.
        local torso = character:FindFirstChild("Torso")
        local shoulder = torso and torso:FindFirstChild("Right Shoulder")
        if shoulder and shoulder:IsA("Motor6D") then
                return shoulder
        end
        return nil
end

-- The character's facing, used to place the slash in front of them.
local function facing(character: Model): CFrame?
        local root = character:FindFirstChild("HumanoidRootPart")
        if not root or not root:IsA("BasePart") then
                return nil
        end
        return root.CFrame
end

-- Draw one slash: a thin glowing blade that sweeps and fades. Built from a Part
-- so nothing has to be uploaded as an asset.
local function drawSlash(character: Model, style: string)
        local base = facing(character)
        if not base then
                return
        end
        local kf = keyframesFor(style)

        local slash = Instance.new("Part")
        slash.Name = "AXSlash"
        slash.Size = Vector3.new(0.25, 0.25, kf.reach)
        slash.Anchored = true
        slash.CanCollide = false
        slash.CanQuery = false
        slash.CanTouch = false
        slash.Material = Enum.Material.Neon
        slash.Color = Color3.fromRGB(255, 245, 200)
        slash.Transparency = 0.15
        slash.CastShadow = false
        slash.Parent = workspace

        local startYaw = math.rad(kf.arcYaw * 0.5)
        local endYaw = math.rad(-kf.arcYaw * 0.5)
        local pitch = math.rad(kf.arcPitch)
        local pivot = base.Position + Vector3.new(0, 1.2, 0)
        local start = CFrame.new(pivot) * CFrame.Angles(0, startYaw, 0) * CFrame.Angles(pitch, 0, 0)
        local finish = CFrame.new(pivot) * CFrame.Angles(0, endYaw, 0) * CFrame.Angles(pitch, 0, 0)

        slash.CFrame = start * CFrame.new(0, 0, -kf.reach * 0.5)

        local sweep = TweenService:Create(slash, TweenInfo.new(SWING_TIME * 0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                CFrame = finish * CFrame.new(0, 0, -kf.reach * 0.5),
                Transparency = 1,
        })
        sweep:Play()
        sweep.Completed:Connect(function()
                slash:Destroy()
        end)
end

-- Rotate the shoulder through the style's arc.
--
-- The rest pose is cached per joint the first time it is seen, so an
-- interrupted swing always returns to the true rest instead of treating a
-- half-finished arc as the new neutral. A generation counter per joint means
-- only the most recent swing is allowed to finish and restore the arm.
local restPose: { [Motor6D]: CFrame } = {}
local generation: { [Motor6D]: number } = {}

local function swingArm(character: Model, style: string)
        local joint = rightShoulder(character)
        if not joint then
                return
        end
        if not restPose[joint] then
                restPose[joint] = joint.C0
        end
        local rest = restPose[joint]
        local kf = keyframesFor(style)

        generation[joint] = (generation[joint] or 0) + 1
        local mine = generation[joint]

        local function pose(angles: { number }): CFrame
                return rest * CFrame.Angles(math.rad(angles[1]), math.rad(angles[2]), math.rad(angles[3]))
        end

        local wind = TweenService:Create(joint, TweenInfo.new(SWING_TIME * 0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                C0 = pose(kf.back),
        })
        wind:Play()
        wind.Completed:Connect(function()
                if generation[joint] ~= mine or not joint.Parent then
                        return
                end
                local strike = TweenService:Create(joint, TweenInfo.new(SWING_TIME * 0.6, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
                        C0 = pose(kf.through),
                })
                strike:Play()
                strike.Completed:Connect(function()
                        if generation[joint] ~= mine or not joint.Parent then
                                return
                        end
                        TweenService:Create(joint, TweenInfo.new(SWING_TIME * 0.5, Enum.EasingStyle.Sine), {
                                C0 = rest,
                        }):Play()
                end)
        end)
end

-- Play the swing for a character. Called for the local player on a tap, and
-- again when the server reports that somebody else attacked.
function AttackAnim.play(character: Model?, style: string?)
        if not character or not character.Parent then
                return
        end
        local chosen = style or "slash"
        swingArm(character, chosen)
        drawSlash(character, chosen)
end

-- Play for any player's avatar by user id, the local one included: the server
-- broadcasts every swing, so an auto-attack animates too, and a manual tap is
-- not animated twice because this is the only place a swing starts.
function AttackAnim.playForUserId(userId: number, style: string?)
        local who = Players:GetPlayerByUserId(userId)
        local character = who and who.Character
        AttackAnim.play(character, style)
end

AttackAnim.STYLES = STYLES

return AttackAnim
