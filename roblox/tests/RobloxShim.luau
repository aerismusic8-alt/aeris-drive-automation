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
Vector3.__type = "Vector3"

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

function Vector3.__div(a, b)
        if type(b) == "number" then
                return Vector3.new(a.X / b, a.Y / b, a.Z / b)
        end
        return Vector3.new(a.X / b.X, a.Y / b.Y, a.Z / b.Z)
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
-- The firearm rig guards its shot handler with `typeof(cameraCF) ~= "CFrame"`,
-- and typeof reads the class table's tag. Without this the guard rejected every
-- shot and the damage path was unreachable from a test.
CFrame.__type = "CFrame"

function CFrame.new(x: any, y: number?, z: number?)
        -- A Roblox CFrame faces -Z, so a fresh one looks along (0, 0, -1). The
        -- shim keeps only the position and a look vector, which is all the
        -- firearm rig reads back: it dots the camera's LookVector against the
        -- shot direction to reject a spoofed aim.
        if type(x) == "table" and getmetatable(x) == Vector3 then
                return setmetatable({ Position = x, LookVector = Vector3.new(0, 0, -1) }, CFrame)
        end
        return setmetatable({ Position = Vector3.new(x or 0, y or 0, z or 0), LookVector = Vector3.new(0, 0, -1) }, CFrame)
end

function CFrame.Angles(_rx: number?, _ry: number?, _rz: number?)
        return setmetatable({ Position = Vector3.new(0, 0, 0) }, CFrame)
end

function CFrame.lookAt(at, look)
        local dir = look - at
        local magnitude = dir.Magnitude
        local unit = if magnitude > 0.001 then dir / magnitude else Vector3.new(0, 0, -1)
        return setmetatable({ Position = at, LookVector = unit }, CFrame)
end

function CFrame.__mul(a, b)
        return setmetatable({ Position = a.Position + b.Position, LookVector = a.LookVector or Vector3.new(0, 0, -1) }, CFrame)
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
Color3.__type = "Color3"

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
UDim2.__type = "UDim2"

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
Vector2.__type = "Vector2"

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
        Material = {
                Grass = 1,
                Ground = 2,
                Neon = 3,
                Slate = 4,
                SmoothPlastic = 5,
                Wood = 6,
                -- The garden's scenery uses these. Adding a material to the shim
                -- is cheaper than flattening the world to the four the old game
                -- happened to use, and the shim's job is to model what the
                -- engine accepts.
                LeafyGrass = 7,
                Pebble = 8,
                Cobblestone = 9,
                Concrete = 10,
                Sand = 11,
                Rock = 12,
                Limestone = 13,
                Fabric = 14,
                Marble = 15,
                Metal = 16,
                WoodPlanks = 17,
                Brick = 18,
                Granite = 19,
                Glass = 20,
                Plastic = 21,
                CorrodedMetal = 22,
                Ice = 23,
                Foil = 24,
                DiamondPlate = 25,
        },
        SurfaceType = { Smooth = 1, Studs = 2, Inlet = 3 },
        PartType = { Ball = 1, Cylinder = 2, Block = 3, Wedge = 4 },
        Font = { GothamBlack = 1, GothamBold = 2, Gotham = 3 },
        ScreenInsets = { CoreUISafeInsets = 1, None = 2, DeviceSafeInsets = 3 },
        ZIndexBehavior = { Sibling = 1, Global = 2 },
        EasingStyle = { Quad = 1, Quart = 2, Sine = 3, Linear = 4 },
        EasingDirection = { Out = 1, In = 2, InOut = 3 },
        TextTruncate = { AtEnd = 1, None = 2 },
        ApplyStrokeMode = { Border = 1, Contextual = 2 },
        -- The HUD sizes a scrolling list to its content with AutomaticSize, so
        -- the enum has to resolve or every panel build throws.
        AutomaticSize = { None = 1, X = 2, Y = 3, XY = 4 },
        ScrollingDirection = { Y = 1, X = 2, XY = 3 },
        TextXAlignment = { Center = 1, Left = 2, Right = 3 },
        TextYAlignment = { Center = 1, Top = 2, Bottom = 3 },
        ProductPurchaseDecision = { NotProcessedYet = 1, PurchaseGranted = 2 },
        -- Services use these; the shim only needs the names to resolve.
        RunContext = { Server = 1, Client = 2, Legacy = 3 },
        -- The buy menu opens on the B key and the client reads the keycode off
        -- the input object. Only the codes the game compares against are here;
        -- an unmodelled one raises, which is the shim's contract.
        KeyCode = { Unknown = 0, B = 1, One = 2, Two = 3, Three = 4, Four = 5, R = 6, E = 7 },
        CameraMode = { Classic = 1, LockFirstPerson = 2 },
        -- The weapon's server raycast excludes the tool and the shooter.
        RaycastFilterType = { Exclude = 1, Include = 2, Blacklist = 1, Whitelist = 2 },
        HumanoidStateType = { Running = 1, Dead = 2, Jumping = 3 },
        HumanoidRigType = { R6 = 1, R15 = 2 },
        Platform = { Windows = 1, Macintosh = 2, Linux = 3, Android = 4, iOS = 5 },
}

