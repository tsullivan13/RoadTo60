-- Road to 60: Raid ready — the finale. From level 55 it shows first and turns the
-- other pillars into a checklist for WoW Forever's first raids.
--
-- Forever raids (open December 9, 2026, all level 60): Barrow Deeps (10 players),
-- Hyjal Summit (20) and Onyxia's Lair (40). Only Onyxia's Lair has an attunement:
-- you're attuned when the Drakefire Amulet is in your bags. No gear or item-level
-- requirement has been published.
local _, ns = ...

local SHOWN_FROM = 55
local RAIDS_OPEN = "20261209"   -- YYYYMMDD
local AMULET = "Drakefire Amulet"

local function hasAmulet()
    if not (C_Container and C_Container.GetContainerNumSlots) then return false end
    local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            local name = info and info.hyperlink and getInfo(info.hyperlink)
            if name == AMULET then return true end
        end
    end
    return false
end

-- Once seen it's remembered, in case it ends up in the bank
local function attuned()
    if hasAmulet() then ns.char.drakefireAmulet = true end
    return ns.char.drakefireAmulet == true
end

local Raid = {
    -- weight 0: it summarises other pillars, so it isn't counted twice in the overall grade
    key = "raid", name = "Raid ready", order = 99, displayOrder = 0, weight = 0,
    events = { "PLAYER_LEVEL_UP", "BAG_UPDATE_DELAYED" },
}

function Raid:Hidden() return UnitLevel("player") < SHOWN_FROM end

function Raid:Evaluate()
    local level = UnitLevel("player")
    local res = { breakdown = {}, details = {} }
    local total, weights, worst = 0, 0, nil

    local function item(label, score, weight, note, action)
        res.breakdown[#res.breakdown + 1] = { label = label, score = score, note = note }
        if score then
            total, weights = total + score * weight, weights + weight
            if action and score < 90 and (not worst or score * weight < worst.v) then
                worst = { v = score * weight, action = action }
            end
        end
    end
    local function from(key)
        local r = ns.results[key]
        return r and r.score, r and r.action
    end

    -- Your level isn't a lack of preparation, so it's information, not a grade
    res.breakdown[#res.breakdown + 1] = { label = "Level 60",
        note = level >= 60 and "reached" or string.format("%d to go", 60 - level) }

    local gear, gearAction = from("gear")
    item("Gear", gear, 1.5, gear and (gear >= 90 and "in good shape" or "some slots need work") or "not graded",
        gearAction)

    local spells, spellsAction = from("spells")
    item("Spells and talents", spells, 1, spells and (spells >= 90 and "trained and spent" or "ranks or points waiting") or "not graded",
        spellsAction)

    local sup, supAction = from("supplies")
    item("Supplies", sup, 0.75, sup and (sup >= 90 and "stocked" or "running low") or "not graded", supAction)

    local amulet = attuned()
    item("Onyxia's Lair attunement", amulet and 100 or 0, 0.75,
        amulet and "Drakefire Amulet in your bags" or "needs the Drakefire Amulet from the attunement quest chain",
        not amulet and "Work on the Onyxia attunement chain (Drakefire Amulet)." or nil)

    -- Information only
    local open = date("%Y%m%d") >= RAIDS_OPEN
    res.breakdown[#res.breakdown + 1] = { label = "Raids",
        note = (open and "open now: " or "open December 9: ")
            .. "Barrow Deeps (10), Hyjal Summit (20), Onyxia's Lair (40)" }
    for _, g in ipairs(ns.settings.goldGoals or {}) do
        if g.level == 60 and ns.GoalCost then
            local cost = ns.GoalCost(g)
            res.breakdown[#res.breakdown + 1] = { label = "Gold for level 60",
                note = string.format("%s of %s for %s (not needed to raid)", ns.FormatMoney(GetMoney()),
                    ns.FormatMoney(cost), ns.GoalLabel and ns.GoalLabel(g):lower() or "your goal") }
        end
    end

    res.score = weights > 0 and math.floor(total / weights) or nil
    res.action = worst and worst.action
    res.reason = level < 60 and string.format("Getting ready for the level 60 raids (%d levels to go).", 60 - level)
        or (res.score and res.score >= 90 and "Ready to raid." or "Almost raid ready.")
    return res
end

ns:RegisterPillar(Raid)
