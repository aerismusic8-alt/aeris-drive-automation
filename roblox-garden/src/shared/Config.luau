--!strict
-- Every tunable number in AX Garden Legends, in one place.
--
-- The game is a collection garden: buy a seed, plant it, wait for it to grow,
-- harvest it, sell the crop, spend the coins on better seeds, more plots and
-- pets. Crops keep growing while the player is offline, so a session starts by
-- seeing what ripened overnight.
--
-- The shape is copied from the genre that owns Roblox right now, not from a
-- fight game. Grow a Garden sits at roughly 36 billion visits and a 90% rating
-- with no combat in it at all: the loop is patience and collection, and the
-- reason to return is a seed you do not own yet. That is a loop the server can
-- be authoritative about without simulating anything, which is exactly what the
-- previous arena could not be.

local Config = {}

Config.Version = "1.0.0"

-- The experience identity. The publish pipeline reads these: GameName becomes the
-- universe displayName, so the game page reads properly from a phone, and the
-- live-state check compares the public API's name against GameName.
Config.GameName = "AX Garden Legends"
Config.Tagline = "สวนสะสม: ซื้อเมล็ด ปลูก รอเก็บเกี่ยว ขาย แล้วอัปเกรด"

-- The seven collection tiers. A tier carries the odds of drawing it and how
-- much its crops are worth, so rarity is one number in one place rather than a
-- colour repeated in the shop, the save file and the HUD.
Config.Rarities = {
        { id = "Common", name = "ธรรมดา", weight = 500, valueMultiplier = 1.0, color = { 210, 210, 210 } },
        { id = "Uncommon", name = "ไม่ธรรมดา", weight = 250, valueMultiplier = 1.6, color = { 120, 220, 120 } },
        { id = "Rare", name = "หายาก", weight = 150, valueMultiplier = 2.6, color = { 110, 180, 255 } },
        { id = "Epic", name = "เอปิก", weight = 60, valueMultiplier = 4.5, color = { 190, 120, 255 } },
        { id = "Legendary", name = "ตำนาน", weight = 30, valueMultiplier = 8.0, color = { 255, 190, 70 } },
        { id = "Mythic", name = "เทพนิยาย", weight = 9, valueMultiplier = 15.0, color = { 255, 110, 110 } },
        { id = "Divine", name = "สวรรค์", weight = 1, valueMultiplier = 30.0, color = { 255, 255, 255 } },
}

-- The garden. A new player starts with four plots unlocked and the rest are
-- bought with coins, so the first upgrade is always one tap away.
Config.Garden = {
        TotalPlots = 12,
        StartingPlots = 4,
        -- The plot grid is 4 wide, so 12 plots is three rows.
        Columns = 4,
        -- World spacing between plot centres.
        Spacing = 14,
        Origin = { x = 0, z = 0 },
}

Config.Economy = {
        StartingCoins = 50,
        -- Selling a crop pays baseValue * rarity * mutation * pet bonus, floored.
        -- This is the one place the multipliers are combined.
        SellFloor = 1,
}

-- The basket holds harvested crops until the player cashes them in. Capped so a
-- long session has a reason to go and sell rather than hoarding forever.
Config.Basket = {
        Capacity = 40,
}

-- The rotating shop. Six seeds on the shelf at a time, drawn by rarity weight,
-- which is few enough to read on a phone and enough that a good seed is worth
-- coming back for.
Config.Shop = {
        StockSize = 6,
}