local Enum = {}
local enumGroups = {}
setmetatable(Enum, {
        __index = function(_, group)
                local cached = enumGroups[group]
                if cached then
                        return cached
                end
                local members = ENUM_MEMBERS[group]
                -- A group the shim has not enumerated is treated permissively:
                -- its members are created on demand. The defined groups above stay
                -- strict, because those are the ones this game's code compares
                -- against and a typo there should still fail. The weapon rig
                -- touches a long tail of input, camera and render enums whose
                -- exact values no test depends on -- erroring on those would block
                -- the damage path for no benefit.
                local strict = members ~= nil
                if not members then
                        members = setmetatable({}, {
                                __index = function(_, member)
                                        return member
                                end,
                        })
                end
                local out = {}
                -- Enum items are singletons in the engine, so `a.Shape ==
                -- Enum.PartType.Ball` is an identity test. Handing out a fresh
                -- table per access made every such comparison false, which hid
                -- whether the world was built from balls or boxes. Both the group
                -- and its items are therefore created once and reused.
                local items = {}
                setmetatable(out, {
                        __index = function(_, member)
                                if members[member] == nil then
                                        if strict then
                                                error("RobloxShim: unknown Enum." .. group .. "." .. tostring(member), 2)
                                        end
                                        members[member] = 0
                                end
                                local item = items[member]
                                if not item then
                                        item = {
                                                EnumType = group,
                                                Name = member,
                                                Value = members[member],
                                        }
                                        items[member] = item
                                end
                                return item
                        end,
                })
                enumGroups[group] = out
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
        local connection
        connection = {
                Connected = true,
                -- A real Disconnect stops the handler being called. Modelling it
                -- as a no-op makes a test that disconnects and then fires the
                -- signal see stale handlers, which is a test passing on a
                -- behaviour the game does not have.
                Disconnect = function()
                        connection.Connected = false
                        for index, handler in ipairs(self.handlers) do
                                if handler == fn then
                                        table.remove(self.handlers, index)
                                        break
                                end
                        end
                end,
        }
        return connection
end

function Signal:Fire(...)
        -- Iterate a copy: a handler that connects or disconnects during the fire
        -- must not disturb the walk.
        local handlers = table.clone(self.handlers)
        for _, fn in ipairs(handlers) do
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
        "UICorner", "UIStroke", "UIPadding", "ViewportFrame", "Camera", "BillboardGui",
        "ParticleEmitter", "PointLight", "WeldConstraint", "Atmosphere", "Clouds", "Sky",
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
        -- Breachline's match layer. A weapon is a Tool in a player's Backpack,
        -- a team is a Team in the Teams service, and a range target signals a
        -- hit through a BindableEvent.
        "Tool", "Backpack", "Team", "BindableEvent",
        -- The firearm rig welds itself to the character with a Motor6D and owns
        -- an UnreliableRemoteEvent for muzzle flashes.
        "Motor6D", "UnreliableRemoteEvent",
}) do
        VALID_CLASSES[name] = true
end

local Instance = {}
Instance.__index = Instance

-- The engine's typeof() reports an Instance as "Instance", and shipped guards
-- test exactly that: recenterModelPivot and FourDToolAuthority both reject a
-- non-Instance with `typeof(x) ~= "Instance"`. The typeof global below reads
-- this tag off the class table, so without it every instance looked like a
-- plain table and those guards dropped real work -- a map model handed to the
-- registry was rejected as "not a Model" for the same reason.
Instance.__type = "Instance"

-- The screen the shim reports. A ScreenGui's AbsoluteSize is the viewport, and
-- a child's AbsoluteSize is derived from its parent, so the HUD's layout maths
-- has real numbers to work with rather than zeros. Kept in step with
-- Camera.ViewportSize wherever that is set.
local screenSize = Vector2.new(1280, 720)

-- Roblox's own topbar height. Declared here, next to the screen size, because the
-- Instance __index below derives a ScreenGui's AbsoluteSize from it; a local
-- declared further down would be a different upvalue and the derivation would
-- read a nil global instead.
local guiInset = Vector2.new(0, 36)

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
        -- A Tool and a Backpack are both containers the match code looks up by
        -- class, and a Player is a Model for the weapon's ancestry walk.
        if className == "Tool" then
                return self.ClassName == "Tool"
        end
        if className == "Backpack" then
                return self.ClassName == "Backpack"
        end
        if className == "Model" then
                return self.ClassName == "Model" or self.ClassName == "Player"
        end
        if className == "Player" then
                return self.ClassName == "Player"
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
                -- Physics and render defaults the match code and the range
                -- targets read back: a target flips CanQuery on death, a planted
                -- bomb is Anchored, and a vest is Massless.
                self.Anchored = false
                self.CanCollide = true
                self.CanQuery = true
                self.CanTouch = true
                self.Massless = false
                self.Transparency = 0
                self.Color = Color3.fromRGB(163, 162, 165)
                -- A Part defaults to a Block in the engine, and the garden sets
                -- Shape to Ball or Cylinder on most of its scenery. Without the
                -- default every part read back as nil and a shape test could not
                -- tell a rounded garden from a boxy one.
                if className == "Part" then
                        self.Shape = Enum.PartType.Block
                end
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

        -- A Tool is a weapon in a Backpack or a character. The game reads its
        -- Name, parents it, and (for the starting gun) checks it is a Tool.
        if className == "Tool" then
                self.CanBeDropped = true
                self.RequiresHandle = true
                self.Enabled = true
        end

        -- A BindableEvent is the range target's damage channel: RangeTargets
        -- parents one named TakeDamage under each target, and the weapon fires
        -- it. Modelling it as a real Signal is what lets a hit be observed.
        if className == "BindableEvent" then
                self.Event = Signal.new()
        end

        -- The hold weld. setupHoldWeld assigns Part0/Part1/C0/C1, so the fields
        -- exist rather than being raw writes the rig would read back as nil.
        if className == "Motor6D" then
                self.Part0 = nil
                self.Part1 = nil
                self.C0 = CFrame.new(0, 0, 0)
                self.C1 = CFrame.new(0, 0, 0)
        end

        -- A Humanoid carries health, and the weapon's damage path calls
        -- TakeDamage on it while the match loop waits on Died. Both are modelled
        -- so a shot that lands is observable and a death ends the round.
        -- A weapon's shot origin is an Attachment on the tool, and its world
        -- position is what the ballistics solve from. Defaulting it here keeps
        -- a tool that never set a CFrame from erroring on the read.
        if className == "Attachment" then
                self.CFrame = CFrame.new(0, 0, 0)
                self.WorldPosition = Vector3.new(0, 0, 0)
                self.WorldCFrame = CFrame.new(0, 0, 0)
        end

        -- A ProximityPrompt carries its player-facing text, which the plant and
        -- defuse prompts set and a test can read back.
        if className == "ProximityPrompt" then
                self.ActionText = ""
                self.ObjectText = ""
                self.HoldDuration = 0
                self.Enabled = true
        end

        if className == "Humanoid" then
                self.Health = 100
                self.MaxHealth = 100
                self.WalkSpeed = 16
                self.JumpPower = 50
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
        -- Tool events. The firearm rig welds itself to the character on Equipped
        -- and tears the weld down on Unequipped.
        Equipped = true,
        Unequipped = true,
}

