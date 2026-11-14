-- Road to 60: Gear pillar — stale and empty slots vs. character level.
local _, ns = ...

-- core = counts when empty, from level `from` (head/shoulder drops are rare early);
-- jewelry = only after settings.jewelryLevel
ns.GEAR_SLOTS = {
    { id = 1,  name = "Head",      core = true, from = 20 },
    { id = 2,  name = "Neck",      jewelry = true },
    { id = 3,  name = "Shoulders", core = true, from = 20 },
    { id = 15, name = "Back",      core = true, from = 12 },
    { id = 5,  name = "Chest",     core = true, from = 5 },
    { id = 9,  name = "Wrists",    core = true, from = 15 },
    { id = 10, name = "Hands",     core = true, from = 15 },
    { id = 6,  name = "Waist",     core = true, from = 15 },
    { id = 7,  name = "Legs",      core = true, from = 5 },
    { id = 8,  name = "Feet",      core = true, from = 5 },
    { id = 11, name = "Ring 1",    jewelry = true },
    { id = 12, name = "Ring 2",    jewelry = true },
    { id = 13, name = "Trinket 1", jewelry = true },
    { id = 14, name = "Trinket 2", jewelry = true },
    { id = 16, name = "Main hand", core = true },
    { id = 17, name = "Off hand" },  -- may be empty with a two-hander
    { id = 18, name = "Ranged" },
}

local slotNameById = {}
for _, s in ipairs(ns.GEAR_SLOTS) do slotNameById[s.id] = s.name end

-- Returns { link, ilvl, req, effective } or nil if the slot is empty.
-- effective = the character level this item "belongs" to.
function ns.ReadSlot(slotId)
    local link = GetInventoryItemLink("player", slotId)
    if not link then return nil end
    local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local getDetailed = (C_Item and C_Item.GetDetailedItemLevelInfo) or GetDetailedItemLevelInfo
    local _, _, quality, ilvl, req = getInfo(link)
    if getDetailed then
        local detailed = getDetailed(link)
        if detailed and detailed > 0 then ilvl = detailed end
    end
    if not ilvl then
        return { link = link, pending = true }   -- item not cached yet
    end
    local effective = (req and req > 0) and req or math.max(1, ilvl - 5)
    return { link = link, ilvl = ilvl, req = req or 0, quality = quality, effective = effective }
end