-- Seeds. `growSeconds` is the patience cost and `baseValue` the payout, so a
-- seed is only worth buying if the player is willing to wait for it. Both
-- numbers rise together; a Divine seed is the reward for leaving the game
-- running, which is the whole point of the genre.
Config.Seeds = {
        -- Common
        { id = "Carrot", rarity = "Common", growSeconds = 10, baseValue = 12, color = { 240, 150, 70 } },
        { id = "Strawberry", rarity = "Common", growSeconds = 15, baseValue = 20, color = { 230, 90, 100 } },
        { id = "Blueberry", rarity = "Common", growSeconds = 20, baseValue = 30, color = { 90, 130, 230 } },
        { id = "Corn", rarity = "Common", growSeconds = 28, baseValue = 48, color = { 240, 210, 100 } },
        -- Uncommon
        { id = "Tomato", rarity = "Uncommon", growSeconds = 40, baseValue = 80, color = { 220, 70, 60 } },
        { id = "Pumpkin", rarity = "Uncommon", growSeconds = 55, baseValue = 130, color = { 235, 140, 50 } },
        { id = "Watermelon", rarity = "Uncommon", growSeconds = 75, baseValue = 210, color = { 90, 200, 110 } },
        { id = "Chili", rarity = "Uncommon", growSeconds = 95, baseValue = 300, color = { 200, 50, 50 } },
        -- Rare
        { id = "Dragonfruit", rarity = "Rare", growSeconds = 130, baseValue = 480, color = { 240, 90, 190 } },
        { id = "Starfruit", rarity = "Rare", growSeconds = 170, baseValue = 720, color = { 250, 230, 120 } },
        { id = "Moonflower", rarity = "Rare", growSeconds = 220, baseValue = 1050, color = { 180, 190, 255 } },
        { id = "CrystalBerry", rarity = "Rare", growSeconds = 280, baseValue = 1500, color = { 150, 240, 250 } },
        -- Epic
        { id = "GlowMushroom", rarity = "Epic", growSeconds = 360, baseValue = 2200, color = { 140, 255, 200 } },
        { id = "GhostPepper", rarity = "Epic", growSeconds = 450, baseValue = 3100, color = { 255, 250, 220 } },
        { id = "AuroraBloom", rarity = "Epic", growSeconds = 560, baseValue = 4400, color = { 130, 255, 210 } },
        { id = "PhoenixLotus", rarity = "Epic", growSeconds = 700, baseValue = 6200, color = { 255, 140, 60 } },
        -- Legendary
        { id = "VoidOrchid", rarity = "Legendary", growSeconds = 900, baseValue = 9000, color = { 120, 80, 200 } },
        { id = "SunflowerCrown", rarity = "Legendary", growSeconds = 1150, baseValue = 13000, color = { 255, 220, 60 } },
        { id = "StormLily", rarity = "Legendary", growSeconds = 1450, baseValue = 18500, color = { 160, 200, 255 } },
        { id = "EclipseRose", rarity = "Legendary", growSeconds = 1800, baseValue = 26000, color = { 200, 60, 140 } },
        -- Mythic
        { id = "CelestialVine", rarity = "Mythic", growSeconds = 2300, baseValue = 38000, color = { 255, 240, 180 } },
        { id = "NebulaMelon", rarity = "Mythic", growSeconds = 2900, baseValue = 55000, color = { 170, 120, 255 } },
        { id = "PrismCactus", rarity = "Mythic", growSeconds = 3600, baseValue = 80000, color = { 120, 255, 240 } },
        { id = "AstralPumpkin", rarity = "Mythic", growSeconds = 4300, baseValue = 115000, color = { 255, 160, 90 } },
        -- Divine
        { id = "GenesisTree", rarity = "Divine", growSeconds = 5000, baseValue = 140000, color = { 190, 255, 190 } },
        { id = "ChronoBlossom", rarity = "Divine", growSeconds = 6500, baseValue = 210000, color = { 200, 220, 255 } },
        { id = "InfinityRose", rarity = "Divine", growSeconds = 8500, baseValue = 320000, color = { 255, 180, 220 } },
        { id = "OmegaLily", rarity = "Divine", growSeconds = 11000, baseValue = 480000, color = { 255, 255, 255 } },
}

-- Mutations. A harvest has one roll, and a mutation multiplies what the crop
-- sells for. This is the variance that makes a session worth starting: the same
-- seed can pay 1x or 240x, and the 240x is the story the player tells.
--
-- Weights are relative, not percentages; `Mutations.roll` normalises them.
Config.Mutations = {
        { id = "None", name = "ปกติ", multiplier = 1, weight = 1000, color = { 200, 200, 200 } },
        { id = "Moonlit", name = "แสงจันทร์", multiplier = 2, weight = 150, color = { 180, 190, 255 } },
        { id = "Pollinated", name = "ผสมเกสร", multiplier = 3, weight = 120, color = { 240, 230, 130 } },
        { id = "Silver", name = "เงิน", multiplier = 5, weight = 80, color = { 220, 230, 240 } },
        { id = "Gold", name = "ทอง", multiplier = 20, weight = 40, color = { 255, 200, 60 } },
        { id = "Rainbow", name = "รุ้ง", multiplier = 50, weight = 15, color = { 255, 120, 220 } },
        { id = "Shocked", name = "สายฟ้า", multiplier = 100, weight = 6, color = { 255, 250, 120 } },
        { id = "Celestial", name = "ท้องฟ้า", multiplier = 120, weight = 3, color = { 190, 230, 255 } },
        { id = "Void", name = "วอยด์", multiplier = 135, weight = 2, color = { 130, 80, 200 } },
        { id = "Cosmic", name = "คอสมิก", multiplier = 240, weight = 1, color = { 255, 255, 255 } },
}

