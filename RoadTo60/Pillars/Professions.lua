-- Road to 60: Professions pillar — skill vs. the cap for your tier, and tier unlocks.
-- Uses GetProfessions/GetProfessionInfo (Forever has no GetSkillLineInfo).
local _, ns = ...

local TIER_NAMES = { [75] = "Apprentice", [150] = "Journeyman", [225] = "Expert", [300] = "Artisan" }

-- Secondary professions by skill line (names as a fallback)
local SECONDARY_LINES = { [129] = true, [185] = true, [356] = true, [794] = true }  -- First Aid, Cooking, Fishing, Archaeology
local SECONDARY_NAMES = { ["First Aid"] = true, Cooking = true, Fishing = true, Archaeology = true }

-- Returns a list of { name, skill, max, skillLine, primary }.
-- Reads every position GetProfessions returns (as LOF does on Forever) and decides
-- primary/secondary by skill line: Forever doesn't put First Aid in the 6th position.
function ns.ReadProfessions()
    local list = {}
    if not GetProfessions or not GetProfessionInfo then return list end
    local indexes = { GetProfessions() }
    local seen, hasFirstAid = {}, false
    for i = 1, math.max(6, #indexes) do
        local index = indexes[i]
        if index and not seen[index] then
            seen[index] = true
            local name, _, skill, max, _, _, skillLine = GetProfessionInfo(index)
            if name then
                local secondary = SECONDARY_LINES[skillLine or 0] or SECONDARY_NAMES[name] or false
                list[#list + 1] = { name = name, skill = skill or 0, max = max or 0, skillLine = skillLine,
                    primary = not secondary, position = i }
                if skillLine == 129 or name == "First Aid" then hasFirstAid = true end
            end
        end
    end
    -- Forever can leave First Aid out of GetProfessions; fall back to the spellbook
    if not hasFirstAid and ns.KnowsFirstAid() then
        list[#list + 1] = { name = "First Aid", skill = 0, max = 0, skillLine = 129, primary = false,
            fromSpellbook = true }
    end
    return list
end

-- First Aid ranks (Apprentice, Journeyman, Expert, Artisan), or the spell by name
local FIRST_AID_SPELLS = { 3273, 3274, 7924, 10846 }
function ns.KnowsFirstAid()
    for _, id in ipairs(FIRST_AID_SPELLS) do
        if IsPlayerSpell and IsPlayerSpell(id) then return true end
        if ns.IsSpellKnownByID and ns.IsSpellKnownByID(id) then return true end
    end
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, "First Aid")
        if ok and type(info) == "table" and info.spellID then
            return not IsPlayerSpell or IsPlayerSpell(info.spellID)
        end
    end
    return false
end

-- The next tier you could train right now, or nil
local function trainableTier(p, level)
    local nextCap = p.max + 75
    local req = ns.settings.profTiers[nextCap]
    if not req then return nil end
    if level >= req.level and p.skill >= req.skill then
        return TIER_NAMES[nextCap] or ("cap " .. nextCap), req
    end
end

-- Highest cap your level allows (Apprentice is always available)
local function capForLevel(level)
    local cap = 75
    for c, req in pairs(ns.settings.profTiers) do
        if level >= req.level and c > cap then cap = c end
    end
    return cap
end

-- History: skill at each level and the level each tier was trained
local function record()
    local level = UnitLevel("player")
    ns.char.profHistory = ns.char.profHistory or {}
    ns.char.profTiers = ns.char.profTiers or {}
    for _, p in ipairs(ns.ReadProfessions()) do
        local h = ns.char.profHistory[p.name] or {}
        ns.char.profHistory[p.name] = h
        if (h[level] or -1) < p.skill then h[level] = p.skill end
        local t = ns.char.profTiers[p.name] or {}
        ns.char.profTiers[p.name] = t
        if p.max > 0 and not t[p.max] then t[p.max] = level end
    end
