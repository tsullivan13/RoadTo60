-- Road to 60: weapon training (feeds the Spells pillar).
-- Which weapon types your class can learn but hasn't, who teaches them, and
-- whether a weapon you carry or wear needs one of them.
-- Each weapon proficiency is a spell whose ID equals its skill line ID, so
-- IsPlayerSpell(id) tells whether you know it.
local _, ns = ...

local SKILLS = {
    [196] = "One-Handed Axes", [197] = "Two-Handed Axes", [198] = "One-Handed Maces",
    [199] = "Two-Handed Maces", [200] = "Polearms", [201] = "One-Handed Swords",
    [202] = "Two-Handed Swords", [227] = "Staves", [264] = "Bows", [266] = "Guns",
    [1180] = "Daggers", [2567] = "Thrown", [5011] = "Crossbows", [15590] = "Fist Weapons",
}

-- Classic proficiencies by class, plus Forever's additions (Druid polearms, Rogue one-handed axes)
local CLASS_SKILLS = {
    WARRIOR = { 196, 197, 198, 199, 200, 201, 202, 227, 264, 266, 1180, 2567, 5011, 15590 },
    PALADIN = { 196, 197, 198, 199, 200, 201, 202 },
    HUNTER  = { 196, 197, 200, 201, 202, 227, 264, 266, 1180, 2567, 5011, 15590 },
    ROGUE   = { 196, 198, 201, 264, 266, 1180, 2567, 5011, 15590 },
    PRIEST  = { 198, 227, 1180 },
    SHAMAN  = { 196, 197, 198, 199, 227, 1180, 15590 },
    MAGE    = { 201, 227, 1180 },
    WARLOCK = { 201, 227, 1180 },
    DRUID   = { 198, 199, 200, 227, 1180, 15590 },
}

-- Weapon masters by faction and what each teaches
local MASTERS = {
    { npc = "Archibald",          place = "Undercity",     faction = "Horde",    skills = { 200, 201, 202, 1180, 5011 } },
    { npc = "Hanashi",            place = "Orgrimmar",     faction = "Horde",    skills = { 196, 197, 227, 264, 2567 } },
    { npc = "Sayoc",              place = "Orgrimmar",     faction = "Horde",    skills = { 196, 197, 264, 1180, 2567, 15590 } },
    { npc = "Ansekhwa",           place = "Thunder Bluff", faction = "Horde",    skills = { 198, 199, 227, 266 } },
    { npc = "Woo Ping",           place = "Stormwind",     faction = "Alliance", skills = { 200, 201, 202, 227, 1180, 5011 } },
    { npc = "Bixi Wobblebonk",    place = "Ironforge",     faction = "Alliance", skills = { 1180, 2567, 5011 } },
    { npc = "Buliwyf Stonehand",  place = "Ironforge",     faction = "Alliance", skills = { 196, 197, 198, 199, 266, 15590 } },
    { npc = "Ilyenia Moonfire",   place = "Darnassus",     faction = "Alliance", skills = { 227, 264, 1180, 2567, 15590 } },
}

local LEVEL = { [200] = 20 }       -- Polearms need level 20
local COST  = { [200] = 10000 }    -- and cost 1g; everything else 10s
local DEFAULT_COST = 1000

-- Weapon item subclass -> skill (item class 2 = weapon)
local SUBCLASS_SKILL = {
    [0] = 196, [1] = 197, [2] = 264, [3] = 266, [4] = 198, [5] = 199, [6] = 200,
    [7] = 201, [8] = 202, [10] = 227, [13] = 15590, [15] = 1180, [16] = 2567, [18] = 5011,
}

local function known(id)
    if IsPlayerSpell and IsPlayerSpell(id) then return true end
    return ns.IsSpellKnownByID and ns.IsSpellKnownByID(id) or false
end

local function mastersFor(id)
    local faction = UnitFactionGroup and UnitFactionGroup("player")
    local out = {}
    for _, m in ipairs(MASTERS) do
        if m.faction == faction then
            for _, s in ipairs(m.skills) do
                if s == id then out[#out + 1] = m.npc .. " (" .. m.place .. ")"; break end
            end
        end
    end
    return out
end

-- The skill a weapon item needs, or nil
local function skillForItem(link)
    local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local name, _, _, _, _, _, _, _, _, _, _, classID, subclassID = getInfo(link)
    if not name or classID ~= 2 then return nil end
    return SUBCLASS_SKILL[subclassID], name
end

-- Weapons you carry or wear: equipped weapon slots and bags
local function carriedWeapons()
    local out = {}
    for _, slot in ipairs({ 16, 17, 18 }) do
        local link = GetInventoryItemLink("player", slot)
        if link then out[#out + 1] = { link = link, equipped = true } end
    end
    if C_Container and C_Container.GetContainerNumSlots then
        for bag = 0, (NUM_BAG_SLOTS or 4) do
            for slot = 1, C_Container.GetContainerNumSlots(bag) do
                local info = C_Container.GetContainerItemInfo(bag, slot)
                if info and info.hyperlink then out[#out + 1] = { link = info.hyperlink } end
            end
        end
    end
    return out
end

-- Returns { known = {names}, learnable = {{id, name, level, cost, where}}, needed = {{...entry, item}} }
function ns.WeaponStatus()
    local _, class = UnitClass("player")
    local level = UnitLevel("player")
    local status = { known = {}, learnable = {}, needed = {} }
    local canLearn, entries = {}, {}
    for _, id in ipairs(CLASS_SKILLS[class] or {}) do
        canLearn[id] = true
        if known(id) then
            status.known[#status.known + 1] = SKILLS[id]
        else
            local e = { id = id, name = SKILLS[id], level = LEVEL[id] or 1, cost = COST[id] or DEFAULT_COST,
                where = mastersFor(id) }
            e.available = level >= e.level
            entries[id] = e
            status.learnable[#status.learnable + 1] = e
        end
    end
    table.sort(status.known)
    table.sort(status.learnable, function(a, b) return a.name < b.name end)

    -- A weapon you have but can't use yet (and could learn)
    local seen = {}
    for _, w in ipairs(carriedWeapons()) do
        local id, itemName = skillForItem(w.link)
        if id and canLearn[id] and entries[id] and not seen[id] then
            seen[id] = true
            status.needed[#status.needed + 1] = { entry = entries[id], item = itemName, link = w.link, equipped = w.equipped }
        end
    end
    return status
end

-- For the trainer scan and trainer locations: weapon skills aren't spell ranks,
-- and weapon masters aren't class trainers.
function ns.IsWeaponSkill(id) return SKILLS[id] ~= nil end
local masterNames = {}
for _, m in ipairs(MASTERS) do masterNames[m.npc] = true end
function ns.IsWeaponMaster(name) return name ~= nil and masterNames[name] == true end
