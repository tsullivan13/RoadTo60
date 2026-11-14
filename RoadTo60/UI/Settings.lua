-- Road to 60: settings window (/r60 settings), also reachable from the game's
-- Options > AddOns list. Built from basic button / check button / input box
-- templates so it doesn't depend on slider templates that differ between clients.
local _, ns = ...

local win = CreateFrame("Frame", "RoadTo60Settings", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
win:SetSize(560, 470)
win:SetPoint("CENTER")
win:SetFrameStrata("DIALOG")
win:SetMovable(true)
win:EnableMouse(true)
win:RegisterForDrag("LeftButton")
win:SetScript("OnDragStart", win.StartMoving)
win:SetScript("OnDragStop", win.StopMovingOrSizing)
win:SetClampedToScreen(true)
win:Hide()
tinsert(UISpecialFrames, "RoadTo60Settings")
if win.SetBackdrop then
    win:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        edgeSize = 24, insets = { left = 6, right = 6, top = 6, bottom = 6 },
    })
end
local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
close:SetPoint("TOPRIGHT", -4, -4)
local title = win:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 20, -18)
title:SetText("Road to 60 — Settings")

local controls = {}  -- each has :refresh()

local function heading(text, x, y)
    local h = win:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    h:SetPoint("TOPLEFT", x, y)
    h:SetText(text)
    return h
end

