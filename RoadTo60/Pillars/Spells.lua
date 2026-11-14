-- Road to 60: Spells pillar — ranks available at the trainer vs. ranks you know.
--
-- Learn-as-you-go: every class-trainer visit records what it offers into the
-- account-wide table RoadTo60DB.learned[CLASS][spellID], so alts of the same
-- class benefit immediately. "Known" is checked live by spell ID, so it stays
-- correct between trainer visits.
local _, ns = ...

local FILTERS = { "available", "unavailable", "used" }

---------------------------------------------------------------------------
-- Client differences (confirmed against Forever 1.60.1 via LevelUpInfo):
-- Forever: name, serviceType, _, _, subText = GetTrainerServiceInfo(i)
-- Classic: name, subText, serviceType, isExpanded = GetTrainerServiceInfo(i)
---------------------------------------------------------------------------
local function isModernClient()
    return C_TooltipInfo ~= nil and C_TooltipInfo.GetTrainerService ~= nil
end

local function serviceInfo(i, modern)
    if modern then
        local name, serviceType, _, _, subText = GetTrainerServiceInfo(i)
        return name, serviceType, subText, true
    end
    local name, subText, serviceType, isExpanded = GetTrainerServiceInfo(i)
    return name, serviceType, subText, isExpanded
end

local scanTip
local function serviceSpellID(i, modern)
    if modern then
        local data = C_TooltipInfo.GetTrainerService(i)
        if data and type(data.id) == "number"
            and (not Enum or not Enum.TooltipDataType or data.type == Enum.TooltipDataType.Spell) then
            return data.id
        end
        return nil
    end
    scanTip = scanTip or CreateFrame("GameTooltip", "RoadTo60ScanTip", nil, "GameTooltipTemplate")
    scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
    scanTip:SetTrainerService(i)
    local _, id = scanTip:GetSpell()
    scanTip:Hide()
    return type(id) == "number" and id or nil
end

local function isClassTrainer()
    if C_Trainer and C_Trainer.GetTrainerType and Enum and Enum.TrainerType
        and C_Trainer.GetTrainerType() ~= Enum.TrainerType.General then
        return false
    end
    return not (IsTradeskillTrainer and IsTradeskillTrainer())
end

function ns.IsSpellKnownByID(id)
    if C_SpellBook and C_SpellBook.IsSpellKnown and C_SpellBook.IsSpellKnown(id) then return true end
    if IsPlayerSpell and IsPlayerSpell(id) then return true end
    if IsSpellKnown and IsSpellKnown(id) then return true end
    return false
end

local function classTable()
    local _, class = UnitClass("player")
    ns.db.learned[class] = ns.db.learned[class] or {}
    return ns.db.learned[class], class
end

---------------------------------------------------------------------------
-- Trainer scan
---------------------------------------------------------------------------
local scanning = false

-- Diagnostic lines for the current trainer visit, saved to RoadTo60DB.log.trainer
local visit  -- { scans = n, best = rows } while a trainer window is open
local function diag(line)
    ns.db.log = ns.db.log or {}
    local t = ns.db.log.trainer
    if t and #t.lines < 60 then t.lines[#t.lines + 1] = line end
end

