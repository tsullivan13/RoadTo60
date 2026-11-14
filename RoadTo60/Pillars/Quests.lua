-- Road to 60: Quests pillar — quest log health.
-- Gray quests, finished quests piling up, and a log that's nearly full.
-- Uses C_QuestLog (Forever has no GetQuestLogTitle).
local _, ns = ...

-- How many levels below you a quest can be before it turns gray
local function grayRange(level)
    if UnitQuestTrivialLevelRange then
        local ok, r = pcall(UnitQuestTrivialLevelRange, "player")
        if ok and type(r) == "number" and r > 0 then return r end
    end
    if GetQuestGreenRange then
        local ok, r = pcall(GetQuestGreenRange, "player")
        if ok and type(r) == "number" and r > 0 then return r end
    end
    return level < 20 and 5 or 8
end

local function maxQuests()
    if C_QuestLog and C_QuestLog.GetMaxNumQuestsCanAccept then
        local ok, n = pcall(C_QuestLog.GetMaxNumQuestsCanAccept)
        if ok and type(n) == "number" and n > 0 then return n end
    end
    return 20
end

-- Returns { quests = {...}, max = n } where each quest is
-- { id, title, level, zone, complete, gray, red, group }
function ns.ReadQuestLog()
    local out = { quests = {}, max = maxQuests() }
    if not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo) then return out end
    local level = UnitLevel("player")
    local range = grayRange(level)
    local zone
    local n = C_QuestLog.GetNumQuestLogEntries()
    for i = 1, n do
        local info = C_QuestLog.GetInfo(i)
        if info then
            if info.isHeader then
                zone = info.title
            elseif not info.isHidden and info.questID then
                local qlevel = info.level or level
                local complete = C_QuestLog.IsComplete and C_QuestLog.IsComplete(info.questID) or false
                out.quests[#out.quests + 1] = {
                    id = info.questID, title = info.title or "?", level = qlevel, zone = zone,
                    complete = complete and true or false,
                    gray = not info.isScaling and (level - qlevel) > range,
                    red = qlevel >= level + 5,
                    group = (info.suggestedGroup or 0) > 1,
                }
            end
        end
    end
    return out
end

-- Quests turned in per level, for records and the ghost run later
ns:On("QUEST_TURNED_IN", function()
    if not ns.char then return end
    ns.char.questsByLevel = ns.char.questsByLevel or {}
    local lvl = UnitLevel("player")
    ns.char.questsByLevel[lvl] = (ns.char.questsByLevel[lvl] or 0) + 1
end)

local Quests = {
    key = "quests", name = "Quests", order = 3, weight = 1,
    events = { "QUEST_LOG_UPDATE", "QUEST_TURNED_IN", "PLAYER_LEVEL_UP" },
}

function Quests:Evaluate()
    local log = ns.ReadQuestLog()
    local q, max = log.quests, log.max
    local res = { details = {} }
    if #q == 0 then
        -- No quests means grinding: the slowest way to level
        res.score = 60
        res.reason = "Quest log is empty."
        res.action = "Pick up quests — find a quest hub for your level."
        return res
    end

    local gray, ready, red, workable = {}, {}, 0, 0
    local readyByZone = {}
    for _, x in ipairs(q) do
        if not x.complete and not x.gray and not x.red then workable = workable + 1 end
        if x.complete then
            ready[#ready + 1] = x
            if x.zone then readyByZone[x.zone] = (readyByZone[x.zone] or 0) + 1 end
        elseif x.gray then
            gray[#gray + 1] = x
        end
        if x.red and not x.complete then red = red + 1 end
    end

    local score = 100 - #gray * 6
    if #ready > 2 then score = score - (#ready - 2) * 8 end
    local free = max - #q
    if free <= 1 then score = score - 20 elseif free <= 3 then score = score - 8 end
    -- Running out of quests you can actually do at your level
    local THIN = 3
    if workable < THIN then score = score - (THIN - workable) * 6 end
    res.score = math.max(0, math.min(100, score))
    res.workable = workable

    res.reason = string.format("%d/%d quests: %d ready, %d gray%s, %d to work on.", #q, max, #ready, #gray,
        red > 0 and string.format(", %d red", red) or "", workable)

    -- Next action: the biggest problem first
    if #ready >= 3 then
        local bestZone, bestN
        for z, n in pairs(readyByZone) do
            if not bestN or n > bestN then bestZone, bestN = z, n end
        end
        res.action = string.format("%d quests ready to turn in%s.", #ready,
            bestZone and string.format(" (%d from %s)", bestN, bestZone) or "")
    elseif free <= 1 then
        res.action = string.format("Quest log %d/%d — clear some space.", #q, max)
    elseif #gray >= 2 then
        res.action = string.format("Finish or abandon %d gray quests.", #gray)
    elseif workable < THIN then
        res.action = string.format("Only %d quest%s you can work on at your level — pick up more or move to a new zone.",
            workable, workable == 1 and "" or "s")
    end

    -- Breakdown by quest log group (zone, class, profession...): finished quests
    -- left sitting and gray quests count against their group
    local groups, order = {}, {}
    for _, x in ipairs(q) do
        local z = x.zone or "Other"
        if not groups[z] then groups[z] = { n = 0, ready = 0, gray = 0, readyNames = {} }; order[#order + 1] = z end
        local g = groups[z]
        g.n = g.n + 1
        if x.complete then g.ready = g.ready + 1; g.readyNames[#g.readyNames + 1] = x.title
        elseif x.gray then g.gray = g.gray + 1 end
    end
    res.breakdown = {}
    for _, z in ipairs(order) do
        local g = groups[z]
        local parts = { string.format("%d quest%s", g.n, g.n == 1 and "" or "s") }
        if g.ready > 0 then parts[#parts + 1] = string.format("%d ready to turn in (%s)", g.ready, table.concat(g.readyNames, ", ")) end
        if g.gray > 0 then parts[#parts + 1] = g.gray .. " gray" end
        res.breakdown[#res.breakdown + 1] = {
            label = z, score = math.max(0, 100 - g.ready * 8 - g.gray * 6), note = table.concat(parts, " · "),
        }
    end

    for _, x in ipairs(ready) do
        res.details[#res.details + 1] = string.format("|cff33ff33Ready|r [%d] %s", x.level, x.title)
    end
    for _, x in ipairs(gray) do
        res.details[#res.details + 1] = string.format("|cff9d9d9dGray|r [%d] %s", x.level, x.title)
    end
    return res
end

ns:RegisterPillar(Quests)
