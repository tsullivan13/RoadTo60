-- Road to 60: compact pip bar — one colored pip per pillar.
-- Hover for the reason, click a pip for its breakdown or the bar for the dashboard, drag to move.
-- Layout comes from settings (pipBar.*), never decided automatically.
local _, ns = ...

local GAP = 4

local bar = CreateFrame("Frame", "RoadTo60PipBar", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
bar:SetFrameStrata("MEDIUM")
bar:SetMovable(true)
bar:EnableMouse(true)
bar:RegisterForDrag("LeftButton")
bar:SetClampedToScreen(true)
if bar.SetBackdrop then
    bar:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10, insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    bar:SetBackdropColor(0, 0, 0, 0.7)
end

bar.label = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
bar.label:SetText("R60")

bar.grade = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
bar.pips = {}

local function opts() return ns.settings.pipBar end
local function isVertical() return opts().orientation == "vertical" end
local function pipSize() return opts().pipSize or 14 end

---------------------------------------------------------------------------
-- Fade while everything is green (optional): full strength on hover or when
-- anything slips. The next-step line fades with the bar.
---------------------------------------------------------------------------
local function allGreen()
    local any = false
    for _, p in ipairs(ns.PillarsInOrder()) do
        local r = ns.results[p.key]
        if r and r.score then
            if r.status ~= "green" then return false end
            any = true
        end
    end
    return any
end

local function applyFade()
    local o = opts()
    local alpha = 1
    if o.fade and not bar:IsMouseOver() and allGreen() then alpha = (o.fadeAlpha or 35) / 100 end
    bar:SetAlpha(alpha)
    if RoadTo60NextStep then RoadTo60NextStep:SetAlpha(alpha) end
end
ns.ApplyPipBarFade = applyFade

local function onEnterBar() bar:SetAlpha(1); if RoadTo60NextStep then RoadTo60NextStep:SetAlpha(1) end end
-- Leaving the bar onto one of its pips isn't really leaving: check a moment later
local function onLeaveBar() C_Timer.After(0.2, applyFade) end
bar:SetScript("OnEnter", onEnterBar)
bar:SetScript("OnLeave", onLeaveBar)

bar:SetScript("OnMouseDown", function(self) self.moved = false end)
bar:SetScript("OnDragStart", function(self)
    self.moved = true
    if not opts().locked then self:StartMoving() end
end)
bar:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, _, x, y = self:GetPoint()
    local pos = opts()
    pos.point, pos.x, pos.y = point, x, y
end)
-- Clicking the bar itself (not a pip, not a drag) opens the dashboard
bar:SetScript("OnMouseUp", function(self, button)
    if button == "LeftButton" and not self.moved then ns:ToggleDashboard() end
end)

-- Tooltips open away from the bar, on the side the next-step line isn't using
local function tooltipAnchor()
    local side = opts().nextStepSide or "below"
    if isVertical() then
        return side == "right" and "ANCHOR_LEFT" or "ANCHOR_RIGHT"
    end
    return side == "below" and "ANCHOR_TOP" or "ANCHOR_BOTTOM"
end

local function onPipEnter(pip)
    onEnterBar()
    local p = pip.pillar
    local r = ns.results[p.key] or {}
    GameTooltip:SetOwner(pip, tooltipAnchor())
    GameTooltip:AddDoubleLine(p.name, r.score and (r.grade .. " — " .. ns.StatusLabel(r.score)) or "—",
        1, 1, 1, unpack(ns.COLORS[r.status or "gray"]))
    if r.reason then GameTooltip:AddLine(r.reason, 0.9, 0.9, 0.9, true) end
    if r.action then GameTooltip:AddLine("Next: " .. r.action, 1, 0.82, 0, true) end
    GameTooltip:AddLine("Click for the breakdown. Right-click to hide this pillar.", 0.5, 0.5, 0.5, true)
    GameTooltip:Show()
end

local function onPipLeave()
    GameTooltip_Hide()
    onLeaveBar()
end

-- Color, size and (optional) grade letter of one pip
local function stylePip(pip)
    local r = ns.results[pip.pillar.key]
    local size = pipSize()
    pip:SetSize(size, size)
    pip.tex:SetColorTexture(unpack(ns.COLORS[(r and r.status) or "gray"]))
    local font = pip.letter:GetFont()
    if font then pip.letter:SetFont(font, math.max(8, size - 4), "OUTLINE") end
    pip.letter:SetText(opts().letters and r and r.score and r.grade or "")