-- Remotes carry their own events. The client connects OnClientEvent and the
-- server connects OnServerEvent; a missing one here is a Connect on nil, which
-- is exactly the class of failure this harness exists to catch.
local REMOTE_EVENTS = {
        RemoteEvent = { OnClientEvent = true, OnServerEvent = true },
        -- The firearm rig replicates muzzle flashes over an unreliable remote,
        -- so it needs the same OnClientEvent/OnServerEvent surface.
        UnreliableRemoteEvent = { OnClientEvent = true, OnServerEvent = true },
        RemoteFunction = { OnClientInvoke = true, OnServerInvoke = true },
}

-- A property read that was never assigned returns nil, the way the engine
-- returns the class default. The glue only reads back what it set.
function Instance:__index(key)
        local raw = rawget(Instance, key)
        if raw ~= nil then
                return raw
        end
        -- AbsoluteSize is derived, not stored: a GuiObject's absolute size is its
        -- parent's absolute size times its scale, plus its offset. The garden HUD
        -- reads it to size the progress fill, so returning nil here would make
        -- the fill zero-width and look like a bug in the game rather than a gap
        -- in the shim.
        if key == "AbsoluteSize" then
                local parent = rawget(self, "Parent")
                local parentSize
                if rawget(self, "ClassName") == "ScreenGui" or parent == nil then
                        -- A ScreenGui with IgnoreGuiInset off draws in the space
                        -- below Roblox's topbar, so its absolute size is the
                        -- viewport less the inset. Reporting the raw viewport here
                        -- was the blind spot that let the bottom bar be placed off
                        -- the real bottom edge of a phone.
                        parentSize = screenSize
                        if rawget(self, "ClassName") == "ScreenGui" and rawget(self, "IgnoreGuiInset") ~= true then
                                parentSize = Vector2.new(screenSize.X, math.max(1, screenSize.Y - guiInset.Y))
                        end
                else
                        parentSize = parent.AbsoluteSize
                end
                local size = rawget(self, "Size")
                if not size then
                        return parentSize
                end
                local x = (parentSize and parentSize.X or 0) * size.X.Scale + size.X.Offset
                local y = (parentSize and parentSize.Y or 0) * size.Y.Scale + size.Y.Offset
                return Vector2.new(x, y)
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
        -- A child is reachable by name, the way the engine resolves it. The
        -- match code depends on this: it walks `range.BombSites`,
        -- `site.PlantPrompt` and `state.JoinMatch` rather than calling
        -- FindFirstChild, so without the lookup the round loop sees nil.
        if type(key) == "string" then
                for _, child in ipairs(rawget(self, "children") or {}) do
                        if rawget(child, "Name") == key then
                                return child
                        end
                end
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
--
-- The payload is deep-copied on the way out, because that is what the engine's
-- remote serialisation does. Without the copy the "pushed" table is the server's
-- own live save, so a later server-side mutation changes a payload the test
-- already captured -- a test that passes or fails for a reason the real game
-- does not have. Tables with a metatable are left alone: those are Instances,
-- which the engine passes by reference.
local function copyForRemote(value: any): any
        if type(value) ~= "table" then
                return value
        end
        if getmetatable(value) ~= nil then
                return value
        end
        local out = {}
        for key, inner in pairs(value) do
                out[key] = copyForRemote(inner)
        end
        return out
end

function Instance:FireClient(_player, ...)
        local sig = rawget(self, "signals").OnClientEvent
        if sig then
                sig:Fire(copyForRemote(...))
        end
end

function Instance:FireAllClients(...)
        local sig = rawget(self, "signals").OnClientEvent
        if sig then
                sig:Fire(copyForRemote(...))
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

