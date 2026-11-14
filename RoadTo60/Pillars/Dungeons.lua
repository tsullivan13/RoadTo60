-- Road to 60: Dungeons pillar — dungeons in your level range and their quests.
--
-- Dungeon data (level ranges, quests, bosses) is read at runtime from the
-- ForeverDungeonJournal addon if it's installed (global ForeverDungeonJournal_NS.DB).
-- Quest completion is checked live with C_QuestLog.IsQuestFlaggedCompleted.
-- Runs and boss kills are recorded by this addon either way.
local _, ns = ...

local function journal()
    local fdj = _G.ForeverDungeonJournal_NS
    if type(fdj) == "table" and type(fdj.DB) == "table" then return fdj end
end

local function questDone(id)
    local f = (C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted) or IsQuestFlaggedCompleted
    if not f then return false end
    local ok, v = pcall(f, id)
    return ok and v and true or false
end

local function inLog(id)
    if C_QuestLog and C_QuestLog.GetLogIndexForQuestID then
        local ok, idx = pcall(C_QuestLog.GetLogIndexForQuestID, id)
        return ok and idx and idx > 0
    end
    return false
end

local function questXP(q)
    local s = q.rewards and q.rewards:match("([%d,]+) XP")
    if s then return tonumber((s:gsub(",", ""))) or 0 end
    return q.liveXPFallback or 0
end

local function finalBoss(d)
    if type(d.bosses) ~= "table" then return nil end
    for i = #d.bosses, 1, -1 do
        local b = d.bosses[i]
        if b.name and not b.rare and not b.trash and b.name ~= "Trash Drops" then return b end
    end
end

