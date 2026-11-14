-- Road to 60: dashboard — one row per pillar: grade, progress bar, next action.
local _, ns = ...

local WIDTH, ROW_H = 460, 46

local hasTemplate = pcall(function()
    local f = CreateFrame("Frame", nil, nil, "BasicFrameTemplateWithInset"); f:Hide()
end)

local dash = CreateFrame("Frame", "RoadTo60Dashboard", UIParent,
    hasTemplate and "BasicFrameTemplateWithInset" or (BackdropTemplateMixin and "BackdropTemplate" or nil))
dash:SetFrameStrata("DIALOG")
dash:SetPoint("CENTER")
dash:SetMovable(true)
dash:EnableMouse(true)
dash:RegisterForDrag("LeftButton")
dash:SetScript("OnDragStart", dash.StartMoving)
dash:SetScript("OnDragStop", dash.StopMovingOrSizing)
dash:SetClampedToScreen(true)
dash:SetToplevel(true)  -- raised to the front when shown or clicked
dash:Hide()
tinsert(UISpecialFrames, "RoadTo60Dashboard")  -- Esc closes it

if not hasTemplate then
    if dash.SetBackdrop then
        dash:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            edgeSize = 24, insets = { left = 6, right = 6, top = 6, bottom = 6 },
        })
    end
    local close = CreateFrame("Button", nil, dash, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)
end

local templateTitle = type(rawget(dash, "TitleText")) == "table" and dash.TitleText or nil
dash.title = templateTitle or dash:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
if not templateTitle then dash.title:SetPoint("TOP", 0, -6) end
dash.title:SetText("Road to 60")

dash.header = dash:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
dash.header:SetPoint("TOPLEFT", 16, -34)

dash.overall = dash:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
dash.overall:SetPoint("TOPRIGHT", -20, -30)

dash.footer = dash:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
dash.footer:SetPoint("BOTTOMRIGHT", -16, 16)
dash.footer:SetText("")  -- the bottom row is taken by the four tabs

-- Light highlight under the mouse for clickable rows
local function addHover(frame)
    local hl = frame:CreateTexture(nil, "BACKGROUND")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.06)
    hl:Hide()
    frame:HookScript("OnEnter", function() hl:Show() end)
    frame:HookScript("OnLeave", function() hl:Hide() end)
end

-- Pages + tabs along the bottom
dash.pages = {}
local PAGE_ORDER = { { "pillars", "Pillars" }, { "progress", "Progress" } }
for _, pg in ipairs(PAGE_ORDER) do
    local f = CreateFrame("Frame", nil, dash)
    f:SetPoint("TOPLEFT", 0, -60)
    f:SetPoint("BOTTOMRIGHT", 0, 40)
    f:Hide()
    dash.pages[pg[1]] = f
end
dash.tabs = {}
local currentPage = "pillars"
local updatePage  -- defined below

local function showPage(key)
    currentPage = key
    for k, f in pairs(dash.pages) do f:SetShown(k == key) end
    for k, b in pairs(dash.tabs) do
        if k == key then b:LockHighlight() else b:UnlockHighlight() end
    end
    if updatePage then updatePage() end
end
for i, pg in ipairs(PAGE_ORDER) do
    local b = CreateFrame("Button", nil, dash, "UIPanelButtonTemplate")
    b:SetSize(100, 22)
    b:SetPoint("BOTTOMLEFT", 14 + (i - 1) * 104, 12)
    b:SetText(pg[2])
    b:SetScript("OnClick", function() ns:Safe(pg[2] .. " tab", showPage, pg[1]) end)
    dash.tabs[pg[1]] = b