end
ns:On("SKILL_LINES_CHANGED", function() if ns.ready then record() end end)
ns:Listen("LOGIN", record)
ns:Listen("LEVEL_UP", record)

local Professions = {
    key = "professions", name = "Professions", order = 7, weight = 0.5,
    events = { "SKILL_LINES_CHANGED", "PLAYER_LEVEL_UP" },
}

---------------------------------------------------------------------------
-- Advice: what to pick when a primary profession slot is empty
---------------------------------------------------------------------------
local GATHERING = { Mining = true, Herbalism = true, Skinning = true }

-- Crafting partner for a gathering profession (and the reverse), best first per class
local PARTNERS = {
    Mining = function(class)
        if class == "WARRIOR" or class == "PALADIN" then
            return "Blacksmithing", "it turns your ore into plate armor and weapons you can wear"
        end
        return "Engineering", "it turns your ore into gadgets, scopes and goggles"
    end,
    Herbalism = function() return "Alchemy", "it turns your herbs into potions and elixirs" end,
    Skinning = function(class)
        if class == "MAGE" or class == "PRIEST" or class == "WARLOCK" then
            return "Leatherworking", "it turns your leather into armor kits and bags"
        end
        return "Leatherworking", "it turns your leather into armor you can wear"
    end,
    Blacksmithing = function() return "Mining", "it gathers the ore Blacksmithing needs" end,
    Engineering = function() return "Mining", "it gathers the ore Engineering needs" end,
    Alchemy = function() return "Herbalism", "it gathers the herbs Alchemy needs" end,
    Leatherworking = function() return "Skinning", "it gathers the leather Leatherworking needs" end,
    Tailoring = function() return "Enchanting", "it disenchants the cloth gear you make" end,
    Enchanting = function() return "Tailoring", "it makes cloth gear to wear or disenchant" end,
}

-- A full pair for a character with no professions, by class
local CLASS_PAIRS = {
    WARRIOR = { "Mining", "Blacksmithing", "plate armor and weapons for yourself" },
    PALADIN = { "Mining", "Blacksmithing", "plate armor and weapons for yourself" },
    HUNTER  = { "Skinning", "Leatherworking", "leather and mail armor; you skin what you kill" },
    ROGUE   = { "Skinning", "Leatherworking", "leather armor; you skin what you kill" },
    DRUID   = { "Herbalism", "Alchemy", "potions and elixirs; herbs show while you travel" },
    SHAMAN  = { "Skinning", "Leatherworking", "leather and mail armor; you skin what you kill" },
    MAGE    = { "Tailoring", "Enchanting", "cloth gear for yourself, then enchant it" },
    PRIEST  = { "Tailoring", "Enchanting", "cloth gear for yourself, then enchant it" },
    WARLOCK = { "Tailoring", "Enchanting", "cloth gear for yourself, then enchant it" },
}

