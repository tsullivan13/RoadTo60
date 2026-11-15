-- Road to 60: core — events, storage, pillar registry, grading.
local ADDON, ns = ...
_G.RoadTo60 = ns

ns.version = "1.2.0"

---------------------------------------------------------------------------
-- Defaults (account-wide settings live in RoadTo60DB.settings)
---------------------------------------------------------------------------
ns.defaults = {
    settings = {
        staleLevels    = 8,      -- gear slot older than this many levels = stale
        jewelryLevel   = 25,     -- empty neck/ring/trinket only counts after this level
        headLevel      = 25,     -- empty head/shoulders only count after this level
        hideInCombat   = true,   -- hide the dashboard while in combat
        spellOverdue   = 4,      -- trainable rank this many levels late = overdue (about one trainer trip)
        goldCurve      = 2.5,    -- expected savings = cost * (progress ^ goldCurve), progress from level 10
        disabledPillars = {},    -- [key] = true: left out of grading entirely
        pillarWeights  = {},     -- [key] = percent of the pillar's built-in weight (nil = 100)
        nextStep       = true,   -- the "next best step" line under the pip bar
        -- Profession tier unlocks: [new cap] = { level, skill } needed to train it.
        -- Classic values; Forever's may differ.
        profTiers = {
            [150] = { level = 10, skill = 50 },
            [225] = { level = 20, skill = 125 },
            [300] = { level = 35, skill = 200 },
        },
        alerts = {
            pillarRed  = true,
            trainable  = true,
            checkpoint = true,
            record     = true,
            levelRecap = true,   -- one chat line at each ding: what changed during the level
        },
        cardShare      = true,   -- "Share" button on report cards
        minimap        = { shown = true, angle = 200 },   -- minimap button
        dataBroker     = true,   -- feed Titan / ChocolateBar / other LibDataBroker displays
        -- Class checks: conjure = Mages are told to conjure food/water, not buy it;
        -- wand = Priests, Mages and Warlocks get their wand graded like a weapon.
        -- (The Hunter pet check is its own pillar, switched in Settings > Pillars.)
        classChecks    = { conjure = true, wand = true },
        -- Gold goals: { level, cost = copper, label, id }. Forever prices (Nov 2026):
        -- Apprentice riding 100g with a mount; Journeyman riding 1000g + epic mount 200g.
        -- Goals with a riding id get the 10% Honored discount.
        goldGoals = {
            { level = 40, cost = 100 * 10000,  label = "Apprentice riding + mount", id = "riding40" },
            { level = 60, cost = 1200 * 10000, label = "Journeyman riding + epic mount", id = "riding60" },
        },
        -- orientation: "horizontal" | "vertical"
        -- nextStepSide: where the next-step line sits, "below" | "above" | "left" | "right"
        -- nextStepBox: draw it in a box like the bar's; nextStepWidth: widest it gets before wrapping
        -- scale: percent; pipSize: pixels; letters: grade letter on each pip (colorblind help);
        -- fade: dim the bar while every pillar is green, to fadeAlpha percent
        pipBar = { point = "TOP", x = 0, y = -120, shown = true, locked = false,
                   orientation = "horizontal", nextStepSide = "below",
                   nextStepBox = true, nextStepWidth = 320,
                   scale = 100, pipSize = 14, letters = false, fade = false, fadeAlpha = 35 },
    },
    learned = {},   -- learned spell tables per class (M2)
    runs    = {},   -- past runs for ghost comparison (M5)
}

ns.charDefaults = {
    gearHistory  = {},  -- [slot] = { {link, level, time}, ... }
    moneyByLevel = {},  -- [level] = copper at ding
    goalsReached = {},  -- [goal level] = true once you've held that goal's cost
    checkpoints  = {},  -- M4
    lastStatus   = {},  -- [pillarKey] = "green"/"yellow"/"red"
}

