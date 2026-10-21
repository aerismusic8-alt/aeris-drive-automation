--!nocheck
-- A headless stand-in for the Roblox engine, so the server, the world builder
-- and the client can actually be executed by the test suite.
--
-- Why this exists. Every test in this repo loaded only the pure modules in
-- src/shared. World.luau, init.server.luau and init.client.luau were never
-- executed at all, and the checks that guarded them read the source as text
-- instead. So the suite passed 353/353 while the game crashed the moment a
-- player joined: pushPlayerState passed an out-of-scope `broadcastNow`, which
-- is nil, straight into Farm.secondsUntilReady, which subtracts it. A text
-- check cannot see that. Running the code can.
--
-- This is deliberately small and honest about what it does not do: it
-- implements the parts of the engine the glue actually touches (Instance,
-- properties, children, the datatypes, the services, signals) and raises a
-- clear error for anything else, so a new engine call is a loud failure rather
-- than a silent nil. It is not a Roblox emulator and makes no claim to be.
--
-- Nothing here is shipped: Rojo only builds roblox/src, and this lives in
-- roblox/tests.

local Shim = {}

--------------------------------------------------------------------------
-- Datatypes
--------------------------------------------------------------------------

local Vector3 = {}
Vector3.__index = Vector3

function Vector3.new(x: number?, y: number?, z: number?)
        return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, Vector3)
end

function Vector3.__add(a, b)
        return Vector3.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end

