-- Road to 60: checkpoint report cards at 10, 20, 30, 40, 50 and 60, plus /played tracking.
local _, ns = ...

ns.CHECKPOINTS = { 10, 20, 30, 40, 50, 60 }
local isCheckpoint = {}
for _, l in ipairs(ns.CHECKPOINTS) do isCheckpoint[l] = true end

function ns.FormatDuration(sec)
    if not sec then return "?" end
    sec = math.floor(sec)
    local d, h, m = math.floor(sec / 86400), math.floor(sec % 86400 / 3600), math.floor(sec % 3600 / 60)
    if d > 0 then return string.format("%dd %dh", d, h) end
    if h > 0 then return string.format("%dh %dm", h, m) end
    return string.format("%dm", m)
end

---------------------------------------------------------------------------
-- /played: ask quietly. The answer normally prints to chat; we hide the
-- copy we asked for (the player's own /played still prints).
---------------------------------------------------------------------------
local quietRequests = 0

local function wrapDisplay(tbl, key)
    if type(tbl) ~= "table" or type(tbl[key]) ~= "function" then return end
    local orig = tbl[key]
    tbl[key] = function(...)
        if quietRequests > 0 then
            quietRequests = quietRequests - 1
            return
        end
        return orig(...)
    end
end
wrapDisplay(_G, "ChatFrame_DisplayTimePlayed")
if ChatFrameUtil then wrapDisplay(ChatFrameUtil, "DisplayTimePlayed") end

function ns:RequestPlayed()
    if not RequestTimePlayed then return end
    quietRequests = quietRequests + 1
    RequestTimePlayed()
    -- if nothing was suppressed (e.g. the display function has another name), stop hiding
    C_Timer.After(5, function() quietRequests = 0 end)
end

-- Total /played right now, in seconds (nil until the first answer)
function ns.PlayedNow()
    local p = ns.char and ns.char.played
    if not p then return nil end
    return p.total + (GetTime() - p.at)
end

local pendingCard

ns:On("TIME_PLAYED_MSG", function(_, total, thisLevel)
    if not ns.char then return end
    ns.char.played = { total = total, at = GetTime() }
    local level = UnitLevel("player")
    ns.char.playedAtLevel = ns.char.playedAtLevel or {}
    if not ns.char.playedAtLevel[level] then
        ns.char.playedAtLevel[level] = total - (thisLevel or 0)
    end
    if pendingCard then
        local l = pendingCard
        pendingCard = nil
        ns:CreateCheckpoint(l)
    end
    ns:Fire("PLAYED_UPDATED")
end)

ns:Listen("LOGIN", function() C_Timer.After(3, function() ns:RequestPlayed() end) end)

---------------------------------------------------------------------------
-- Cards
---------------------------------------------------------------------------
-- card = { level, time, played, money, overall, grades = { [key] = {score, grade, note} }, segment }
function ns:BuildCard(level)
    ns:Refresh()
    local card = {
        level = level, time = time(), played = ns.PlayedNow(), money = GetMoney(),
        overall = ns.overall, grades = {},
    }
    for _, p in ipairs(ns.pillars) do
        local r = ns.results[p.key]
        if r and r.score then
            card.grades[p.key] = { score = math.floor(r.score), grade = r.grade, note = r.action or r.reason }
        end
    end
    -- /played since the previous checkpoint
    local prevLevel
    for _, l in ipairs(ns.CHECKPOINTS) do
        if l < level and ns.char.checkpoints[l] then prevLevel = l end
    end
    local prev = prevLevel and ns.char.checkpoints[prevLevel]
    if prev and prev.played and card.played then
        card.segment = { from = prevLevel, seconds = card.played - prev.played }
    elseif card.played and ns.char.playedAtLevel and ns.char.playedAtLevel[level - 10] then
        card.segment = { from = level - 10, seconds = card.played - ns.char.playedAtLevel[level - 10] }
    end
    return card
end

function ns:CreateCheckpoint(level)
    local card = ns:BuildCard(level)
    ns.char.checkpoints[level] = card
    ns:Fire("CHECKPOINT", card)
    ns:Alert("checkpoint", string.format("Level %d checkpoint: %s", level, ns.Grade(card.overall)))
    ns:ShowCard(card)
end

ns:Listen("LEVEL_UP", function(newLevel)
    ns:RequestPlayed()
    if isCheckpoint[newLevel] and not ns.char.checkpoints[newLevel] then
        pendingCard = newLevel
        -- If /played never answers, make the card anyway
        C_Timer.After(6, function()
            if pendingCard == newLevel then
                pendingCard = nil
                ns:CreateCheckpoint(newLevel)
            end
        end)
    end
end)

---------------------------------------------------------------------------
-- Card window
---------------------------------------------------------------------------
local card = CreateFrame("Frame", "RoadTo60Card", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
card:SetSize(380, 350)
card:SetPoint("CENTER", 0, 60)
card:SetFrameStrata("DIALOG")
card:SetMovable(true)
card:EnableMouse(true)
card:RegisterForDrag("LeftButton")
card:SetScript("OnDragStart", card.StartMoving)
card:SetScript("OnDragStop", card.StopMovingOrSizing)
card:SetClampedToScreen(true)
card:SetToplevel(true)  -- clicking it brings it to the front
card:Hide()
-- Only one pop-up at a time: a report card replaces the settings window
card:SetScript("OnShow", function(self)
    if RoadTo60Settings and RoadTo60Settings:IsShown() then RoadTo60Settings:Hide() end
    self:Raise()
end)
tinsert(UISpecialFrames, "RoadTo60Card")
if card.SetBackdrop then
    card:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border",
        edgeSize = 24, insets = { left = 6, right = 6, top = 6, bottom = 6 },
    })
