-- Road to 60: slash commands.
local _, ns = ...

local function parseGold(s)
    -- accepts "100", "100g", "100g50s"
    if not s then return nil end
    local g = tonumber(s:match("^(%d+)g?")) or 0
    local sv = tonumber(s:match("(%d+)s")) or 0
    return g * 10000 + sv * 100
end

local commands = {}

commands.help = function()
    ns:Print("commands:")
    print("  /r60 — toggle the dashboard")
    print("  /r60 settings — thresholds, alerts, pillars, gold goals")
    print("  /r60 progress — checkpoint cards, records and your ghost run")
    print("  /r60 card [level] — a saved checkpoint card, or a preview of today's")
    print("  /r60 next — every next-step option, ranked (\"here\" = doable where you stand)")
    print("  /r60 goals, /r60 goal <level> <gold> [label], /r60 delgoal <level> — gold goals")
    print("  /r60 share [party|raid|guild|say] — post your grades in one line")
    print("  /r60 bar [show|hide|reset] — the compact pip bar")
    print("  /r60 mute <pillarRed|trainable|checkpoint|record> — toggle an alert type")
    print("  /r60 debug — tools for troubleshooting")
end

-- Troubleshooting tools; each saves its output to disk for a /reload.
-- The old direct names (/r60 probe etc.) still work.
local DEBUG = {
    { "probe", "which game API calls exist in this client" },
    { "info", "level, gold and equipped item levels" },
    { "spells", "ranks waiting, coming next, and what the addon has learned" },
    { "profs", "profession skill, caps and tier unlocks" },
    { "quests", "every quest in your log with its status" },
    { "dungeons", "every dungeon: level range, quests, runs" },
    { "supplies", "food, drink, potions, bandages and class supplies in your bags" },
    { "talents", "raw talent-point data (to check the unspent count)" },
    { "legacy", "scan for Forever's Legacy System data" },
}
commands.supplies = function()
    ns:Capture("supplies", function()
        local s = ns.ScanSupplies()
        ns:Print(string.format("food %d · drink %d · healing potions %d · mana potions %d · bandages %d · ammo %d · soul shards %d · poisons %d%s",
            s.food, s.drink, s.healPotion, s.manaPotion, s.bandage, s.ammo, s.shards, s.poison,
            s.pending and " (some items still loading)" or ""))
        local h = ns.HearthStatus()
        if h then
            ns:Print(string.format("hearthstone: %s (zone %s, last there at level %s)", h.bind, h.zone, tostring(h.lastLevel)))
        end
    end)
end