function Instance:GetPropertyChangedSignal(property: string)
        local signals = rawget(self, "propertySignals")
        if not signals then
                signals = {}
                rawset(self, "propertySignals", signals)
        end
        if not signals[property] then
                signals[property] = Signal.new()
        end
        return signals[property]
end

-- Clone deep-copies a subtree, which is how the shop hands a player a weapon:
-- it clones the template out of ServerStorage and parents the copy to the
-- Backpack. The copy carries the same ClassName, Name, source and children, so
-- the clone is the same weapon the template is.
function Instance:Clone()
        local function copy(node)
                local out = setmetatable({}, Instance)
                for key, value in pairs(rawget(node, "__props") or {}) do
                        rawset(out, key, value)
                end
                for key, value in pairs(node) do
                        if key ~= "children" and key ~= "signals" and key ~= "Parent" then
                                rawset(out, key, value)
                        end
                end
                rawset(out, "children", {})
                rawset(out, "signals", {})
                rawset(out, "Parent", nil)
                for _, child in ipairs(rawget(node, "children")) do
                        local childCopy = copy(child)
                        childCopy.Parent = out
                end
                return out
        end
        return copy(self)
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
        local previous = rawget(self, "pivot") or CFrame.new(0, 0, 0)
        rawset(self, "pivot", cf)
        -- Move the parts with the pivot. A character is spawned by pivoting it to
        -- a SpawnLocation, and the match code then checks the distance from the
        -- character's root to a bomb site -- so a pivot that did not move the
        -- root would make every plant look out of range.
        local delta = cf.Position - previous.Position
        for _, descendant in ipairs(self:GetDescendants()) do
                local partCFrame = rawget(descendant, "CFrame")
                if partCFrame and rawget(descendant, "Size") then
                        local moved = CFrame.new(partCFrame.Position + delta)
                        rawset(descendant, "CFrame", moved)
                        rawset(descendant, "Position", moved.Position)
                end
        end
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
        local previous = attrs[name]
        attrs[name] = value

        -- A change has to notify, or a HUD that only refreshes on the signal
        -- would never repaint. The engine fires both the generic AttributeChanged
        -- and the per-name signal, so both are fired here.
        if previous ~= value then
                local signals = rawget(self, "attributeSignals")
                if signals and signals[name] then
                        signals[name]:Fire()
                end
                local generic = rawget(self, "signals")
                if generic and generic.AttributeChanged then
                        generic.AttributeChanged:Fire(name, value)
                end
        end
end

-- The per-name attribute signal. The HUDs connect this for Money, Armor, HasSMG,
-- Alive and Phase, so it has to be a stable Signal per name.
function Instance:GetAttributeChangedSignal(name: string)
        local signals = rawget(self, "attributeSignals")
        if not signals then
                signals = {}
                rawset(self, "attributeSignals", signals)
        end
        if not signals[name] then
                signals[name] = Signal.new()
        end
        return signals[name]
end

-- TakeDamage is the engine's own damage entry point and the last thing the
-- weapon's applyDamage does. A test reads Health back, so the number that lands
-- is the number the game computed, armour multiplier included.
-- IsDescendantOf walks the parent chain, the way the pickup guard's
-- `Tool:IsDescendantOf(workspace)` does.
function Instance:IsDescendantOf(ancestor)
        local current = rawget(self, "Parent")
        while current do
                if current == ancestor then return true end
                current = rawget(current, "Parent")
        end
        return false
end

-- IsA walks the class name against the queried class. The shim has no class
-- hierarchy, so it matches the exact class name and the base classes a script in
-- this game actually asks about.
local ISA_BASES = {
        BasePart = { "Part", "WedgePart", "CornerWedgePart", "MeshPart", "UnionOperation", "TrussPart" },
        Part = { "WedgePart", "CornerWedgePart", "MeshPart", "UnionOperation" },
        GuiObject = { "Frame", "TextLabel", "TextButton", "ImageLabel", "ImageButton", "TextBox", "ScrollingFrame", "ViewportFrame" },
        LayerCollector = { "ScreenGui", "SurfaceGui", "BillboardGui" },
}

function Instance:IsA(className: string)
        local own = rawget(self, "ClassName")
        if own == className then return true end
        local bases = ISA_BASES[className]
        if bases then
                for _, base in ipairs(bases) do
                        if own == base then return true end
                end
        end
        return false
end

function Instance:TakeDamage(amount: number)
        if rawget(self, "ClassName") ~= "Humanoid" then
                error("RobloxShim: TakeDamage is only modelled on a Humanoid", 2)
        end
        if type(amount) ~= "number" then return end
        local health = rawget(self, "Health") or 100
        local next = math.max(0, health - amount)
        rawset(self, "Health", next)
        if next <= 0 then
                local signals = rawget(self, "signals")
                if signals and signals.Died then
                        signals.Died:Fire()
                end
        end
end

function Instance:MoveTo(_position)
        return nil
end

function Instance:LoadAnimation(animation)
        -- The weapon rig loads an animation and calls Play. Returning a stub with
        -- Play/Stop keeps the rig loadable without modelling the animation graph.
        if animation == nil then
                error("RobloxShim: LoadAnimation needs an Animation", 2)
        end
        return setmetatable({ Play = function() end, Stop = function() end, AdjustSpeed = function() end }, {})
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

