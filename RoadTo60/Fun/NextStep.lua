-- Road to 60: Next Best Step — one line under the pip bar with the single action
-- that would raise your grades most, preferring what you can do where you stand.
--
-- "Where you stand" comes from the game's own data:
--   * quest turn-ins: C_QuestLog.GetQuestsOnMap gives each finished quest's turn-in spot
--   * trainers: the spot of every trainer you've opened is remembered (learn-as-you-go)
local _, ns = ...

local NEAR = 250        -- yards that count as "here"
local HERE_BONUS = 3    -- things doable here outrank bigger wins elsewhere

---------------------------------------------------------------------------
-- Positions
---------------------------------------------------------------------------
local function playerSpot()
    if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition) then return nil end
    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID then return nil end
    local pos = C_Map.GetPlayerMapPosition(mapID, "player")
    if not pos then return nil end  -- e.g. inside instances
    local x, y = pos:GetXY()
    return { mapID = mapID, x = x, y = y }
end

local function world(spot)
    if C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D then
        local ok, cont, v = pcall(C_Map.GetWorldPosFromMapPos, spot.mapID, CreateVector2D(spot.x, spot.y))
        if ok and cont and v then
            local wx, wy = v:GetXY()
            return cont, wx, wy
        end
    end
end

-- Distance in yards; same-map fallback if world coordinates aren't available
local function distance(a, b)
    local ca, ax, ay = world(a)
    local cb, bx, by = world(b)
    if ca and cb then
        if ca ~= cb then return math.huge end
        return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2)
    end
    if a.mapID == b.mapID then
        return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) * 3000  -- rough zone size
    end
    return math.huge
end

---------------------------------------------------------------------------
-- Remember where trainers are
---------------------------------------------------------------------------
-- Three kinds: your class trainer, weapon masters, profession trainers. A weapon
-- master's window looks like a class trainer's, so the kind is decided when the
-- window closes, after the scan has seen what it teaches (ns.lastTrainerKind).
local function spots()
    ns.db.trainerSpots = ns.db.trainerSpots or {}
    local t = ns.db.trainerSpots
    t.class, t.profession, t.weapon = t.class or {}, t.profession or {}, t.weapon or {}
    return t
end

local function spotList(kind)
    local t = spots()
    if kind == "class" then
        local _, class = UnitClass("player")
        t.class[class] = t.class[class] or {}
        return t.class[class]
    end
    return t[kind]
end

local pendingSpot
ns:On("TRAINER_SHOW", function()
    local me = playerSpot()
    if not me or not ns.db then return end
    pendingSpot = { spot = me, name = UnitName("npc") or "?",
        isProf = IsTradeskillTrainer and IsTradeskillTrainer() or false }
end)

