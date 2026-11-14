-- Road to 60: Gold pillar — savings vs. the next goal.
--
-- WoW Forever mount costs (Nov 2026): Apprentice riding at 40 is 100g including your
-- first mount; Journeyman riding at 60 is 1000g plus 200g for an epic mount. Honored
-- with your home faction takes 10% off both. Paladins and Warlocks get class mounts
-- from quests, so their real costs are lower; their goals can be edited in settings.
local _, ns = ...

local GRADED_FROM = 20   -- early levels go to training and gear, so gold isn't graded yet
local SAVING_FROM = 10   -- the savings curve assumes almost nothing saved before this
local SOFTEN = 0.6       -- score = 100 * (have / expected) ^ SOFTEN: half pace is a C, not a D

local Gold = {
    key = "gold", name = "Gold", order = 5, weight = 1,
    events = { "PLAYER_MONEY", "PLAYER_LEVEL_UP", "UPDATE_FACTION" },
}

---------------------------------------------------------------------------
-- Honored discount on riding and mounts
---------------------------------------------------------------------------
-- Home faction by race (race file token from UnitRace)
local HOME_FACTION = {
    Human = 72, Dwarf = 47, NightElf = 69, Gnome = 54,
    Orc = 76, Scourge = 68, Tauren = 81, Troll = 530,
}
local HONORED = 6

local function standing(factionID)
    if C_Reputation and C_Reputation.GetFactionDataByID then
        local ok, data = pcall(C_Reputation.GetFactionDataByID, factionID)
        if ok and type(data) == "table" then return data.reaction, data.name end
    end
    if GetFactionInfoByID then
        local ok, name, _, standingID = pcall(GetFactionInfoByID, factionID)
        if ok then return standingID, name end
    end
end

-- 0.9 at Honored or better with your home faction, else 1; plus the faction's name
function ns.MountDiscount()
    local _, race = UnitRace("player")
    local id = HOME_FACTION[race or ""]
    if not id then return 1 end
    local s, name = standing(id)
    if s and s >= HONORED then return 0.9, name end
    return 1, name
end

-- Riding goal prices by class (copper). `disc` is the part the Honored discount
-- applies to (riding training and vendor mounts, not quest fees).
-- Paladin: Warhorse comes from a class quest, Apprentice riding is still 100g;
-- the Charger quest chain costs ~350g in NPC fees on top of Journeyman riding.
local G = 10000
local PRICES = {
    riding40 = {
        default = { cost = 100 * G, disc = 100 * G, label = "Apprentice riding + mount" },
        PALADIN = { cost = 100 * G, disc = 100 * G, label = "Apprentice riding (Warhorse from class quest)" },
    },
    riding60 = {
        default = { cost = 1200 * G, disc = 1200 * G, label = "Journeyman riding + epic mount" },
        PALADIN = { cost = 1350 * G, disc = 1000 * G, label = "Journeyman riding + Charger quest chain" },
    },
}

-- A goal's price before any discount, the discountable part, and its label.
-- Riding goals follow your class unless you set the price yourself (g.custom).
local function goalPrice(g)
    local p = g.id and PRICES[g.id]
    if p and not g.custom then
        local _, class = UnitClass("player")
        local c = p[class] or p.default
        return c.cost, c.disc, g.customLabel and g.label or c.label
    end
    return g.cost, g.id and g.cost or 0, g.label
end

function ns.GoalBaseCost(g) return (goalPrice(g)) end
function ns.GoalLabel(g) return select(3, goalPrice(g)) end

-- What a goal really costs you, after the Honored discount on its riding part
function ns.GoalCost(g)
    local cost, disc = goalPrice(g)
    return math.floor(cost - disc * (1 - ns.MountDiscount()))
end

---------------------------------------------------------------------------
-- Goals and income
---------------------------------------------------------------------------
-- Next goal = the lowest-level goal not yet reached. A goal counts as reached the
-- first time you hold its cost, so spending the money on it doesn't bring it back.
function ns.NextGoldGoal()
    local money = GetMoney()
    local goals = ns.settings.goldGoals
    local reached = ns.char.goalsReached
    table.sort(goals, function(a, b) return a.level < b.level end)
    for _, g in ipairs(goals) do
        if money >= ns.GoalCost(g) then reached[g.level] = true end
        if not reached[g.level] then return g end
    end
    return nil
end

-- Average copper gained per level, from recorded dings.
function ns.GoldPerLevel()
    local level = UnitLevel("player")
    local firstLevel, firstMoney
    for lvl, money in pairs(ns.char.moneyByLevel) do
        if lvl < level and (not firstLevel or lvl < firstLevel) then
            firstLevel, firstMoney = lvl, money
        end
    end
    if firstLevel then
        return (GetMoney() - firstMoney) / (level - firstLevel)
    end
    -- No history yet (first session): assume money was earned evenly since level 1.
    return GetMoney() / math.max(1, level - 1)