-- Roblox draws its own topbar over the top of the screen. A ScreenGui with
-- IgnoreGuiInset off -- which the garden HUD sets on purpose, so its buttons do
-- not sit under Roblox's -- has its coordinate space pushed down by that inset
-- and shortened by it. GetGuiInset is the only way for the client to learn the
-- real number, so the shim models it here. The value itself lives next to
-- screenSize, because the AbsoluteSize derivation above reads it too.
--
-- Without this the shim reported a screen taller than the one a phone really
-- draws in, every "is this on screen" assertion passed, and the bottom bar
-- landed past the real bottom edge on a device. The gap was the bug.
local GuiService = makeService("GuiService")
function GuiService:GetGuiInset()
        return guiInset
end
function GuiService:GetTopbarInset()
        return guiInset
end

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

        -- A Backpack is where the shop puts a bought weapon and where the match
        -- code looks for one. Created with the player, as the engine does.
        local backpack = newInstance("Backpack")
        backpack.Name = "Backpack"
        backpack.Parent = player
        player.Backpack = backpack

        -- Team is nil until the match assigns one, exactly as on join. Kept as a
        -- real field so the weapon's same-team check reads a real Team.
        player.Team = nil
        player.Neutral = true

        player.LoadCharacter = function()
                local character = newInstance("Model")
                character.Name = player.Name
                local root = newInstance("Part")
                root.Name = "HumanoidRootPart"
                root.Parent = character
                -- The weapon validates a shot by comparing the client camera to
                -- the shooter's Head, so a character without one cannot fire.
                local head = newInstance("Part")
                head.Name = "Head"
                head.Parent = character
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
        return rawget(self, "children") or {}
end

-- The weapon resolves its victim with GetPlayerFromCharacter, and the match
-- layer needs it to tell a team-mate hit from an enemy hit. A stub returning nil
-- made the whole damage path unreachable, so this walks the registered players
-- and matches on Character identity -- the same lookup the engine does.
function PlayersService:GetPlayerFromCharacter(character)
        if character == nil then return nil end
        for _, player in ipairs(rawget(self, "children") or {}) do
                if rawget(player, "Character") == character then
                        return player
                end
        end
        return nil
end

function PlayersService:GetPlayerByUserId()
        return nil
end

-- RunService.Heartbeat is never fired by the harness; the tests drive the loop
-- themselves by calling the callback they captured.
-- A controllable monotonic clock for the game code that rate-limits on
-- os.clock(). The real clock counts from process start, so a limiter of
-- 1/FireRate seconds rejects the first shot of a test that runs in
-- milliseconds; advancing this lets a test fire at will. os.time is deliberately
-- left alone -- it is a wall clock the save code uses.
local engineClock = 1000
Shim.advanceClock = function(seconds: number)
        engineClock += seconds
end

local RunService = makeSignalHost({ ClassName = "RunService", Name = "RunService" })

-- The harness runs server code, so the server branches of the glue execute and
-- the client branches do not -- the same split the engine gives a server script.
function RunService:IsServer() return true end
function RunService:IsClient() return false end
function RunService:IsStudio() return false end

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

-- HttpService: the garden server stores its save as JSON, so it decodes with
-- the engine's own decoder. The shim delegates to the CLI's json library so a
-- save round trip is genuinely exercised rather than stubbed out.
local HttpService = makeSignalHost({
        ClassName = "HttpService",
        Name = "HttpService",
})

function HttpService:JSONDecode(text)
        if type(text) ~= "string" or text == "" then
                error("HttpService:JSONDecode: empty input", 2)
        end
        return _G.json.decode(text)
end

function HttpService:JSONEncode(value)
        return _G.json.encode(value)
end

-- Teams is a service whose children are Team instances, and Breachline's whole
-- match layer is keyed on them: MatchManager assigns `player.Team`, and the
-- weapon's damage code refuses a shot whose shooter and victim share a team.
-- The teams are created here rather than in the harness because
-- MatchManager reads `Teams.Attackers` and `Teams.Defenders` as raw fields, and
-- makeSignalHost's __index would hand back a Signal for a missing key rather
-- than nil -- so a missing team would look like a team and the assignment would
-- silently go nowhere.
local Teams = makeSignalHost({ ClassName = "Teams", Name = "Teams", children = {} })
local function makeTeam(name: string, color: any)
        local team = newInstance("Team")
        team.Name = name
        team.TeamColor = color
        team.Parent = Teams
        return team
end
Teams.Attackers = makeTeam("Attackers", Color3.fromRGB(196, 84, 62))
Teams.Defenders = makeTeam("Defenders", Color3.fromRGB(76, 118, 168))

-- ServerStorage holds the shop's weapon templates, which MatchShop clones into
-- a player's Backpack. Breachline names it directly, so it is modelled as a
-- real container the harness can populate.
local ServerStorage = makeService("ServerStorage")
ServerStorage.Parent = nil

-- CollectionService tags range targets as damageable; the weapon walks up from
-- the hit part looking for the tag. A real tag store is what makes that path
-- testable rather than assumed.
local tagStore: { [string]: { [any]: boolean } } = {}
local CollectionService = makeSignalHost({ ClassName = "CollectionService", Name = "CollectionService" })
function CollectionService:AddTag(instance, tag)
        tagStore[tag] = tagStore[tag] or {}
        tagStore[tag][instance] = true
