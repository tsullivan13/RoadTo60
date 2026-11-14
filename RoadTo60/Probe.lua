-- Road to 60: M0 "Hello Azeroth" — prove the API calls work in Forever.
local _, ns = ...

-- Every global this addon (now or in later milestones) expects, grouped by pillar.
local API = {
    { "Core",        { "GetBuildInfo", "UnitLevel", "GetMoney", "RequestTimePlayed", "C_Timer" } },
    { "Gear",        { "GetInventoryItemLink", "C_Item.GetItemInfo", "C_Item.GetDetailedItemLevelInfo" } },
    -- Forever uses the modern C_* APIs (confirmed by other Forever addons + first probe)
    { "Spells",      { "GetNumTrainerServices", "GetTrainerServiceInfo", "GetTrainerServiceCost",
                       "GetTrainerServiceLevelReq", "C_SpellBook.IsSpellKnown", "C_Spell.GetSpellInfo",
                       "C_Spell.GetSpellSubtext", "C_TooltipInfo.GetTrainerService",
                       "GetTrainerServiceTypeFilter", "SetTrainerServiceTypeFilter", "IsTradeskillTrainer" } },
    -- Forever has trait trees, not Classic talent functions (probe, 2026-11-09)
    { "Talents",     { "C_ClassTalents.GetActiveConfigID", "C_Traits.GetConfigInfo",
                       "C_Traits.GetGroupDisplayInfoByTreeID", "C_Traits.GetGroupCurrencyInfo" } },
    { "Talents (optional)", { "C_Traits.GetTreeCurrencyInfo" } },
    { "Action bars", { "GetActionInfo" } },
    { "Professions", { "GetProfessions", "GetProfessionInfo" } },
    { "Quests",      { "C_QuestLog.GetNumQuestLogEntries", "C_QuestLog.GetInfo", "C_QuestLog.IsComplete",
                       "C_QuestLog.GetQuestObjectives" } },
    { "Quest extras", { "C_QuestLog.GetMaxNumQuestsCanAccept", "C_QuestLog.IsQuestFlaggedCompleted",
                        "C_QuestLog.GetLogIndexForQuestID", "UnitQuestTrivialLevelRange" } },
    { "Dungeons",    { "GetInstanceInfo", "IsInInstance", "GetZoneText", "ForeverDungeonJournal_NS.DB" } },
    { "Other addons", { "LevelUpInfoDB.trainers" } },
    { "Bags",        { "C_Container.GetContainerNumSlots", "C_Container.GetContainerItemInfo" } },
}

-- Events to sanity-check: registering an unknown event errors, so pcall each.
local EVENTS = {
    "PLAYER_EQUIPMENT_CHANGED", "PLAYER_MONEY", "PLAYER_LEVEL_UP",
    -- LEARNED_SPELL_IN_TAB is unknown in Forever 1.60.1; check the modern replacements
    "TRAINER_SHOW", "TRAINER_UPDATE", "TRAINER_CLOSED",
    "LEARNED_SPELL_IN_SKILL_LINE", "SPELLS_CHANGED",
    "SKILL_LINES_CHANGED", "QUEST_LOG_UPDATE", "QUEST_TURNED_IN", "ZONE_CHANGED_NEW_AREA",
    "ENCOUNTER_END", "BOSS_KILL", "TIME_PLAYED_MSG", "PLAYER_REGEN_ENABLED",
}

function ns:RunProbe()
    local version, build, date, iface = GetBuildInfo()
    ns:Print(string.format("Client %s (build %s, %s) — Interface |cffffff00%s|r", version, build, date, tostring(iface)))

    for _, group in ipairs(API) do
        local missing = {}
        for _, fn in ipairs(group[2]) do
            -- supports dotted names like "C_Item.GetItemInfo"
            local v = _G
            for part in fn:gmatch("[^%.]+") do v = type(v) == "table" and v[part] or nil end
            if v == nil then missing[#missing + 1] = fn end
        end
        if #missing == 0 then
            ns:Print(group[1] .. ": |cff33ff33all present|r")
        else
            ns:Print(group[1] .. ": |cffff3333missing|r " .. table.concat(missing, ", "))
        end
    end

    local f = CreateFrame("Frame")
    local badEvents = {}
    for _, ev in ipairs(EVENTS) do
        if not pcall(f.RegisterEvent, f, ev) then badEvents[#badEvents + 1] = ev end
    end
    f:UnregisterAllEvents()
    if #badEvents == 0 then
        ns:Print("Events: |cff33ff33all registrable|r")
    else
        ns:Print("Events: |cffff3333unknown|r " .. table.concat(badEvents, ", "))
    end
    if ns.unknownEvents then
        ns:Print("Skipped by the addon: " .. table.concat(ns.unknownEvents, ", "))
    end
end

-- /r60 info — level, gold and equipped item levels
function ns:PrintInfo()
    ns:Print(string.format("%s, level %d — %s", UnitName("player"), UnitLevel("player"), ns.FormatMoney(GetMoney())))
    for _, slot in ipairs(ns.GEAR_SLOTS or {}) do
        local info = ns.ReadSlot and ns.ReadSlot(slot.id)
        if info then
            ns:Print(string.format("  %-9s %s  ilvl %d, req %d", slot.name, info.link, info.ilvl or 0, info.req or 0))
        else
            ns:Print(string.format("  %-9s |cff888888empty|r", slot.name))
        end
    end
end