local function applyDefaults(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            -- only deep-merge keyed tables; arrays (goldGoals) are copied once
            if #v > 0 then
                if #dst[k] == 0 then
                    for i, item in ipairs(v) do
                        dst[k][i] = type(item) == "table" and CopyTable(item) or item
                    end
                end
            else
                applyDefaults(dst[k], v)
            end
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

---------------------------------------------------------------------------
-- Printing helpers
---------------------------------------------------------------------------
ns.PREFIX = "|cff33ff99Road to 60|r: "

function ns:Print(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    local msg = table.concat(parts, " ")
    DEFAULT_CHAT_FRAME:AddMessage(ns.PREFIX .. msg)
    if ns.capture then ns.capture[#ns.capture + 1] = msg:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") end
end

-- Run fn while recording everything it prints into RoadTo60DB.log[name],
-- so the output can be read from WTF\...\SavedVariables\RoadTo60.lua after /reload.
function ns:Capture(name, fn)
    ns.capture = {}
    local ok, err = pcall(fn)
    if not ok then ns:Print("|cffff3333error|r " .. tostring(err)) end
    ns.db.log = ns.db.log or {}
    ns.db.log[name] = { when = date("%Y-%m-%d %H:%M:%S"), lines = ns.capture }
    ns.capture = nil
    DEFAULT_CHAT_FRAME:AddMessage(ns.PREFIX .. "|cff888888saved to disk — type /reload so it's written.|r")
end

-- Run fn safely: on error, log it to disk, say so in chat, and keep going.
function ns:Safe(where, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then
        ns:LogError(where .. ": " .. tostring(err))
        ns:Print("|cffff3333error in " .. where .. "|r — saved for debugging: " .. tostring(err))
    end
    return ok
end

-- Keep the last 30 addon errors on disk too
function ns:LogError(err)
    if not ns.db then return end
    ns.db.errors = ns.db.errors or {}
    table.insert(ns.db.errors, date("%Y-%m-%d %H:%M:%S") .. " " .. tostring(err))
    while #ns.db.errors > 30 do table.remove(ns.db.errors, 1) end
end

function ns.FormatMoney(copper)
    copper = math.floor(copper or 0)
    local neg = copper < 0
    copper = math.abs(copper)
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    local c = copper % 100
    local out
    if g > 0 then
        out = string.format("%dg %ds", g, s)
    elseif s > 0 then
        out = string.format("%ds %dc", s, c)
    else
        out = string.format("%dc", c)
    end
    return neg and ("-" .. out) or out
end

---------------------------------------------------------------------------
-- Event bus
---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
local handlers = {}

function ns:On(event, fn)
    if not handlers[event] then
        handlers[event] = {}
        -- Unknown event names raise an error; skip them so one renamed event
        -- in a client patch can't stop the whole addon from loading.
        if not pcall(eventFrame.RegisterEvent, eventFrame, event) then
            ns.unknownEvents = ns.unknownEvents or {}
            ns.unknownEvents[#ns.unknownEvents + 1] = event
        end
    end
    table.insert(handlers[event], fn)
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if not list then return end
    for _, fn in ipairs(list) do
        local ok, err = pcall(fn, event, ...)
        if not ok then ns:LogError(err); geterrorhandler()(err) end
    end
end)

-- Internal callbacks (e.g. "PILLARS_UPDATED") for UI modules
local callbacks = {}
function ns:Listen(name, fn)
    callbacks[name] = callbacks[name] or {}
    table.insert(callbacks[name], fn)
end
function ns:Fire(name, ...)
    for _, fn in ipairs(callbacks[name] or {}) do fn(...) end
end

---------------------------------------------------------------------------
-- Grading
---------------------------------------------------------------------------
ns.GRADE_BANDS = { { 90, "A" }, { 75, "B" }, { 60, "C" }, { 40, "D" }, { 0, "F" } }

function ns.Grade(score)
    if not score then return "-" end
    for _, band in ipairs(ns.GRADE_BANDS) do
        if score >= band[1] then return band[2] end
    end
    return "F"
end

-- Pip color for a score: green = on pace/ahead, yellow = slipping, red = behind
function ns.StatusFor(score)
    if not score then return "gray" end
    if score >= 75 then return "green" end
    if score >= 50 then return "yellow" end
    return "red"
end

function ns.StatusLabel(score)
    if not score then return "Not tracked yet" end
    if score >= 90 then return "Ahead" end
    if score >= 75 then return "On pace" end
    if score >= 50 then return "Slipping" end
    return "Behind"
end

ns.COLORS = {
    green  = { 0.20, 0.85, 0.30 },
    yellow = { 1.00, 0.80, 0.10 },
    red    = { 0.95, 0.20, 0.20 },
    gray   = { 0.45, 0.45, 0.45 },
}

---------------------------------------------------------------------------
-- Pillar registry
--   def = {
--     key, name, order, weight,
--     Evaluate = function(self) return { score=0-100|nil, reason="", action="" } end,
--     events = { "EVENT", ... }   -- events that should trigger a refresh
--   }
---------------------------------------------------------------------------
ns.pillars = {}
ns.results = {}

function ns:RegisterPillar(def)
    def.weight = def.weight or 1
    table.insert(ns.pillars, def)
    table.sort(ns.pillars, function(a, b) return a.order < b.order end)
    for _, ev in ipairs(def.events or {}) do
        ns:On(ev, function() ns:RequestRefresh() end)
    end
end

function ns:GetPillar(key)
    for _, p in ipairs(ns.pillars) do
        if p.key == key then return p end
    end
end

-- A pillar is hidden when the player turned it off in settings, or hides itself
-- until it matters (Legacy while locked, Raid below 55).
-- Hidden pillars get no pip, no dashboard row, no report-card line and no part in
-- the overall grade.
function ns.IsPillarShown(p)
    if ns.settings and ns.settings.disabledPillars[p.key] then return false end
    if p.Hidden then
        local ok, hidden = pcall(p.Hidden, p)
        if ok and hidden then return false end
    end
    return true
end

-- A pillar's weight in the overall grade: built-in weight times the player's percent
-- (Settings > Pillars). 0 keeps the pillar visible but out of the overall grade.
function ns.PillarWeight(p)
    if ns.settings.disabledPillars[p.key] then return 0 end
    return (p.weight or 1) * (ns.settings.pillarWeights[p.key] or 100) / 100
end

-- Turn a pillar on or off (the same switch as the checkboxes in settings)
function ns:SetPillarTracked(key, on)
    local p = ns:GetPillar(key)
    if not p then return end
    ns.settings.disabledPillars[key] = (not on) or nil
    if on then
        ns:Print(p.name .. " is tracked again.")
    else
        ns:Print(p.name .. " is hidden. Bring it back with /r60 show " .. key .. " or in /r60 settings.")
    end
    if RoadTo60Settings and RoadTo60Settings:IsShown() then RoadTo60Settings.refresh() end
    ns:Refresh()
end

-- Visible pillars in a fixed order of importance (each pillar's `order`), so every
-- pip keeps its place; colors show what's behind. Shared by the pip bar and dashboard.
function ns.PillarsInOrder()
    local list = {}
    for _, p in ipairs(ns.pillars) do
        if ns.IsPillarShown(p) then list[#list + 1] = p end
    end
    -- `displayOrder` lets a pillar show early but be graded last (Raid reads the others)
    table.sort(list, function(a, b) return (a.displayOrder or a.order) < (b.displayOrder or b.order) end)
    return list
end

local refreshPending = false
function ns:RequestRefresh()
    if refreshPending or not ns.ready then return end
    refreshPending = true
    C_Timer.After(0.5, function()
        refreshPending = false
        ns:Refresh()
    end)
end

function ns:Refresh()
    local total, weights = 0, 0
    for _, p in ipairs(ns.pillars) do
        local ok, res
        if ns.settings.disabledPillars[p.key] then
            ok, res = true, { reason = "Turned off in settings.", hidden = true }
        elseif not ns.IsPillarShown(p) then
            ok, res = true, { reason = "Not relevant yet.", hidden = true }
        else
            ok, res = pcall(p.Evaluate, p)
        end
        if not ok then
            ns:LogError(p.key .. ": " .. tostring(res))
            res = { reason = "Error: " .. tostring(res) }
        end
        res = res or {}
        res.status = ns.StatusFor(res.score)
        res.grade = ns.Grade(res.score)
        ns.results[p.key] = res

        if res.score then
            total = total + res.score * ns.PillarWeight(p)
            weights = weights + ns.PillarWeight(p)
        end

        -- status-change alerts
        local last = ns.char.lastStatus[p.key]
        -- only when a pillar drops to red, not when it first gets data (gray -> red)
        if last and last ~= "gray" and last ~= res.status and res.status == "red" then
            ns:Alert("pillarRed", string.format("%s is behind: %s", p.name, res.action or res.reason or ""))
        end
        ns.char.lastStatus[p.key] = res.status
    end
    ns.overall = weights > 0 and (total / weights) or nil
    ns:Fire("PILLARS_UPDATED")
end

-- Back to defaults (settings only; history, cards and records are kept)
function ns:ResetSettings()
    RoadTo60DB.settings = { schema = 3 }  -- defaults are already current
    applyDefaults(RoadTo60DB.settings, ns.defaults.settings)
    ns.settings = RoadTo60DB.settings
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------
ns:On("ADDON_LOADED", function(_, name)
    if name ~= ADDON then return end
    RoadTo60DB = RoadTo60DB or {}
    RoadTo60CharDB = RoadTo60CharDB or {}
    applyDefaults(RoadTo60DB, ns.defaults)
    applyDefaults(RoadTo60CharDB, ns.charDefaults)
    ns.db = RoadTo60DB
    ns.char = RoadTo60CharDB
    ns.settings = RoadTo60DB.settings
    ns:MigrateSettings()
end)

-- One-time updates to saved settings. Only values still at an old default change,
-- so anything the player set by hand is kept.
function ns:MigrateSettings()
    local s = ns.settings
    if (s.schema or 1) < 2 then
        -- v0.9.1: gentler gold curve; Forever's real mount prices
        if s.goldCurve == 3 then s.goldCurve = 2.5 end
        for _, g in ipairs(s.goldGoals or {}) do
            if g.level == 40 and g.cost == 100 * 10000 and (g.label == "Riding + mount" or g.id == "riding40") then
                g.id, g.label = "riding40", "Apprentice riding + mount"
            elseif g.level == 60 and g.cost == 1000 * 10000 and g.label == "Epic mount" then
                g.id, g.cost, g.label = "riding60", 1200 * 10000, "Journeyman riding + epic mount"
            end
        end
        s.schema = 2
    end
    if s.schema < 3 then
        -- v0.10.0: a rank is overdue after 4 levels (was 2, shorter than a trainer trip)
        if s.spellOverdue == 2 then s.spellOverdue = 4 end
        s.schema = 3
    end
end

ns:On("PLAYER_LOGIN", function()
    ns.ready = true
    -- Which version is actually running (handy after a /reload)
    ns.db.loaded = { version = ns.version, at = date("%Y-%m-%d %H:%M:%S") }
    DEFAULT_CHAT_FRAME:AddMessage(ns.PREFIX .. "|cff888888v" .. ns.version .. " loaded — /r60|r")
    ns.session = { startMoney = GetMoney(), startTime = GetTime() }
    -- Record money at current level if we have nothing for it yet
    local lvl = UnitLevel("player")
    if not ns.char.moneyByLevel[lvl] then
        ns.char.moneyByLevel[lvl] = GetMoney()
    end
    ns:Fire("LOGIN")
    ns:Refresh()
end)

ns:On("PLAYER_LEVEL_UP", function(_, newLevel)
    ns.char.moneyByLevel[newLevel] = GetMoney()
    ns:Fire("LEVEL_UP", newLevel)
    ns:RequestRefresh()
end)