-- Raw talent data, so the unspent-points reading can be checked against Forever
commands.talents = function()
    ns:Capture("talents", function()
        ns:Print("unspent (as read): " .. tostring(ns.UnspentTalentPoints()))
        local configID, treeID, entries = ns.TalentCurrencies()
        ns:Print(string.format("configID %s, treeID %s, %d currency entries", tostring(configID), tostring(treeID),
            entries and #entries or 0))
        for i, c in ipairs(entries or {}) do
            local parts = {}
            for k, v in pairs(c) do parts[#parts + 1] = tostring(k) .. "=" .. tostring(v) end
            table.sort(parts)
            ns:Print(string.format("  %d: %s", i, table.concat(parts, ", ")))
        end
    end)
end

commands.debug = function(args)
    local sub, rest = (args or ""):match("^(%S*)%s*(.*)$")
    if sub and sub ~= "" and commands[sub] then return commands[sub](rest) end
    ns:Print("debug tools (output is saved to disk; /reload to write it):")
    for _, d in ipairs(DEBUG) do print(string.format("  /r60 debug %s — %s", d[1], d[2])) end
end

commands.spells = function()
    ns:Capture("spells", function()
        local waiting, upcoming, hasData = ns.SpellStatus()
        local _, class = UnitClass("player")
        local n = 0
        for _ in pairs(ns.db.learned[class] or {}) do n = n + 1 end
        local visit = ns.char.lastTrainerVisit
        ns:Print(string.format("%s: %d ranks learned from trainers%s", class, n,
            visit and string.format(" (last visit at level %d, %d rows)", visit.level, visit.rows) or ", no visit yet"))
        if not hasData then return ns:Print("Visit your class trainer to fill this in.") end
        ns:Print(#waiting .. " waiting:")
        for _, s in ipairs(waiting) do
            ns:Print(string.format("  %d  %s  %s  [%d]", s.level, ns.SpellLabel(s), ns.FormatMoney(s.cost), s.id))
        end
        ns:Print("Coming up:")
        for i = 1, math.min(10, #upcoming) do
            local s = upcoming[i]
            ns:Print(string.format("  %d  %s  %s  [%d]", s.level, ns.SpellLabel(s), ns.FormatMoney(s.cost), s.id))
        end
    end)
end

commands.profs = function()
    ns:Capture("profs", function()
        -- Raw positions first, so a client that orders them differently shows up
        local raw = GetProfessions and { GetProfessions() } or {}
        local parts = {}
        for i = 1, math.max(6, #raw) do parts[#parts + 1] = i .. "=" .. tostring(raw[i]) end
        ns:Print("GetProfessions positions: " .. table.concat(parts, " "))
        local list = ns.ReadProfessions()
        if #list == 0 then return ns:Print("No professions found.") end
        for _, p in ipairs(list) do
            ns:Print(string.format("%s %d/%d (%s, skillLine %s, position %s)", p.name, p.skill, p.max,
                p.primary and "primary" or "secondary", tostring(p.skillLine), tostring(p.position)))
        end
    end)
end

commands.quests = function()
    ns:Capture("quests", function()
        local log = ns.ReadQuestLog()
        ns:Print(string.format("%d/%d quests", #log.quests, log.max))
        for _, q in ipairs(log.quests) do
            ns:Print(string.format("  [%d] %s — %s%s%s%s  (id %d, %s)", q.level, q.title,
                q.complete and "ready" or "open", q.gray and ", gray" or "", q.red and ", red" or "",
                q.group and ", group" or "", q.id, tostring(q.zone)))
        end
    end)
end

commands.dungeons = function()
    ns:Capture("dungeons", function()
        local list = ns.DungeonStatus()
        if not list then return ns:Print("ForeverDungeonJournal not loaded.") end
        for _, d in ipairs(list) do
            ns:Print(string.format("%s%s %d-%d: quests %d done, %d open (%d XP), %d in log; %s",
                d.forever and "* " or "  ", d.name, d.min, d.max, d.done, d.open, d.xpOpen, d.inLog,
                d.run and string.format("run %dx, %d clears", d.run.runs or 0, d.run.clears or 0) or "not run"))
        end
        ns:Print("* = new in Forever")
    end)
end

commands.card = function(args)
    local lvl = tonumber(args)
    if lvl then
        local c = ns.char.checkpoints[lvl]
        if c then return ns:ShowCard(c) end
        return ns:Print("No card saved for level " .. lvl .. ".")
    end
    ns:ShowCard(ns:BuildCard(UnitLevel("player")), true)
end
commands.next = function()
    ns:Capture("next", function()
        local list = ns.NextStepCandidates()
        if #list == 0 then return ns:Print("Nothing to do right now — you're on pace.") end
        for i, c in ipairs(list) do
            ns:Print(string.format("%d. %s%s  (%s %d to %d, value %.1f)", i, c.here and "[here] " or "",
                c.text, c.pillar, math.floor(c.before or 0), math.floor(c.after or 0), c.value))
        end
    end)
end
commands.settings = function() ns:ToggleSettings() end
commands.config, commands.options = commands.settings, commands.settings
commands.share = function(args) ns:Share(args) end
commands.legacy = function()
    local found = ns:ScanLegacy()
    ns:Print(string.format("Legacy scan: %d entries found — saved to disk, /reload so I can read them.", #found))
    for i = 1, math.min(8, #found) do print("  " .. found[i]) end
    ns:Refresh()
end
commands.records = function() ns:ShowDashboardPage("progress") end
commands.checkpoints = commands.records
commands.progress = commands.records

commands.overdue = function(args)
    local n = tonumber(args)
    if not n or n < 0 then return ns:Print("usage: /r60 overdue 2") end
    ns.settings.spellOverdue = n
    ns:Print("A trainable rank is overdue after " .. n .. " levels.")
    ns:Refresh()
end

commands.info = function() ns:Capture("info", function() ns:PrintInfo() end) end
commands.probe = function()
    ns:Capture("probe", function()
        ns:RunProbe()
        ns:PrintInfo()
        ns:Print("--- pillars")
        for _, p in ipairs(ns.pillars) do
            local r = ns.results[p.key] or {}
            ns:Print(string.format("%s: %s (%s) %s %s", p.name, r.grade or "-",
                tostring(r.score), r.reason or "", r.action and ("-> " .. r.action) or ""))
        end
    end)
end

commands.goals = function()
    for _, g in ipairs(ns.settings.goldGoals) do
        local cost, base = ns.GoalCost(g), ns.GoalBaseCost(g)
        ns:Print(string.format("Level %d: %s — %s%s%s", g.level, ns.FormatMoney(cost), ns.GoalLabel(g),
            cost < base and (" (" .. ns.FormatMoney(base) .. " before Honored discount)") or "",
            g.custom and " [your price]" or ""))
    end
end

commands.goal = function(args)
    local lvl, gold, label = args:match("^(%d+)%s+(%S+)%s*(.*)$")
    lvl = tonumber(lvl)
    local cost = parseGold(gold)
    if not lvl or not cost or cost <= 0 then
        return ns:Print("usage: /r60 goal 40 100 Riding + mount")
    end
    for _, g in ipairs(ns.settings.goldGoals) do
        if g.level == lvl then
            g.cost, g.custom = cost, true  -- your price now wins over the class default
            if label ~= "" then g.label, g.customLabel = label, true end
            ns:Print(string.format("Goal at %d is now %s.", lvl, ns.FormatMoney(cost)))
            return ns:Refresh()
        end
    end
    table.insert(ns.settings.goldGoals, { level = lvl, cost = cost, label = label ~= "" and label or ("Level " .. lvl .. " goal") })
    ns:Print(string.format("Added goal: %s by %d.", ns.FormatMoney(cost), lvl))
    ns:Refresh()
end

commands.delgoal = function(args)
    local lvl = tonumber(args)
    for i, g in ipairs(ns.settings.goldGoals) do
        if g.level == lvl then
            table.remove(ns.settings.goldGoals, i)
            ns:Print("Removed the level " .. lvl .. " goal.")
            return ns:Refresh()
        end
    end
    ns:Print("No goal at level " .. tostring(args) .. ".")
end

commands.stale = function(args)
    local n = tonumber(args)
    if not n or n < 1 then return ns:Print("usage: /r60 stale 8") end
    ns.settings.staleLevels = n
    ns:Print("Gear counts as stale after " .. n .. " levels.")
    ns:Refresh()
end

commands.bar = function(args)
    local pos = ns.settings.pipBar
    if args == "hide" then
        pos.shown = false
    elseif args == "reset" then
        pos.point, pos.x, pos.y, pos.shown = "TOP", 0, -120, true
    else
        pos.shown = true
    end
    ns:ApplyPipBarPosition()
end

commands.mute = function(args)
    local a = ns.settings.alerts
    if a[args] == nil then return ns:Print("alert types: pillarRed, trainable, checkpoint, record") end
    a[args] = not a[args]
    ns:Print(args .. " alerts " .. (a[args] and "on" or "muted") .. ".")
end

SLASH_ROADTO601 = "/r60"
SLASH_ROADTO602 = "/roadto60"
SlashCmdList.ROADTO60 = function(msg)
    msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local cmd, rest = msg:match("^(%S*)%s*(.*)$")
    cmd = (cmd or ""):lower()
    if cmd == "" then return ns:Safe("/r60", ns.ToggleDashboard, ns) end
    local fn = commands[cmd]
    if fn then ns:Safe("/r60 " .. cmd, fn, rest) else commands.help() end
end
