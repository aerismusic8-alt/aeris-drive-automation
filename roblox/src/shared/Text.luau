--!strict
-- Thai display text for everything a player reads. Pure Luau, no Roblox
-- globals, so the mapping can be tested outside Studio like the other modules.
--
-- Ids stay English on purpose. `Fields`, `Zones`, `Enemies`, `Farm` and the
-- client intents key off `id`, and a save file stores the zone by id, so
-- renaming an id would break saves and travel. Only the text a player sees is
-- translated, and it is translated here and nowhere else.

local Text = {}

-- Fallback rule: an unknown key returns the key unchanged. A missing line then
-- shows as `Cavern` rather than an empty label, which is far easier to spot in
-- a screenshot than a blank button.

local STRINGS: { [string]: string } = {
        -- Stats panel
        coins = "เงิน",
        level = "เลเวล",
        health = "เลือด",
        field = "แผนที่",
        zone = "โซน",
        rebirth = "รีเบิร์ธ",
        combo = "คอมโบ",
        wave = "เวฟ",
        boss = "บอส",
        max = "สูงสุด",

        -- Buttons and panels
        rewards = "รางวัล",
        dailyReward = "รับรางวัลรายวัน",
        dailyClaim = "กดรับรายวัน (วันที่ %d)",
        dailyWait = "รออีก %d ชม. %d นาที",
        redeemCode = "ใส่โค้ด",
        enterCode = "ใส่โค้ดโปรโมชัน",
        codePlaceholder = "โค้ด",
        redeem = "ยืนยัน",
        cancel = "ยกเลิก",
        axe = "ขวาน",
        axeEmpty = "ขวาน (ว่าง)",
        farm = "เก็บเกี่ยว",
        farmReady = "เก็บเกี่ยว (%d พร้อม)",
        map = "แผนที่",
        chooseField = "เลือกแผนที่",

        -- Wave banner
        townPickField = "ในเมือง - กด แผนที่ เพื่อเลือกแมพ",
        waveNext = "%s: เวฟ %d ใน %d วิ",
        waveFighting = "%s: เวฟ %d - เหลือ %d ตัว",
        bossDown = "สังหารบอสได้!",

        -- Travel list
        town = "เมือง",
        here = "อยู่ที่นี่",
        locked = "ล็อก",
        returnToTown = "กลับเมือง",

        -- Fields
        PronteraTown = "เมืองพรอนเทรา",
        Meadow = "ทุ่งหญ้าอรุณ",
        Cavern = "ถ้ำคริสตัล",
        Volcano = "ภูเขาไฟเอมเบอร์",
        Void = "รอยแยกแห่งความว่างเปล่า",
        Heaven = "ประตูสวรรค์",

        -- Field taglines
        MeadowTagline = "ที่ที่นักผจญภัยทุกคนเริ่มต้น",
        CavernTagline = "หินหนาว และอะไรที่หนาวกว่า",
        VolcanoTagline = "พื้นดินยังจดจำไฟได้",
        VoidTagline = "ที่นี่ไม่มีอะไรอยากให้เจ้ากลับไป",
        HeavenTagline = "ประตูสุดท้ายก่อนถึงจุดจบ",

        -- Notifications
        rebirthDone = "รีเบิร์ธ %d สำเร็จ!",
        returnedToTown = "กลับเข้าเมืองแล้ว",
        entered = "เข้าสู่ %s",
        dailyGain = "รายวันวันที่ %d: +%d เหรียญ",
        codeGain = "โค้ด %s: +%d เหรียญ",
        harvestGain = "เก็บ %s ได้: +%d เหรียญ",
        purchaseApplied = "ซื้อสำเร็จ: %s",

        -- Farm plot signs
        plot = "แปลง %d",
        ready = "สุกแล้ว",

        -- Crops
        Wheat = "ข้าวสาลี",
        Carrot = "แครอท",
        Star = "ดาว",
}

-- Monsters reach the client as a display name rather than an id, so they get
-- their own table keyed by the English name Enemies.luau ships.
local ENEMIES: { [string]: string } = {
        Slime = "สไลม์",
        Hornet = "ตัวต่อ",
        ["Slime King"] = "ราชาสไลม์",
        ["Cave Bat"] = "ค้างคาวถ้ำ",
        ["Rock Golem"] = "โกเลมหิน",
        ["Crystal Golem"] = "โกเลมคริสตัล",
        Scorpion = "แมงป่อง",
        Mummy = "มัมมี่",
        ["Sand Wraith"] = "ภูตทราย",
        ["Ember Imp"] = "ปีศาจไฟ",
        ["Magma Hound"] = "หมาลาวา",
        ["Volcano Dragon"] = "มังกรภูเขาไฟ",
        ["Void Wisp"] = "แสงเวทว่างเปล่า",
        ["Rift Stalker"] = "นักล่าแห่งรอยแยก",
        ["Void Sovereign"] = "ราชันความว่างเปล่า",
}

local TAGLINES: { [string]: string } = {
        Meadow = "MeadowTagline",
        Cavern = "CavernTagline",
        Volcano = "VolcanoTagline",
        Void = "VoidTagline",
        Heaven = "HeavenTagline",
}

-- The one lookup. `format` args are applied when any are given.
function Text.get(key: string, ...: any): string
        local line = STRINGS[key] or key
        if select("#", ...) > 0 then
                return string.format(line, ...)
        end
        return line
end

-- Display name for a field or the town, by id.
function Text.placeName(id: string?): string
        if id == nil or id == "" then
                return STRINGS.PronteraTown
        end
        if id == "Town" then
                return STRINGS.PronteraTown
        end
        return STRINGS[id] or id
end

-- The short line under a field name.
function Text.tagline(id: string): string
        local key = TAGLINES[id]
        if not key then
                return ""
        end
        return STRINGS[key] or ""
end

-- Display name for a crop, by id. Unknown ids pass through, which keeps a new
-- crop visible before its translation is added.
function Text.cropName(id: string): string
        return STRINGS[id] or id
end

-- Display name for a monster, given the English name the server sent. Falls
-- back to the English name so a new monster is readable before it is translated.
function Text.enemyName(name: string?): string
        if name == nil then
                return ""
        end
        return ENEMIES[name] or name
end

-- True when every key has a non-empty translation, so a typo cannot ship a
-- blank button. Returns the list of missing keys.
function Text.missingKeys(keys: { string }): { string }
        local missing: { string } = {}
        for _, key in ipairs(keys) do
                local line = STRINGS[key]
                if line == nil or line == "" then
                        table.insert(missing, key)
                end
        end
        return missing
end

Text.STRINGS = STRINGS
Text.ENEMIES = ENEMIES

return Text
