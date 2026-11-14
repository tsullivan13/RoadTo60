-- Road to 60: history — every character's run is saved account-wide, so a later
-- character can compare its preparation with your best earlier run (the "ghost").
-- It compares grades, not speed: Road to 60 is about being ready, not rushing.
--   RoadTo60DB.runs[realm-name] = { name, class, classFile, race, level, updated,
--       moneyByLevel = {[lvl] = copper},
--       checkpoints = {[lvl] = {overall, money, scores = {[pillar] = score}}} }
local _, ns = ...

local function myKey()
    return (GetRealmName and GetRealmName() or "?") .. "-" .. (UnitName("player") or "?")
end

local function copy(t)
    local out = {}
    for k, v in pairs(t or {}) do out[k] = v end
    return out
end

function ns:SaveRun()
    if not ns.char or not ns.db then return end
    ns.db.runs = ns.db.runs or {}
    local className, classFile = UnitClass("player")
    local cps = {}
    for lvl, c in pairs(ns.char.checkpoints or {}) do
        local scores = {}
        for key, g in pairs(c.grades or {}) do scores[key] = g.score end
        cps[lvl] = { overall = c.overall, money = c.money, scores = scores }
    end
    ns.db.runs[myKey()] = {
        name = UnitName("player"), class = className, classFile = classFile,
        race = select(1, UnitRace("player")), level = UnitLevel("player"), updated = time(),
        moneyByLevel = copy(ns.char.moneyByLevel), checkpoints = cps,
    }
end

ns:Listen("LOGIN", function() ns:SaveRun() end)
ns:Listen("CHECKPOINT", function() ns:SaveRun() end)

-- The ghost for a checkpoint: your best-prepared earlier run that reached it.
-- Same class first, then the highest overall grade.
function ns.FindGhost(level)
    local me = myKey()
    local _, myClass = UnitClass("player")
    local best, bestCp, bestSame
    for key, run in pairs(ns.db.runs or {}) do
        local cp = key ~= me and run.checkpoints and run.checkpoints[level]
        if cp and cp.overall then
            local same = run.classFile == myClass
            if not best or (same and not bestSame)
                or (same == bestSame and cp.overall > bestCp.overall) then
                best, bestCp, bestSame = run, cp, same
            end
        end
    end
    return best, bestCp
end

local function pillarName(key)
    local p = ns:GetPillar(key)
    return p and p.name or key
end

-- Short grade summary of a saved checkpoint: "B (Gear A, Gold C)"
local function summary(cp)
    local parts = {}
    for _, p in ipairs(ns.pillars) do
        local s = cp.scores and cp.scores[p.key]
        if s then parts[#parts + 1] = p.name .. " " .. ns.Grade(s) end
    end
    return ns.Grade(cp.overall) .. (#parts > 0 and (" (" .. table.concat(parts, ", ") .. ")") or "")
end

-- "Oldpally (Paladin) was C at 30 — you're ahead on Gear, behind on Gold"
-- `mine` = { overall, grades = {[key] = {score}} } (a checkpoint card)
function ns.GhostCompare(level, mine)
    local ghost, cp = ns.FindGhost(level)
    if not ghost or not mine or not mine.overall then return nil end
    local ahead, behind = {}, {}
    for _, p in ipairs(ns.pillars) do
        local a = mine.grades and mine.grades[p.key] and mine.grades[p.key].score
        local b = cp.scores and cp.scores[p.key]
        -- Pillars you turned off aren't something to be ahead or behind on
        if a and b and not ns.settings.disabledPillars[p.key] then
            if a - b >= 10 then ahead[#ahead + 1] = pillarName(p.key)
            elseif b - a >= 10 then behind[#behind + 1] = pillarName(p.key) end
        end
    end
    local text = string.format("%s (%s) was %s at %d", ghost.name, ghost.class, ns.Grade(cp.overall), level)
    local verdict
    if #ahead > 0 and #behind > 0 then
        verdict = "you're ahead on " .. table.concat(ahead, ", ") .. ", behind on " .. table.concat(behind, ", ")
    elseif #ahead > 0 then
        verdict = "you're better prepared on " .. table.concat(ahead, ", ")
    elseif #behind > 0 then
        verdict = "you're behind on " .. table.concat(behind, ", ")
    else
        verdict = "you're level with them"
    end
    return text .. " — " .. verdict, ghost
end

-- Add the ghost line to each new checkpoint card
ns:Listen("CHECKPOINT", function(card)
    local txt = ns.GhostCompare(card.level, card)
    if txt then card.ghost = txt end
end)

-- Lines for the Records tab: your next checkpoint, and how the ghost looked there
function ns.GhostLines()
    local level = UnitLevel("player")
    local nextCp
    for _, l in ipairs(ns.CHECKPOINTS) do if l >= level then nextCp = l; break end end
    local others = 0
    for k in pairs(ns.db.runs or {}) do if k ~= myKey() then others = others + 1 end end
    if others == 0 then
        return { { "Ghost run", "|cff888888your next character compares with this one|r" } }
    end
    if not nextCp then return { { "Ghost run", "|cff888888every checkpoint reached|r" } } end
    local ghost, cp = ns.FindGhost(nextCp)
    if not ghost then
        return { { "Ghost run", string.format("|cff888888no earlier run reached %d|r", nextCp) } }
    end
    return {
        { "Ghost run", ghost.name .. " (" .. ghost.class .. ")" },
        { "   at level " .. nextCp .. " they were", summary(cp) },
    }
end

---------------------------------------------------------------------------
-- /r60 share: one line to party, raid, guild or say
---------------------------------------------------------------------------
local SHORT = { gear = "Gear", spells = "Spells", professions = "Prof", gold = "Gold",
    quests = "Quests", dungeons = "Dungeons", legacy = "Legacy" }

-- `card` (optional): share that report card instead of today's grades
function ns.ShareText(card)
    ns:Refresh()
    local level = card and card.level or UnitLevel("player")
    local cp = card or ns.char.checkpoints[level]
    local src = cp and cp.grades or nil
    local parts = {}
    for _, p in ipairs(ns.pillars) do
        local g = src and src[p.key] or (ns.results[p.key] and ns.results[p.key].score and ns.results[p.key])
        -- A checkpoint saved before a pillar was turned off still has its grade; leave it out
        if g and g.grade and not ns.settings.disabledPillars[p.key] then parts[#parts + 1] = (SHORT[p.key] or p.name) .. " " .. g.grade end
    end
    local overall = ns.Grade(cp and cp.overall or ns.overall)
    local text = string.format("[Road to 60] Lv %d%s: %s (%s)", level, cp and " checkpoint" or "",
        overall, table.concat(parts, ", "))
    if cp and cp.ghost then text = text .. " — " .. cp.ghost end
    return text
end

local CHANNELS = { party = "PARTY", raid = "RAID", guild = "GUILD", say = "SAY", instance = "INSTANCE_CHAT" }

function ns:Share(arg, card)
    local text = ns.ShareText(card)
    local channel = CHANNELS[(arg or ""):lower()]
    if not channel then
        if IsInRaid and IsInRaid() then channel = "RAID"
        elseif IsInGroup and IsInGroup() then channel = "PARTY"
        elseif IsInGuild and IsInGuild() then channel = "GUILD" end
    end
    if not channel then
        ns:Print("Not in a group or guild. Preview: " .. text)
        ns:Print("Post it with /r60 share say")
        return
    end
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    send(text, channel)
end