-- Another gathering profession: the most gold while leveling
local function otherGathering(have)
    local out = {}
    for _, g in ipairs({ "Herbalism", "Mining", "Skinning" }) do
        if g ~= have then out[#out + 1] = g end
    end
    return table.concat(out, " or ")
end

function ns.ProfessionAdvice(primaries)
    local _, class = UnitClass("player")
    if #primaries == 0 then
        local pair = CLASS_PAIRS[class] or { "Herbalism", "Mining", "two gathering professions make the most gold" }
        return {
            pick = pair[1] .. " + " .. pair[2],
            why = pair[3],
            alt = "For gold while leveling: two gathering professions, such as Herbalism + Mining.",
        }
    end
    if #primaries == 1 then
        local first = primaries[1].name
        local partner = PARTNERS[first]
        if partner then
            local pick, why = partner(class)
            return {
                pick = pick, why = why .. " (pairs with " .. first .. ")",
                alt = GATHERING[first] and ("For gold instead: " .. otherGathering(first) .. ".") or nil,
            }
        end
        return { pick = "a gathering profession", why = "Herbalism, Mining or Skinning sell well while leveling" }
    end
end

function Professions:Evaluate()
    local level = UnitLevel("player")
    local profs = ns.ReadProfessions()
    local res = { details = {}, breakdown = {} }

    local total, weights, worst = 0, 0, nil
    for _, p in ipairs(profs) do
        -- Expected skill: about 5 points per level, capped by what your level can unlock
        -- (Secondary professions are optional: only their tier unlocks are graded.)
        local expected = math.min(capForLevel(level), level * 5)
        local gap = p.primary and (expected - p.skill) or 0
        local score = 100 - math.max(0, gap - 15) * 1.5
        local action
        local tier = trainableTier(p, level)
        if tier and p.skill >= p.max - 10 then
            score = math.min(score, 50)
            action = string.format("%s %d/%d — train %s.", p.name, p.skill, p.max, tier)
        elseif gap > 15 then
            action = string.format("%s %d/%d — about %d behind for level %d.", p.name, p.skill, p.max, gap, level)
        end
        score = math.max(0, math.min(100, score))
        -- Secondary professions only count when a tier is waiting; otherwise they'd
        -- average a behind primary profession up to a B
        local w = p.primary and 1 or ((tier and p.skill >= p.max - 10) and 0.5 or 0)
        total, weights = total + score * w, weights + w
        if action and (not worst or score < worst.score) then worst = { score = score, action = action } end
        res.details[#res.details + 1] = string.format("%s: %d/%d%s", p.name, p.skill, p.max,
            tier and (" |cffffd100(" .. tier .. " available)|r") or "")
        res.breakdown = res.breakdown or {}
        res.breakdown[#res.breakdown + 1] = {
            label = p.name .. (p.primary and "" or " (secondary)"), score = w > 0 and score or nil,
            note = p.fromSpellbook and "learned (the game doesn't report its skill level here)"
                or string.format("%d/%d%s%s", p.skill, p.max,
                p.primary and string.format(" · ~%d expected at level %d", expected, level) or "",
                tier and (" · " .. tier .. " available") or ""),
        }
    end

    -- Empty primary slots count against the grade, with a recommendation
    local primaries, hasFirstAid = {}, false
    for _, p in ipairs(profs) do
        if p.primary then primaries[#primaries + 1] = p end
        if p.name == "First Aid" then hasFirstAid = true end
    end
    local advice = ns.ProfessionAdvice(primaries)
    if advice then
        local empty = 2 - #primaries
        -- Choosing fewer professions is allowed; it costs some gold-making, not a failing grade
        local emptyScore = 70
        for i = 1, empty do
            total, weights = total + emptyScore, weights + 1
            res.breakdown[#res.breakdown + 1] = {
                label = empty == 2 and ("Primary profession " .. i) or "Second profession",
                score = emptyScore,
                note = i == 1 and ("none — suggested: " .. advice.pick) or "none",
            }
        end
        res.breakdown[#res.breakdown + 1] = { label = "Why " .. advice.pick, note = advice.why }
        if advice.alt then res.breakdown[#res.breakdown + 1] = { label = "Alternative", note = advice.alt } end
        local action = #primaries == 0
            and string.format("Learn %s — %s.", advice.pick, advice.why)
            or string.format("Learn %s as your second profession — %s.", advice.pick, advice.why)
        if not worst or worst.score > emptyScore then worst = { score = emptyScore, action = action } end
    end
    if not hasFirstAid then
        res.breakdown[#res.breakdown + 1] = { label = "First Aid (secondary)",
            note = "not learned — cheap bandages for healing between fights" }
    end

    res.score = weights > 0 and math.floor(total / weights) or nil
    local parts = {}
    for _, p in ipairs(primaries) do parts[#parts + 1] = string.format("%s %d/%d", p.name, p.skill, p.max) end
    res.reason = #parts > 0 and table.concat(parts, ", ") .. (#parts == 1 and " · no second profession" or "")
        or "No primary professions yet."
    res.action = worst and worst.action
    return res
end

ns:RegisterPillar(Professions)