end
-- Last tab opens the settings window
local settingsBtn = CreateFrame("Button", nil, dash, "UIPanelButtonTemplate")
settingsBtn:SetSize(100, 22)
settingsBtn:SetPoint("BOTTOMLEFT", 14 + #PAGE_ORDER * 104, 12)
settingsBtn:SetText("Settings")
settingsBtn:SetScript("OnClick", function() ns:Safe("Settings", ns.ToggleSettings, ns) end)

dash.rows = {}

local function rowTooltip(row)
    local r = ns.results[row.pillar.key] or {}
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:AddLine(row.pillar.name)
    for _, line in ipairs(r.details or {}) do GameTooltip:AddLine(line, 0.9, 0.9, 0.9, true) end
    GameTooltip:AddLine("Click for the full breakdown.", 0.5, 0.5, 0.5)
    GameTooltip:Show()
end

local function buildRows()
    for i, p in ipairs(ns.pillars) do
        local row = CreateFrame("Frame", nil, dash.pages.pillars)
        row:SetSize(WIDTH - 32, ROW_H)
        row:SetPoint("TOPLEFT", 16, -4 - (i - 1) * ROW_H)
        row:EnableMouse(true)
        row:SetScript("OnEnter", rowTooltip)
        row:SetScript("OnLeave", GameTooltip_Hide)
        row:SetScript("OnMouseUp", function(self)
            GameTooltip_Hide()
            ns:Safe("breakdown", ns.ShowPillarDetail, ns, self.pillar.key)
        end)
        addHover(row)
        row.pillar = p

        row.grade = row:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
        row.grade:SetPoint("LEFT", 0, 0)
        row.grade:SetWidth(34)

        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.name:SetPoint("TOPLEFT", 42, -4)
        row.name:SetText(p.name)

        row.status = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.status:SetPoint("LEFT", row.name, "RIGHT", 8, 0)

        row.bar = CreateFrame("StatusBar", nil, row)
        row.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
        row.bar:SetMinMaxValues(0, 100)
        row.bar:SetSize(120, 10)
        row.bar:SetPoint("TOPRIGHT", 0, -6)
        local bbg = row.bar:CreateTexture(nil, "BACKGROUND")
        bbg:SetAllPoints()
        bbg:SetColorTexture(0.15, 0.15, 0.15, 0.8)

        row.line = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.line:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -4)
        row.line:SetWidth(WIDTH - 32 - 42)
        row.line:SetJustifyH("LEFT")
        row.line:SetWordWrap(true)

        dash.rows[i] = row
    end
end

-- Tall enough for the visible rows, and never shorter than the Progress page needs
local MIN_ROWS = 7
local function fitHeight(visibleRows)
    dash:SetSize(WIDTH, 64 + math.max(MIN_ROWS, visibleRows) * ROW_H + 50)
end

---------------------------------------------------------------------------
-- Progress page: checkpoint cards as six tiles, then records and the ghost run
---------------------------------------------------------------------------
local prog = dash.pages.progress
prog.intro = prog:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
prog.intro:SetPoint("TOPLEFT", 18, -6)
prog.intro:SetWidth(WIDTH - 36)
prog.intro:SetJustifyH("LEFT")

