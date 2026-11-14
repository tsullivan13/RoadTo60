-- Road to 60: settings window (/r60 settings), also reachable from the game's
-- Options > AddOns list. Built from basic button / check button / input box
-- templates so it doesn't depend on slider templates that differ between clients.
-- Three tabs: General (grading, gold goals, alerts), Pillars (track + weight),
-- Display (pip bar, next step, minimap).
local _, ns = ...

local win = CreateFrame("Frame", "RoadTo60Settings", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
win:SetSize(560, 480)
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

---------------------------------------------------------------------------
-- Control helpers (each takes the page it goes on)
---------------------------------------------------------------------------
local function heading(parent, text, x, y)
    local h = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    h:SetPoint("TOPLEFT", x, y)
    h:SetText(text)
    return h
end

local function note(parent, text, x, y, width)
    local n = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    n:SetPoint("TOPLEFT", x, y)
    if width then n:SetWidth(width); n:SetJustifyH("LEFT") end
    n:SetText(text)
    return n
end

local function checkbox(parent, label, x, y, get, set)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
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
local function stepper(parent, label, x, y, min, max, step, get, set, fmt, width)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(width or 240, 24)
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
    val:SetWidth(40)
    local minus = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    minus:SetSize(22, 20)
    minus:SetPoint("RIGHT", val, "LEFT", -6, 0)
    minus:SetText("-")
    -- The label stops before the buttons (cut short rather than running into them)
    t:SetPoint("RIGHT", minus, "LEFT", -6, 0)
    t:SetJustifyH("LEFT")
    t:SetWordWrap(false)
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

-- label  [ value ]  — click the button to step through options = { {value, text}, ... }
local function cycler(parent, label, x, y, options, get, set)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(240, 24)
    f:SetPoint("TOPLEFT", x, y)
    local t = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    t:SetPoint("LEFT")
    t:SetText(label)
    local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    b:SetSize(96, 20)
    b:SetPoint("RIGHT")
    t:SetPoint("RIGHT", b, "LEFT", -6, 0)
    t:SetJustifyH("LEFT")
    t:SetWordWrap(false)
    local function index()
        for i, o in ipairs(options) do if o[1] == get() then return i end end
        return 1
    end
    b:SetScript("OnClick", function()
        set(options[index() % #options + 1][1])
        f.refresh()
    end)
    f.refresh = function() b:SetText(options[index()][2]) end
    controls[#controls + 1] = f
    return f
end

local function input(parent, x, y, width, get, set)
    local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
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

local function button(parent, text, x, y, width, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 22)
    b:SetPoint("TOPLEFT", x, y)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

local S = function() return ns.settings end
local function bar() return ns.settings.pipBar end
local function relayout() ns:ApplyPipBarPosition() end

---------------------------------------------------------------------------
-- Tabs
---------------------------------------------------------------------------
local pages, tabs = {}, {}
local TOP = -84   -- where page content starts
local L, R = 22, 300

local function showPage(name)
    for key, page in pairs(pages) do page:SetShown(key == name) end
    for key, tab in pairs(tabs) do
        -- The open tab stays lit
        if key == name then tab:LockHighlight() else tab:UnlockHighlight() end
    end
    win.page = name
end

local function newPage(key, label, i)
    local page = CreateFrame("Frame", nil, win)
    page:SetAllPoints()
    page:Hide()
    pages[key] = page
    local tab = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    tab:SetSize(100, 22)
    tab:SetPoint("TOPLEFT", 20 + (i - 1) * 106, -46)
    tab:SetText(label)
    tab:SetScript("OnClick", function() showPage(key) end)
    tabs[key] = tab
    return page
end

---------------------------------------------------------------------------
-- General: grading, gold goals, alerts
---------------------------------------------------------------------------
local general = newPage("general", "General", 1)

heading(general, "Grading", L, TOP)
-- Wider than the default so the labels fit beside the buttons
local GW = 262
stepper(general, "Gear is stale after (levels)", L, TOP - 22, 3, 20, 1,
    function() return S().staleLevels end, function(v) S().staleLevels = v end, nil, GW)
stepper(general, "Spell rank late after (levels)", L, TOP - 48, 0, 6, 1,
    function() return S().spellOverdue end, function(v) S().spellOverdue = v end, nil, GW)
stepper(general, "Rings, neck, trinkets from level", L, TOP - 74, 10, 60, 5,
    function() return S().jewelryLevel end, function(v) S().jewelryLevel = v end, nil, GW)
-- (The gold curve stays a saved setting but isn't shown: its default is tuned.)

heading(general, "Gold goals", L, TOP - 116)
for i = 1, 2 do
    local y = TOP - 138 - (i - 1) * 26
    local t = general:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    t:SetPoint("TOPLEFT", L, y - 4)
    t:SetText("Level")
    local function goal() return S().goldGoals[i] end
    input(general, L + 36, y, 30, function() return goal() and goal().level end, function(v)
        local n = tonumber(v)
        if n and n >= 1 and n <= 60 then
            if not goal() then S().goldGoals[i] = { level = n, cost = 0, label = "Level " .. n .. " goal" } end
            goal().level = n
        end
    end)
    local g = general:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    g:SetPoint("TOPLEFT", L + 76, y - 4)
    g:SetText("gold")
    -- Shows the class-aware price; typing a different one makes it yours (custom)
    input(general, L + 108, y, 50, function() return goal() and math.floor(ns.GoalBaseCost(goal()) / 10000) end, function(v)
        local n = tonumber(v)
        if n and n >= 0 and goal() and n * 10000 ~= ns.GoalBaseCost(goal()) then
            goal().cost, goal().custom = n * 10000, true
        end
    end)
    input(general, L + 166, y, 100, function() return goal() and ns.GoalLabel(goal()) end, function(v)
        if goal() and v ~= "" and v ~= ns.GoalLabel(goal()) then
            goal().label, goal().customLabel = v, true
        end
    end)
end
note(general, "More goals: /r60 goal <level> <gold> <label>", L, TOP - 194)

heading(general, "Alerts", R, TOP)
local ALERTS = {
    { "pillarRed", "A pillar turns red" },
    { "trainable", "New ranks at your trainer" },
    { "checkpoint", "Checkpoint report cards" },
    { "record", "New personal records" },
    { "levelRecap", "Level-up recap in chat" },
}
for i, a in ipairs(ALERTS) do
    checkbox(general, a[2], R, TOP - 20 - (i - 1) * 24,
        function() return S().alerts[a[1]] ~= false end,
        function(on) S().alerts[a[1]] = on end)
end

heading(general, "Windows", R, TOP - 150)
checkbox(general, "Hide the dashboard in combat", R, TOP - 170,
    function() return S().hideInCombat end,
    function(on) S().hideInCombat = on end)
checkbox(general, "Share button on report cards", R, TOP - 194,
    function() return S().cardShare ~= false end,
    function(on) S().cardShare = on end)

---------------------------------------------------------------------------
-- Pillars: which to track, and how much each counts in the overall grade
---------------------------------------------------------------------------
local pillarsPage = newPage("pillars", "Pillars", 2)

heading(pillarsPage, "Pillars to track", L, TOP)
note(pillarsPage, "Unchecked pillars disappear from the bar, dashboard and report cards. "
    .. "Weight is how much a pillar counts in your overall grade; 0% keeps it visible but ungraded. "
    .. "Right-click a pip to hide it quickly.", L, TOP - 18, 500)

local PILLARS = { { "gear", "Gear" }, { "spells", "Spells" }, { "quests", "Quests" },
    { "supplies", "Supplies" }, { "gold", "Gold" }, { "dungeons", "Dungeons" },
    { "professions", "Professions" }, { "legacy", "Legacy" }, { "raid", "Raid ready" } }
local ROW0 = TOP - 60
for i, p in ipairs(PILLARS) do
    local y = ROW0 - (i - 1) * 26
    checkbox(pillarsPage, p[2], L, y,
        function() return not S().disabledPillars[p[1]] end,
        function(on) S().disabledPillars[p[1]] = (not on) or nil end)
    if p[1] == "raid" then
        -- Raid ready reads the other pillars, so it never counts in the overall grade
        note(pillarsPage, "a checklist of the others; not in the overall grade", L + 170, y - 6)
    else
        stepper(pillarsPage, "Weight", L + 170, y, 0, 200, 25,
            function() return S().pillarWeights[p[1]] or 100 end,
            function(v) S().pillarWeights[p[1]] = (v ~= 100) and v or nil end, "%d%%", 200)
    end
end
button(pillarsPage, "Reset weights", L, ROW0 - #PILLARS * 26 - 8, 130, function()
    wipe(S().pillarWeights)
    win.refresh()
    ns:Refresh()
end)

---------------------------------------------------------------------------
-- Display: pip bar, next best step, minimap and broker
---------------------------------------------------------------------------
local display = newPage("display", "Display", 3)

heading(display, "Pip bar", L, TOP)
checkbox(display, "Show the pip bar", L, TOP - 20,
    function() return bar().shown ~= false end,
    function(on) bar().shown = on; relayout() end)
checkbox(display, "Lock it in place", L, TOP - 44,
    function() return bar().locked end,
    function(on) bar().locked = on end)
cycler(display, "Direction", L + 4, TOP - 72,
    { { "horizontal", "Row" }, { "vertical", "Column" } },
    function() return bar().orientation end,
    function(v) bar().orientation = v; relayout() end)
stepper(display, "Scale", L + 4, TOP - 98, 50, 200, 10,
    function() return bar().scale or 100 end,
    function(v) bar().scale = v; relayout() end, "%d%%")
stepper(display, "Pip size", L + 4, TOP - 124, 10, 24, 2,
    function() return bar().pipSize or 14 end,
    function(v) bar().pipSize = v; relayout() end, "%dpx")
checkbox(display, "Grade letter on each pip", L, TOP - 150,
    function() return bar().letters end,
    function(on) bar().letters = on; relayout() end)
checkbox(display, "Fade while everything is green", L, TOP - 174,
    function() return bar().fade end,
    function(on) bar().fade = on; relayout() end)
stepper(display, "Faded opacity", L + 4, TOP - 200, 10, 80, 5,
    function() return bar().fadeAlpha or 35 end,
    function(v) bar().fadeAlpha = v; relayout() end, "%d%%")
button(display, "Reset pip bar position", L, TOP - 236, 160, function()
    local p = bar()
    p.point, p.x, p.y, p.shown = "TOP", 0, -120, true
    relayout()
    win.refresh()
end)

heading(display, "Next best step", R, TOP)
checkbox(display, "Show the next best step", R, TOP - 20,
    function() return S().nextStep ~= false end,
    function(on) S().nextStep = on; ns:Safe("next step", ns.UpdateNextStep, ns) end)
cycler(display, "Position", R + 4, TOP - 48,
    { { "below", "Below" }, { "above", "Above" }, { "left", "Left" }, { "right", "Right" } },
    function() return bar().nextStepSide end,
    function(v) bar().nextStepSide = v; ns:Safe("next step", ns.UpdateNextStep, ns) end)

checkbox(display, "In a box", R, TOP - 74,
    function() return bar().nextStepBox ~= false end,
    function(on) bar().nextStepBox = on; ns:Safe("next step", ns.UpdateNextStep, ns) end)
stepper(display, "Wrap at width", R + 4, TOP - 100, 160, 640, 20,
    function() return bar().nextStepWidth or 320 end,
    function(v) bar().nextStepWidth = v; ns:Safe("next step", ns.UpdateNextStep, ns) end, "%dpx")

heading(display, "Elsewhere", R, TOP - 142)
checkbox(display, "Minimap button", R, TOP - 162,
    function() return S().minimap.shown end,
    function(on) S().minimap.shown = on; ns:ApplyMinimapButton() end)
checkbox(display, "Titan / ChocolateBar feed", R, TOP - 186,
    function() return S().dataBroker ~= false end,
    function(on)
        S().dataBroker = on
        ns:Print("The broker feed change applies after /reload.")
    end)
note(display, "Needs a LibDataBroker display addon. Applies after /reload.", R + 4, TOP - 212, 230)

---------------------------------------------------------------------------
-- Always visible: reset everything, version
---------------------------------------------------------------------------
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
    ns:ApplyMinimapButton()
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
    showPage(win.page or "general")
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