-- Identity of an item, ignoring the parts of a link that change without the item
-- changing: the name (blank until cached), the quality color, and the link level
-- (Forever writes your current level into every link).
function ns.ItemKey(link)
    local s = link and link:match("|H(item:[^|]+)|h")
    if not s then return link end
    local fields = {}
    for f in (s .. ":"):gmatch("([^:]*):") do fields[#fields + 1] = f end
    fields[10] = ""  -- linkLevel (item:id:enchant:gem1-4:suffix:unique:linkLevel)
    return table.concat(fields, ":")
end

-- Item history: what was equipped, at which level, and when
local function recordSlot(slotId)
    local link = GetInventoryItemLink("player", slotId)
    local hist = ns.char.gearHistory[slotId]
    if not hist then
        hist = {}
        ns.char.gearHistory[slotId] = hist
    end
    local last = hist[#hist]
    if last and link and ns.ItemKey(last.link) == ns.ItemKey(link) then
        last.link = link  -- same item; keep the newest (named) link
    elseif link then
        if last then last.replacedAt = UnitLevel("player") end
        hist[#hist + 1] = { link = link, level = UnitLevel("player"), time = time() }
        -- keep history bounded
        if #hist > 20 then table.remove(hist, 1) end
    end
end

ns:On("PLAYER_EQUIPMENT_CHANGED", function(_, slotId)
    if ns.char and slotNameById[slotId] then recordSlot(slotId) end
end)

ns:Listen("LOGIN", function()
    -- Clean up duplicates saved by v0.1.0 (same item recorded twice: unnamed, then named)
    for _, hist in pairs(ns.char.gearHistory) do
        for i = #hist, 2, -1 do
            if ns.ItemKey(hist[i].link) == ns.ItemKey(hist[i - 1].link) then
                hist[i - 1].link = hist[i].link
                hist[i - 1].replacedAt = hist[i].replacedAt
                table.remove(hist, i)
            end
        end
    end
    for _, s in ipairs(ns.GEAR_SLOTS) do recordSlot(s.id) end
end)

local Gear = {
    key = "gear", name = "Gear", order = 1, weight = 1.5,
    events = { "PLAYER_EQUIPMENT_CHANGED", "PLAYER_LEVEL_UP", "GET_ITEM_INFO_RECEIVED", "BAG_UPDATE_DELAYED" },
}

-- How much each slot matters while leveling. Your weapon decides how fast you kill
-- things; big armor pieces carry the most stats; small pieces and jewelry less.
-- Hunters fight with their ranged weapon, so it swaps places with the main hand.
local IMPACT = {
    ["Main hand"] = 2, Chest = 1, Legs = 1, Head = 1, Shoulders = 1,
    Back = 0.6, Wrists = 0.6, Hands = 0.6, Waist = 0.6, Feet = 0.6,
    ["Off hand"] = 0.5, Ranged = 0.5,
    Neck = 0.4, ["Ring 1"] = 0.4, ["Ring 2"] = 0.4, ["Trinket 1"] = 0.4, ["Trinket 2"] = 0.4,
}
-- A better quality item stays useful for longer: counted as this many levels newer
local QUALITY_LEVELS = { [0] = -3, [1] = 0, [2] = 3, [3] = 6, [4] = 9 }
-- The grade loses (sum of impact x missing points) / SPREAD. One badly stale chest
-- costs ~15 (a B), a stale weapon ~30 (a C), half your gear stale is an F.
local SPREAD = 4.5

local function impact(s, class)
    if class == "HUNTER" then
        if s.name == "Ranged" then return 2 elseif s.name == "Main hand" then return 0.6 end
    end
    return IMPACT[s.name] or 0.5
end

-- 100 while within half the stale threshold, 75 at the threshold, then -6 a level
local function slotScore(age, threshold)
    local half = threshold / 2
    if age <= half then return 100 end
    if age <= threshold then return 100 - (age - half) / half * 25 end
    return math.max(10, 70 - (age - threshold) * 6)
end
ns.GearSlotScore = slotScore

function Gear:Evaluate()
    local level = UnitLevel("player")
    local threshold = ns.settings.staleLevels
    local _, class = UnitClass("player")
    local issues, breakdown, missing = {}, {}, 0
    local pending, staleCount = false, 0

    for _, s in ipairs(ns.GEAR_SLOTS) do
        local info = ns.ReadSlot(s.id)
        local w = impact(s, class)
        if not info then
            local from = s.core and (s.from or 1) or (s.jewelry and ns.settings.jewelryLevel) or nil
            if class == "HUNTER" and s.name == "Ranged" then from = 1 end
            if from and level >= from then
                missing = missing + w * 100
                breakdown[#breakdown + 1] = { label = s.name, score = 0, note = "Empty" }
                issues[#issues + 1] = { slot = s.name, empty = true, cost = w * 100, penalty = w * 100 / SPREAD }
            else
                breakdown[#breakdown + 1] = { label = s.name, note = from
                    and string.format("Empty (counts from level %d)", from) or "Empty (optional)" }
            end
        elseif info.pending then
            pending = true
        else
            local age = level - info.effective - (QUALITY_LEVELS[info.quality or 1] or 0)
            local sc = slotScore(age, threshold)
            missing = missing + w * (100 - sc)
            local realAge = level - info.effective
            breakdown[#breakdown + 1] = { label = s.name, score = math.floor(sc + 0.5),
                note = string.format("%s — %s", info.link,
                    realAge <= 0 and "current" or (realAge .. " level" .. (realAge == 1 and "" or "s") .. " old")) }
            if age > threshold then
                staleCount = staleCount + 1
                issues[#issues + 1] = { slot = s.name, age = realAge, link = info.link,
                    cost = w * (100 - sc), penalty = w * (100 - sc) / SPREAD }
            end
        end
    end

    local score = math.max(0, math.min(100, math.floor(100 - missing / SPREAD + 0.5)))
    table.sort(issues, function(a, b) return a.cost > b.cost end)  -- biggest effect first

    local res = { score = score, details = {}, staleCount = staleCount, breakdown = breakdown }
    res.issues = issues  -- biggest effect first; each has slot, penalty, and empty or age
    res.slotsNeeding = {}
    for _, i in ipairs(issues) do res.slotsNeeding[#res.slotsNeeding + 1] = i.slot:lower() end
    for _, i in ipairs(issues) do
        res.details[#res.details + 1] = i.empty
            and string.format("%s: empty", i.slot)
            or string.format("%s: %d levels old %s", i.slot, i.age, i.link)
    end

    if #issues == 0 then
        res.reason = pending and "Loading item info..." or "Every slot is within " .. threshold .. " levels."
    else
        local worst = issues[1]
        if worst.empty then
            res.action = string.format("Fill your empty %s slot.", worst.slot:lower())
        else
            -- "Your feet are", "Your chest is"
            local plural = ({ Shoulders = true, Wrists = true, Hands = true, Legs = true, Feet = true })[worst.slot]
            res.action = string.format("Your %s %s %d levels old.", worst.slot:lower(), plural and "are" or "is", worst.age)
        end
        res.reason = string.format("%d slot%s need%s attention.", #issues, #issues == 1 and "" or "s", #issues == 1 and "s" or "")
    end
    return res
end

---------------------------------------------------------------------------
-- Bags: empty bag slots and bags well below the size your level can easily get
---------------------------------------------------------------------------
local BAGS_FROM = 8
local function expectedBagSize(level)
    if level < 20 then return 6 elseif level < 30 then return 8
    elseif level < 40 then return 10 elseif level < 50 then return 12 end
    return 14
end

-- { {bag, size}, ... } for the four bag slots (size 0 = empty slot)
function ns.BagStatus()
    if not (C_Container and C_Container.GetContainerNumSlots) then return nil end
    local out = {}
    for bag = 1, (NUM_BAG_SLOTS or 4) do
        out[#out + 1] = { bag = bag, size = C_Container.GetContainerNumSlots(bag) or 0 }
    end
    return out
end

local evaluateSlots = Gear.Evaluate
function Gear:Evaluate()
    local res = evaluateSlots(self)
    local level = UnitLevel("player")
    local bags = ns.BagStatus()
    if not bags or level < BAGS_FROM then return res end

    local want = expectedBagSize(level)
    local penalty, empty, small, smallest = 0, 0, 0, nil
    for _, b in ipairs(bags) do
        local row = { label = "Bag " .. b.bag }
        if b.size == 0 then
            empty = empty + 1
            penalty = penalty + 6
            row.score, row.note = 0, "empty bag slot — any bag helps"
        elseif want - b.size >= 2 then
            small = small + 1
            penalty = penalty + 3
            row.score, row.note = 60, string.format("%d slots · %d+ is easy to find at level %d", b.size, want, level)
        else
            row.score, row.note = 100, b.size .. " slots"
        end
        if b.size > 0 and (not smallest or b.size < smallest) then smallest = b.size end
        res.breakdown[#res.breakdown + 1] = row
    end
    if penalty > 0 then
        res.score = math.max(0, (res.score or 100) - math.min(20, penalty))
        res.bagAction = empty > 0
            and string.format("Fill your empty bag slot%s.", empty == 1 and "" or "s")
            or string.format("Get a bigger bag (smallest is %d slots; %d+ is easy now).", smallest or 0, want)
        if not res.action then res.action = res.bagAction end
    end
    return res
end

ns:RegisterPillar(Gear)