end

-- Place the label, the shown pips (fixed order of importance, ns.PillarsInOrder)
-- and the overall grade in a row or a column; hidden pillars get no pip and the
-- bar shrinks to fit.
local function layout()
    if #bar.pips == 0 then return end
    local pipFor = {}
    for _, pip in ipairs(bar.pips) do
        pipFor[pip.pillar] = pip
        stylePip(pip)
        pip:Hide()
    end
    local shown = ns.PillarsInOrder()
    local n, size, vertical = #shown, pipSize(), isVertical()
    local step = size + GAP

    bar:SetScale((opts().scale or 100) / 100)
    bar.label:ClearAllPoints()
    bar.grade:ClearAllPoints()
    if vertical then
        bar.label:SetPoint("TOP", bar, "TOP", 0, -8)
    else
        bar.label:SetPoint("LEFT", bar, "LEFT", 8, 0)
    end
    for i, p in ipairs(shown) do
        local pip = pipFor[p]
        if pip then
            pip:ClearAllPoints()
            local offset = (i - 1) * step
            if vertical then
                pip:SetPoint("TOP", bar.label, "BOTTOM", 0, -6 - offset)
            else
                pip:SetPoint("LEFT", bar.label, "RIGHT", 6 + offset, 0)
            end
            pip:Show()
        end
    end
    -- Fixed spot after the last pip position (pips reorder, so don't anchor to one)
    if vertical then
        bar.grade:SetPoint("TOP", bar.label, "BOTTOM", 0, -6 - n * step - 2)
        bar:SetSize(math.max(38, size + 24), 34 + n * step + 14)
    else
        bar.grade:SetPoint("LEFT", bar.label, "RIGHT", 6 + n * step + 4, 0)
        bar:SetSize(36 + n * step + 36, math.max(26, size + 12))
    end
    applyFade()
end

local function build()
    for i, p in ipairs(ns.pillars) do
        local pip = CreateFrame("Button", nil, bar)
        pip.tex = pip:CreateTexture(nil, "ARTWORK")
        pip.tex:SetAllPoints()
        -- Fill the pip and center within it; no drop shadow (the outline is enough),
        -- since the shadow's offset made letters sit off-center
        pip.letter = pip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        pip.letter:SetAllPoints()
        pip.letter:SetJustifyH("CENTER")
        pip.letter:SetJustifyV("MIDDLE")
        pip.letter:SetShadowOffset(0, 0)
        pip.pillar = p
        pip:RegisterForDrag("LeftButton")
        pip:SetScript("OnDragStart", function() bar:GetScript("OnDragStart")(bar) end)
        pip:SetScript("OnDragStop", function() bar:GetScript("OnDragStop")(bar) end)
        pip:SetScript("OnEnter", onPipEnter)
        pip:SetScript("OnLeave", onPipLeave)
        pip:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        pip:SetScript("OnClick", function(self, button)
            if button == "RightButton" then
                GameTooltip_Hide()
                ns:SetPillarTracked(self.pillar.key, false)
            else
                ns:Safe("breakdown", ns.ShowPillarDetail, ns, self.pillar.key)
            end
        end)
        bar.pips[i] = pip
    end
end

-- Position, visibility and layout all come from settings; call after changing any of them.
function ns:ApplyPipBarPosition()
    local pos = opts()
    bar:ClearAllPoints()
    bar:SetPoint(pos.point or "TOP", UIParent, pos.point or "TOP", pos.x or 0, pos.y or -120)
    bar:SetShown(pos.shown ~= false)
    layout()
    if ns.ready and ns.UpdateNextStep then ns:Safe("next step", ns.UpdateNextStep, ns) end
end

ns:Listen("LOGIN", function()
    build()
    ns:ApplyPipBarPosition()
end)

ns:Listen("PILLARS_UPDATED", function()
    layout()
    bar.grade:SetText(ns.Grade(ns.overall))
    -- Same green / yellow / red as the pips (gray until there's a grade)
    bar.grade:SetTextColor(unpack(ns.COLORS[ns.StatusFor(ns.overall)]))
end)

ns.pipBar = bar
