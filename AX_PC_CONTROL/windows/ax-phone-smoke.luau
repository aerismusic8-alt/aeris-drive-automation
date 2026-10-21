-- AX Arena: does the HUD that was actually built fit a phone screen?
--
-- Roblox Studio runs this against the built .rbxlx through --task RunScript.
-- It requires the real HudLayout module out of the place file, not the repo,
-- so it fails if the fix did not make it into the build.
--
-- The arithmetic is the part that broke: at 640x360 the 430px character sheet
-- was centred at -35, which puts its close button above the top of the screen.
-- This recomputes that, at the phone sizes, from the shipped module.

local function report(ok: boolean, label: string, detail: string)
        print(string.format("%s|%s|%s", ok and "PHONE_PASS" or "PHONE_FAIL", label, detail or ""))
end

local client = game:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts")
if client then client = client:FindFirstChild("AXArenaClient") end
if not client then
        report(false, "client-found", "AXArenaClient is missing from the place")
        return
end
report(true, "client-found", client.ClassName)

local layoutModule = client:FindFirstChild("HudLayout")
if not layoutModule then
        report(false, "layout-module", "HudLayout did not ship in the place")
        return
end

local ok, HudLayout = pcall(require, layoutModule)
if not ok then
        report(false, "layout-require", tostring(HudLayout))
        return
end
report(true, "layout-require", "HudLayout loaded from the built place")

-- Every phone size the HUD has to survive, in landscape.
local sizes = {
        { name = "small", w = 640, h = 360 },
        { name = "mid", w = 800, h = 375 },
        { name = "iphone", w = 844, h = 390 },
}

local panels = {"Stats","QuestPanel","WavePanel","BossPanel","Rewards","TravelPanel","Combat","Actions","CharPanel"}

for _, s in ipairs(sizes) do
        local room = s.h - HudLayout.SAFE_TOP - HudLayout.SAFE_BOTTOM
        local worst = 0
        for _, name in ipairs(panels) do
                local built = HudLayout.builtHeight(name, s.h)
                local top = HudLayout.centredTop(built, s.h)
                local bottom = top + built
                if bottom > s.h then
                        report(false, s.name .. "-" .. name,
                                string.format("runs to %.0f, past the %.0f screen", bottom, s.h))
                end
                if built > room then
                        report(false, s.name .. "-" .. name,
                                string.format("is %.0f tall, past the %.0f safe area", built, room))
                end
                if built > worst then worst = built end
        end
        report(true, s.name .. "-fits", string.format("%dx%d, tallest panel %.0f of %.0f safe", s.w, s.h, worst, room))
end

-- The specific regression: a 430px sheet on a 360px screen centred naively
-- lands at -35. centredTop must never return a negative offset.
local charTop = HudLayout.centredTop(HudLayout.builtHeight("CharPanel", 360), 360)
report(charTop >= 0, "char-sheet-on-screen", string.format("the character sheet starts at %.0f", charTop))

local charH = HudLayout.builtHeight("CharPanel", 360)
report(charH <= 360, "char-sheet-height", string.format("the character sheet is %.0f tall on a 360 screen", charH))

report(true, "phone-complete", "checked " .. tostring(#sizes) .. " phone sizes")
