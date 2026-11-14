-- Road to 60: Legacy pillar — Forever's account-wide Legacy System.
--
-- Legacy Challenges award account-wide Legacy Points; each character spends them in
-- Legacy Trees (Professions, Adventure, Resourcefulness), up to a per-character cap.
-- No addon API for it is documented yet, so this pillar starts with a discovery
-- scan (/r60 legacy) that saves everything Legacy-related the client exposes to
-- RoadTo60DB.log.legacy. Once the real API is known, Evaluate grades on it.
local _, ns = ...

local function matches(s) return type(s) == "string" and s:lower():find("legacy", 1, true) end

function ns:ScanLegacy()
    local found = {}
    local function add(s) if #found < 120 then found[#found + 1] = s end end

    -- Globals: functions, C_ namespaces, frames, constants
    local names = {}
    for k, v in pairs(_G) do
        if matches(k) then
            local t = type(v)
            local preview = (t == "string" or t == "number") and (": " .. tostring(v):sub(1, 60)) or ""
            names[#names + 1] = string.format("_G.%s (%s)%s", k, t, preview)
        end
    end
    table.sort(names)
    for _, s in ipairs(names) do add(s) end

    -- Functions inside C_ namespaces
    for k, v in pairs(_G) do
        if type(k) == "string" and k:match("^C_") and type(v) == "table" then
            if matches(k) then
                for fk in pairs(v) do add(k .. "." .. tostring(fk)) end
            else
                for fk in pairs(v) do if matches(fk) then add(k .. "." .. fk) end end
            end
        end
    end

    -- Enum entries
    if type(Enum) == "table" then
        for ek, ev in pairs(Enum) do
            if matches(ek) then add("Enum." .. ek) end
            if type(ev) == "table" then
                for vk in pairs(ev) do if matches(vk) then add("Enum." .. ek .. "." .. vk) end end
            end
        end
    end

    -- Currencies named Legacy
    if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyListSize then
        for i = 1, C_CurrencyInfo.GetCurrencyListSize() do
            local info = C_CurrencyInfo.GetCurrencyListInfo(i)
            if info and matches(info.name) then
                add(string.format("currency: %s = %s (max %s)", info.name, tostring(info.quantity), tostring(info.maxQuantity)))
            end
        end
    end

    -- Achievement categories named Legacy
    if GetCategoryList and GetCategoryInfo then
        for _, id in ipairs(GetCategoryList() or {}) do
            local title = GetCategoryInfo(id)
            if matches(title) then
                local n = GetCategoryNumAchievements and select(1, GetCategoryNumAchievements(id)) or "?"
                add(string.format("achievement category %d: %s (%s achievements)", id, title, tostring(n)))
            end
        end
    end

    ns.db.log = ns.db.log or {}
    ns.db.log.legacy = { when = date("%Y-%m-%d %H:%M:%S"), version = ns.version, level = UnitLevel("player"), lines = found }
    return found
end

local Legacy = {
    key = "legacy", name = "Legacy", order = 8, weight = 0.5, events = {},
}

-- Legacy unlocks account-wide once any character reaches this level.
local UNLOCK_LEVEL = 25

local function highestLevel()
    local best = UnitLevel("player")
    for _, run in pairs(ns.db.runs or {}) do
        if (run.level or 0) > best then best = run.level end
    end
    return best
end

-- Nudge once, the first time the account reaches the unlock level
ns:Listen("LEVEL_UP", function(newLevel)
    if newLevel >= UNLOCK_LEVEL and not ns.db.legacyUnlockedNoticed then
        ns.db.legacyUnlockedNoticed = true
        ns:Alert("checkpoint", "Legacy unlocked! Type /r60 legacy, then /reload, so Road to 60 can track it.")
    end
end)

-- Levels until Legacy unlocks on this account (0 once unlocked)
function ns.LegacyLevelsToGo()
    return math.max(0, UNLOCK_LEVEL - highestLevel())
end

-- No pip while locked; the Progress page shows the countdown instead
function Legacy:Hidden() return ns.LegacyLevelsToGo() > 0 end

function Legacy:Evaluate()
    -- Real grading goes here once the API is known: unspent points available to
    -- this character (nudge: "Spend 2 Legacy Points"), and points earned per level.
    local top = highestLevel()
    if top < UNLOCK_LEVEL then
        return {
            reason = string.format("Unlocks when a character reaches level %d (%d to go).", UNLOCK_LEVEL, UNLOCK_LEVEL - top),
            progress = top / UNLOCK_LEVEL,
        }
    end
    local scanned = ns.db.log and ns.db.log.legacy
    if scanned and (scanned.level or 0) < UNLOCK_LEVEL then scanned = nil end  -- scanned while locked
    if scanned then
        return { reason = string.format("Scanned %s: %d Legacy entries found. Waiting on the API details.",
            scanned.when, #scanned.lines) }
    end
    return { reason = "Unlocked — run /r60 legacy, then /reload, so I can find what Forever exposes." }
end

ns:RegisterPillar(Legacy)