ns:On("TRAINER_CLOSED", function()
    local p = pendingSpot
    pendingSpot = nil
    if not p then return end
    local kind = p.isProf and "profession"
        or ((ns.lastTrainerKind == "weapon" or (ns.IsWeaponMaster and ns.IsWeaponMaster(p.name))) and "weapon")
        or "class"
    local list = spotList(kind)
    for _, s in ipairs(list) do
        if s.name == p.name and distance(s, p.spot) < 50 then return end  -- already known
    end
    list[#list + 1] = { name = p.name, mapID = p.spot.mapID, x = p.spot.x, y = p.spot.y }
end)

-- Clean-up: before v0.11.2 weapon masters were filed as class trainers
ns:Listen("LOGIN", function()
    if not (ns.IsWeaponMaster and ns.db) then return end
    local t = spots()
    for _, list in pairs(t.class) do
        for i = #list, 1, -1 do
            if ns.IsWeaponMaster(list[i].name) then
                table.insert(t.weapon, table.remove(list, i))
            end
        end
    end
end)

local function nearTrainer(kind, me)
    if not me or not ns.db.trainerSpots then return nil end
    local list = spotList(kind)
    for _, s in ipairs(list or {}) do
        if distance(s, me) <= NEAR then return s end
    end
end

local function nearbyTurnIns(me)
    local n, seen = 0, {}
    if not (me and C_QuestLog and C_QuestLog.GetQuestsOnMap and C_QuestLog.IsComplete) then return 0 end
    for _, q in ipairs(C_QuestLog.GetQuestsOnMap(me.mapID) or {}) do
        local id = q.questID
        if id and q.x and q.y and not seen[id] and not q.isMapIndicatorQuest and C_QuestLog.IsComplete(id) then
            seen[id] = true
            if distance(me, { mapID = me.mapID, x = q.x, y = q.y }) <= NEAR then n = n + 1 end
        end
    end
    return n
end

---------------------------------------------------------------------------
-- Candidates: { text, pillar, before, after, here, value }
---------------------------------------------------------------------------
local function weight(key)
    local p = ns:GetPillar(key)
    if not p or ns.settings.disabledPillars[key] then return 0 end
    return ns.PillarWeight(p)
end

local function gradeShift(key, before, after)
    local p = ns:GetPillar(key)
    local name = p and p.name or key
    if ns.Grade(before) ~= ns.Grade(after) then
        return string.format("%s %s to %s", name, ns.Grade(before), ns.Grade(after))
    end
    return string.format("%s +%d", name, math.floor(after - before + 0.5))
end

function ns.NextStepCandidates()
    local me = playerSpot()
    local out = {}
    local function add(c)
        c.gain = math.max(0, (c.after or 0) - (c.before or 0))
        c.value = (c.gain * weight(c.pillar) + (c.bonus or 0)) * (c.here and HERE_BONUS or 1)
        if c.value > 0 then out[#out + 1] = c end
    end

    -- Quests: turn-ins near you
    local q = ns.results.quests
    if q and q.score then
        local ready = 0
        for _, x in ipairs(ns.ReadQuestLog().quests) do if x.complete then ready = ready + 1 end end
        local here = nearbyTurnIns(me)
        if here > 0 then
            local after = math.min(100, q.score + 8 * (math.max(0, ready - 2) - math.max(0, ready - here - 2)))
            add({ pillar = "quests", here = true, before = q.score, after = after, bonus = 2 * here,
                text = string.format("Turn in %d quest%s", here, here == 1 and "" or "s") })
        end
    end

    -- Spells: train what you can afford
    local s = ns.results.spells
    if s and s.score and s.waiting and #s.waiting > 0 then
        local trainer = nearTrainer("class", me)
        local money, cost, n = GetMoney(), 0, 0
        for _, w in ipairs(s.waiting) do
            if cost + w.cost <= money then cost = cost + w.cost; n = n + 1 end
        end
        if n > 0 then
            add({ pillar = "spells", here = trainer ~= nil, before = s.score,
                after = n == #s.waiting and 100 or s.score + (100 - s.score) * n / #s.waiting,
                text = string.format("Train %d rank%s%s (%s)", n, n == 1 and "" or "s",
                    trainer and "" or " at your trainer", ns.FormatMoney(cost)) })
        end
    end

    -- Talents: free and doable anywhere
    if s and s.talentPoints and s.talentPoints > 0 then
        add({ pillar = "spells", here = true, before = s.score or 0,
            after = math.min(100, (s.score or 0) + math.min(40, s.talentPoints * 12)), bonus = 5,
            text = string.format("Spend %d talent point%s", s.talentPoints, s.talentPoints == 1 and "" or "s") })
    end

    -- Weapon training: a weapon you carry but can't use yet
    if s and s.weaponAction then
        -- "Here" when you're next to a weapon master who teaches the skill you need
        local here = false
        local needed = s.weapons and s.weapons.needed and s.weapons.needed[1]
        local master = me and nearTrainer("weapon", me)
        if master and needed then
            for _, w in ipairs(needed.entry.where or {}) do
                if w:find(master.name, 1, true) then here = true end
            end
        end
        add({ pillar = "spells", here = here, before = s.score or 0, after = math.min(100, (s.score or 0) + 10),
            bonus = 5, text = (s.weaponAction:gsub("%.$", "")) })
    end

    -- Professions: a tier you can train now
    local p = ns.results.professions
    if p and p.score and p.action and p.action:find("train") then
        local trainer = nearTrainer("profession", me)
        add({ pillar = "professions", here = trainer ~= nil, before = p.score, after = math.min(100, p.score + 35),
            text = (p.action:gsub("%.$", "")) })
    end

    -- Gear: the worst slot
    local g = ns.results.gear
    if g and g.score and g.issues and g.issues[1] then
        local i = g.issues[1]
        add({ pillar = "gear", before = g.score, after = math.min(100, g.score + (i.penalty or 0)),
            text = i.empty and (i.slot == "Wand" and "Get a wand" or string.format("Find a %s item", i.slot:lower()))
                or string.format("Upgrade your %s (%d levels old)", i.slot:lower(), i.age) })
    end

    -- Supplies: buying and repairing happen in towns, so a rest area counts as "here"
    local sup = ns.results.supplies
    if sup and sup.score and sup.action then
        add({ pillar = "supplies", here = IsResting and IsResting() or false,
            before = sup.score, after = 100, bonus = 2, text = (sup.action:gsub("%.$", "")) })
    end

    -- Hunter pet: feeding works anywhere ("here"); leveling or training it doesn't
    local pet = ns.results.pet
    if pet and pet.score and pet.action then
        add({ pillar = "pet", here = pet.actionHere or false,
            before = pet.score, after = 100, bonus = 1, text = (pet.action:gsub("%.$", "")) })
    end

    -- Dungeon prep: quests to pick up in town before going in
    local dn = ns.results.dungeons
    if dn and dn.pickupAction then
        add({ pillar = "dungeons", before = dn.score or 0, after = dn.score or 0, bonus = 4,
            text = (dn.pickupAction:gsub("%.$", "")) })
    end

    -- Hearthstone set somewhere you've left behind
    if sup and sup.hearthAction and sup.hearthAction ~= sup.action then
        add({ pillar = "supplies", here = IsResting and IsResting() or false,
            before = sup.score or 0, after = math.min(100, (sup.score or 0) + 6), bonus = 1,
            text = (sup.hearthAction:gsub("%.$", "")) })
    end

    -- Bags
    if g and g.bagAction then
        add({ pillar = "gear", before = g.score or 0, after = math.min(100, (g.score or 0) + 6),
            bonus = 2, text = (g.bagAction:gsub("%.$", "")) })
    end

    -- Dungeons: best target in range
    local d = ns.results.dungeons
    if d and d.score ~= nil and d.action then
        local closing = d.action:find("^Last chance")
        add({ pillar = "dungeons", before = d.score, after = math.min(100, d.score + math.max(0, d.actionGain or 0)),
            bonus = closing and 0 or 3, text = d.action:gsub("%.$", "") })
    end

    -- Anything doable where you stand comes first; then the biggest win elsewhere
    table.sort(out, function(a, b)
        if (a.here or false) ~= (b.here or false) then return a.here == true end
        return a.value > b.value
    end)
    return out
end

---------------------------------------------------------------------------
-- The next-step line beside the pip bar: optionally in a box like the bar's,
-- wrapping at a width set in settings (pipBar.nextStepBox / nextStepWidth)
---------------------------------------------------------------------------
local PAD_X, PAD_Y = 8, 5
local line = CreateFrame("Button", "RoadTo60NextStep", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
line:SetSize(320, 18)
line:SetClampedToScreen(true)  -- never pushed off the edge, whichever side it's set to
line:Hide()
if line.SetBackdrop then
    line:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10, insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
end

local function applyBox(on)
    if not line.SetBackdropColor then return end
    line:SetBackdropColor(0, 0, 0, on and 0.7 or 0)
    line:SetBackdropBorderColor(1, 1, 1, on and 1 or 0)
end

-- nextStepSide -> { line point, bar point, x, y }
local SIDES = {
    below = { "TOP", "BOTTOM", 0, -2 },
    above = { "BOTTOM", "TOP", 0, 2 },
    left  = { "RIGHT", "LEFT", -4, 0 },
    right = { "LEFT", "RIGHT", 4, 0 },
}
line.text = line:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
line.text:SetPoint("TOPLEFT", PAD_X, -PAD_Y)
line.text:SetWordWrap(true)
line.text:SetShadowOffset(1, -1)
line:SetScript("OnClick", function() ns:ToggleDashboard() end)
line:SetScript("OnEnter", function(self)
    self:SetAlpha(1)  -- undo the all-green fade while hovered
    -- Open away from the bar
    GameTooltip:SetOwner(self, ns.settings.pipBar.nextStepSide == "above" and "ANCHOR_TOP" or "ANCHOR_BOTTOM")
    GameTooltip:AddLine("Next best steps")
    for i, c in ipairs(self.candidates or {}) do
        if i > 4 then break end
        GameTooltip:AddDoubleLine((c.here and "|cff33ff99Here:|r " or "") .. c.text,
            c.gain > 0 and gradeShift(c.pillar, c.before, c.after) or "", 1, 1, 1, 0.7, 0.7, 0.7)
    end
    GameTooltip:AddLine("Click to open the dashboard.", 0.5, 0.5, 0.5)
    GameTooltip:Show()
end)
line:SetScript("OnLeave", function()
    GameTooltip_Hide()
    if ns.ApplyPipBarFade then ns.ApplyPipBarFade() end
end)

local function describe(c)
    local tail = c.gain > 0 and ("  |cffaaaaaa(" .. gradeShift(c.pillar, c.before, c.after) .. ")|r") or ""
    return (c.here and "|cff33ff99Here:|r " or "|cffffd100Next:|r ") .. c.text .. tail
end

function ns:UpdateNextStep()
    local bar = ns.pipBar
    local show = ns.settings.nextStep ~= false and bar and bar:IsShown() and not InCombatLockdown()
    if not show then line:Hide(); return end
    local list = ns.NextStepCandidates()
    line.candidates = list
    if #list == 0 then line:Hide(); return end
    -- Which side of the bar is a setting (pipBar.nextStepSide), not decided automatically
    local a = SIDES[ns.settings.pipBar.nextStepSide] or SIDES.below
    line:SetScale(bar:GetScale())  -- same size setting as the bar
    line:ClearAllPoints()
    line:SetPoint(a[1], bar, a[2], a[3], a[4])
    -- Size: as wide as the text needs, up to the width setting, then wrap and grow taller
    local o = ns.settings.pipBar
    applyBox(o.nextStepBox ~= false)
    local maxText = (o.nextStepWidth or 320) - PAD_X * 2
    local t = line.text
    t:SetWidth(0)  -- measure unwrapped first
    t:SetText(describe(list[1]))
    local textW = math.min(maxText, math.ceil(t:GetStringWidth() or maxText) + 2)
    t:SetWidth(textW)
    t:SetJustifyH((o.nextStepSide == "left" or o.nextStepSide == "right") and "LEFT" or "CENTER")
    line:SetSize(textW + PAD_X * 2, math.ceil(t:GetStringHeight() or 12) + PAD_Y * 2)
    line:Show()
end

local function update() if ns.ready then ns:Safe("next step", ns.UpdateNextStep, ns) end end
ns:Listen("PILLARS_UPDATED", update)
ns:On("ZONE_CHANGED", update)
ns:On("ZONE_CHANGED_INDOORS", update)
ns:On("ZONE_CHANGED_NEW_AREA", update)
ns:On("PLAYER_REGEN_DISABLED", function() line:Hide() end)
ns:On("PLAYER_REGEN_ENABLED", update)
-- Position changes as you walk: a cheap re-check every few seconds
ns:Listen("LOGIN", function()
    if C_Timer.NewTicker then C_Timer.NewTicker(4, update) end
end)
