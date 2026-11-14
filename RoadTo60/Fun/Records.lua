-- Road to 60: personal records — about being prepared, not about speed.
--   Best checkpoint grade (yours, and the account's with the character's name)
--   On-pace streak: levels in a row at B or better overall (judged at each ding)
--   No-stale-gear streak: levels in a row with no stale gear slot
--   Quests turned in, dungeon runs and clears
local _, ns = ...

local ON_PACE = 75  -- B or better

local function rec()
    ns.char.records = ns.char.records or {}
    ns.db.records = ns.db.records or {}
    return ns.char.records, ns.db.records
end

local function charName()
    return (UnitName("player") or "?") .. " (" .. (select(1, UnitClass("player")) or "?") .. ")"
end

local function streak(r, key, ok)
    r[key] = r[key] or { current = 0, best = 0 }
    local s = r[key]
    if ok then
        s.current = s.current + 1
        if s.current > s.best then s.best = s.current end
    else
        s.current = 0
    end
end

-- Streaks, judged at each ding
ns:Listen("LEVEL_UP", function()
    C_Timer.After(1, function()
        ns:Refresh()
        local r = rec()
        local gear = ns.results.gear
        streak(r, "gearStreak", gear and (gear.staleCount or 0) == 0)
        streak(r, "paceStreak", ns.overall and ns.overall >= ON_PACE)
    end)
end)

-- Best checkpoint grade
ns:Listen("CHECKPOINT", function(card)
    if not card.overall then return end
    local r, acct = rec()
    local prev = r.bestCheckpoint
    if not prev or card.overall > prev.overall then
        if prev and ns.Grade(card.overall) ~= ns.Grade(prev.overall) then
            ns:Alert("record", string.format("New best checkpoint: %s at %d (was %s at %d)!",
                ns.Grade(card.overall), card.level, ns.Grade(prev.overall), prev.level))
        end
        r.bestCheckpoint = { overall = card.overall, level = card.level }
    end
    if not acct.bestCheckpoint or card.overall > acct.bestCheckpoint.overall then
        acct.bestCheckpoint = { overall = card.overall, level = card.level, char = charName() }
    end
end)

-- Lines for the dashboard's Records tab
function ns.RecordLines()
    local r, acct = rec()
    local lines = {}
    local function add(label, value) lines[#lines + 1] = { label, value } end

    local b = r.bestCheckpoint
    add("Best checkpoint grade", b and string.format("%s at level %d", ns.Grade(b.overall), b.level)
        or "|cff888888your first card is at level 10|r")
    if acct.bestCheckpoint and acct.bestCheckpoint.char ~= charName() then
        add("   account best", string.format("%s at %d — %s", ns.Grade(acct.bestCheckpoint.overall),
            acct.bestCheckpoint.level, acct.bestCheckpoint.char))
    end

    local function streakLine(label, s)
        add(label, s and string.format("%d level%s (best %d)", s.current, s.current == 1 and "" or "s", s.best)
            or "starts at your next ding")
    end
    streakLine("On-pace streak (B or better)", r.paceStreak)
    streakLine("No-stale-gear streak", r.gearStreak)

    local quests = 0
    for _, n in pairs(ns.char.questsByLevel or {}) do quests = quests + n end
    add("Quests turned in (tracked)", tostring(quests))

    local runs, clears = 0, 0
    for _, d in pairs(ns.char.dungeons or {}) do runs = runs + (d.runs or 0); clears = clears + (d.clears or 0) end
    add("Dungeon runs / clears", runs .. " / " .. clears)

    local played = ns.PlayedNow()
    if played then add("Time played", ns.FormatDuration(played)) end

    local toGo = ns.LegacyLevelsToGo and ns.LegacyLevelsToGo() or 0
    if toGo > 0 then add("Legacy System", string.format("unlocks at level 25 (%d to go)", toGo)) end

    if ns.GhostLines then
        for _, l in ipairs(ns.GhostLines()) do lines[#lines + 1] = l end
    end
    return lines
end