end

local function soften(ratio)
    return math.max(0, math.min(100, math.floor(100 * math.min(1, ratio) ^ SOFTEN)))
end

-- Expected savings toward a goal at a level: a curve from the start level
-- (SAVING_FROM, or the level of the goal you last reached) to the goal's level.
function ns.ExpectedSavings(goal, level)
    local start = SAVING_FROM
    for _, g in ipairs(ns.settings.goldGoals) do
        if g.level < goal.level and g.level > start and ns.char.goalsReached[g.level] then start = g.level end
    end
    if level <= start then return 0 end
    local t = math.min(1, (level - start) / (goal.level - start))
    return ns.GoalCost(goal) * t ^ (ns.settings.goldCurve or 2.5)
end

---------------------------------------------------------------------------
-- Pillar
---------------------------------------------------------------------------
function Gold:Evaluate()
    local money = GetMoney()
    local level = UnitLevel("player")
    local goal = ns.NextGoldGoal()
    local res = { details = {} }

    res.details[#res.details + 1] = "Per level: " .. ns.FormatMoney(ns.GoldPerLevel())

    if not goal then
        res.score, res.progress = 100, 1
        res.reason = "Every gold goal is covered."
        return res
    end

    local cost = ns.GoalCost(goal)
    res.goal, res.cost = goal, cost
    res.progress = math.min(1, money / cost)
    res.reason = string.format("%s by %d: %s of %s", ns.GoalLabel(goal), goal.level, ns.FormatMoney(money), ns.FormatMoney(cost))

    if level >= goal.level then
        -- At the goal level and short
        res.score = soften(money / cost)
        res.action = string.format("%s short for %s.", ns.FormatMoney(cost - money), ns.GoalLabel(goal):lower())
        return res
    end

    local expected = ns.ExpectedSavings(goal, level)
    res.expected = expected
    if level < GRADED_FROM then
        res.reason = res.reason .. string.format(" (graded from level %d)", GRADED_FROM)
        return res
    end
    local ratio = expected > 0 and money / expected or 1
    res.score = soften(ratio)
    if ratio < 0.9 then
        res.action = string.format("On pace for %s you'd have ~%s by now; you have %s.",
            ns.GoalLabel(goal):lower(), ns.FormatMoney(expected), ns.FormatMoney(money))
    end
    return res
end

-- Breakdown: every goal (reached, current, later), the discount, plus income figures
local evaluateGrade = Gold.Evaluate
function Gold:Evaluate()
    local res = evaluateGrade(self)
    local money = GetMoney()
    local level = UnitLevel("player")
    res.breakdown = {}
    for _, g in ipairs(ns.settings.goldGoals) do
        local cost = ns.GoalCost(g)
        local row = { label = string.format("%s (level %d)", ns.GoalLabel(g), g.level) }
        if ns.char.goalsReached[g.level] then
            row.score, row.note = 100, "reached · " .. ns.FormatMoney(cost)
        elseif res.goal == g then
            row.score = res.score
            row.note = string.format("%s of %s%s%s", ns.FormatMoney(money), ns.FormatMoney(cost),
                (res.expected and res.expected > 0) and (" · ~" .. ns.FormatMoney(res.expected) .. " expected by now") or "",
                level < GRADED_FROM and string.format(" · graded from %d", GRADED_FROM) or "")
        else
            row.note = "after the current goal · " .. ns.FormatMoney(cost)
        end
        res.breakdown[#res.breakdown + 1] = row
    end

    local discount, faction = ns.MountDiscount()
    if faction then
        res.breakdown[#res.breakdown + 1] = { label = "Honored discount (" .. faction .. ")",
            note = discount < 1 and "10% off riding and mounts — applied" or "not yet Honored — 10% off riding and mounts when you are" }
    end
    local _, class = UnitClass("player")
    if class == "PALADIN" then
        res.breakdown[#res.breakdown + 1] = { label = "Class mounts",
            note = "Warhorse: free class quest at 40 · Charger: 12-quest chain, ~350g fees + materials" }
    elseif class == "WARLOCK" then
        res.breakdown[#res.breakdown + 1] = { label = "Class mount",
            note = "yours comes from a class quest, so costs may differ — edit goals in /r60 settings" }
    end
    res.breakdown[#res.breakdown + 1] = { label = "Gold per level", note = ns.FormatMoney(ns.GoldPerLevel()) }
    return res
end

ns:RegisterPillar(Gold)
