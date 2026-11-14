-- Road to 60: Supplies pillar — what's in your bags before you head out.
-- Food, drink (if you use mana), healing potions, bandages (if you know First Aid),
-- class supplies (Hunter ammo, Warlock soul shards, Rogue poisons), repairs, and
-- whether your hearthstone is still set somewhere you've left behind.
-- Items are recognised by the game's item class and use effect, not by item lists.
local _, ns = ...

local CONSUMABLE, PROJECTILE = 0, 6
local SUB_POTION, SUB_FOOD, SUB_BANDAGE = 1, 5, 7
local SOUL_SHARD = 6265
local HEARTH_STALE = 5   -- levels since you were last in your hearthstone's zone

local function itemSpellName(link)
    local f = (C_Item and C_Item.GetItemSpell) or GetItemSpell
    if not f then return nil end
    local ok, name = pcall(f, link)
    return ok and name or nil
end

-- Counts of each kind of supply in your bags (quiver included)
function ns.ScanSupplies()
    local c = { food = 0, drink = 0, healPotion = 0, manaPotion = 0, bandage = 0,
        ammo = 0, shards = 0, poison = 0, pending = false }
    if not (C_Container and C_Container.GetContainerNumSlots) then return c end
    local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.hyperlink then
                local n = info.stackCount or 1
                local name, _, _, _, _, _, _, _, _, _, _, classID, subID = getInfo(info.hyperlink)
                if not name then
                    c.pending = true
                elseif info.itemID == SOUL_SHARD then
                    c.shards = c.shards + n
                elseif classID == PROJECTILE then
                    c.ammo = c.ammo + n
                elseif classID == CONSUMABLE then
                    local spell = (itemSpellName(info.hyperlink) or ""):lower()
                    local lname = name:lower()
                    local L = ns.L  -- words to look for (Locale.lua)
                    if subID == SUB_FOOD then
                        if spell:find(L.drink, 1, true) then c.drink = c.drink + n
                        elseif spell:find(L.refreshment, 1, true) then c.food = c.food + n; c.drink = c.drink + n
                        else c.food = c.food + n end
                    elseif subID == SUB_BANDAGE then
                        c.bandage = c.bandage + n
                    elseif subID == SUB_POTION then
                        if lname:find(L.healing, 1, true) then c.healPotion = c.healPotion + n
                        elseif lname:find(L.mana, 1, true) then c.manaPotion = c.manaPotion + n end
                    elseif lname:find(L.poison, 1, true) then
                        c.poison = c.poison + n
                    end
                end
            end
        end
    end
    return c
end

local function lowestDurability()
    if not GetInventoryItemDurability then return 1, nil end
    local low, slotName = 1, nil
    for _, s in ipairs(ns.GEAR_SLOTS or {}) do
        local cur, max = GetInventoryItemDurability(s.id)
        if cur and max and max > 0 and cur / max < low then low, slotName = cur / max, s.name end
    end
    return low, slotName
end

---------------------------------------------------------------------------
-- Hearthstone: remember which zone each town is in and when you were last there
---------------------------------------------------------------------------
local function rememberZone()
    if not ns.char then return end
    ns.char.zoneSeen = ns.char.zoneSeen or {}
    ns.char.townZone = ns.char.townZone or {}
    local zone = GetZoneText and GetZoneText()
    if not zone or zone == "" then return end
    ns.char.zoneSeen[zone] = UnitLevel("player")
    local sub = GetSubZoneText and GetSubZoneText()
    if sub and sub ~= "" then ns.char.townZone[sub] = zone end
end
ns:On("ZONE_CHANGED_NEW_AREA", rememberZone)
ns:On("ZONE_CHANGED", rememberZone)
ns:On("ZONE_CHANGED_INDOORS", rememberZone)
ns:On("PLAYER_LEVEL_UP", function() C_Timer.After(0.5, rememberZone) end)
ns:Listen("LOGIN", rememberZone)

-- Where your hearthstone is set and how long since you were in that zone
function ns.HearthStatus()
    local bind = GetBindLocation and GetBindLocation()
    if not bind or bind == "" then return nil end
    local zone = (ns.char.townZone or {})[bind] or bind
    local seen = (ns.char.zoneSeen or {})[zone]
    return { bind = bind, zone = zone, lastLevel = seen, levelsAgo = seen and (UnitLevel("player") - seen) or nil }
end

