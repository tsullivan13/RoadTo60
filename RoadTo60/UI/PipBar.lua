-- Road to 60: compact pip bar — one colored pip per pillar.
-- Hover for the reason, click a pip for its breakdown or the bar for the dashboard, drag to move.
local _, ns = ...

local PIP, GAP = 14, 4

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
bar.label:SetPoint("LEFT", 8, 0)
bar.label:SetText("R60")

bar.grade = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
bar.pips = {}

bar:SetScript("OnMouseDown", function(self) self.moved = false end)
bar:SetScript("OnDragStart", function(self)
    self.moved = true
    if not ns.settings.pipBar.locked then self:StartMoving() end
end)
bar:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, _, x, y = self:GetPoint()
    local pos = ns.settings.pipBar
    pos.point, pos.x, pos.y = point, x, y
end)
-- Clicking the bar itself (not a pip, not a drag) opens the dashboard
bar:SetScript("OnMouseUp", function(self, button)
    if button == "LeftButton" and not self.moved then ns:ToggleDashboard() end
end)

local function onPipEnter(pip)
    local p = pip.pillar
    local r = ns.results[p.key] or {}
    GameTooltip:SetOwner(pip, "ANCHOR_BOTTOM")
    GameTooltip:AddDoubleLine(p.name, r.score and (r.grade .. " — " .. ns.StatusLabel(r.score)) or "—",
        1, 1, 1, unpack(ns.COLORS[r.status or "gray"]))
    if r.reason then GameTooltip:AddLine(r.reason, 0.9, 0.9, 0.9, true) end
    if r.action then GameTooltip:AddLine("Next: " .. r.action, 1, 0.82, 0, true) end
    GameTooltip:AddLine("Click for the breakdown.", 0.5, 0.5, 0.5)
    GameTooltip:Show()
end

local function build()
    for i, p in ipairs(ns.pillars) do
        local pip = CreateFrame("Button", nil, bar)
        pip:SetSize(PIP, PIP)
        pip:SetPoint("LEFT", bar.label, "RIGHT", 6 + (i - 1) * (PIP + GAP), 0)
        pip.tex = pip:CreateTexture(nil, "ARTWORK")
        pip.tex:SetAllPoints()
        pip.tex:SetColorTexture(unpack(ns.COLORS.gray))
        pip.pillar = p
        pip:RegisterForDrag("LeftButton")
        pip:SetScript("OnDragStart", function() bar:GetScript("OnDragStart")(bar) end)
        pip:SetScript("OnDragStop", function() bar:GetScript("OnDragStop")(bar) end)
        pip:SetScript("OnEnter", onPipEnter)
        pip:SetScript("OnLeave", GameTooltip_Hide)
        pip:SetScript("OnClick", function(self) ns:Safe("breakdown", ns.ShowPillarDetail, ns, self.pillar.key) end)
        bar.pips[i] = pip
    end
    -- Fixed spot after the last pip position (pips reorder, so don't anchor to one)
    bar.grade:SetPoint("LEFT", bar.label, "RIGHT", 6 + #ns.pillars * (PIP + GAP) + 4, 0)
    bar:SetSize(36 + #ns.pillars * (PIP + GAP) + 36, PIP + 12)
end

function ns:ApplyPipBarPosition()
    local pos = ns.settings.pipBar
    bar:ClearAllPoints()
    bar:SetPoint(pos.point or "TOP", UIParent, pos.point or "TOP", pos.x or 0, pos.y or -120)
    bar:SetShown(pos.shown ~= false)
end

ns:Listen("LOGIN", function()
    build()
    ns:ApplyPipBarPosition()
end)

-- Pips in a fixed order of importance (ns.PillarsInOrder); hidden pillars get no pip
-- and the bar shrinks to fit.
ns:Listen("PILLARS_UPDATED", function()
    local pipFor = {}
    for _, pip in ipairs(bar.pips) do
        local r = ns.results[pip.pillar.key]
        pip.tex:SetColorTexture(unpack(ns.COLORS[(r and r.status) or "gray"]))
        pipFor[pip.pillar] = pip
        pip:Hide()
    end
    local shown = ns.PillarsInOrder()
    for i, p in ipairs(shown) do
        local pip = pipFor[p]
        if pip then
            pip:ClearAllPoints()
            pip:SetPoint("LEFT", bar.label, "RIGHT", 6 + (i - 1) * (PIP + GAP), 0)
            pip:Show()
        end
    end
    bar.grade:ClearAllPoints()
    bar.grade:SetPoint("LEFT", bar.label, "RIGHT", 6 + #shown * (PIP + GAP) + 4, 0)
    bar:SetWidth(36 + #shown * (PIP + GAP) + 36)
    bar.grade:SetText(ns.Grade(ns.overall))
end)

ns.pipBar = bar