-- Pets. An egg is a coin sink with a payoff the player keeps: a pet sits in a
-- slot and multiplies growth speed or sale value for as long as it is equipped.
--
-- The value multiplier is the reason to buy the dearer egg, so it has to climb
-- steeply with tier. A flat ladder makes a 1500x price jump buy a 2x pet, which
-- is a sink a player can see through. Growth multipliers stay gentler than value
-- multipliers because they compound with the speed upgrade and with each other.
Config.Pets = {
        MaxEquipped = 3,
        Pets = {
                -- Basic
                { id = "Pup", rarity = "Common", growthMultiplier = 1.05, valueMultiplier = 1.0 },
                { id = "Kitten", rarity = "Common", growthMultiplier = 1.05, valueMultiplier = 1.0 },
                { id = "Chick", rarity = "Common", growthMultiplier = 1.05, valueMultiplier = 1.0 },
                -- Uncommon
                { id = "Bunny", rarity = "Uncommon", growthMultiplier = 1.10, valueMultiplier = 1.25 },
                { id = "Fox", rarity = "Uncommon", growthMultiplier = 1.10, valueMultiplier = 1.25 },
                { id = "Bee", rarity = "Uncommon", growthMultiplier = 1.15, valueMultiplier = 1.20 },
                -- Rare
                { id = "Wolf", rarity = "Rare", growthMultiplier = 1.22, valueMultiplier = 1.8 },
                { id = "Panda", rarity = "Rare", growthMultiplier = 1.22, valueMultiplier = 1.8 },
                { id = "Owl", rarity = "Rare", growthMultiplier = 1.28, valueMultiplier = 1.7 },
                -- Epic
                { id = "Dragon", rarity = "Epic", growthMultiplier = 1.4, valueMultiplier = 3.0 },
                { id = "Phoenix", rarity = "Epic", growthMultiplier = 1.4, valueMultiplier = 3.0 },
                { id = "Griffin", rarity = "Epic", growthMultiplier = 1.5, valueMultiplier = 2.8 },
                -- Legendary
                { id = "Unicorn", rarity = "Legendary", growthMultiplier = 1.7, valueMultiplier = 6.0 },
                { id = "Leviathan", rarity = "Legendary", growthMultiplier = 1.8, valueMultiplier = 5.5 },
                -- Mythic
                { id = "Voidling", rarity = "Mythic", growthMultiplier = 2.2, valueMultiplier = 12.0 },
                { id = "Seraph", rarity = "Mythic", growthMultiplier = 2.5, valueMultiplier = 10.0 },
        },
        Eggs = {
                {
                        id = "Basic",
                        name = "ไข่ธรรมดา",
                        cost = 100,
                        -- Weights within the egg, so a cheap egg cannot drop a Mythic.
                        odds = { Common = 80, Uncommon = 20 },
                },
                {
                        id = "Spotted",
                        name = "ไข่ลายจุด",
                        cost = 1200,
                        odds = { Common = 40, Uncommon = 45, Rare = 15 },
                },
                {
                        id = "Mythic",
                        name = "ไข่เทพนิยาย",
                        cost = 15000,
                        odds = { Rare = 50, Epic = 40, Legendary = 10 },
                },
                {
                        id = "Divine",
                        name = "ไข่สวรรค์",
                        cost = 150000,
                        odds = { Epic = 30, Legendary = 50, Mythic = 20 },
                },
        },
}

-- Upgrades bought with coins. Each has a cost curve; the curve lives in the
-- module that owns it (Plots, Upgrades) and only the shape lives here.
Config.Upgrades = {
        -- Buying the next locked plot.
        PlotBaseCost = 250,
        PlotCostGrowth = 1.85,
        -- Growth speed: level N shortens grow time by SpeedPerLevel, capped.
        SpeedBaseCost = 400,
        SpeedCostGrowth = 1.9,
        SpeedPerLevel = 0.04,
        SpeedMaxLevel = 15,
        -- Sale value: level N raises every sale by ValuePerLevel, capped.
        ValueBaseCost = 500,
        ValueCostGrowth = 2.0,
        ValuePerLevel = 0.06,
        ValueMaxLevel = 15,
}

-- Offline growth. A crop grows while the player is away, but only up to a cap,
-- so leaving for a week is not the same as leaving for a day. This is the
-- single most important number for retention in the genre and it is deliberate.
Config.Offline = {
        MaxOfflineSeconds = 8 * 60 * 60,
        -- Below this the elapsed time is treated as a rejoin, not a growth window.
        MinimumSeconds = 5,
}