local function checkbox(label, x, y, get, set)
    local cb = CreateFrame("CheckButton", nil, win, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    cb:SetPoint("TOPLEFT", x, y)
    local t = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    t:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    t:SetText(label)
    cb:SetScript("OnClick", function(self)
        set(self:GetChecked() and true or false)
        ns:Refresh()
    end)
    cb.refresh = function() cb:SetChecked(get() and true or false) end
    controls[#controls + 1] = cb
    return cb
end

-- label  [-] value [+]
local function stepper(label, x, y, min, max, step, get, set, fmt)
    local f = CreateFrame("Frame", nil, win)
    f:SetSize(250, 24)
    f:SetPoint("TOPLEFT", x, y)
    local t = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    t:SetPoint("LEFT")
    t:SetText(label)
    local plus = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    plus:SetSize(22, 20)
    plus:SetPoint("RIGHT")
    plus:SetText("+")
    local val = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    val:SetPoint("RIGHT", plus, "LEFT", -6, 0)
    val:SetWidth(34)
    local minus = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    minus:SetSize(22, 20)
    minus:SetPoint("RIGHT", val, "LEFT", -6, 0)
    minus:SetText("-")
    local function change(d)
        local v = math.max(min, math.min(max, (get() or min) + d))
        set(math.floor(v / step + 0.5) * step)
        f.refresh()
        ns:Refresh()
    end
    plus:SetScript("OnClick", function() change(step) end)
    minus:SetScript("OnClick", function() change(-step) end)
    f.refresh = function() val:SetText(string.format(fmt or "%d", get() or 0)) end
    controls[#controls + 1] = f
    return f
end

local function input(x, y, width, get, set)
    local e = CreateFrame("EditBox", nil, win, "InputBoxTemplate")
    e:SetSize(width, 20)
    e:SetPoint("TOPLEFT", x, y)
    e:SetAutoFocus(false)
    local function commit(self)
        set(self:GetText())
        self:ClearFocus()
        e.refresh()
        ns:Refresh()
    end
    e:SetScript("OnEnterPressed", commit)
    e:SetScript("OnEditFocusLost", function(self) set(self:GetText()); e.refresh(); ns:Refresh() end)
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus(); e.refresh() end)
    e.refresh = function() e:SetText(tostring(get() or "")) end
    controls[#controls + 1] = e
    return e
end

local S = function() return ns.settings end

---------------------------------------------------------------------------
-- Left column: grading
---------------------------------------------------------------------------
local L, R = 22, 300
heading("Grading", L, -52)
stepper("Gear is stale after (levels)", L, -74, 3, 20, 1,
    function() return S().staleLevels end, function(v) S().staleLevels = v end)
stepper("Spell rank overdue after (levels)", L, -100, 0, 6, 1,
    function() return S().spellOverdue end, function(v) S().spellOverdue = v end)
stepper("Rings/neck/trinkets count from level", L, -126, 10, 60, 5,
    function() return S().jewelryLevel end, function(v) S().jewelryLevel = v end)
-- (The gold curve stays a saved setting but isn't shown: its default is tuned.)

heading("Pillars in your overall grade", L, -164)
local PILLARS = { { "gear", "Gear" }, { "spells", "Spells" }, { "quests", "Quests" },
    { "supplies", "Supplies" }, { "gold", "Gold" }, { "dungeons", "Dungeons" },
    { "professions", "Professions" }, { "legacy", "Legacy" }, { "raid", "Raid ready" } }
for i, p in ipairs(PILLARS) do
    local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
    checkbox(p[2], L + col * 125, -184 - row * 24,
        function() return not S().disabledPillars[p[1]] end,
        function(on) S().disabledPillars[p[1]] = (not on) or nil end)
end

heading("Gold goals", L, -320)
local goalRows = {}
for i = 1, 2 do
    local y = -342 - (i - 1) * 26
    local t = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    t:SetPoint("TOPLEFT", L, y - 4)
    t:SetText("Level")
    local function goal() return S().goldGoals[i] end
    input(L + 36, y, 30, function() return goal() and goal().level end, function(v)
        local n = tonumber(v)
        if n and n >= 1 and n <= 60 then
            if not goal() then S().goldGoals[i] = { level = n, cost = 0, label = "Level " .. n .. " goal" } end
            goal().level = n
        end
    end)
    local g = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    g:SetPoint("TOPLEFT", L + 76, y - 4)
    g:SetText("gold")
    -- Shows the class-aware price; typing a different one makes it yours (custom)
    input(L + 108, y, 50, function() return goal() and math.floor(ns.GoalBaseCost(goal()) / 10000) end, function(v)
        local n = tonumber(v)
        if n and n >= 0 and goal() and n * 10000 ~= ns.GoalBaseCost(goal()) then
            goal().cost, goal().custom = n * 10000, true
        end
    end)
    input(L + 166, y, 100, function() return goal() and ns.GoalLabel(goal()) end, function(v)
        if goal() and v ~= "" and v ~= ns.GoalLabel(goal()) then
            goal().label, goal().customLabel = v, true
        end
    end)
    goalRows[i] = true
end
local goalNote = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
goalNote:SetPoint("TOPLEFT", L, -398)
goalNote:SetText("More goals: /r60 goal <level> <gold> <label>")

---------------------------------------------------------------------------
-- Right column: alerts and display
---------------------------------------------------------------------------
heading("Alerts", R, -52)
local ALERTS = {
    { "pillarRed", "A pillar turns red" },
    { "trainable", "New ranks at your trainer" }, { "checkpoint", "Checkpoint report cards" },
    { "record", "New personal records" },
}
for i, a in ipairs(ALERTS) do
    checkbox(a[2], R, -72 - (i - 1) * 24,
        function() return S().alerts[a[1]] ~= false end,
        function(on) S().alerts[a[1]] = on end)
end

heading("Display", R, -206)
checkbox("Show the pip bar", R, -226,
    function() return S().pipBar.shown ~= false end,
    function(on) S().pipBar.shown = on; ns:ApplyPipBarPosition(); ns:Safe("next step", ns.UpdateNextStep, ns) end)
checkbox("Show the next best step under it", R, -250,
    function() return S().nextStep ~= false end,
    function(on) S().nextStep = on; ns:Safe("next step", ns.UpdateNextStep, ns) end)
checkbox("Lock the pip bar in place", R, -274,
    function() return S().pipBar.locked end,
    function(on) S().pipBar.locked = on end)
checkbox("Hide the dashboard in combat", R, -298,
    function() return S().hideInCombat end,
    function(on) S().hideInCombat = on end)

local resetBar = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
resetBar:SetSize(150, 22)
resetBar:SetPoint("TOPLEFT", R, -330)
resetBar:SetText("Reset pip bar position")
resetBar:SetScript("OnClick", function()
    local p = S().pipBar
    p.point, p.x, p.y, p.shown = "TOP", 0, -120, true
    ns:ApplyPipBarPosition()
    win.refresh()
end)

-- Reset everything: two clicks to confirm
local resetAll = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
resetAll:SetSize(170, 22)
resetAll:SetPoint("BOTTOMRIGHT", -20, 18)
resetAll:SetText("Reset all settings")
resetAll:SetScript("OnClick", function(self)
    if not self.armed then
        self.armed = true
        self:SetText("Click again to reset")
        C_Timer.After(3, function() self.armed = false; self:SetText("Reset all settings") end)
        return
    end
    self.armed = false
    self:SetText("Reset all settings")
    ns:ResetSettings()
    ns:ApplyPipBarPosition()
    win.refresh()
    ns:Refresh()
    ns:Print("Settings reset to defaults.")
end)

local foot = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
foot:SetPoint("BOTTOMLEFT", 22, 24)
foot:SetText("Changes apply right away. v" .. ns.version)

function win.refresh()
    for _, c in ipairs(controls) do c.refresh() end
end
win:SetToplevel(true)  -- clicking it brings it to the front
win:SetScript("OnShow", function()
    -- Only one pop-up at a time: settings replaces an open report card
    if RoadTo60Card and RoadTo60Card:IsShown() then RoadTo60Card:Hide() end
    win:Raise()
    win.refresh()
end)

function ns:ToggleSettings()
    if win:IsShown() then win:Hide() else win:Show() end
end

---------------------------------------------------------------------------
-- Entry in the game's Options > AddOns list: a button that opens this window
---------------------------------------------------------------------------
ns:Listen("LOGIN", function()
    local panel = CreateFrame("Frame")
    panel.name = "Road to 60"
    local t = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    t:SetPoint("TOPLEFT", 16, -16)
    t:SetText("Road to 60")
    local d = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    d:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -8)
    d:SetText("Settings live in their own window. You can also type /r60 settings.")
    local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    b:SetSize(200, 26)
    b:SetPoint("TOPLEFT", d, "BOTTOMLEFT", 0, -12)
    b:SetText("Open Road to 60 settings")
    b:SetScript("OnClick", function()
        if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
        if InterfaceOptionsFrame and InterfaceOptionsFrame:IsShown() then HideUIPanel(InterfaceOptionsFrame) end
        win:Show()
    end)
    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        local cat = Settings.RegisterCanvasLayoutCategory(panel, "Road to 60")
        Settings.RegisterAddOnCategory(cat)
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end
end)