local TILE_GAP = 6
local TILE_W = math.floor((WIDTH - 36 - TILE_GAP * (#ns.CHECKPOINTS - 1)) / #ns.CHECKPOINTS)
prog.tiles = {}
for i, level in ipairs(ns.CHECKPOINTS) do
    local b = CreateFrame("Button", nil, prog)
    b:SetSize(TILE_W, 46)
    b:SetPoint("TOPLEFT", 18 + (i - 1) * (TILE_W + TILE_GAP), -24)
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(1, 1, 1, 0.05)
    b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    b.grade = b:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    b.grade:SetPoint("TOP", 0, -4)
    b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.label:SetPoint("BOTTOM", 0, 4)
    b.label:SetText("Lv " .. level)
    b.level = level
    b:SetScript("OnClick", function(self)
        local c = ns.char.checkpoints[self.level]
        if c then ns:ShowCard(c) end
    end)
    b:SetScript("OnEnter", function(self)
        local c = ns.char.checkpoints[self.level]
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Level " .. self.level .. " checkpoint")
        if c then
            GameTooltip:AddLine(date("%b %d", c.time) .. " · " .. ns.FormatMoney(c.money) .. " on hand", 0.9, 0.9, 0.9)
            GameTooltip:AddLine("Click to open the card.", 0.5, 0.5, 0.5)
        else
            GameTooltip:AddLine(self.level <= UnitLevel("player") and "Reached before Road to 60 was installed."
                or "Not reached yet.", 0.6, 0.6, 0.6)
        end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    prog.tiles[i] = b
end

prog.preview = CreateFrame("Button", nil, prog, "UIPanelButtonTemplate")
prog.preview:SetSize(150, 22)
prog.preview:SetPoint("BOTTOMRIGHT", -18, 4)
prog.preview:SetText("Preview today's card")
prog.preview:SetScript("OnClick", function()
    ns:Safe("card preview", function() ns:ShowCard(ns:BuildCard(UnitLevel("player")), true) end)
end)

prog.rows = {}
local function updateProgress()
    local level = UnitLevel("player")
    local nextCp
    for _, l in ipairs(ns.CHECKPOINTS) do if l > level then nextCp = l; break end end
    prog.intro:SetText(nextCp and string.format("A report card is saved at each checkpoint. Next: level %d.", nextCp)
        or "Every checkpoint reached.")
    for _, b in ipairs(prog.tiles) do
        local c = ns.char.checkpoints[b.level]
        b.grade:SetText(c and ns.Grade(c.overall) or "–")
        b.grade:SetTextColor(unpack(ns.COLORS[c and ns.StatusFor(c.overall) or "gray"]))
        b:SetAlpha(c and 1 or 0.45)
    end

    local lines = ns.RecordLines()
    for i, l in ipairs(lines) do
        local r = prog.rows[i]
        if not r then
            r = {}
            r.label = prog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            r.label:SetPoint("TOPLEFT", 18, -82 - (i - 1) * 22)
            r.value = prog:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            r.value:SetPoint("TOPRIGHT", -18, -82 - (i - 1) * 22)
            prog.rows[i] = r
        end
        r.label:SetText(l[1])
        r.value:SetText(l[2])
        r.label:Show(); r.value:Show()
    end
    for i = #lines + 1, #prog.rows do prog.rows[i].label:Hide(); prog.rows[i].value:Hide() end
end

---------------------------------------------------------------------------
-- Detail page: one pillar's breakdown (click a pillar row or a pip)
---------------------------------------------------------------------------
local detail = CreateFrame("Frame", nil, dash)
detail:SetPoint("TOPLEFT", 0, -60)
detail:SetPoint("BOTTOMRIGHT", 0, 40)
detail:Hide()
dash.pages.detail = detail

local back = CreateFrame("Button", nil, detail, "UIPanelButtonTemplate")
back:SetSize(90, 20)
back:SetPoint("TOPLEFT", 16, -2)
back:SetText("< Pillars")
back:SetScript("OnClick", function() showPage("pillars") end)

detail.grade = detail:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
detail.grade:SetPoint("TOPLEFT", 116, 0)
detail.name = detail:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
detail.name:SetPoint("LEFT", detail.grade, "RIGHT", 8, 0)
detail.reason = detail:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
detail.reason:SetPoint("TOPLEFT", 18, -28)
detail.reason:SetWidth(WIDTH - 36)
detail.reason:SetJustifyH("LEFT")

-- First item link in a string, for hover tooltips on breakdown rows
local function findLink(s)
    return s and s:match("|H(item:[^|]+)|h")
end

local D_ROW, D_ROWS = 28, 10
detail.rows = {}
for i = 1, D_ROWS do
    local r = CreateFrame("Frame", nil, detail)
    r:SetSize(WIDTH - 36, D_ROW)
    r:SetPoint("TOPLEFT", 18, -50 - (i - 1) * D_ROW)
    r.grade = r:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    r.grade:SetPoint("LEFT", 0, 0)
    r.grade:SetWidth(22)
    r.label = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    r.label:SetPoint("TOPLEFT", 28, -1)
    r.label:SetWidth(WIDTH - 36 - 28 - 100)
    r.label:SetJustifyH("LEFT")
    r.label:SetWordWrap(false)
    r.note = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.note:SetPoint("TOPLEFT", r.label, "BOTTOMLEFT", 0, -1)
    r.note:SetWidth(WIDTH - 36 - 28)
    r.note:SetJustifyH("LEFT")
    r.note:SetWordWrap(false)
    r.bar = CreateFrame("StatusBar", nil, r)
    r.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    r.bar:SetMinMaxValues(0, 100)
    r.bar:SetSize(90, 8)
    r.bar:SetPoint("TOPRIGHT", 0, -4)
    local bg = r.bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.15, 0.15, 0.15, 0.8)
    -- Hover: an item's own tooltip if the row names one, otherwise the row in full
    r:EnableMouse(true)
    r:SetScript("OnEnter", function(self)
        local link = findLink(self.label:GetText()) or findLink(self.note:GetText())
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if link then
            GameTooltip:SetHyperlink(link)
        else
            GameTooltip:AddLine(self.label:GetText() or "", 1, 1, 1)
            local note = self.note:GetText()
            if note and note ~= "" then GameTooltip:AddLine(note, 0.9, 0.9, 0.9, true) end
        end
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", GameTooltip_Hide)
    addHover(r)
    detail.rows[i] = r
end
detail.more = detail:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
detail.more:SetPoint("BOTTOMRIGHT", -18, 2)

-- Scroll with the mouse wheel when there are more rows than fit
detail.offset = 0
detail:EnableMouseWheel(true)
detail:SetScript("OnMouseWheel", function(self, delta)
    self.offset = math.max(0, math.min((self.total or 0) - D_ROWS, self.offset - delta))
    if updatePage then updatePage() end
end)

local function updateDetail()
    local p = ns:GetPillar(detail.key)
    if not p then return end
    local r = ns.results[p.key] or {}
    local c = ns.COLORS[r.status or "gray"]
    detail.grade:SetText(r.score and r.grade or "–")
    detail.grade:SetTextColor(unpack(c))
    detail.name:SetText(p.name .. "  |cffaaaaaa" .. ns.StatusLabel(r.score) .. "|r")
    detail.reason:SetText(r.action and ("|cffffd100Next: " .. r.action .. "|r") or (r.reason or ""))

    local list = r.breakdown or {}
    if #list == 0 then
        list = { { label = r.reason or "No breakdown for this pillar yet." } }
    end
    detail.total = #list
    detail.offset = math.max(0, math.min(detail.offset, #list - D_ROWS))
    for i, row in ipairs(detail.rows) do
        local b = list[i + detail.offset]
        if b then
            local col = ns.COLORS[ns.StatusFor(b.score)]
            row.grade:SetText(b.score and ns.Grade(b.score) or "·")
            row.grade:SetTextColor(unpack(col))
            row.label:SetText(b.label or "")
            row.note:SetText(b.note or "")
            row.bar:SetShown(b.score ~= nil)
            row.bar:SetValue(b.score or 0)
            row.bar:SetStatusBarColor(unpack(col))
            row:Show()
        else
            row:Hide()
        end
    end
    local hidden = #list - D_ROWS
    detail.more:SetText(hidden > 0 and string.format("%d-%d of %d · scroll for more",
        detail.offset + 1, math.min(#list, detail.offset + D_ROWS), #list) or "")
end

function ns:ShowPillarDetail(key)
    if not dash:IsShown() then ns:ToggleDashboard() end
    if not dash:IsShown() then return end  -- e.g. blocked in combat
    detail.key, detail.offset = key, 0
    showPage("detail")
end

-- How far along the road to 60 you are, counting XP into this level
local MAX_LEVEL = 60
local function roadPercent()
    local level = UnitLevel("player")
    if level >= MAX_LEVEL then return 100 end
    local xp, xpMax = UnitXP("player") or 0, UnitXPMax("player") or 1
    return math.floor(((level - 1) + (xpMax > 0 and xp / xpMax or 0)) / (MAX_LEVEL - 1) * 100)
end

local function update()
    if not dash:IsShown() then return end
    if currentPage == "detail" then ns:Safe("breakdown", updateDetail) end
    dash.header:SetText(string.format("%s · Level %d · %s  |cffaaaaaa(%d%% to 60)|r",
        UnitName("player"), UnitLevel("player"), ns.FormatMoney(GetMoney()), roadPercent()))
    dash.overall:SetText(ns.Grade(ns.overall))

    if currentPage == "progress" then ns:Safe("Progress tab", updateProgress) end

    -- Rows in the same fixed importance order as the pip bar; hidden pillars get no row
    local rowFor = {}
    for _, row in ipairs(dash.rows) do rowFor[row.pillar] = row; row:Hide() end
    local shown = ns.PillarsInOrder()
    for i, p in ipairs(shown) do
        local row = rowFor[p]
        if row then
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 16, -4 - (i - 1) * ROW_H)
            row:Show()
        end
    end
    fitHeight(#shown)

    for _, row in ipairs(dash.rows) do
        local r = ns.results[row.pillar.key] or {}
        local c = ns.COLORS[r.status or "gray"]
        row.grade:SetText(r.score and r.grade or "–")
        row.grade:SetTextColor(unpack(c))
        row.status:SetText(ns.StatusLabel(r.score))
        row.status:SetTextColor(unpack(c))
        -- The bar is the grade; progress (e.g. gold saved, levels to Legacy) only when ungraded
        row.bar:SetValue(r.score or (r.progress and r.progress * 100) or 0)
        row.bar:SetStatusBarColor(unpack(c))
        row.bar:SetShown(r.score ~= nil or r.progress ~= nil)  -- ungraded pillars can still show progress
        if r.action then
            row.line:SetText("|cffffd100Next: " .. r.action .. "|r")
        else
            row.line:SetText(r.reason or "")
        end
        row:SetAlpha(row.pillar.planned and 0.5 or 1)
    end
end

function ns:ToggleDashboard()
    if dash:IsShown() then
        dash:Hide()
    elseif InCombatLockdown() and ns.settings.hideInCombat then
        ns:Print("The dashboard opens after combat.")
    else
        dash:Show()
        ns:Refresh()
    end
end

updatePage = update
function ns:ShowDashboardPage(key)
    if not dash:IsShown() then ns:ToggleDashboard() end
    showPage(key)
end

dash:SetScript("OnShow", update)
ns:Listen("LOGIN", function()
    buildRows()
    showPage("pillars")
end)
ns:Listen("PLAYED_UPDATED", update)
ns:Listen("PILLARS_UPDATED", update)
ns:On("PLAYER_XP_UPDATE", update)

-- Nothing shows during combat
local reopen = false
ns:On("PLAYER_REGEN_DISABLED", function()
    if ns.settings.hideInCombat and dash:IsShown() then
        reopen = true
        dash:Hide()
    end
end)
ns:On("PLAYER_REGEN_ENABLED", function()
    if reopen then reopen = false; dash:Show() end
end)
