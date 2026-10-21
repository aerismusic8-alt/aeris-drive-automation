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
        version = "เวอร์ชัน",
        combo = "คอมโบ",
        wave = "เวฟ",
        menu = "เมนู",
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
        -- Shown while standing in the first field, which cannot kill the player.
        safeField = "สนามฝึก: ศัตรูฆ่าเราไม่ได้ เก็บเวลได้เรื่อยๆ",

        -- The people in Prontera Town. Each one opens the panel named by its
        -- `opens` field, so the label under a villager always says what tapping
        -- them will do.
        npcElder = "ผู้เฒ่า",
        npcElderTitle = "ภารกิจ",
        npcMerchant = "พ่อค้า",
        npcMerchantTitle = "ร้านค้า",
        npcTrainer = "ครูฝึก",
        npcTrainerTitle = "ตัวละคร",
        npcCaptain = "กัปตัน",
        npcCaptainTitle = "แผนที่",
        npcKeeper = "ผู้ดูแล",
        npcKeeperTitle = "รางวัล",
        npcTapToOpen = "แตะเพื่อเปิด %s",
        npcAway = "เดินเข้าไปใกล้ๆ แล้วแตะอีกครั้ง",

        -- Death has to cost something outside the training field, or the only
        -- way to lose is to stop playing.
        diedInField = "คุณล้มใน %s — กลับไปที่เมือง",
        deathPenalty = "เสีย %d เหรียญจากค่าฟื้น",
        townAfterDeath = "พักที่เมืองก่อน แล้วค่อยออกไปใหม่",

        -- Quest spine. One line at a time, so a new player always has a named
        -- next action instead of a field full of monsters and no instructions.
        quest = "ภารกิจ",
        questComplete = "ภารกิจสำเร็จ!",
        questReward = "ได้: +%d เหรียญ, +%d EXP",
        questItemReward = "ได้: +%d เหรียญ, +%d EXP, %s x%d",
        questProgress = "%s (%d/%d)",
        questAllDone = "ทำภารกิจครบทุกข้อแล้ว!",
        qFirstBlood = "เริ่มต้นที่ทุ่งหญ้า",
        qFirstBloodBody = "กำจัดมอนสเตอร์ 3 ตัว (เดินชนแล้วสู้เองอัตโนมัติ)",
        qPickJob = "เลือกอาชีพ",
        qPickJobBody = "เปิดเมนู แล้วกด ตัวละคร เพื่อเลือกอาชีพแรก",
        qPlantAndPick = "รู้จักฟาร์ม",
        qPlantAndPickBody = "กด เก็บเกี่ยว ปลูกพืชแล้วเก็บให้ครบ 3 ครั้ง (ฟาร์มชาร์จขวาน)",
        qSwingAxe = "ลองฟาดขวาน",
        qSwingAxeBody = "เก็บพืชให้ได้ 5 ชาร์จ แล้วกด ขวาน ฟาดศัตรูรอบตัว (กำจัด 10 ตัว)",
        qWearGear = "ใส่ของ",
        qWearGearBody = "เปิดเมนู กระเป๋า แล้วใส่อาวุธที่ได้มา",
        qSlimeKing = "ราชาสไลม์",
        qSlimeKingBody = "ทุ่งหญ้า เวฟ 5 - สังหารบอส สไลม์คิง",
        qCavern = "สู่ถ้ำคริสตัล",
        qCavernBody = "ไปที่ แผนที่ แล้วเลือก ถ้ำคริสตัล (เวล 10)",
        qCrystalGolem = "โกเลมคริสตัล",
        qCrystalGolemBody = "ถ้ำคริสตัล เวฟ 5 - สังหารบอส โกเลมคริสตัล",
        qVolcano = "สู่ภูเขาไฟ",
        qVolcanoBody = "ไปที่ แผนที่ แล้วเลือก ภูเขาไฟเอมเบอร์ (เวล 25)",
        qVolcanoDragon = "มังกรภูเขาไฟ",
        qVolcanoDragonBody = "ภูเขาไฟ เวฟ 5 - สังหารบอส มังกรภูเขาไฟ",
        qVoid = "สู่รอยแยกวอยด์",
        qVoidBody = "ไปที่ แผนที่ แล้วเลือก รอยแยกวอยด์ (เวล 50)",
        qVoidSovereign = "เจ้าแห่งวอยด์",
        qVoidSovereignBody = "รอยแยกวอยด์ เวฟ 5 - สังหารบอส เจ้าแห่งวอยด์",
        qHeaven = "ประตูสวรรค์",
        qHeavenBody = "ไปที่ แผนที่ แล้วเลือก ประตูสวรรค์ (เวล 80)",
        qHeavenGate = "ประตูสวรรค์ด่านสุดท้าย",
        qHeavenGateBody = "สวรรค์ เวฟ 5 - สังหารบอส ประตูสวรรค์ - ด่านสุดท้ายของเนื้อเรื่อง",

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

        -- Character sheet
        character = "ตัวละคร",
        stats = "ค่าพลัง",
        attributes = "ค่าสถานะ",
        pointsLeft = "แต้มเหลือ %d",
        attack = "โจมตี",
        magicAttack = "โจมตีเวท",
        defense = "ป้องกัน",
        magicDefense = "ต้านเวท",
        hit = "แม่นยำ",
        flee = "หลบหลีก",
        critChance = "คริติคอล",
        attackSpeed = "ความเร็วโจมตี",
        maxHealth = "เลือดสูงสุด",
        maxSp = "มานาสูงสุด",
        addPoint = "+1",
        addTen = "+10",
        noPoints = "ไม่มีแต้ม",
        STR = "STR พลัง",
        AGI = "AGI ความไว",
        VIT = "VIT อึด",
        INT = "INT ปัญญา",
        DEX = "DEX แม่น",
        LUK = "LUK โชค",

        -- Job and skills
        job = "อาชีพ",
        jobLevel = "เลเวลอาชีพ",
        jobXp = "ค่าอาชีพ",
        skillPoints = "แต้มสกิล %d",
        skills = "สกิล",
        learn = "เรียน",
        learned = "เรียนแล้ว",
        changeJob = "เปลี่ยนอาชีพ",
        jobAdvance = "เลื่อนอาชีพ",
        jobRequirements = "ต้องเลเวล %d และเลเวลอาชีพ %d",
        jobLevelUp = "เลเวลอาชีพขึ้นเป็น %d",
        jobAdvanceOk = "เปลี่ยนอาชีพเป็น %s แล้ว",
        attributeUp = "%s +1 (เหลือ %d แต้ม)",
        skillLearned = "เรียน %s เลเวล %d",
        noAttributePoints = "แต้มไม่พอ",
        branchOf = "สายอาชีพ",
        notEnoughSkillPoints = "แต้มสกิลไม่พอ",
        needPrerequisite = "ต้องเรียน %s ก่อน",
        maxSkill = "เต็มแล้ว",
        passiveSkill = "ติดตัว",
        spCostLabel = "ใช้ %d มานา",
        cooldownLabel = "คูลดาวน์ %.1f วิ",
        cast = "ใช้สกิล",
        noSp = "มานาไม่พอ",
        skillOnCooldown = "รอคูลดาวน์",
        buffActive = "บัฟทำงาน",

        -- Inventory and equipment
        inventory = "กระเป๋า",
        equipment = "อุปกรณ์",
        bag = "ของ",
        equip = "สวมใส่",
        unequip = "ถอด",
        use = "ใช้",
        drop = "ทิ้ง",
        empty = "ว่าง",
        full = "กระเป๋าเต็ม",
        levelTooLow = "เลเวลไม่พอ",
        notEquipment = "ใส่อย่างอื่น",
        twoHandedBlocks = "สองมือ ต้องถอดโล่",
        slotEmpty = "ไม่มี",
        pickup = "เก็บของ",
        autoPickupOn = "เก็บของอัตโนมัติ: เปิด",
        autoPickupOff = "เก็บของอัตโนมัติ: ปิด",
        looted = "เก็บได้ %s x%d",
        equipped = "สวม %s แล้ว",
        usedItem = "ใช้ %s",
        itemLevelReq = "ต้องเลเวล %d",

        -- Attack modes
        attackButton = "โจมตี",
        autoAttackOn = "โจมตีอัตโนมัติ: เปิด",
        autoAttackOff = "โจมตีอัตโนมัติ: ปิด",
        auto = "ออโต้",
        manual = "กดเอง",
        skillReady = "พร้อม",
        killGain = "สังหาร %s: +%d",

        -- Equipment slots
        Weapon = "อาวุธ",
        Shield = "โล่",
        Head = "หมวก",
        Body = "เสื้อเกราะ",
        Garment = "ผ้าคลุม",
        Shoes = "รองเท้า",
        Accessory1 = "แหวน",
        Accessory2 = "เครื่องราง",

        -- Classes
        Novice = "โนวิซ",
        Swordsman = "นักดาบ",
        Archer = "นักธนู",
        Mage = "จอมเวท",
        Thief = "โจร",
        Acolyte = "นักบวชฝึกหัด",
        Knight = "อัศวิน",
        Hunter = "นายพราน",
        Wizard = "พ่อมด",
        Assassin = "นักฆ่า",
        Priest = "บาทหลวง",

        -- Class taglines
        NoviceTagline = "ทุกคนเริ่มต้นที่นี่",
        SwordsmanTagline = "เกราะหนัก ฟันหนัก",
        ArcherTagline = "ฆ่าก่อนที่มันจะถึงตัว",
        MageTagline = "ให้ธาตุเป็นคนเดิน",
        ThiefTagline = "เร็ว เงียบ และอยู่ข้างหลังเจ้าแล้ว",
        AcolyteTagline = "ทำให้ปาร์ตี้ไม่ล้ม",
        KnightTagline = "แนวรบยังอยู่ เพราะเจ้ายังยืน",
        HunterTagline = "ไม่มีอะไรวิ่งหนีลูกธนูได้",
        WizardTagline = "ความจริงเป็นแค่ข้อเสนอ",
        AssassinTagline = "สองดาบ คำตอบเดียว",
        PriestTagline = "แสงมาถึงก่อนตัวเจ้า",

        -- Skill names
        BasicAttack = "โจมตีปกติ",
        FirstAid = "ปฐมพยาบาล",
        Bash = "ทุบ",
        MagnumBreak = "ฟันหมุน",
        Endure = "ทนทาน",
        BowlingBash = "พุ่งชน",
        TwoHandQuicken = "เร่งสองมือ",
        DoubleStrafe = "ยิงคู่",
        OwlEyes = "ตาเหยี่ยว",
        ArrowShower = "ห่าธนู",
        BeastFang = "เขี้ยวสัตว์",
        FireBolt = "ลูกไฟ",
        ColdBolt = "ลูกน้ำแข็ง",
        IncreaseSpRecovery = "ฟื้นมานาเร็ว",
        StormGust = "พายุหิมะ",
        MagicCrasher = "ทุบด้วยเวท",
        DoubleAttack = "ตีคู่",
        ImproveDodge = "หลบเก่งขึ้น",
        SonicBlow = "หมัดเสียง",
        Cloaking = "ล่องหน",
        Heal = "รักษา",
        Blessing = "พร",
        MagnusExorcismus = "แสงศักดิ์สิทธิ์",
        Sanctuary = "เขตศักดิ์สิทธิ์",

        -- Item names
        NoviceKnife = "มีดโนวิซ",
        ShortSword = "ดาบสั้น",
        LongSword = "ดาบยาว",
        BroadSword = "ดาบกว้าง",
        Claymore = "ดาบใหญ่",
        DragonSlayer = "ดาบสังหารมังกร",
        ShortBow = "ธนูสั้น",
        HunterBow = "ธนูพราน",
        GreatBow = "ธนูใหญ่",
        ArtemisBow = "ธนูอาร์เทมิส",
        NoviceRod = "คทาโนวิซ",
        BoneWand = "คทากระดูก",
        StaffOfFire = "คทาไฟ",
        ArcWand = "คทาสายฟ้า",
        Dagger = "กริช",
        MainGauche = "กริชซ้าย",
        Katar = "กาตาร์",
        Jur = "Jur",
        NoviceMace = "ค้อนโนวิซ",
        Mace = "ค้อน",
        WarMace = "ค้อนสงคราม",
        DivineMace = "ค้อนศักดิ์สิทธิ์",
        CottonShirt = "เสื้อผ้าฝ้าย",
        LeatherArmor = "เกราะหนัง",
        ChainMail = "เกราะโซ่",
        PlateArmor = "เกราะเหล็ก",
        LeatherCap = "หมวกหนัง",
        IronHelm = "หมวกเหล็ก",
        Crown = "มงกุฎ",
        Hood = "ฮู้ด",
        Muffler = "ผ้าพันคอ",
        WindCloak = "ผ้าคลุมลม",
        Sandals = "รองเท้าแตะ",
        Boots = "บูท",
        Greaves = "สนับแข้ง",
        WoodenShield = "โล่ไม้",
        Buckler = "โล่กลม",
        GuardianShield = "โล่ผู้พิทักษ์",
        RingOfStrength = "แหวนพลัง",
        RingOfWisdom = "แหวนปัญญา",
        RingOfSpeed = "แหวนความเร็ว",
        AmuletOfLuck = "เครื่องรางโชค",
        VoidPendant = "จี้แห่งความว่างเปล่า",
        RedPotion = "ยาน้ำแดง",
        RedPotionBig = "ยาแดงใหญ่",
        BluePotion = "ยาน้ำเงิน",
        BluePotionBig = "ยาเงินใหญ่",
        SpeedPotion = "ยาเพิ่มความเร็ว",
        LuckPotion = "ยาเพิ่มโชค",
        Jellopy = "เจลลอปปี้",
        Fluff = "ขนปุย",
        Chitin = "เปลือกแข็ง",
        Stone = "เศษหิน",
        IronOre = "แร่เหล็ก",
        Crystal = "เศษคริสตัล",
        Ember = "แกนไฟ",
        RiftShard = "เศษรอยแยก",
        CelestialFeather = "ขนสวรรค์",
        BossToken = "ตราบอส",

        -- Item rarity
        common = "ธรรมดา",
        uncommon = "ไม่ธรรมดา",
        rare = "หายาก",
        epic = "มหากาพย์",
        legendary = "ตำนาน",
}