Config.Save = {
        SchemaVersion = 4,
        -- A save is written at most this often while a player is active.
        AutosaveSeconds = 60,
}

-- The look of the world. K's report was that the garden "is only square blocks,
-- not pretty or smooth", so the shapes and the light are data too, not literals
-- buried in World.luau. Every number here is safe on the Intel HD and mobile
-- targets: Voxel lighting, no global shadows, no Future technology. The
-- low-end gate in scripts/check-low-end-lighting.py enforces that.
Config.Visuals = {
        Lighting = {
                ClockTime = 14.5,
                GeographicLatitude = 12,
                Brightness = 2.8,
                Ambient = { 0.26, 0.28, 0.24 },
                OutdoorAmbient = { 0.56, 0.58, 0.54 },
                ShadowSoftness = 0.4,
                EnvironmentDiffuseScale = 0.55,
                EnvironmentSpecularScale = 0.35,
                GlobalShadows = false,
        },
        Atmosphere = {
                Color = { 0.78, 0.85, 0.95 },
                Decay = { 0.35, 0.5, 0.7 },
                Density = 0.3,
                Glare = 0.15,
                Haze = 1.35,
                Offset = 0.1,
        },
        -- A Sky is what the horizon and the clouds are drawn from. Without one the
        -- engine draws a flat gradient, which is most of why the first build read
        -- as a plain green room rather than as outdoors.
        Sky = {
                SkyboxBk = "rbxasset://textures/sky/sky512_bk.tex",
                SkyboxDn = "rbxasset://textures/sky/sky512_dn.tex",
                SkyboxFt = "rbxasset://textures/sky/sky512_ft.tex",
                SkyboxLf = "rbxasset://textures/sky/sky512_lf.tex",
                SkyboxRt = "rbxasset://textures/sky/sky512_rt.tex",
                SkyboxUp = "rbxasset://textures/sky/sky512_up.tex",
                SunAngularSize = 22,
                MoonAngularSize = 12,
                StarCount = 2500,
                CelestialBodiesShown = true,
        },
        Clouds = { Cover = 0.45, Density = 0.5, Color = { 1, 1, 1 } },
        Bloom = { Enabled = true, Intensity = 0.5, Size = 22, Threshold = 1.1 },
        Colour = { Enabled = true, Brightness = 0.02, Contrast = 0.12, Saturation = 0.18, TintColor = { 1, 0.99, 0.95 } },
        SunRays = { Enabled = true, Intensity = 0.05, Spread = 0.6 },
}

-- The scenery. Counts, sizes and colours live here so the garden can be
-- re-dressed without touching code, which is the whole point of the data-only
-- rule: the look is a table, not a rewrite.
Config.Scenery = {
        -- Fixed, so the same tree is at the same coordinate on every boot and a
        -- screenshot can be compared to the last one.
        Seed = 20261018,
        Palette = {
                Trunk = { 108, 74, 46 },
                CanopyDark = { 52, 112, 48 },
                CanopyMid = { 66, 132, 54 },
                CanopyLight = { 92, 168, 72 },
                Bush = { 70, 132, 58 },
                Flower = { 240, 120, 170 },
                FlowerAlt = { 255, 214, 120 },
                Grass = { 96, 132, 72 },
                GrassTuft = { 122, 168, 84 },
                Rock = { 138, 138, 144 },
                Path = { 178, 172, 160 },
                Fence = { 196, 168, 130 },
                FenceRail = { 206, 180, 142 },
                Water = { 68, 132, 186 },
                ShopWall = { 150, 110, 70 },
                ShopRoof = { 172, 74, 62 },
                ShopSign = { 250, 230, 180 },
                Lantern = { 255, 216, 142 },
        },
        Trees = { Count = 26, MinScale = 0.8, MaxScale = 1.5, MinRadius = 12, MaxRadius = 72 },
        Bushes = { Count = 24, MinScale = 0.7, MaxScale = 1.2, MinRadius = 4, MaxRadius = 24 },
        Flowers = { Count = 44, MinScale = 0.9, MaxScale = 1.4 },
        Rocks = { Count = 18, MinScale = 0.6, MaxScale = 1.6, MinRadius = 8, MaxRadius = 60 },
        GrassTufts = { Count = 70, MinScale = 0.8, MaxScale = 1.6 },
        Lanterns = { Count = 4, Height = 7 },
        Path = { Steps = 9, Width = 7, Depth = 4 },
        Fence = { PostEvery = 8, Height = 5 },
        -- A small pond outside the fence, so the horizon has more than one colour
        -- in it and the light has something to reflect.
        Pond = { Radius = 18, Depth = 1.2, Distance = 46 },
}

return Config