end
local close = CreateFrame("Button", nil, card, "UIPanelCloseButton")
close:SetPoint("TOPRIGHT", -4, -4)

card.title = card:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
card.title:SetPoint("TOPLEFT", 20, -20)
card.sub = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
card.sub:SetPoint("TOPLEFT", card.title, "BOTTOMLEFT", 0, -4)
card.grade = card:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
card.grade:SetPoint("TOPRIGHT", -44, -18)
card.grade:SetFont(card.grade:GetFont(), 36, "OUTLINE")

card.lines = {}
for i = 1, 9 do
    local g = card:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    g:SetPoint("TOPLEFT", 22, -70 - (i - 1) * 30)
    g:SetWidth(24)
    local n = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    n:SetPoint("TOPLEFT", 52, -68 - (i - 1) * 30)
    local note = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    note:SetPoint("TOPLEFT", n, "BOTTOMLEFT", 0, -1)
    note:SetWidth(300)
    note:SetJustifyH("LEFT")
    note:SetWordWrap(false)
    card.lines[i] = { grade = g, name = n, note = note }
end

card.footer = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
card.footer:SetPoint("BOTTOM", 0, 18)
card.ghostLine = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
card.ghostLine:SetPoint("BOTTOM", card.footer, "TOP", 0, 6)
card.ghostLine:SetWidth(340)

local function navButton(text, point, x)
    local b = CreateFrame("Button", nil, card, "UIPanelButtonTemplate")
    b:SetSize(28, 20)
    b:SetText(text)
    b:SetPoint(point, x, 14)
    return b
end
card.prevBtn = navButton("<", "BOTTOMLEFT", 14)
card.nextBtn = navButton(">", "BOTTOMRIGHT", -14)

local function savedLevels()
    local out = {}
    for _, l in ipairs(ns.CHECKPOINTS) do
        if ns.char.checkpoints[l] then out[#out + 1] = l end
    end
    return out
end

local function step(dir)
    local levels = savedLevels()
    local cur = card.shown and card.shown.level
    local idx
    for i, l in ipairs(levels) do if l == cur then idx = i end end
    idx = (idx or (dir > 0 and 0 or #levels + 1)) + dir
    if levels[idx] then ns:ShowCard(ns.char.checkpoints[levels[idx]]) end
end
card.prevBtn:SetScript("OnClick", function() step(-1) end)
card.nextBtn:SetScript("OnClick", function() step(1) end)

local queuedCard
function ns:ShowCard(c, preview)
    if InCombatLockdown() then queuedCard = c; return end
    card.shown = c
    card.title:SetText(preview and string.format("Level %d — preview", c.level)
        or string.format("Level %d Checkpoint", c.level))
    card.sub:SetText(string.format("%s · %s%s", UnitName("player"), date("%b %d", c.time),
        c.played and (" · " .. ns.FormatDuration(c.played) .. " played") or ""))
    local overall = ns.Grade(c.overall)
    card.grade:SetText(overall)
    card.grade:SetTextColor(unpack(ns.COLORS[ns.StatusFor(c.overall)]))

    -- Same order as the pip bar; the card grows to fit the pillars shown
    local i = 0
    local shown = ns.PillarsInOrder()
    for _, l in ipairs(card.lines) do l.grade:SetText(""); l.name:SetText(""); l.note:SetText("") end
    card:SetHeight(140 + #shown * 30)
    for _, p in ipairs(shown) do
        local g = c.grades[p.key]
        i = i + 1
        local line = card.lines[i]
        if line then
            line.name:SetText(p.name)
            if g then
                line.grade:SetText(g.grade)
                line.grade:SetTextColor(unpack(ns.COLORS[ns.StatusFor(g.score)]))
                line.note:SetText(g.note or "")
            else
                line.grade:SetText("–")
                line.grade:SetTextColor(unpack(ns.COLORS.gray))
                line.note:SetText("|cff888888not graded|r")
            end
        end
    end

    -- Gold on hand; no time comparisons (Road to 60 is about being ready, not fast)
    card.footer:SetText(ns.FormatMoney(c.money) .. " on hand")
    local ghost = c.ghost
    if not ghost and preview and ns.GhostCompare then
        ghost = ns.GhostCompare(c.level, c)
    end
    card.ghostLine:SetText(ghost and ("Ghost: " .. ghost) or "")
    local levels = savedLevels()
    card.prevBtn:SetShown(not preview and #levels > 1)
    card.nextBtn:SetShown(not preview and #levels > 1)
    card:Show()
end

ns:On("PLAYER_REGEN_DISABLED", function() if card:IsShown() then queuedCard = card.shown; card:Hide() end end)
ns:On("PLAYER_REGEN_ENABLED", function()
    if queuedCard then local c = queuedCard; queuedCard = nil; ns:ShowCard(c) end
end)