-- Monsters reach the client as a display name rather than an id, so they get
-- their own table keyed by the English name Enemies.luau ships.
local ENEMIES: { [string]: string } = {
        Poring = "โพริ่ง",
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
        ["Baby Boar"] = "หมูป่าน้อย",
        Lunatic = "กระต่ายคลั่ง",
        Skeleton = "โครงกระดูก",
        Familiar = "ภูตน้อย",
        Anubis = "อานูบิส",
        ["Fire Elemental"] = "ภูตไฟ",
        ["Lava Toad"] = "คางคกลาวา",
        ["Abyss Hound"] = "หมาขุมนรก",
        ["Void Priest"] = "นักบวชว่างเปล่า",
        ["Celestial Guard"] = "ทหารสวรรค์",
        Seraph = "เซราฟิม",
        ["Divine Knight"] = "อัศวินสวรรค์",
        ["Heaven's Gate"] = "ประตูสวรรค์",
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

-- Display name for an item, by id. Unknown ids pass through, so a new item is
-- readable before its translation lands.
function Text.itemName(id: string?): string
        if id == nil then
                return ""
        end
        return STRINGS[id] or id
end

-- Display name for a class, by id.
function Text.className(id: string?): string
        if id == nil then
                return ""
        end
        return STRINGS[id] or id
end

-- The flavour line under a class name.
function Text.classTagline(id: string): string
        return STRINGS[id .. "Tagline"] or ""
end

-- Display name for a skill, by id.
function Text.skillName(id: string?): string
        if id == nil then
                return ""
        end
        return STRINGS[id] or id
end

-- Display name for an equipment slot.
function Text.slotName(slot: string?): string
        if slot == nil then
                return ""
        end
        return STRINGS[slot] or slot
end

-- Display name for a stat, by id.
function Text.statName(id: string): string
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
