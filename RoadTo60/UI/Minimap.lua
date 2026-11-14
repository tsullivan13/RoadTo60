-- Road to 60: minimap button and a LibDataBroker feed (Titan Panel, ChocolateBar,
-- Bazooka and friends). Both are optional in settings. The broker feed needs a
-- display addon that ships LibDataBroker; Road to 60 doesn't bundle it.
local _, ns = ...

local ICON = "Interface\\Icons\\Ability_Rogue_Sprint"

-- Shared tooltip: overall grade, then each shown pillar
local function fillTooltip(tt)
    tt:AddDoubleLine("Road to 60", ns.Grade(ns.overall), 1, 0.82, 0,
        unpack(ns.COLORS[ns.StatusFor(ns.overall)]))
    for _, p in ipairs(ns.PillarsInOrder()) do
        local r = ns.results[p.key] or {}
        tt:AddDoubleLine(p.name, r.score and r.grade or "—", 1, 1, 1, unpack(ns.COLORS[r.status or "gray"]))
    end
    tt:AddLine("Click: dashboard · Right-click: settings", 0.5, 0.5, 0.5)
end

local function onClick(button)
    if button == "RightButton" then ns:ToggleSettings() else ns:ToggleDashboard() end
end

---------------------------------------------------------------------------
-- Minimap button: drag it around the minimap's edge
---------------------------------------------------------------------------
local btn

local function placeButton()
    local angle = math.rad(ns.settings.minimap.angle or 200)
    local r = (Minimap:GetWidth() / 2) + 5
    btn:ClearAllPoints()
    btn:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * r, math.sin(angle) * r)
end

local function createButton()
    btn = CreateFrame("Button", "RoadTo60MinimapButton", Minimap)
    btn:SetSize(31, 31)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel(8)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:RegisterForDrag("LeftButton")
    btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetSize(20, 20)
    bg:SetPoint("TOPLEFT", 7, -5)
    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(ICON)
    icon:SetSize(17, 17)
    icon:SetPoint("TOPLEFT", 7, -6)
    local border = btn:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")

    btn:SetScript("OnClick", function(_, button) onClick(button) end)
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        fillTooltip(GameTooltip)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", GameTooltip_Hide)
    btn:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            ns.settings.minimap.angle = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
            placeButton()
        end)
    end)
    btn:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
end

function ns:ApplyMinimapButton()
    local on = ns.settings.minimap.shown
    if on and not btn then createButton() end
    if btn then
        btn:SetShown(on and true or false)
        if on then placeButton() end
    end
end

---------------------------------------------------------------------------
-- LibDataBroker feed: "R60 B", same tooltip and clicks
---------------------------------------------------------------------------
local feed

local function createFeed()
    local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
    if not LDB then return end
    feed = LDB:NewDataObject("Road to 60", {
        type = "data source",
        label = "Road to 60",
        icon = ICON,
        text = "R60",
        OnClick = function(_, button) onClick(button) end,
        OnTooltipShow = fillTooltip,
    })
end

ns:Listen("LOGIN", function()
    ns:ApplyMinimapButton()
    -- A broker feed can't be removed once registered, so turning it off applies after /reload
    if ns.settings.dataBroker then createFeed() end
end)

ns:Listen("PILLARS_UPDATED", function()
    if feed then feed.text = "R60 " .. ns.Grade(ns.overall) end
end)