-- One entry per dungeon: { name, min, max, forever, quests = {open, done, inLog, xpOpen}, run }
function ns.DungeonStatus()
    local fdj = journal()
    if not fdj then return nil end
    local level = UnitLevel("player")
    local faction = UnitFactionGroup("player")
    local _, class = UnitClass("player")
    local list = {}
    for name, d in pairs(fdj.DB) do
        local min, max = tostring(d.level or ""):match("(%d+)%-(%d+)")
        min, max = tonumber(min), tonumber(max)
        if min and max then
            local open, done, logged, xpOpen, total = 0, 0, 0, 0, 0
            -- Open XP split by whether the quest is in your log; quests with no XP in the
            -- journal are counted separately (unknownLog / unknownOther) and estimated later.
            local xpLog, xpOther, unknownLog, unknownOther = 0, 0, 0, 0
            local pickups = {}  -- open quests to grab in town before going in
            for _, q in ipairs(d.quests or {}) do
                local applies = q.id and not q.hideFromMainList
                    and (q.faction == nil or q.faction == "Both" or q.faction == faction)
                    and (q.classOnly == nil or q.classOnly == class)
                if applies then
                    total = total + 1
                    if questDone(q.id) then
                        done = done + 1
                    elseif (q.requires or 0) <= level then
                        open = open + 1
                        local xp, logd = questXP(q), inLog(q.id)
                        xpOpen = xpOpen + xp
                        if logd then logged = logged + 1 end
                        -- Only quests you can grab beforehand: the journal doesn't always flag
                        -- ones that start inside (an NPC inside, an item that drops)
                        local where = (q.pickup or ""):lower()
                        local insideStart = q.startsInDungeon or where:find("inside", 1, true)
                            or where:find("^item start") or where:find("dropped by", 1, true)
                            or where:find("taken from", 1, true)
                        -- Some "Both" quests start in the other faction's capital: skip those
                        local otherCapital = false
                        for _, city in ipairs(faction == "Horde" and { "ironforge", "stormwind", "darnassus" }
                            or { "orgrimmar", "undercity", "thunder bluff" }) do
                            if where:find(city, 1, true) then otherCapital = true end
                        end
                        if not logd and not insideStart and not otherCapital and q.pickup and q.name then
                            pickups[#pickups + 1] = { name = q.name, where = q.pickup, xp = xp }
                        end
                        if xp > 0 then
                            if logd then xpLog = xpLog + xp else xpOther = xpOther + xp end
                        else
                            if logd then unknownLog = unknownLog + 1 else unknownOther = unknownOther + 1 end
                        end
                    end
                end
            end
            list[#list + 1] = {
                name = name, min = min, max = max,
                forever = fdj.FOREVER_DUNGEONS and fdj.FOREVER_DUNGEONS[name] or false,
                total = total, open = open, done = done, inLog = logged, xpOpen = xpOpen,
                xpLog = xpLog, xpOther = xpOther, unknownLog = unknownLog, unknownOther = unknownOther,
                pickups = pickups,
                run = ns.char.dungeons and ns.char.dungeons[name:lower()],
            }
        end
    end
    table.sort(list, function(a, b) return a.min < b.min or (a.min == b.min and a.name < b.name) end)
    return list
end

---------------------------------------------------------------------------
-- Recording runs and boss kills
---------------------------------------------------------------------------
local function currentDungeon()
    local name, instanceType = GetInstanceInfo()
    if instanceType == "party" and name then return name end
end

local function onEnter()
    if not ns.char then return end
    local name = currentDungeon()
    if not name then return end
    ns.char.dungeons = ns.char.dungeons or {}
    local key = name:lower()
    local r = ns.char.dungeons[key]
    if not r then
        r = { name = name, firstLevel = UnitLevel("player"), runs = 0, clears = 0, bosses = {} }
        ns.char.dungeons[key] = r
    end
    -- A new run if you've been out for more than an hour
    if not r.last or time() - r.last > 3600 then r.runs = r.runs + 1 end
    r.last = time()
end
ns:On("PLAYER_ENTERING_WORLD", onEnter)
ns:On("ZONE_CHANGED_NEW_AREA", onEnter)

ns:On("ENCOUNTER_END", function(_, _, encounterName, _, _, success)
    if success ~= 1 and success ~= true then return end
    local name = currentDungeon()
    if not name or not ns.char.dungeons then return end
    local r = ns.char.dungeons[name:lower()]
    if not r then return end
    r.bosses[encounterName] = UnitLevel("player")
    r.last = time()
    -- Final boss down = a clear
    local fdj = journal()
    local d = fdj and (fdj.DB[name] or fdj.DB[r.name])
    local fb = d and finalBoss(d)
    if fb then
        for _, alias in ipairs(fb.aliases or { fb.name }) do
            if alias == encounterName then
                r.clears = (r.clears or 0) + 1
                r.clearedAt = r.clearedAt or UnitLevel("player")
                ns:Alert(nil, string.format("%s cleared!", r.name))
                break
            end
        end
    end
end)

---------------------------------------------------------------------------
-- Pillar
---------------------------------------------------------------------------
local Dungeons = {
    key = "dungeons", name = "Dungeons", order = 6, weight = 0.5,
    events = { "PLAYER_LEVEL_UP", "QUEST_TURNED_IN", "QUEST_ACCEPTED", "ZONE_CHANGED_NEW_AREA" },
}

-- Grading: dungeon quest XP you're about to leave behind, measured against the XP
-- of your current level (missing a level's worth matters more at 15 than at 45).
--   * Quests in your log count fully. Ones you haven't picked up count half: you may
--     not have found the giver, or they may need an earlier quest in the chain.
--   * Urgency rises from 0 at the middle of a dungeon's range to 1 at its top level,
--     so the grade slips gradually as the window closes instead of dropping at once.
--   * Out-levelled dungeons count fully for MISS_GRACE levels, then stop being graded
--     (you can't fix the past); they stay in the breakdown marked as skipped.
--   * Leaving a whole level's worth of XP behind costs POINTS_PER_LEVEL points.
local MISS_GRACE = 5
local SKIPPED_SHOWN = 10        -- breakdown keeps skipped dungeons this many levels
local POINTS_PER_LEVEL = 60
local UNKNOWN_XP = 0.05         -- a quest with no XP in the journal ~ 5% of a level
local MAX_LEVEL = 60

local function shortXP(xp)
    if xp >= 1000 then return string.format("~%dk XP", math.floor(xp / 1000 + 0.5)) end
    return string.format("%d XP", math.floor(xp + 0.5))
end

-- 0 at the middle of the range or below, 1 at the top level and beyond
local function urgency(d, level)
    if level >= d.max then return 1 end
    local mid = math.floor((d.min + d.max) / 2)
    if level <= mid then return 0 end
    return (level - mid) / math.max(1, d.max - mid)
end

local function weightedXP(d, xpMax)
    local est = xpMax * UNKNOWN_XP
    return (d.xpLog or 0) + (d.unknownLog or 0) * est
        + 0.5 * ((d.xpOther or 0) + (d.unknownOther or 0) * est)
end

local function scoreFor(atRisk, xpMax)
    return math.max(0, math.min(100, math.floor(100 - POINTS_PER_LEVEL * atRisk / xpMax + 0.5)))
end

local function runText(d)
    return d.run and string.format("run %dx%s", d.run.runs or 0, (d.run.clears or 0) > 0 and ", cleared" or "")
        or "not run"
end

function Dungeons:Evaluate()
    local res = { details = {}, breakdown = {} }
    local list = ns.DungeonStatus()
    if not list then
        local n = 0
        for _ in pairs(ns.char.dungeons or {}) do n = n + 1 end
        res.reason = string.format("Install ForeverDungeonJournal to track dungeon quests. %d dungeon%s visited.",
            n, n == 1 and "" or "s")
        return res
    end

    local level = UnitLevel("player")
    if level >= MAX_LEVEL then
        res.reason = "You made it to 60. Dungeons are for gear from here."
        return res
    end
    local xpMax = math.max(1, UnitXPMax("player") or 1)

    local current, upcoming, graded, totalRisk, missedRisk = {}, {}, false, 0, 0
    for _, d in ipairs(list) do
        d.urgency = urgency(d, level)
        d.weighted = weightedXP(d, xpMax)
        d.atRisk = 0
        local missedBy = level - d.max
        if d.min > level then
            if d.min <= level + 3 then upcoming[#upcoming + 1] = d end
        elseif missedBy <= 0 then
            current[#current + 1] = d
            graded = true
            d.atRisk = d.weighted * d.urgency
        elseif missedBy <= MISS_GRACE then
            graded = true
            d.atRisk = d.weighted
            missedRisk = missedRisk + d.atRisk
        end
        totalRisk = totalRisk + d.atRisk
    end
    if graded then res.score = scoreFor(totalRisk, xpMax) end
    res.xpAtRisk = totalRisk

    -- Reason
    if #current > 0 then
        local names = {}
        for _, d in ipairs(current) do names[#names + 1] = d.name end
        res.reason = "In range: " .. table.concat(names, ", ") .. "."
    elseif #upcoming > 0 then
        local names = {}
        for _, d in ipairs(upcoming) do names[#names + 1] = string.format("%s (%d-%d)", d.name, d.min, d.max) end
        res.reason = "Coming up: " .. table.concat(names, ", ") .. "."
    else
        res.reason = "No dungeons in your level range."
    end
    if totalRisk >= 1 then
        res.reason = res.reason .. string.format(" %s at risk (%d%% of this level)%s.", shortXP(totalRisk),
            math.floor(totalRisk / xpMax * 100 + 0.5),
            missedRisk >= 1 and string.format(", %s of it from dungeons you've out-levelled", shortXP(missedRisk)) or "")
    end

    -- Action: the in-range dungeon with the most XP at risk, then the most open XP
    table.sort(current, function(a, b)
        if a.atRisk ~= b.atRisk then return a.atRisk > b.atRisk end
        return a.xpOpen > b.xpOpen
    end)
    local best = current[1]
    if best and best.open > 0 then
        -- "Last chance" only when missing it would cost a letter grade; else "Closing soon"
        local closing = level >= best.max - 2
        local wholeCost = 100 - scoreFor(best.weighted, xpMax)
        local prefix = closing and (wholeCost >= 10 and "Last chance — " or "Closing soon — ") or ""
        res.action = string.format("%s%s (%d-%d): %d quest%s open, %s%s.",
            prefix, best.name, best.min, best.max,
            best.open, best.open == 1 and "" or "s", shortXP(best.xpOpen),
            best.inLog > 0 and string.format(", %d in your log", best.inLog) or "")
        res.actionGain = scoreFor(totalRisk - best.atRisk, xpMax) - (res.score or 100)
    elseif best and not best.run then
        res.action = string.format("Run %s (%d-%d).", best.name, best.min, best.max)
        res.actionGain = 0
    end
    -- Before you go: quests for that dungeon that start outside it
    if best and best.pickups and #best.pickups > 0 then
        local p = best.pickups[1]
        res.pickupAction = string.format("Before %s: pick up %s (%s)%s.", best.name, p.name, p.where,
            #best.pickups > 1 and string.format(" and %d more", #best.pickups - 1) or "")
    end

    -- Breakdown rows use the same math as the grade
    for _, d in ipairs(list) do
        local missedBy = level - d.max
        if d.min <= level + 3 and missedBy <= SKIPPED_SHOWN then
            local quests = d.total > 0 and string.format("quests %d/%d done", d.done, d.total) or "no quests for you"
            local open = d.open > 0 and (" · " .. shortXP(d.xpOpen) .. " open") or ""
            local row = { label = string.format("%s%s (%d-%d)", d.name, d.forever and " *" or "", d.min, d.max) }
            if d.min > level then
                row.note = "coming up · " .. quests
            elseif missedBy > MISS_GRACE then
                if d.open > 0 then row.note = "skipped · no longer graded · " .. quests else row = nil end
            elseif missedBy > 0 then
                row.score = scoreFor(d.atRisk, xpMax)
                row.note = "out-levelled · " .. quests .. open
                    .. (missedBy == MISS_GRACE and " · stops counting next level" or "")
            elseif d.open == 0 then
                row.score = 100
                row.note = runText(d) .. " · " .. quests
            else
                row.score = scoreFor(d.atRisk, xpMax)
                row.note = (level >= d.max - 2 and "window closing · " or "") .. runText(d) .. " · " .. quests .. open
                    .. (d.atRisk >= 1 and (" · " .. shortXP(d.atRisk) .. " at risk") or " · no rush yet")
            end
            if row then res.breakdown[#res.breakdown + 1] = row end
            -- Quests to pick up in town first, for dungeons you're in range of (or nearly)
            if d.min <= level + 2 and level <= d.max then
                local pickups = d.pickups or {}
                for i = 1, math.min(3, #pickups) do
                    local p = pickups[i]
                    res.breakdown[#res.breakdown + 1] = { label = "   Pick up first: " .. p.name,
                        note = p.where .. (p.xp > 0 and (" · " .. shortXP(p.xp)) or "") }
                end
                if #pickups > 3 then
                    res.breakdown[#res.breakdown + 1] = { label = string.format("   + %d more to pick up", #pickups - 3),
                        note = "/r60 debug dungeons lists them all" }
                end
            end
        end
        -- Tooltip lines: dungeons around your level
        if d.min <= level + 3 and missedBy <= MISS_GRACE then
            res.details[#res.details + 1] = string.format("%s%s|r %d-%d — %s; quests %d/%d done%s",
                d.forever and "|cffffd100" or "|cffffffff", d.name, d.min, d.max, runText(d), d.done, d.total,
                d.open > 0 and string.format(" (%s open)", shortXP(d.xpOpen)) or "")
        end
    end
    return res
end

ns:RegisterPillar(Dungeons)