function ns:ScanTrainer()
    if scanning or not visit or not GetNumTrainerServices then return end
    visit.scans = visit.scans + 1
    local ok0, ttype = pcall(function() return C_Trainer and C_Trainer.GetTrainerType and C_Trainer.GetTrainerType() end)
    diag(string.format("scan %d: classTrainer=%s type=%s tradeskill=%s services=%s", visit.scans,
        tostring(isClassTrainer()), tostring(ok0 and ttype),
        tostring(IsTradeskillTrainer and IsTradeskillTrainer()), tostring(GetNumTrainerServices())))
    if not isClassTrainer() then return end
    scanning = true
    local flipped = {}
    local ok, err = pcall(function()
        -- Show every row while we read, then put the player's filters back.
        if GetTrainerServiceTypeFilter and SetTrainerServiceTypeFilter then
            for _, f in ipairs(FILTERS) do
                if not GetTrainerServiceTypeFilter(f) then
                    SetTrainerServiceTypeFilter(f, true)
                    flipped[#flipped + 1] = f
                end
            end
        end
        local modern = isModernClient()
        local tbl = classTable()
        local _, race = UnitRace("player")
        local count, weaponRows = 0, 0
        for i = 1, GetNumTrainerServices() do
            local name, serviceType, subText = serviceInfo(i, modern)
            if visit.scans == 1 and i <= 4 or (visit.scans > 1 and visit.best == 0 and i <= 4) then
                local okd, d = pcall(function()
                    return string.format("  row %d: %s | %s | %s | lvl %s | id %s", i, tostring(name),
                        tostring(serviceType), tostring(subText), tostring(GetTrainerServiceLevelReq(i)),
                        tostring(serviceSpellID(i, modern)))
                end)
                diag(okd and d or ("  row " .. i .. ": " .. tostring(d)))
            end
            if serviceType == "available" or serviceType == "unavailable" or serviceType == "used" then
                local level = GetTrainerServiceLevelReq and GetTrainerServiceLevelReq(i) or 0
                local cost, isProfession = GetTrainerServiceCost(i)
                local isPet = IsTrainerServiceLearnSpell and select(2, IsTrainerServiceLearnSpell(i))
                local id = (level or 0) > 0 and not isProfession and not isPet and serviceSpellID(i, modern)
                -- Weapon skills (a weapon master's window) aren't spell ranks
                local weaponID = serviceSpellID(i, modern)
                if weaponID and ns.IsWeaponSkill and ns.IsWeaponSkill(weaponID) then
                    weaponRows, id = weaponRows + 1, nil
                end
                if id then
                    local e = tbl[id] or { races = {} }
                    e.name, e.rank, e.level, e.cost = name, subText or "", level, cost or 0
                    e.races[race] = true
                    e.seen = time()
                    tbl[id] = e
                    count = count + 1
                end
            end
        end
        diag(string.format("  recorded=%d weaponSkills=%d", count, weaponRows))
        -- Only weapon skills here: a weapon master (used to file the trainer's location)
        if count == 0 and weaponRows > 0 then visit.kind = "weapon"
        elseif count > 0 then visit.kind = "class" end
        ns.lastTrainerKind = visit.kind
        if count > visit.best then
            visit.best = count
            -- Only mark this race as scanned once we actually got rows
            ns.db.learnedRaces = ns.db.learnedRaces or {}
            local _, class = UnitClass("player")
            ns.db.learnedRaces[class] = ns.db.learnedRaces[class] or {}
            ns.db.learnedRaces[class][race] = true
            ns.char.lastTrainerVisit = { level = UnitLevel("player"), time = time(), rows = count }
        end
    end)
    for _, f in ipairs(flipped) do SetTrainerServiceTypeFilter(f, false) end
    scanning = false
    if not ok then ns:LogError("trainer scan: " .. tostring(err)) end
    ns:RequestRefresh()
end

---------------------------------------------------------------------------
-- Import from LevelUpInfo, if installed: its saved table (a global once loaded)
-- holds trainer data by class -> levels -> spellID. Our own scans win on conflict.
---------------------------------------------------------------------------
local function spellName(id)
    if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
    if GetSpellInfo then return (GetSpellInfo(id)) end
end

function ns:ImportLevelUpInfo()
    local src = type(LevelUpInfoDB) == "table" and type(LevelUpInfoDB.trainers) == "table" and LevelUpInfoDB.trainers
    if not src then return 0 end
    local added = 0
    for class, data in pairs(src) do
        if type(data) == "table" and type(data.levels) == "table" then
            ns.db.learned[class] = ns.db.learned[class] or {}
            local tbl = ns.db.learned[class]
            for level, spells in pairs(data.levels) do
                for id, info in pairs(spells) do
                    local e = tbl[id]
                    if not e then
                        e = { races = {}, level = level, cost = info.cost or 0, rank = info.rank or "", source = "LevelUpInfo" }
                        tbl[id] = e
                        added = added + 1
                    end
                    if e.source == "LevelUpInfo" then
                        for race in pairs(info.races or {}) do e.races[race] = true end
                    end
                    e.name = e.name or spellName(id)
                end
            end
            ns.db.learnedRaces = ns.db.learnedRaces or {}
            ns.db.learnedRaces[class] = ns.db.learnedRaces[class] or {}
            for race in pairs(data.covered or {}) do ns.db.learnedRaces[class][race] = true end
        end
    end
    -- Names can come back nil until spell data loads; fill them in on later logins.
    return added
end

ns:Listen("LOGIN", function()
    local n = ns:ImportLevelUpInfo()
    if n > 0 then ns:Print(string.format("Imported %d trainer ranks from LevelUpInfo.", n)) end
end)

-- Clean-up: before v0.11.2 a weapon master's window could save weapon skills
-- (e.g. Polearms) as spell ranks. Remove them on login.
ns:Listen("LOGIN", function()
    if not ns.IsWeaponSkill then return end
    for _, tbl in pairs(ns.db.learned or {}) do
        for id in pairs(tbl) do
            if ns.IsWeaponSkill(id) then tbl[id] = nil end
        end
    end
end)

-- In Forever the service list can still be empty when TRAINER_SHOW fires, and it
-- fills in via TRAINER_UPDATE. So scan on open, then again (debounced) on updates.
-- Flipping filters also fires TRAINER_UPDATE, so scans are capped per visit to
-- rule out a loop.
local MAX_SCANS = 5
local pending = false
local function scheduleScan(delay)
    if pending or not visit or visit.scans >= MAX_SCANS then return end
    pending = true
    C_Timer.After(delay, function()
        pending = false
        ns:ScanTrainer()
    end)
end

ns:On("TRAINER_SHOW", function()
    visit = { scans = 0, best = 0 }
    ns.lastTrainerKind = nil
    ns.db.log = ns.db.log or {}
    ns.db.log.trainer = { when = date("%Y-%m-%d %H:%M:%S"), lines = {} }
    scheduleScan(0.1)
end)
ns:On("TRAINER_UPDATE", function()
    if not scanning then scheduleScan(0.3) end
end)
ns:On("TRAINER_CLOSED", function()
    if visit then diag(string.format("closed after %d scans, best=%d", visit.scans, visit.best)) end
    visit = nil
end)

---------------------------------------------------------------------------
-- Which ranks apply to this character, and which are waiting
---------------------------------------------------------------------------
-- Returns waiting (trainable now, not known), upcoming (above your level), hasData
function ns.SpellStatus()
    local tbl, class = classTable()
    local _, race = UnitRace("player")
    local myRaceScanned = ns.db.learnedRaces and ns.db.learnedRaces[class] and ns.db.learnedRaces[class][race]
    local level = UnitLevel("player")

    -- Highest known rank level per spell name, so skipped lower ranks don't count
    local entries, knownTop = {}, {}
    for id, e in pairs(tbl) do
        if not myRaceScanned or e.races[race] then
            if not e.name then e.name = spellName(id) end
            if not e.name then e.name = "Spell " .. id end  -- data not loaded yet
            local known = ns.IsSpellKnownByID(id)
            entries[#entries + 1] = { id = id, e = e, known = known }
            if known and (knownTop[e.name] or 0) < e.level then knownTop[e.name] = e.level end
        end
    end

    local waiting, upcoming = {}, {}
    for _, x in ipairs(entries) do
        local e = x.e
        if not x.known and (knownTop[e.name] or 0) < e.level then
            if e.level <= level then
                waiting[#waiting + 1] = { id = x.id, name = e.name, rank = e.rank, level = e.level, cost = e.cost }
            else
                upcoming[#upcoming + 1] = { id = x.id, name = e.name, rank = e.rank, level = e.level, cost = e.cost }
            end
        end
    end
    table.sort(waiting, function(a, b) return a.level < b.level end)
    table.sort(upcoming, function(a, b) return a.level < b.level end)
    return waiting, upcoming, #entries > 0
end

local function label(s)
    return (s.rank and s.rank ~= "") and (s.name .. " (" .. s.rank .. ")") or s.name
end
ns.SpellLabel = label

-- Names of spells on your action bars (any rank), or nil if this client can't tell
function ns.SpellsOnBars()
    if not GetActionInfo then return nil end
    local names, any = {}, false
    for slot = 1, 120 do
        local kind, id = GetActionInfo(slot)
        if kind == "spell" and id then
            local name = spellName(id)
            if name then names[name] = true; any = true end
        end
    end
    return any and names or nil
end

---------------------------------------------------------------------------
-- Pillar
---------------------------------------------------------------------------
local Spells = {
    key = "spells", name = "Spells", order = 2, weight = 1.25,
    events = { "PLAYER_LEVEL_UP", "SPELLS_CHANGED", "LEARNED_SPELL_IN_SKILL_LINE", "TRAINER_CLOSED",
        "BAG_UPDATE_DELAYED", "CHARACTER_POINTS_CHANGED", "PLAYER_TALENT_UPDATE", "ACTIONBAR_SLOT_CHANGED",
        "TRAIT_CONFIG_UPDATED", "TRAIT_TREE_CURRENCY_INFO_UPDATED" },
}

function Spells:Evaluate()
    local waiting, upcoming, hasData = ns.SpellStatus()
    local level = UnitLevel("player")
    local res = { details = {} }

    if not hasData then
        res.reason = "Visit your class trainer once so I can learn what it teaches."
        return res
    end

    local limit = ns.settings.spellOverdue
    local bars = ns.SpellsOnBars()
    local score, cost, overdue = 100, 0, 0
    for _, s in ipairs(waiting) do
        local late = level - s.level
        cost = cost + s.cost
        -- A rank of a spell you use (on your action bars) counts fully; others count half
        s.used = not bars or bars[s.name] or false
        local w = s.used and 1 or 0.5
        if late > limit then
            overdue = overdue + 1
            s.penalty = math.min(30, 15 + (late - limit) * 3) * w
        else
            s.penalty = 3 * w
        end
        score = score - s.penalty
        res.details[#res.details + 1] = string.format("%s — level %d, %s%s", label(s), s.level,
            ns.FormatMoney(s.cost), late > limit and string.format(" |cffff5555(%d levels late)|r", late) or "")
    end
    res.score = math.max(0, math.min(100, score))
    res.waiting, res.cost = waiting, cost

    -- Breakdown: each waiting rank, then what's coming next
    res.breakdown = {}
    if #waiting == 0 then
        res.breakdown[1] = { label = "Trainer ranks", score = 100, note = "Everything available is trained." }
    end
    for _, s in ipairs(waiting) do
        local late = level - s.level
        res.breakdown[#res.breakdown + 1] = {
            label = label(s),
            score = math.max(0, math.floor(100 - s.penalty * 3 + 0.5)),
            note = string.format("available since %d · %s%s%s · -%d", s.level, ns.FormatMoney(s.cost),
                late > limit and string.format(" · %d levels late", late) or "",
                s.used and "" or " · not on your bars", math.floor(s.penalty + 0.5)),
        }
    end
    for i = 1, math.min(4, #upcoming) do
        local s = upcoming[i]
        res.breakdown[#res.breakdown + 1] = { label = label(s),
            note = string.format("coming at %d · %s", s.level, ns.FormatMoney(s.cost)) }
    end

    if upcoming[1] then
        local nextLevel = upcoming[1].level
        local names = {}
        for _, s in ipairs(upcoming) do
            if s.level == nextLevel then names[#names + 1] = label(s) end
        end
        res.next = string.format("Next at %d: %s", nextLevel, table.concat(names, ", "))
        res.details[#res.details + 1] = "|cff888888" .. res.next .. "|r"
    end

    if #waiting == 0 then
        res.reason = "All caught up." .. (res.next and ("  " .. res.next .. ".") or "")
    else
        local money = GetMoney()
        local afford = money >= cost and "You can afford it."
            or ("You're " .. ns.FormatMoney(cost - money) .. " short.")
        res.reason = string.format("%d rank%s waiting%s.", #waiting, #waiting == 1 and "" or "s",
            overdue > 0 and string.format(", %d overdue", overdue) or "")
        res.action = string.format("Train %d rank%s — %s. %s", #waiting, #waiting == 1 and "" or "s",
            ns.FormatMoney(cost), afford)
    end
    return res
end

-- Weapon training: rows for each weapon type you could learn; a weapon you carry
-- but can't use yet costs points and can become the next action.
local evaluateRanks = Spells.Evaluate
function Spells:Evaluate()
    local res = evaluateRanks(self)
    local w = ns.WeaponStatus and ns.WeaponStatus()
    if not w then return res end
    res.weapons = w
    res.breakdown = res.breakdown or {}

    local function where(e)
        return #e.where > 0 and table.concat(e.where, " or ") or "a weapon master"
    end
    for _, n in ipairs(w.needed) do
        local e = n.entry
        res.breakdown[#res.breakdown + 1] = {
            label = "Weapon: " .. e.name, score = 40,
            note = string.format("needed for %s · %s · %s%s", n.link, where(e), ns.FormatMoney(e.cost),
                e.available and "" or (" · from level " .. e.level)),
        }
    end
    for _, e in ipairs(w.learnable) do
        local isNeeded = false
        for _, n in ipairs(w.needed) do if n.entry == e then isNeeded = true end end
        if not isNeeded then
            res.breakdown[#res.breakdown + 1] = {
                label = "Weapon: " .. e.name,
                note = string.format("not learned · %s · %s%s", where(e), ns.FormatMoney(e.cost),
                    e.available and "" or (" · from level " .. e.level)),
            }
        end
    end
    if #w.known > 0 then
        res.breakdown[#res.breakdown + 1] = { label = "Weapons you know", note = table.concat(w.known, ", ") }
    end

    -- A usable-soon weapon in your bags is a real gap
    local needNow = {}
    for _, n in ipairs(w.needed) do if n.entry.available then needNow[#needNow + 1] = n end end
    if #needNow > 0 then
        if res.score then res.score = math.max(0, res.score - math.min(20, 10 * #needNow)) end
        local n = needNow[1]
        res.weaponAction = string.format("Learn %s to use %s — %s, %s.", n.entry.name, n.item,
            where(n.entry), ns.FormatMoney(n.entry.cost))
        if not res.waiting or #res.waiting == 0 then res.action = res.weaponAction end
    end
    return res
end

-- Talents: unspent points are free to fix and doable anywhere, so they lead.
-- Forever uses Classic-style talent tabs (GetNumTalentTabs, as GearQuestForever reads them).
local function try(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a = pcall(fn, ...)
    if ok then return a end
end

-- Forever has no Classic talent functions; its talents are trait trees
-- (C_ClassTalents / C_Traits), read as point groups per tree like LOF does.
-- Returns configID, treeID, and the currency entries found (each a table).
function ns.TalentCurrencies()
    local CT, T = C_ClassTalents, C_Traits
    if not (CT and T) then return nil end
    local configID = try(CT.GetActiveConfigID)
    if type(configID) ~= "number" then return nil end
    local info = try(T.GetConfigInfo, configID)
    local treeID = type(info) == "table" and type(info.treeIDs) == "table" and info.treeIDs[1]
    if type(treeID) ~= "number" then return nil end
    local entries = {}
    -- Retail-style: one list of currencies for the whole tree
    local tree = try(T.GetTreeCurrencyInfo, configID, treeID, false)
    if type(tree) == "table" then
        for _, c in ipairs(tree) do if type(c) == "table" then entries[#entries + 1] = c end end
    end
    -- Forever-style: currencies per talent group (as LOF reads spent points)
    if #entries == 0 then
        local displays = try(T.GetGroupDisplayInfoByTreeID, treeID)
        local ids = {}
        for _, d in ipairs(type(displays) == "table" and displays or {}) do
            if type(d) == "table" and type(d.groupID) == "number" then ids[#ids + 1] = d.groupID end
        end
        local groups = #ids > 0 and try(T.GetGroupCurrencyInfo, configID, ids)
        for _, g in ipairs(type(groups) == "table" and groups or {}) do
            for _, c in ipairs(type(g) == "table" and type(g.currencyInfos) == "table" and g.currencyInfos or {}) do
                if type(c) == "table" then entries[#entries + 1] = c end
            end
        end
    end
    return configID, treeID, entries
end

function ns.UnspentTalentPoints()
    if GetUnspentTalentPoints then
        local n = try(GetUnspentTalentPoints, false, false)
        if type(n) == "number" then return n end
    end
    if UnitCharacterPoints then
        local n = try(UnitCharacterPoints, "player")
        if type(n) == "number" then return n end
    end
    -- Trait trees: available points per currency (a shared pool is counted once)
    local configID, _, entries = ns.TalentCurrencies()
    if configID and entries and #entries > 0 then
        local byCurrency, found = {}, false
        for i, c in ipairs(entries) do
            local q = tonumber(c.quantity)
            if q then
                found = true
                local id = c.traitCurrencyID or ("#" .. i)
                byCurrency[id] = math.max(byCurrency[id] or 0, q)
            end
        end
        if found then
            local total = 0
            for _, q in pairs(byCurrency) do total = total + math.max(0, q) end
            return total
        end
    end
    return nil  -- can't tell on this client
end

local evaluateWithWeapons = Spells.Evaluate
function Spells:Evaluate()
    local res = evaluateWithWeapons(self)
    local points = ns.UnspentTalentPoints()
    if not points or UnitLevel("player") < 10 then return res end
    res.breakdown = res.breakdown or {}
    table.insert(res.breakdown, 1, {
        label = "Talent points",
        score = points == 0 and 100 or math.max(20, 100 - points * 15),
        note = points == 0 and "all spent" or string.format("%d unspent — open your talents (N)", points),
    })
    res.talentPoints = points
    if points > 0 then
        if res.score then res.score = math.max(0, res.score - math.min(40, points * 12)) end
        res.action = string.format("Spend %d talent point%s.", points, points == 1 and "" or "s")
    end
    return res
end

ns:RegisterPillar(Spells)

-- Level-up alert: what just became trainable
ns:Listen("LEVEL_UP", function(newLevel)
    C_Timer.After(1, function()
        local waiting = ns.SpellStatus()
        local fresh, cost = {}, 0
        for _, s in ipairs(waiting) do
            if s.level == newLevel then fresh[#fresh + 1] = s.name; cost = cost + s.cost end
        end
        if #fresh > 0 then
            ns:Alert("trainable", string.format("Level %d: %d new rank%s at your trainer (%s) — %s",
                newLevel, #fresh, #fresh == 1 and "" or "s", table.concat(fresh, ", "), ns.FormatMoney(cost)))
        end
    end)
end)