end
function CollectionService:RemoveTag(instance, tag)
        if tagStore[tag] then tagStore[tag][instance] = nil end
end
function CollectionService:HasTag(instance, tag)
        return tagStore[tag] ~= nil and tagStore[tag][instance] == true
end
function CollectionService:GetTagged(tag)
        local out = {}
        for instance in pairs(tagStore[tag] or {}) do
                table.insert(out, instance)
        end
        return out
end

-- UserInputService is how the buy menu opens on B. InputBegan is fired by a
-- test with a synthetic input object, so the keybind is exercised rather than
-- read as text.
local UserInputService = makeSignalHost({ ClassName = "UserInputService", Name = "UserInputService" })
function UserInputService:GetPlatform()
        return Enum.Platform and Enum.Platform.Android or nil
end
function UserInputService:TouchEnabled()
        return true
end
function UserInputService:GetFocusedTextBox()
        return nil
end

local SERVICE_MAP = {
        ReplicatedStorage = ReplicatedStorage,
        Workspace = Workspace,
        Lighting = Lighting,
        GuiService = GuiService,
        Players = PlayersService,
        RunService = RunService,
        DataStoreService = DataStoreService,
        TweenService = TweenService,
        MarketplaceService = MarketplaceService,
        HttpService = HttpService,
        Teams = Teams,
        ServerStorage = ServerStorage,
        CollectionService = CollectionService,
        UserInputService = UserInputService,
}

local game = {
        ClassName = "DataModel",
        Name = "DataModel",
        Workspace = Workspace,
        PlaceId = 0,
        JobId = "shim",
}
-- RaycastParams is a value the weapon fills in and hands to Workspace:Raycast.
-- Modelled as a table the fields are set on, so the weapon's assignment works.
local RaycastParams = {}
RaycastParams.__index = RaycastParams
RaycastParams.__type = "RaycastParams"
function RaycastParams.new()
        return setmetatable({
                FilterType = nil,
                FilterDescendantsInstances = {},
                IgnoreWater = false,
                CollisionGroup = "Default",
        }, RaycastParams)
end

-- Workspace:Raycast. The weapon uses it twice per shot to find the server-side
-- aim point and the barrel hit, then damages the instance it returns. The
-- intersection here is a ray/axis-aligned-box test over the descendants of
-- Workspace, honouring the exclude list. It is deliberately simple: it is a test
-- double for "did the ray reach the target", not a physics engine, and the
-- filtered instances the game passes are what it must respect.
local function rayIntersectsPart(origin, direction, part, maxDistance)
        local cf = rawget(part, "CFrame")
        local size = rawget(part, "Size")
        if not cf or not size then return nil end
        -- Work in the part's local frame so a rotated part still intersects.
        local rel = origin - cf.Position
        local localOrigin = Vector3.new(rel:Dot(cf.RightVector or Vector3.new(1, 0, 0)),
                rel:Dot(cf.UpVector or Vector3.new(0, 1, 0)),
                rel:Dot(cf.LookVector or Vector3.new(0, 0, 1)))
        local dir = Vector3.new(direction:Dot(cf.RightVector or Vector3.new(1, 0, 0)),
                direction:Dot(cf.UpVector or Vector3.new(0, 1, 0)),
                direction:Dot(cf.LookVector or Vector3.new(0, 0, 1)))
        local half = Vector3.new(size.X / 2, size.Y / 2, size.Z / 2)
        local tmin, tmax = 0, maxDistance
        for _, axis in ipairs({ "X", "Y", "Z" }) do
                local o, d, h = localOrigin[axis], dir[axis], half[axis]
                if math.abs(d) < 1e-9 then
                        if o < -h or o > h then return nil end
                else
                        local t1, t2 = (-h - o) / d, (h - o) / d
                        if t1 > t2 then t1, t2 = t2, t1 end
                        if t1 > tmin then tmin = t1 end
                        if t2 < tmax then tmax = t2 end
                        if tmin > tmax then return nil end
                end
        end
        return tmin
end

function Workspace:Raycast(origin, direction, params)
        local distance = direction.Magnitude
        if distance <= 0 then return nil end
        local unit = direction / distance
        local excluded = {}
        if params and params.FilterDescendantsInstances then
                for _, inst in ipairs(params.FilterDescendantsInstances) do
                        excluded[inst] = true
                        for _, d in ipairs(inst:GetDescendants()) do excluded[d] = true end
                end
        end
        local best, bestT = nil, distance
        local function visit(node)
                for _, child in ipairs(rawget(node, "children")) do
                        if not excluded[child] then
                                local size = rawget(child, "Size")
                                local cf = rawget(child, "CFrame")
                                if size and cf and rawget(child, "CanQuery") ~= false then
                                        local t = rayIntersectsPart(origin, unit, child, distance)
                                        if t and t < bestT then bestT, best = t, child end
                                end
                                visit(child)
                        end
                end
        end
        visit(self)
        if not best then return nil end
        return {
                Instance = best,
                Position = origin + unit * bestT,
                Distance = bestT,
                Normal = Vector3.new(0, 1, 0),
                Material = Enum.Material.Plastic,
        }
end

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

-- A round loop is `while true do ... task.wait(1) ... end`, so draining it to
-- completion is impossible and draining it with the default resume cap would
-- abandon it after eight waits. The limits are therefore mutable: a match test
-- raises them and then steps the loop with Shim.tick, one resume at a time, so
-- it can read the state between phases. The defaults are unchanged, which is
-- what keeps the garden's behaviour identical.
function Shim.setTaskLimits(opts)
        if opts.stepCap then taskStepCap = opts.stepCap end
        if opts.resumeCap then taskResumeCap = opts.resumeCap end
