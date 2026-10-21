--!strict
-- Thai display text for everything a player reads. Pure Luau, no Roblox
-- globals, so the mapping can be tested outside Studio.
--
-- Ids stay English. The save file, the shop and the remotes all key off `id`,
-- so renaming one would break saves. Only what the player reads is translated,
-- and it is translated here and nowhere else.

local Text = {}

-- Fallback rule: an unknown key returns the key unchanged, so a missing line
-- shows as `Carrot` in a screenshot rather than as an empty label.

local STRINGS: { [string]: string } = {
        -- Screen
        title = "สวนตำนาน AX",
        coins = "เงิน",
        garden = "สวน",
        shop = "ร้านค้า",
        seeds = "เมล็ดพันธุ์",
        pets = "สัตว์เลี้ยง",
        collection = "คอลเลกชัน",
        upgrades = "อัปเกรด",
        close = "ปิด",
        back = "กลับ",

        -- Garden
        plot = "แปลง %d",
        locked = "ล็อก",
        plant = "ปลูก",
        harvest = "เก็บ",
        harvestAll = "เก็บทั้งหมด",
        empty = "ว่าง",
        growing = "กำลังโต",
        ready = "พร้อมเก็บ",
        secondsLeft = "อีก %d วิ",
        minutesLeft = "อีก %d นาที",
        hoursLeft = "อีก %d ชม.",
        progress = "โตแล้ว %d%%",
        plotLocked = "แปลงนี้ยังล็อกอยู่",
        buyPlot = "ซื้อแปลง (%d เหรียญ)",
        allPlotsUnlocked = "ปลดล็อกแปลงครบแล้ว",

        -- Shop
        buy = "ซื้อ",
        cost = "ราคา %d",
        notEnoughCoins = "เงินไม่พอ",
        restock = "สุ่มร้านใหม่",
        restockCost = "สุ่มใหม่ (%d เหรียญ)",
        stockOdds = "โอกาสออก %.1f%%",
        plantAll = "ปลูกทั้งหมด",
        nothingToPlant = "ไม่มีเมล็ดให้ปลูก",
        bought = "ซื้อแล้ว: %s",
        noSpace = "แปลงเต็มแล้ว",

        -- Sell and mutations
        sold = "ขายได้ %d เหรียญ",
        soldMany = "ขาย %d อย่าง ได้ %d เหรียญ",
        newSeed = "พบเมล็ดใหม่: %s!",
        newMutation = "ได้กลายพันธุ์: %s!",
        bestSale = "สถิติสูงสุด: %d เหรียญ",
        totalSold = "ขายไปทั้งหมด %d อย่าง",

        -- Pets
        hatch = "ฟักไข่",
        hatchCost = "ฟัก (%d เหรียญ)",
        hatched = "ได้สัตว์เลี้ยง: %s!",
        equip = "ใช้งาน",
        unequip = "ถอด",
        equipped = "ใช้งานอยู่",
        slotsFull = "ช่องสัตว์เลี้ยงเต็ม",
        eggOdds = "โอกาส: %s",
        petBonus = "โบนัส: โต x%.2f ขาย x%.2f",
        owned = "มี %d ตัว",
        noPets = "ยังไม่มีสัตว์เลี้ยง",

        -- Upgrades
        growthSpeed = "ความเร็วโต",
        saleValue = "ราคาขาย",
        level = "ระดับ %d",
        maxLevel = "เต็มแล้ว",
        upgrade = "อัปเกรด (%d เหรียญ)",
        speedEffect = "โตเร็วขึ้น +%d%%",
        valueEffect = "ขายได้ +%d%%",

        -- Collection
        discovered = "ค้นพบ %d/%d",
        mutationsFound = "กลายพันธุ์ %d/%d",
        complete = "สะสมครบแล้ว!",
        rarityCommon = "ธรรมดา",
        rarityUncommon = "ไม่ธรรมดา",
        rarityRare = "หายาก",
        rarityEpic = "เอปิก",
        rarityLegendary = "ตำนาน",
        rarityMythic = "เทพนิยาย",
        rarityDivine = "สวรรค์",

        -- Offline
        welcomeBack = "ยินดีต้อนรับกลับ!",
        offlineGrew = "พืชโตตอนคุณไม่อยู่ %s",
        offlineNone = "ไม่มีอะไรโตตอนคุณไม่อยู่",
        offlineCapped = "พืชโตได้สูงสุด 8 ชั่วโมง",

        -- Session
        loading = "กำลังโหลดสวน...",
        saved = "บันทึกแล้ว",
        error = "เกิดข้อผิดพลาด กรุณาลองใหม่",
}

function Text.get(key: string, ...: any): string
        local line = STRINGS[key]
        if not line then
                return key
        end
        local args = { ... }
        if #args > 0 then
                local ok, formatted = pcall(string.format, line, table.unpack(args))
                if ok then
                        return formatted
                end
        end
        return line
end

function Text.has(key: string): boolean
        return STRINGS[key] ~= nil
end

function Text.keys(): { string }
        local out: { string } = {}
        for key in pairs(STRINGS) do
                table.insert(out, key)
        end
        table.sort(out)
        return out
end

-- Human-readable duration for the offline and growth readouts. Deliberately
-- coarse: a player wants "2 ชม." not "2 ชม. 14 นาที 3 วิ".
function Text.duration(seconds: number): string
        local s = math.max(0, math.floor(seconds))
        if s < 60 then
                return Text.get("secondsLeft", s)
        end
        if s < 3600 then
                return Text.get("minutesLeft", math.floor(s / 60))
        end
        return Text.get("hoursLeft", math.floor(s / 3600))
end

return Text
