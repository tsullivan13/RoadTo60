-- Road to 60: alerts — a center-screen toast plus a chat line.
-- Never fires in combat: alerts queue until PLAYER_REGEN_ENABLED.
local _, ns = ...

local queue = {}

local toast = CreateFrame("Frame", "RoadTo60Toast", UIParent)
toast:SetSize(520, 40)
toast:SetPoint("TOP", UIParent, "TOP", 0, -180)
toast:SetFrameStrata("HIGH")
toast:Hide()

local bg = toast:CreateTexture(nil, "BACKGROUND")
bg:SetAllPoints()
bg:SetColorTexture(0, 0, 0, 0.6)

toast.text = toast:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
toast.text:SetPoint("CENTER")
toast.text:SetWidth(500)

local showing = false
local function showNext()
    if showing or #queue == 0 or InCombatLockdown() then return end
    showing = true
    local msg = table.remove(queue, 1)
    toast.text:SetText(msg)
    toast:SetAlpha(1)
    toast:Show()
    ns:Print(msg)
    C_Timer.After(4, function()
        UIFrameFadeOut(toast, 0.5, 1, 0)
        C_Timer.After(0.6, function()
            toast:Hide()
            showing = false
            showNext()
        end)
    end)
end

-- kind = settings.alerts key, so each alert type can be muted
function ns:Alert(kind, msg)
    if kind and ns.settings.alerts[kind] == false then return end
    queue[#queue + 1] = msg
    showNext()
end

ns:On("PLAYER_REGEN_ENABLED", function() showNext() end)

-- (No level-up summary: the next-best-step line under the pip bar already says
-- what to do, and trainer ranks and checkpoints have their own alerts.)
