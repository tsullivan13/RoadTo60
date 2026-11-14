-- Road to 60: alerts — a center-screen toast plus a chat line.
-- Never fires in combat: alerts queue until PLAYER_REGEN_ENABLED.
local _, ns = ...

local queue = {}

local toast = CreateFrame("Frame", "RoadTo60Toast", UIParent)
toast:SetSize(520, 40)
toast:SetPoint("TOP", UIParent, "TOP", 0, -180)
toast:SetFrameStrata("HIGH")
toast:Hide()

local bg = toast:CreateTexture(nil, "BACKGROUND")
bg:SetAllPoints()
bg:SetColorTexture(0, 0, 0, 0.6)

toast.text = toast:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
toast.text:SetPoint("CENTER")
toast.text:SetWidth(500)

local showing = false
local function showNext()
    if showing or #queue == 0 or InCombatLockdown() then return end
    showing = true
    local msg = table.remove(queue, 1)
    toast.text:SetText(msg)
    toast:SetAlpha(1)
    toast:Show()
    ns:Print(msg)
    C_Timer.After(4, function()
        UIFrameFadeOut(toast, 0.5, 1, 0)
        C_Timer.After(0.6, function()
            toast:Hide()
            showing = false
            showNext()
        end)
    end)
end

-- kind = settings.alerts key, so each alert type can be muted
function ns:Alert(kind, msg)
    if kind and ns.settings.alerts[kind] == false then return end
    queue[#queue + 1] = msg
    showNext()
end

ns:On("PLAYER_REGEN_ENABLED", function() showNext() end)

---------------------------------------------------------------------------
-- Level-up recap (alerts.levelRecap): one chat line at each ding saying what
-- changed during the level you just finished. "Level 33 done: Gear B to A,
-- Spells C to B · +62g". Chat only, no toast.
---------------------------------------------------------------------------
local function snapshot(level)
    local grades = {}
    for _, p in ipairs(ns.PillarsInOrder()) do
        local r = ns.results[p.key]
        if r and r.score then grades[p.key] = r.score end
    end
    ns.char.levelSnapshot = { level = level, money = GetMoney(), grades = grades }
end

-- Runs before the post-ding refresh, so ns.results still holds the end of the old level
ns:Listen("LEVEL_UP", function(newLevel)
    local snap = ns.char.levelSnapshot
    if ns.settings.alerts.levelRecap == false or not snap or snap.level ~= newLevel - 1 then return end
    local parts = {}
    for _, p in ipairs(ns.PillarsInOrder()) do
        local r, before = ns.results[p.key], snap.grades[p.key]
        if r and r.score and before and ns.Grade(before) ~= r.grade then
            parts[#parts + 1] = string.format("%s %s to %s", p.name, ns.Grade(before), r.grade)
        end
    end
    local money = GetMoney() - (snap.money or GetMoney())
    local text = string.format("Level %d done: %s", snap.level,
        #parts > 0 and table.concat(parts, ", ") or "grades held steady")
    if money ~= 0 then text = text .. " · " .. (money > 0 and "+" or "") .. ns.FormatMoney(money) end
    ns:Print(text)
end)

-- A fresh snapshot at the start of each level (and the first time we see a character)
ns:Listen("PILLARS_UPDATED", function()
    local level = UnitLevel("player")
    local snap = ns.char.levelSnapshot
    if not snap or snap.level ~= level then snapshot(level) end
end)