---------------------------------------------------------------------------
-- Pillar
---------------------------------------------------------------------------
local Supplies = {
    key = "supplies", name = "Supplies", order = 4, weight = 0.75,
    events = { "BAG_UPDATE_DELAYED", "UPDATE_INVENTORY_DURABILITY", "PLAYER_LEVEL_UP", "ZONE_CHANGED_NEW_AREA" },
}

function Supplies:Evaluate()
    local level = UnitLevel("player")
    local _, class = UnitClass("player")
    local s = ns.ScanSupplies()
    local res = { breakdown = {}, details = {} }
    local score, worst = 100, nil

    -- One graded row; `need` is how many count as stocked, `cost` the points when you have none
    local function row(label, have, need, cost, action, note)
        local sc
        if have >= need then sc = 100
        elseif have == 0 then sc = math.max(0, 100 - cost * 3)
        else sc = 75 end
        local lost = have >= need and 0 or (have == 0 and cost or math.floor(cost / 2))
        score = score - lost
        res.breakdown[#res.breakdown + 1] = { label = label, score = sc,
            note = note or string.format("%d in your bags%s", have, have < need and string.format(" · %d+ is comfortable", need) or "") }
        if lost > 0 and (not worst or lost > worst.lost) then worst = { lost = lost, action = action } end
    end

    if level >= 5 then
        row("Food", s.food, 10, 20, s.food == 0 and "Buy food." or string.format("Stock up on food (you have %d).", s.food))
        if UnitPowerType and UnitPowerType("player") == 0 then
            row("Drink", s.drink, 10, 20, s.drink == 0 and "Buy water." or string.format("Stock up on water (you have %d).", s.drink))
        end
    end
    if level >= 10 then
        row("Healing potions", s.healPotion, 3, 12, "Get a few healing potions.")
    end
    local knowsFirstAid = false
    for _, p in ipairs(ns.ReadProfessions and ns.ReadProfessions() or {}) do
        if p.name == "First Aid" then knowsFirstAid = true end
    end
    if knowsFirstAid then
        row("Bandages", s.bandage, 5, 8, "Make some bandages.")
    end

    -- Class supplies
    if class == "HUNTER" and level >= 10 then
        row("Ammo", s.ammo, 400, 25, string.format("Buy ammo (you have %d).", s.ammo))
    elseif class == "WARLOCK" and level >= 10 then
        row("Soul Shards", s.shards, 3, 20, "Collect soul shards (Drain Soul as a target dies).")
    elseif class == "ROGUE" and level >= 20 then
        row("Poisons", s.poison, 1, 15, "Buy or make poisons.")
    end

    -- Repairs
    local low, slotName = lowestDurability()
    if low < 0.5 then
        local lost = low < 0.2 and 30 or 12
        score = score - lost
        res.breakdown[#res.breakdown + 1] = { label = "Repairs", score = low < 0.2 and 20 or 60,
            note = string.format("%s at %d%%", slotName or "an item", math.floor(low * 100)) }
        if not worst or lost > worst.lost then
            worst = { lost = lost, action = string.format("Repair your gear (%s at %d%%).", (slotName or "an item"):lower(), math.floor(low * 100)) }
        end
    else
        res.breakdown[#res.breakdown + 1] = { label = "Repairs", score = 100,
            note = string.format("lowest item at %d%%", math.floor(low * 100)) }
    end

    -- Hearthstone
    local h = ns.HearthStatus()
    if h then
        if h.levelsAgo and h.levelsAgo >= HEARTH_STALE then
            score = score - 6
            res.breakdown[#res.breakdown + 1] = { label = "Hearthstone", score = 60,
                note = string.format("set to %s · you were last in %s at level %d", h.bind, h.zone, h.lastLevel) }
            res.hearthAction = string.format("Set your hearthstone at an inn near your quests (it's still %s).", h.bind)
            if not worst or 6 > worst.lost then worst = { lost = 6, action = res.hearthAction } end
        else
            res.breakdown[#res.breakdown + 1] = { label = "Hearthstone", score = 100, note = "set to " .. h.bind }
        end
    end

    if #res.breakdown == 0 then
        res.reason = "Nothing to stock yet."
        return res
    end
    res.score = math.max(0, math.min(100, score))
    res.action = worst and worst.action
    res.reason = s.pending and "Reading your bags..." or (worst and "Something's running low." or "Stocked up.")
    res.supplies = s
    return res
end

ns:RegisterPillar(Supplies)