end

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

-- Resume exactly one queued job once, then re-queue it if it is still
-- suspended. This is the stepper a match test uses: one tick advances the
-- round loop by one `task.wait`, so the phase the test observes is the phase the
-- server is really in rather than a guess from a bulk drain.
function Shim.tick(env, times)
        for _ = 1, (times or 1) do
                local job = table.remove(taskQueue, 1)
                if not job then
                        return
                end
                local ok, err = coroutine.resume(job.co, table.unpack(job.args))
                job.args = {}
                if not ok then
                        error("RobloxShim: queued task failed: " .. tostring(err), 2)
                end
                if coroutine.status(job.co) ~= "dead" then
                        job.resumes += 1
                        if job.resumes < taskResumeCap then
                                table.insert(taskQueue, job)
                        end
                end
        end
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
        env.RaycastParams = RaycastParams
        env.Instance = { new = newInstance }
        env.game = game
        -- typeof is an engine global, so a module that reads GuiService:GetGuiInset
        -- and checks it is a Vector2 needs it. The shim tags the vector types with
        -- __type and falls back to the plain Lua type for everything else.
        env.typeof = function(value: any): string
                if type(value) == "table" then
                        -- The tag lives on the class table, which is the metatable
                        -- of an instance, not on the instance itself.
                        local mt = getmetatable(value)
                        local tag = mt and rawget(mt, "__type")
                        if tag then
                                return tag
                        end
                end
                return type(value)
        end
        env.os = setmetatable({ clock = function() return engineClock end }, { __index = os })
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
local function makeRequire(sources: { [string]: string }, env: { [string]: any }, scriptOverrides: { [string]: any }?)
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
                local folder = setmetatable({ __path = dir, Name = dir:match("([^/]+)$") or dir }, {
                        __index = function(_, childName)
                                return handle(dir .. "/" .. childName)
                        end,
                })
                -- The bundle is a source tree, so a container that is a Tool or a
                -- Model in the real place is a folder here. A script that guards
                -- on `script.Parent:IsA("Tool")` must not be short-circuited by
                -- that flattening, so the container reports the classes a script
                -- container can be.
                folder.IsA = function(_, className)
                        return className == "Tool" or className == "Model" or className == "Folder"
                end
                return folder
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
                -- A caller can hand in the instance `script` should be, which is
                -- what lets a server script whose parent is a real Tool (the
                -- firearm rig) run against a real Tool rather than the loader's
                -- folder stand-in. Everything else keeps the folder handle.
                local scriptObj = scriptOverrides and scriptOverrides[path]
                if not scriptObj then
                        -- A real Folder carrying the script's bundle path. Making
                        -- it a real instance rather than a bare handle is what
                        -- lets a module that treats `script` as an instance --
                        -- MuzzleFlashFx calls script:FindFirstChild and parents a
                        -- remote under it -- run outside Roblox.
                        scriptObj = newInstance("Folder")
                        scriptObj.Name = path:match("([^/]+)$")
                        rawset(scriptObj, "__path", path)
                        setmetatable(scriptObj, {
                                __index = function(self, childName)
                                        if childName == "Parent" then
                                                return folderHandle(dir)
                                        end
                                        return handle(childDir .. "/" .. childName) or Instance.__index(self, childName)
                                end,
                                __newindex = Instance.__newindex,
                        })
                end

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
        -- Drop any work left queued by a previous harness. A game's round loop is
        -- `while true do ... task.wait(1) ... end`, so it is still queued when a
        -- test finishes; without clearing it here the next harness inherits a
        -- live loop from the previous one, and Shim.tick resumes the wrong
        -- coroutine. That is a test-harness bug, not a game bug, but it makes
        -- every match test read another test's world.
        for i = #taskQueue, 1, -1 do
                taskQueue[i] = nil
        end
        -- A fresh engine starts its monotonic clock at zero.
        engineClock = 1000
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

        -- The containers Breachline adds. They are module-level like the rest,
        -- so without clearing them a second harness would inherit the first
        -- one's weapon templates, tags and team membership.
        rawset(ServerStorage, "children", {})
        rawset(ServerStorage, "signals", {})
        rawset(Teams, "children", {})
        rawset(Teams, "signals", {})
        rawset(Teams, "Attackers", nil)
        rawset(Teams, "Defenders", nil)
        for tag in pairs(tagStore) do
                tagStore[tag] = nil
        end

        for key in pairs(storeData) do
                storeData[key] = nil
        end
end

function Shim.harness(sources: { [string]: string })
        resetEngine()

        -- resetEngine clears the team store, so the two teams Breachline keys on
        -- are rebuilt here. They are the same two instances the engine would
        -- have, so a harness always starts with Attackers and Defenders present.
        Teams.Attackers = makeTeam("Attackers", Color3.fromRGB(196, 84, 62))
        Teams.Defenders = makeTeam("Defenders", Color3.fromRGB(76, 118, 168))

        -- Every harness starts on the reference screen. A test that wants the
        -- phone layout sets a smaller ViewportSize before loading the client,
        -- which is the same thing the engine does when the screen changes.
        Camera.ViewportSize = Vector2.new(1280, 720)
        screenSize = Camera.ViewportSize
        rawset(Workspace, "children", { Camera })
        rawset(Workspace, "CurrentCamera", Camera)

        local env = install({})
        local load = makeRequire(sources, env)

        local sharedFolder = moduleFolder("Shared", "shared", sources)
        local remotes = newInstance("Folder")
        remotes.Name = "Remotes"
        remotes.Parent = ReplicatedStorage
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