function Vector3.__sub(a, b)
        return Vector3.new(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
end

function Vector3.__mul(a, b)
        if type(a) == "number" then
                return Vector3.new(a * b.X, a * b.Y, a * b.Z)
        elseif type(b) == "number" then
                return Vector3.new(a.X * b, a.Y * b, a.Z * b)
        end
        return Vector3.new(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end

function Vector3.__unm(a)
        return Vector3.new(-a.X, -a.Y, -a.Z)
end

function Vector3.__eq(a, b)
        return a.X == b.X and a.Y == b.Y and a.Z == b.Z
end

function Vector3.__tostring(a)
        return string.format("%g, %g, %g", a.X, a.Y, a.Z)
end

function Vector3.__index(self, key)
        if key == "Magnitude" then
                return math.sqrt(self.X * self.X + self.Y * self.Y + self.Z * self.Z)
        elseif key == "Unit" then
                local m = math.sqrt(self.X * self.X + self.Y * self.Y + self.Z * self.Z)
                if m == 0 then
                        return Vector3.new(0, 0, 0)
                end
                return Vector3.new(self.X / m, self.Y / m, self.Z / m)
        end
        return Vector3[key]
end

function Vector3:Lerp(other, alpha)
        return Vector3.new(
                self.X + (other.X - self.X) * alpha,
                self.Y + (other.Y - self.Y) * alpha,
                self.Z + (other.Z - self.Z) * alpha
        )
end

function Vector3:Dot(other)
        return self.X * other.X + self.Y * other.Y + self.Z * other.Z
end

function Vector3:Cross(other)
        return Vector3.new(
                self.Y * other.Z - self.Z * other.Y,
                self.Z * other.X - self.X * other.Z,
                self.X * other.Y - self.Y * other.X
        )
end

--------------------------------------------------------------------------

local CFrame = {}
CFrame.__index = CFrame

function CFrame.new(x: any, y: number?, z: number?)
        if type(x) == "table" and getmetatable(x) == Vector3 then
                return setmetatable({ Position = x }, CFrame)
        end
        return setmetatable({ Position = Vector3.new(x or 0, y or 0, z or 0) }, CFrame)
end

function CFrame.Angles(_rx: number?, _ry: number?, _rz: number?)
        return setmetatable({ Position = Vector3.new(0, 0, 0) }, CFrame)
end

function CFrame.lookAt(at, _look)
        return setmetatable({ Position = at }, CFrame)
end

function CFrame.__mul(a, b)
        return setmetatable({ Position = a.Position + b.Position }, CFrame)
end

function CFrame.__add(a, b)
        return setmetatable({ Position = a.Position + b.Position }, CFrame)
end

function CFrame.__tostring()
        return "CFrame"
end

--------------------------------------------------------------------------

local Color3 = {}
Color3.__index = Color3

function Color3.new(r: number?, g: number?, b: number?)
        return setmetatable({ R = r or 0, G = g or 0, B = b or 0 }, Color3)
end

function Color3.fromRGB(r: number?, g: number?, b: number?)
        return Color3.new((r or 0) / 255, (g or 0) / 255, (b or 0) / 255)
end

function Color3:Lerp(other, alpha)
        return Color3.new(
                self.R + (other.R - self.R) * alpha,
                self.G + (other.G - self.G) * alpha,
                self.B + (other.B - self.B) * alpha
        )
end

function Color3.__eq(a, b)
        return a.R == b.R and a.G == b.G and a.B == b.B
end

function Color3.__tostring(a)
        return string.format("%g, %g, %g", a.R, a.G, a.B)
end

--------------------------------------------------------------------------

local UDim = {}
UDim.__index = UDim

function UDim.new(scale: number?, offset: number?)
        return setmetatable({ Scale = scale or 0, Offset = offset or 0 }, UDim)
end

local UDim2 = {}
UDim2.__index = UDim2

function UDim2.new(xs: number?, xo: number?, ys: number?, yo: number?)
        return setmetatable({
                X = UDim.new(xs, xo),
                Y = UDim.new(ys, yo),
        }, UDim2)
end

function UDim2.fromScale(xs: number?, ys: number?)
        return UDim2.new(xs, 0, ys, 0)
end

function UDim2.fromOffset(xo: number?, yo: number?)
        return UDim2.new(0, xo, 0, yo)
end

function UDim2.__tostring()
        return "UDim2"
end

--------------------------------------------------------------------------

local TweenInfo = {}
TweenInfo.__index = TweenInfo

function TweenInfo.new(...)
        return setmetatable({ args = { ... } }, TweenInfo)
end

--------------------------------------------------------------------------

--------------------------------------------------------------------------
-- Vector2 and the sequence types
--------------------------------------------------------------------------

local Vector2 = {}
Vector2.__index = Vector2

function Vector2.new(x: number?, y: number?)
        return setmetatable({ X = x or 0, Y = y or 0 }, Vector2)
end

function Vector2.__tostring(a)
        return string.format("%g, %g", a.X, a.Y)
end

-- Sequences are only ever handed to a ParticleEmitter or a Tween, so keeping
-- the keypoints is enough to prove the code ran and built a well-formed one.
local NumberSequence = {}
NumberSequence.__index = NumberSequence

function NumberSequence.new(a: any, b: number?)
        if type(a) == "table" then
                return setmetatable({ keypoints = a }, NumberSequence)
        end
        return setmetatable({ keypoints = { { time = 0, value = a or 0 }, { time = 1, value = b or a or 0 } } }, NumberSequence)
end

local NumberSequenceKeypoint = {}
NumberSequenceKeypoint.__index = NumberSequenceKeypoint

function NumberSequenceKeypoint.new(time: number?, value: number?, envelope: number?)
        return setmetatable({ Time = time or 0, Value = value or 0, Envelope = envelope or 0 }, NumberSequenceKeypoint)
end

local ColorSequence = {}
ColorSequence.__index = ColorSequence

function ColorSequence.new(a: any, b: any?)
        if type(a) == "table" then
                return setmetatable({ keypoints = a }, ColorSequence)
        end
        return setmetatable({ keypoints = { { time = 0, value = a }, { time = 1, value = b or a } } }, ColorSequence)
end

local ColorSequenceKeypoint = {}
ColorSequenceKeypoint.__index = ColorSequenceKeypoint

function ColorSequenceKeypoint.new(time: number?, value: any?)
        return setmetatable({ Time = time or 0, Value = value }, ColorSequenceKeypoint)
end

local NumberRange = {}
NumberRange.__index = NumberRange

function NumberRange.new(min: number?, max: number?)
        if max == nil then
                max = min
        end
        return setmetatable({ Min = min or 0, Max = max or 0 }, NumberRange)
end

--------------------------------------------------------------------------
-- Enum
--------------------------------------------------------------------------

-- Every enum member the glue mentions, grouped. An unknown group raises rather
-- than returning nil, so a typo in an enum name fails the harness instead of
-- silently assigning nil to a property.
local ENUM_MEMBERS = {
        Material = { Grass = 1, Ground = 2, Neon = 3, Slate = 4, SmoothPlastic = 5, Wood = 6 },
        SurfaceType = { Smooth = 1, Studs = 2, Inlet = 3 },
        PartType = { Ball = 1, Cylinder = 2, Block = 3, Wedge = 4 },
        Font = { GothamBlack = 1, GothamBold = 2, Gotham = 3 },
        ScreenInsets = { CoreUISafeInsets = 1, None = 2, DeviceSafeInsets = 3 },
        ZIndexBehavior = { Sibling = 1, Global = 2 },
        EasingStyle = { Quad = 1, Quart = 2, Sine = 3, Linear = 4 },
        EasingDirection = { Out = 1, In = 2, InOut = 3 },
        TextTruncate = { AtEnd = 1, None = 2 },
        ApplyStrokeMode = { Border = 1, Contextual = 2 },
        ScrollingDirection = { Y = 1, X = 2, XY = 3 },
        TextXAlignment = { Center = 1, Left = 2, Right = 3 },
        TextYAlignment = { Center = 1, Top = 2, Bottom = 3 },
        ProductPurchaseDecision = { NotProcessedYet = 1, PurchaseGranted = 2 },
        -- Services use these; the shim only needs the names to resolve.
        RunContext = { Server = 1, Client = 2, Legacy = 3 },
}

local Enum = {}
setmetatable(Enum, {
        __index = function(_, group)
                local members = ENUM_MEMBERS[group]
                if not members then
                        error("RobloxShim: unknown Enum." .. tostring(group), 2)
                end
                local out = {}
                setmetatable(out, {
                        __index = function(_, member)
                                if members[member] == nil then
                                        error("RobloxShim: unknown Enum." .. group .. "." .. tostring(member), 2)
                                end
                                return {
                                        EnumType = group,
                                        Name = member,
                                        Value = members[member],
                                }
                        end,
                })
                return out
        end,
})

--------------------------------------------------------------------------
-- Signal
--------------------------------------------------------------------------

local Signal = {}
Signal.__index = Signal

function Signal.new()
        return setmetatable({ handlers = {} }, Signal)
end

function Signal:Connect(fn)
        table.insert(self.handlers, fn)
        return {
                Disconnect = function() end,
                Connected = true,
        }
end

function Signal:Fire(...)
        for _, fn in ipairs(self.handlers) do
                fn(...)
        end
end

--------------------------------------------------------------------------
-- Instance
--------------------------------------------------------------------------

local VALID_CLASSES = {}
for _, name in ipairs({
        "Part", "WedgePart", "CornerWedgePart", "Model", "Folder", "SpawnLocation",
        "TextLabel", "TextButton", "TextBox", "Frame", "ScrollingFrame", "ScreenGui",
        "UICorner", "UIStroke", "ViewportFrame", "Camera", "BillboardGui",
        "ParticleEmitter", "PointLight", "WeldConstraint", "Atmosphere", "Clouds",
        "BloomEffect", "ColorCorrectionEffect", "SunRaysEffect",
        "Humanoid", "HumanoidRootPart", "MeshPart", "RemoteEvent", "RemoteFunction",
        "ServerScriptService", "ReplicatedStorage", "Workspace", "Lighting",
        "StarterPlayer", "StarterPlayerScripts", "Players", "DataStoreService",
        "RunService", "TweenService", "MarketplaceService", "Terrain",
        "Configuration", "Attachment", "Highlight", "SurfaceGui",
        -- A villager is interacted with through a ProximityPrompt, and a hit has
        -- a Sound. Both are modelled rather than stubbed: a prompt fires
        -- Triggered with the player who triggered it, and a Sound remembers the
        -- id it was given and plays it, because that is what the game reads back.
        "ProximityPrompt", "ClickDetector", "Sound",
}) do
        VALID_CLASSES[name] = true
end

local Instance = {}
Instance.__index = Instance

local function isA(self, className)
        if self.ClassName == className then
                return true
        end
        -- Only the inheritances the glue actually relies on.
        if className == "BasePart" then
                return self.ClassName == "Part" or self.ClassName == "WedgePart" or self.ClassName == "CornerWedgePart"
        end
        if className == "GuiObject" then
                return self.ClassName == "TextLabel" or self.ClassName == "TextButton"
                        or self.ClassName == "TextBox" or self.ClassName == "Frame"
                        or self.ClassName == "ScrollingFrame"
        end
        if className == "Instance" then
                return true
        end
        return false
end

local function newInstance(className: string)
        if not VALID_CLASSES[className] then
                error("RobloxShim: Instance.new(\"" .. tostring(className) .. "\") is not modelled", 3)
        end

        local self = setmetatable({
                ClassName = className,
                Name = className,
                Parent = nil,
                children = {},
                signals = {},
        }, Instance)

        if className == "Part" or className == "WedgePart" or className == "CornerWedgePart" then
                self.Size = Vector3.new(1, 1, 1)
                self.CFrame = CFrame.new(0, 0, 0)
                self.Position = Vector3.new(0, 0, 0)
        end

        -- A prompt is usable only if the game says so, and the interaction text
        -- is read back by tests. Defaults match the engine's.
        if className == "ProximityPrompt" then
                self.Enabled = true
                self.ActionText = ""
                self.ObjectText = ""
                self.HoldDuration = 0
                self.MaxActivationDistance = 10
                self.RequiresLineOfSight = true
                self.KeyboardKeyCode = nil
                self.Style = nil
                -- Flipped by :InputHoldBegin/:InputHoldEnd in the engine. Kept
                -- here so a test can assert a prompt was armed before it fired.
                self.triggeredCount = 0
        end

        -- A Sound carries the id it was told to play and whether it is playing,
        -- because the game only ever reads those two back.
        if className == "Sound" then
                self.SoundId = ""
                self.Volume = 0.5
                self.Playing = false
                self.Looped = false
                self.playCount = 0
        end
        return self
end

-- Events every instance has. The engine creates these on the class, so reading
-- one never returns nil; the shim creates it on first read so a Connect call
-- works the same way.
local INSTANCE_EVENTS = {
        Touched = true,
        -- GuiButton events. A caret or a tab is a TextButton, and the glue
        -- connects Activated on every one of them.
        Activated = true,
        MouseButton1Click = true,
        MouseButton1Down = true,
        MouseButton1Up = true,
        MouseEnter = true,
        MouseLeave = true,
        InputBegan = true,
        InputEnded = true,
        FocusLost = true,
        Focused = true,
        ReturnPressedFromOnScreenKeyboard = true,
        -- Player events. CharacterAdded is how the server learns a body exists;
        -- the rest are here so a new Connect in the glue resolves rather than
        -- failing on nil.
        CharacterAdded = true,
        CharacterRemoving = true,
        CharacterAppearanceLoaded = true,
        OnTeleport = true,
        Chatted = true,
        -- Humanoid events. Died is how the server learns a player was killed.
        Died = true,
        Running = true,
        Jumping = true,
        Climbing = true,
        FreeFalling = true,
        GettingUp = true,
        MoveToFinished = true,
        TouchEnded = true,
        Changed = true,
        ChildAdded = true,
        ChildRemoved = true,
        DescendantAdded = true,
        DescendantRemoving = true,
        AncestryChanged = true,
        Destroying = true,
        AttributeChanged = true,
        -- A ProximityPrompt fires Triggered with the player who used it; a Sound
        -- fires Played when it starts. The game connects both, so the shim has to
        -- hand back a Signal rather than nil.
        Triggered = true,
        Played = true,
        Ended = true,
}

-- Remotes carry their own events. The client connects OnClientEvent and the
-- server connects OnServerEvent; a missing one here is a Connect on nil, which
-- is exactly the class of failure this harness exists to catch.
local REMOTE_EVENTS = {
        RemoteEvent = { OnClientEvent = true, OnServerEvent = true },
        RemoteFunction = { OnClientInvoke = true, OnServerInvoke = true },
}

-- A property read that was never assigned returns nil, the way the engine
-- returns the class default. The glue only reads back what it set.
function Instance:__index(key)
        local raw = rawget(Instance, key)
        if raw ~= nil then
                return raw
        end
        local signals = rawget(self, "signals")
        if signals and signals[key] then
                return signals[key]
        end
        if INSTANCE_EVENTS[key] then
                local sig = Signal.new()
                rawget(self, "signals")[key] = sig
                return sig
        end
        local classEvents = REMOTE_EVENTS[rawget(self, "ClassName")]
        if classEvents and classEvents[key] then
                local sig = Signal.new()
                rawget(self, "signals")[key] = sig
                return sig
        end
        return nil
end

-- Assigning Parent must also maintain the child list, or FindFirstChild cannot
-- find anything and WaitForChild would hang forever.
function Instance:__newindex(key, value)
        if key == "Parent" then
                local old = rawget(self, "Parent")
                if old then
                        local siblings = rawget(old, "children")
                        if siblings then
                                for i, child in ipairs(siblings) do
                                        if child == self then
                                                table.remove(siblings, i)
                                                break
                                        end
                                end
                        end
                end
                rawset(self, "Parent", value)
                if value then
                        local siblings = rawget(value, "children")
                        if siblings then
                                table.insert(siblings, self)
                        end
                end
                return
        end

        -- An event: make it a Signal the first time it is assigned, so
        -- `x.Changed:Connect(fn)` works.
        if type(value) == "table" and getmetatable(value) == Signal then
                rawget(self, "signals")[key] = value
                return
        end

        rawset(self, key, value)
end

function Instance:GetChildren()
        local out = {}
        for _, child in ipairs(rawget(self, "children")) do
                table.insert(out, child)
        end
        return out
end

function Instance:GetDescendants()
        local out = {}
        local function walk(node)
                for _, child in ipairs(rawget(node, "children")) do
                        table.insert(out, child)
                        walk(child)
                end
        end
        walk(self)
        return out
end

-- recursive is the second argument, the way the engine spells it. The client
-- uses it to reach a label inside a panel, so without it every stat lookup
-- silently misses and the HUD keeps its placeholder text.
function Instance:FindFirstChild(name, recursive)
        for _, child in ipairs(rawget(self, "children")) do
                if child.Name == name then
                        return child
                end
        end
        if recursive then
                for _, child in ipairs(rawget(self, "children")) do
                        local found = child:FindFirstChild(name, true)
                        if found then
                                return found
                        end
                end
        end
        return nil
end

-- WaitForChild returns immediately when the child exists. When it does not, the
-- engine yields; here that is a loud error, because in a headless run it means
-- the server never created something the client needs. Hanging forever would be
-- far worse than failing.
function Instance:WaitForChild(name, _timeout)
        local found = self:FindFirstChild(name)
        if found then
                return found
        end
        error("RobloxShim: WaitForChild(\"" .. tostring(name) .. "\") timed out under " .. self.Name, 2)
end

function Instance:FindFirstChildOfClass(className)
        for _, child in ipairs(rawget(self, "children")) do
                if child.ClassName == className then
                        return child
                end
        end
        return nil
end

function Instance:FindFirstChildWhichIsA(className)
        for _, child in ipairs(rawget(self, "children")) do
                if isA(child, className) then
                        return child
                end
        end
        return nil
end

function Instance:IsA(className)
        return isA(self, className)
end

-- Client -> server calls. In a headless run there is no server to answer, so
-- these record the call and return nothing. A test that cares about the answer
-- calls the server's OnServerInvoke directly, which is how the real request
-- path is exercised.
function Instance:InvokeServer(...)
        rawset(self, "invokedWith", { ... })
        return nil
end

-- Server -> client pushes. Firing on the client side is how the harness feeds a
-- payload to the HUD, which is what proves the client can actually render one.
function Instance:FireClient(_player, ...)
        local sig = rawget(self, "signals").OnClientEvent
        if sig then
                sig:Fire(...)
        end
end

function Instance:FireAllClients(...)
        local sig = rawget(self, "signals").OnClientEvent
        if sig then
                sig:Fire(...)
        end
end

-- The server side of a remote function: the glue assigns OnServerInvoke and the
-- harness calls it to drive a real request end to end.
function Instance:InvokeClient(_player, ...)
        return nil
end

function Instance:Destroy()
        self.Parent = nil
        rawset(self, "children", {})
end

-- Sound:Play() in the engine starts playback and fires Played. The shim keeps
-- the state a game reads back, and fires the signal so a listener that reacts to
-- audio actually runs in a test.
function Instance:Play()
        if rawget(self, "ClassName") ~= "Sound" then
                return
        end
        rawset(self, "Playing", true)
        rawset(self, "playCount", (rawget(self, "playCount") or 0) + 1)
        local signals = rawget(self, "signals")
        if signals and signals.Played then
                signals.Played:Fire()
        end
end

function Instance:Stop()
        if rawget(self, "ClassName") ~= "Sound" then
                return
        end
        rawset(self, "Playing", false)
        local signals = rawget(self, "signals")
        if signals and signals.Ended then
                signals.Ended:Fire()
        end
end

-- A ProximityPrompt fires Triggered(player) when a player uses it. Nothing in a
-- headless run presses the key, so tests call this directly; the game's own
-- handler is what is being exercised either way.
function Instance:Trigger(player)
        if rawget(self, "ClassName") ~= "ProximityPrompt" then
                return
        end
        if rawget(self, "Enabled") == false then
                return
        end
        rawset(self, "triggeredCount", (rawget(self, "triggeredCount") or 0) + 1)
        local signals = rawget(self, "signals")
        if signals and signals.Triggered then
                signals.Triggered:Fire(player)
        end
end

function Instance:ClearAllChildren()
        for _, child in ipairs(rawget(self, "children")) do
                rawset(child, "Parent", nil)
        end
        rawset(self, "children", {})
end

-- Models move as a unit. The shim only needs the pivot to be readable, since
-- the world builder positions monsters through it.
function Instance:PivotTo(cf)
        rawset(self, "pivot", cf)
        if rawget(self, "PrimaryPart") then
                rawget(self, "PrimaryPart").CFrame = cf
        end
end

function Instance:GetPivot()
        return rawget(self, "pivot") or CFrame.new(0, 0, 0)
end

-- Attributes: a small per-instance value store, used by the client to
-- remember what it last drew on a panel so it does not rebuild it every
-- frame. Reading one that was never set returns nil, as on the engine.
function Instance:SetAttribute(name, value)
        local attrs = rawget(self, "attributes")
        if not attrs then
                attrs = {}
                rawset(self, "attributes", attrs)
        end
        attrs[name] = value
end

function Instance:GetAttribute(name)
        local attrs = rawget(self, "attributes")
        if not attrs then
                return nil
        end
        return attrs[name]
end

--------------------------------------------------------------------------
-- Services
--------------------------------------------------------------------------

local function makeSignalHost(tbl)
        return setmetatable(tbl, {
                __index = function(self, key)
                        local v = rawget(self, key)
                        if v ~= nil then
                                return v
                        end
                        -- Lazy-create a signal for any event name, so PlayerAdded,
                        -- Heartbeat, Touched and friends all resolve.
                        local sig = Signal.new()
                        rawset(self, key, sig)
                        return sig
                end,
        })
end

local services = {}

local function makeService(className)
        local svc = makeSignalHost({ ClassName = className, Name = className, children = {} })
        -- Services behave like Instances for child lookup.
        svc.FindFirstChild = Instance.FindFirstChild
        svc.WaitForChild = Instance.WaitForChild
        svc.GetChildren = Instance.GetChildren
        svc.GetDescendants = Instance.GetDescendants
        svc.FindFirstChildOfClass = Instance.FindFirstChildOfClass
        return svc
end

local ReplicatedStorage = makeService("ReplicatedStorage")
ReplicatedStorage.Parent = nil
local SharedFolder = newInstance("Folder")
SharedFolder.Name = "Shared"
SharedFolder.Parent = ReplicatedStorage
local RemotesFolder = newInstance("Folder")
RemotesFolder.Name = "Remotes"
RemotesFolder.Parent = ReplicatedStorage

local Workspace = makeService("Workspace")
local Lighting = makeService("Lighting")

-- Workspace.CurrentCamera always exists in a running game, and the HUD reads its
-- ViewportSize to decide how large a panel may be on the screen it is on. The
-- shim models a reference desktop screen; a test that wants to exercise the
-- phone layout passes the size into HudLayout directly, which is why that module
-- takes the viewport as an argument rather than reading this.
local Camera = newInstance("Camera")
Camera.Name = "Camera"
Camera.ViewportSize = Vector2.new(1280, 720)
Camera.Parent = Workspace
-- Set explicitly: Workspace is a signal host that lazy-creates a Signal for any
-- unknown key, so leaving CurrentCamera unset would hand the HUD a Signal
-- instead of a camera.
Workspace.CurrentCamera = Camera

-- A player as the glue sees one: an instance with a UserId, a PlayerGui to hang
-- the HUD on, and the events a join and a respawn fire. Made here rather than in
-- the harness so the server's own Players.PlayerAdded can hand it out.
local function makePlayer(userId: number, name: string)
        local player = newInstance("Model")
        player.ClassName = "Player"
        player.Name = name or ("Player" .. tostring(userId))
        player.UserId = userId
        player.DisplayName = player.Name

        local gui = newInstance("ScreenGui")
        gui.Name = "PlayerGui"
        gui.Parent = player

        player.PlayerGui = gui
        player.Character = nil

        player.LoadCharacter = function()
                local character = newInstance("Model")
                character.Name = player.Name
                local root = newInstance("Part")
                root.Name = "HumanoidRootPart"
                root.Parent = character
                local humanoid = newInstance("Humanoid")
                humanoid.Name = "Humanoid"
                humanoid.Parent = character
                player.Character = character
                player.CharacterAdded:Fire(character)
        end

        player.Kick = function() end
        player.IsDescendantOf = function() return true end
        return player
end

Shim.makePlayer = makePlayer
local PlayersService = makeSignalHost({
        ClassName = "Players",
        Name = "Players",
        children = {},
        LocalPlayer = nil,
})

function PlayersService:GetPlayers()
        return {}
end

function PlayersService:GetPlayerFromCharacter()
        return nil
end

function PlayersService:GetPlayerByUserId()
        return nil
end

-- RunService.Heartbeat is never fired by the harness; the tests drive the loop
-- themselves by calling the callback they captured.
local RunService = makeSignalHost({ ClassName = "RunService", Name = "RunService" })

-- DataStore: in-memory, so a save/load round trip is exercised without a
-- network. A store that always returned nil would hide the load path.
local storeData = {}
local DataStoreService = {
        ClassName = "DataStoreService",
        Name = "DataStoreService",
}

function DataStoreService:GetDataStore(name)
        return {
                GetAsync = function(_, key)
                        return storeData[name .. "/" .. key]
                end,
                SetAsync = function(_, key, value)
                        storeData[name .. "/" .. key] = value
                        return key
                end,
                UpdateAsync = function(_, key, fn)
                        local new = fn(storeData[name .. "/" .. key])
                        storeData[name .. "/" .. key] = new
                        return new
                end,
        }
end

local TweenService = {
        ClassName = "TweenService",
        Name = "TweenService",
}
function TweenService:Create(_instance, _info, _goal)
        return {
                Play = function() end,
                Cancel = function() end,
                Completed = Signal.new(),
        }
end

local MarketplaceService = makeSignalHost({
        ClassName = "MarketplaceService",
        Name = "MarketplaceService",
})
function MarketplaceService:PromptGamePassPurchase() end
function MarketplaceService:PromptProductPurchase() end
function MarketplaceService:UserOwnsGamePassAsync()
        return false
end
function MarketplaceService:GetProductInfo()
        return nil
end

local SERVICE_MAP = {
        ReplicatedStorage = ReplicatedStorage,
        Workspace = Workspace,
        Lighting = Lighting,
        Players = PlayersService,
        RunService = RunService,
        DataStoreService = DataStoreService,
        TweenService = TweenService,
        MarketplaceService = MarketplaceService,
}

local game = {
        ClassName = "DataModel",
        Name = "DataModel",
        Workspace = Workspace,
        PlaceId = 0,
        JobId = "shim",
}
function game:GetService(name)
        local svc = SERVICE_MAP[name]
        if not svc then
                error("RobloxShim: GetService(\"" .. tostring(name) .. "\") is not modelled", 2)
        end
        return svc
end
function game:BindToClose(fn)
        rawset(self, "bindToClose", fn)
end

--------------------------------------------------------------------------
-- Globals the glue expects
--------------------------------------------------------------------------

-- task.spawn and friends run their work on coroutines, and task.wait yields.
--
-- This is not decoration. The server ends with
-- `task.spawn(function() while true do task.wait(90) ... end end)` for periodic
-- saving. If task.wait returned instantly and the body ran inline, that loop
-- would never end and the harness would hang. Yielding models what the engine
-- actually does: the body runs up to its first wait, then parks.
--
-- __drain resumes parked work a bounded number of times and then abandons
-- anything still parked. A background loop therefore runs a few iterations and
-- stops, while a one-shot spawn (onPlayerAdded, a damage-number tween) runs to
-- completion. Nothing in the glue needs a scheduler more faithful than this.
local taskQueue = {}
local taskStepCap = 2000
local taskResumeCap = 8

local task = {}

local function enqueue(fn, args)
        local job = {
                co = coroutine.create(fn),
                args = args,
                resumes = 0,
        }
        table.insert(taskQueue, job)
        return job
end

task.spawn = function(fn, ...)
        enqueue(fn, { ... })
end

task.delay = function(_seconds, fn, ...)
        enqueue(fn, { ... })
end

task.defer = function(fn, ...)
        enqueue(fn, { ... })
end

-- Yielding is what parks a job; drain resumes it.
task.wait = function(_seconds)
        return coroutine.yield()
end

-- Run queued work. Returns the number of resumes performed.
task.drain = function(maxSteps: number?)
        local cap = maxSteps or taskStepCap
        local steps = 0
        local queue = taskQueue

        while #queue > 0 do
                local job = table.remove(queue, 1)
                steps += 1
                if steps > cap then
                        error(string.format(
                                "RobloxShim: task queue still busy after %d steps; a queued task is not terminating",
                                cap), 2)
                end

                local ok, err = coroutine.resume(job.co, table.unpack(job.args))
                job.args = {}
                if not ok then
                        error("RobloxShim: queued task failed: " .. tostring(err), 2)
                end

                -- A job that is still suspended has more to do. Re-queue it until
                -- its resume budget runs out, then leave it parked: that is what
                -- stops a background `while true` loop from spinning forever.
                if coroutine.status(job.co) ~= "dead" then
                        job.resumes += 1
                        if job.resumes < taskResumeCap then
                                table.insert(queue, job)
                        end
                end
        end
        return steps
end

local function install(env: { [string]: any })
        env.Vector3 = Vector3
        env.CFrame = CFrame
        env.Color3 = Color3
        env.UDim = UDim
        env.UDim2 = UDim2
        env.TweenInfo = TweenInfo
        env.Vector2 = Vector2
        env.NumberSequence = NumberSequence
        env.NumberSequenceKeypoint = NumberSequenceKeypoint
        env.ColorSequence = ColorSequence
        env.ColorSequenceKeypoint = ColorSequenceKeypoint
        env.NumberRange = NumberRange
        env.Enum = Enum
        env.Instance = { new = newInstance }
        env.game = game
        env.task = task
        env.wait = task.wait
        env.spawn = task.spawn
        env.delay = task.delay
        env.workspace = Workspace
        -- setfenv replaces a chunk's whole environment, so without this a module
        -- would lose math, string, table, ipairs, pairs and friends. The engine
        -- globals above win; everything else comes from the real standard
        -- library, which is what the engine provides too.
        return setmetatable(env, { __index = _G })
end

--------------------------------------------------------------------------
-- Loading the real files
--------------------------------------------------------------------------

-- Turn a logical path like "shared/Config" into a require-able module, out of
-- the generated source bundle. Relative requires resolve against the requiring
-- module's directory, and `script.Child` resolves to a sibling file, which is
-- what Rojo does in the real place.
--
-- The bundle exists because the standalone Luau CLI has no io library, so a
-- test cannot read a .luau file. scripts/gen-roblox-sources.py writes the whole
-- roblox/src tree into tests/.generated/Sources.luau, and test-roblox.sh
-- regenerates it before every run so it can never be stale.
local function makeRequire(sources: { [string]: string }, env: { [string]: any })
        local cache = {}
        local pending = {}
        -- One table, shared by every module, standing in for the engine's _G.
        local sharedGlobals = {}

        local function normalise(path: string, fromDir: string): string
                if path:sub(1, 1) ~= "." then
                        return path
                end
                local parts = {}
                for part in string.gmatch(fromDir, "[^/]+") do
                        table.insert(parts, part)
                end
                for part in string.gmatch(path, "[^/]+") do
                        if part == ".." then
                                table.remove(parts)
                        elseif part ~= "." then
                                table.insert(parts, part)
                        end
                end
                return table.concat(parts, "/")
        end

        -- A module handle is a table with __path; both require styles and
        -- script.Child produce one, so there is a single resolution path.
        local function handle(path: string)
                if sources[path] == nil then
                        return nil
                end
                return { __path = path, Name = path:match("([^/]+)$") }
        end

        -- A folder handle, for script.Parent. A folder is not a module -- there
        -- is no source at its path -- so it cannot be required, but its children
        -- resolve exactly as they do through script.Child. Without this,
        -- require(script.Parent.X) fails under the harness while working in
        -- Roblox, which is the class of shim/game mismatch this file exists to
        -- avoid.
        local function folderHandle(dir: string)
                return setmetatable({ __path = dir, Name = dir:match("([^/]+)$") or dir }, {
                        __index = function(_, childName)
                                return handle(dir .. "/" .. childName)
                        end,
                })
        end

        local load

        local function run(path: string)
                if cache[path] ~= nil then
                        return cache[path]
                end
                local source = sources[path]
                if source == nil then
                        error("RobloxShim: no module at " .. path, 2)
                end
                if pending[path] then
                        error("RobloxShim: circular require through " .. path, 2)
                end
                pending[path] = true

                local chunk, err = loadstring(source, "@" .. path .. ".luau")
                if not chunk then
                        error("RobloxShim: " .. path .. " failed to compile: " .. tostring(err), 2)
                end

                local dir = path:match("^(.*)/[^/]+$") or ""
                local moduleRequire = function(spec: any)
                        if type(spec) == "string" then
                                return load(normalise(spec, dir))
                        end
                        if type(spec) == "table" and spec.__path then
                                return load(spec.__path)
                        end
                        error("RobloxShim: unsupported require argument", 2)
                end

                -- Inside a Roblox module `script` is the module. For an
                -- init.server.luau the module IS the folder, so its children are
                -- siblings; for a plain module they are a subfolder of its name.
                local isInit = path:match("/init%.[^/]+$") ~= nil or path:match("^init%.") ~= nil
                local childDir = isInit and dir or path
                local scriptObj = setmetatable({
                        __path = path,
                        Name = path:match("([^/]+)$"),
                }, {
                        __index = function(_, childName)
                                if childName == "Parent" then
                                        return folderHandle(dir)
                                end
                                return handle(childDir .. "/" .. childName)
                        end,
                })

                -- A Roblox module reads `require` and `script` as globals, not
                -- parameters. Each module gets its own environment that falls
                -- back to the engine globals, so a nested require binds the
                -- nested module's own script without clobbering its parent.
                local moduleEnv = setmetatable({
                        require = moduleRequire,
                        script = scriptObj,
                        -- The client publishes _G.AXArena. The CLI's own _G is
                        -- read-only, so each module gets a writable one; it is
                        -- the same table across modules so a publish is visible.
                        _G = sharedGlobals,
                }, { __index = env })

                setfenv(chunk, moduleEnv)
                local result = chunk()
                pending[path] = nil
                cache[path] = result
                return result
        end

        load = function(path: string)
                local resolved = normalise(path, "")
                return run(resolved)
        end

        return load
end

-- A folder whose children are modules on disk. The glue reaches modules by
-- name (`Shared.Config`, `Shared:WaitForChild("Config")`), so both lookup
-- styles resolve to a module handle.
local function moduleFolder(name: string, dir: string, sources: { [string]: string })
        local folder = newInstance("Folder")
        folder.Name = name

        local function resolve(childName: string)
                local path = dir .. "/" .. childName
                if sources[path] == nil then
                        return nil
                end
                return { __path = path, Name = childName }
        end

        setmetatable(folder, {
                __index = function(self, key)
                        return resolve(key) or Instance.__index(self, key)
                end,
                __newindex = Instance.__newindex,
        })

        folder.FindFirstChild = function(_, childName)
                return resolve(childName)
        end
        folder.WaitForChild = function(self, childName)
                local found = resolve(childName)
                if not found then
                        error("RobloxShim: WaitForChild(\"" .. tostring(childName) .. "\") has no module under " .. dir, 2)
                end
                return found
        end

        return folder
end

-- The one call a test needs. Returns an environment carrying the engine
-- globals, a require() that runs the real source, and a ReplicatedStorage tree
-- wired so the glue's own lookups work.
-- The services above are module-level, so two harnesses in one process would
-- otherwise share world state, connected handlers and saved data. Clearing them
-- here is what makes each test start from an empty engine.
local function resetEngine()
        rawset(Workspace, "children", {})
        rawset(Workspace, "signals", {})

        rawset(Lighting, "children", {})
        rawset(Lighting, "signals", {})

        rawset(RunService, "signals", {})

        rawset(PlayersService, "children", {})
        rawset(PlayersService, "signals", {})
        rawset(PlayersService, "LocalPlayer", nil)

        rawset(ReplicatedStorage, "children", {})
        rawset(ReplicatedStorage, "signals", {})
        rawset(ReplicatedStorage, "Remotes", nil)

        for key in pairs(storeData) do
                storeData[key] = nil
        end
end

function Shim.harness(sources: { [string]: string })
        resetEngine()

        -- Every harness starts on the reference screen. A test that wants the
        -- phone layout sets a smaller ViewportSize before loading the client,
        -- which is the same thing the engine does when the screen changes.
        Camera.ViewportSize = Vector2.new(1280, 720)
        rawset(Workspace, "children", { Camera })
        rawset(Workspace, "CurrentCamera", Camera)

        local env = install({})
        local load = makeRequire(sources, env)

        local sharedFolder = moduleFolder("Shared", "shared", sources)
        local remotes = newInstance("Folder")
        remotes.Name = "Remotes"
        rawset(ReplicatedStorage, "children", { sharedFolder, remotes })
        rawset(ReplicatedStorage, "Remotes", remotes)

        -- The client reads Players.LocalPlayer at load time, so a harness run
        -- has to supply one before the client is loaded.
        env.__player = makePlayer(1, "ShimPlayer")
        rawset(PlayersService, "LocalPlayer", env.__player)
        rawset(PlayersService, "children", { env.__player })

        env.__load = load
        env.__drain = task.drain
        env.__remotes = remotes
        env.__shared = sharedFolder
        env.__replicatedRemotes = remotes
        env.__players = PlayersService
        env.__workspace = Workspace
        env.__game = game
        return env
end

-- Boot the server and let its queued work run, the way a live server does
-- before anyone joins. Returns the environment.
function Shim.bootServer(sources: { [string]: string })
        local env = Shim.harness(sources)
        env.__load("server/init.server")
        env.__drain()
        return env
end

-- Join a player: fire PlayerAdded and spawn a character, then let the queued
-- work run. This is the exact path a real join takes.
function Shim.joinPlayer(env, userId: number?, name: string?)
        local player = makePlayer(userId or 2, name or "ShimPlayer")
        rawset(PlayersService, "children", { player })
        rawset(PlayersService, "LocalPlayer", player)
        env.__player = player

        PlayersService.PlayerAdded:Fire(player)
        env.__drain()
        player.LoadCharacter()
        env.__drain()
        return player
end

function Shim.install(env)
        return install(env)
end

Shim.Vector3 = Vector3
Shim.Vector2 = Vector2
Shim.CFrame = CFrame
Shim.Color3 = Color3
Shim.UDim2 = UDim2
Shim.Signal = Signal

return Shim