-- Put the harness on a given screen size. A test that cares about the phone
-- layout calls this before loading the client, which is the same thing the
-- engine does when the screen changes. Both the camera and the derived screen
-- size move together, because the HUD reads AbsoluteSize off the ScreenGui.
function Shim.setViewport(env, width: number, height: number)
        Camera.ViewportSize = Vector2.new(width, height)
        screenSize = Camera.ViewportSize
end

-- Move the Roblox topbar inset. A test that wants the phone case sets the
-- viewport and the inset together, because the HUD lays itself out in the space
-- that is left after the inset, not in the raw viewport.
function Shim.setGuiInset(env, topPixels: number)
        guiInset = Vector2.new(0, topPixels)
end

-- Write a save into the DataStore before a player joins. A save is stored as
-- plain data, the same shape the server writes, so this is the exact record a
-- returning player would have on disk. Used to test offline growth and to reach
-- game states a new player cannot afford yet.
function Shim.putSave(env, userId: number, payload: any)
        local store = env.__game:GetService("DataStoreService"):GetDataStore("AXGardenLegends_v1")
        store:SetAsync(tostring(userId), payload)
end

Shim.Vector3 = Vector3
Shim.Vector2 = Vector2
Shim.CFrame = CFrame
Shim.Color3 = Color3
Shim.UDim2 = UDim2
Shim.Signal = Signal

-- The same module folder the garden harness uses, exported so a second game can
-- build its own service tree out of its own bundle. Breachline reaches its match
-- modules through ReplicatedStorage and its weapon scripts through ServerStorage,
-- and both have to resolve by name for the glue's own lookups to work.
Shim.moduleFolder = moduleFolder

-- The engine globals a module environment needs -- Vector3, CFrame, Instance,
-- Enum and friends -- returned fresh so a test that builds its own place can use
-- the same datatypes the code under test does. Nothing engine-global is mutated.
function Shim.globals()
        local env = {}
        install(env)
        return env
end

-- Mount a bundle's subtree under a service, so the glue's own path lookups --
-- ReplicatedStorage.FourD, ServerStorage.WeaponTemplates -- resolve to real
-- folders whose children the loader can require. Without this the weapon
-- script's `require(FourD.Architects...)` cannot resolve and the damage path is
-- unreachable outside Roblox.
--
-- The tree is built out of real shim Instances, so child-by-name lookup,
-- WaitForChild, FindFirstChild and GetDescendants all behave as they do in the
-- engine. A bundle directory that also has its own source (an init module, or
-- Firearm2 which is both a module and a folder of submodules) gets a __path so
-- it can be required as well as descended into; a plain leaf module is a table
-- with __path, which the loader's require accepts.
function Shim.mount(sources, env, serviceName, root)
        local service = env.__game:GetService(serviceName)

        local function hasChildren(dir: string): boolean
                local prefix = dir .. "/"
                for path in pairs(sources) do
                        if path:sub(1, #prefix) == prefix then
                                return true
                        end
                end
                return false
        end

        local function build(dir: string)
                local node = newInstance("Folder")
                node.Name = dir:match("([^/]+)$") or dir
                if sources[dir] then
                        rawset(node, "__path", dir)
                end

                local prefix = dir .. "/"
                local names = {}
                for path in pairs(sources) do
                        if path:sub(1, #prefix) == prefix then
                                local head = path:sub(#prefix + 1):match("^([^/]+)")
                                if head then names[head] = true end
                        end
                end

                for name in pairs(names) do
                        local childPath = prefix .. name
                        if hasChildren(childPath) then
                                local child = build(childPath)
                                rawset(child, "Parent", node)
                                table.insert(rawget(node, "children"), child)
                        else
                                local leaf = setmetatable({ __path = childPath, Name = name }, Instance)
                                table.insert(rawget(node, "children"), leaf)
                        end
                end
                return node
        end

        local mount = build(root)
        mount.Name = root:match("([^/]+)$") or root
        rawset(mount, "Parent", service)
        table.insert(rawget(service, "children"), mount)
        return mount
end

-- A standalone loader over a source bundle. A test that needs to require a
-- module directly -- rather than through a booted server's own require -- uses
-- this, so the module it gets is the same instance the server would load.
function Shim.loader(sources)
        return makeRequire(sources, install({}))
end

-- Run a source at `path` as if it were a child of `container`, which is where a
-- real place puts it: the firearm rig is a Script inside the weapon Tool, so
-- `script.Parent` is the Tool and `script.Parent:IsA("Tool")` gates it. Binding
-- `script` to the container itself instead would make script.Parent the
-- character and the script would return before connecting anything.
function Shim.runScript(sources, env, path, container)
        local scriptInstance = newInstance("Folder")
        scriptInstance.Name = (path:match("([^/]+)$") or path):gsub("%.[^.]+$", "")
        scriptInstance.Parent = container
        local loader = makeRequire(sources, env, { [path] = scriptInstance })
        return loader(path)
end

return Shim
