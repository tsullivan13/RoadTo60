-- Road to 60: Pet pillar (Hunters) — a pet that falls behind is the most common
-- class-specific way to be underprepared. Shown for Hunters from level 10; switch
-- it off like any pillar in Settings > Pillars.
--
-- Reads only the game's pet functions (level, happiness, training points), so it
-- doesn't depend on Forever's class changes. Every call is guarded: a function
-- Forever lacks just leaves that row out.
local _, ns = ...

local SHOWN_FROM = 10     -- Tame Beast comes from the level 10 class quest
local NO_PET_FROM = 12    -- give a couple of levels to finish that quest
local SPARE_POINTS = 30   -- unspent training points worth a trip to the pet trainer

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c = pcall(fn, ...)
    if ok then return a, b, c end
end

local Pet = {
    key = "pet", name = "Pet", order = 4.5, weight = 0.75,
    events = { "UNIT_PET", "UNIT_HAPPINESS", "UNIT_LEVEL", "PET_UI_UPDATE",
        "PET_BAR_UPDATE", "PLAYER_LEVEL_UP", "UNIT_PET_TRAINING_POINTS" },
}

function Pet:Hidden()
    local _, class = UnitClass("player")
    return class ~= "HUNTER" or UnitLevel("player") < SHOWN_FROM
end

-- 100 while the pet is within a level of you, then down quickly: a pet a few
-- levels behind loses fights it should win
local function gapScore(gap)
    if gap <= 1 then return 100 elseif gap == 2 then return 85
    elseif gap == 3 then return 65 elseif gap == 4 then return 45 end
    return 25
end

local HAPPINESS = {
    [1] = { score = 30, note = "unhappy — it deals less damage and may run off" },
    [2] = { score = 70, note = "content" },
    [3] = { score = 100, note = "happy" },
}

function Pet:Evaluate()
    local level = UnitLevel("player")
    local res = { breakdown = {}, details = {} }
    local out = UnitExists("pet") and (select(2, call(HasPetUI)) ~= false)

    -- Remember the pet while it's out, so a dismissed or stabled pet still counts
    if out then
        ns.char.pet = { name = UnitName("pet"), level = UnitLevel("pet") }
    end
    local pet = ns.char.pet

    if not pet then
        if level < NO_PET_FROM then
            res.reason = "Tame your first pet with the level 10 Hunter quest."
            return res
        end
        res.score = 20
        res.reason = "No pet seen yet."
        res.action = "Tame a pet (Hunter class quest from level 10)."
        res.breakdown[1] = { label = "Pet", score = 20, note = "none seen on this character" }
        return res
    end

    local rows, worst = {}, nil
    local function row(label, score, weight, note, action, here)
        res.breakdown[#res.breakdown + 1] = { label = label, score = score, note = note }
        rows[#rows + 1] = { score = score, weight = weight }
        if action and score < 90 and (not worst or score < worst.score) then
            worst = { score = score, action = action, here = here }
        end
    end

    -- Level: the pet only gains experience while it's out, so the remembered level holds
    local gap = level - (pet.level or level)
    row("Level", gapScore(gap), 2,
        string.format("%s is level %d%s", pet.name or "Your pet", pet.level or 0,
            gap > 0 and string.format(" (%d behind)", gap) or "")
            .. (out and "" or " · last seen, not out now"),
        string.format("Your pet is %d levels behind: keep it out to catch up, or tame one nearer your level.", gap))

    if out then
        -- Happiness: 1 unhappy, 2 content, 3 happy
        local happy = call(GetPetHappiness)
        local h = HAPPINESS[happy]
        if h then row("Happiness", h.score, 1, h.note, "Feed your pet.", true) end

        -- Training points left to spend at a pet trainer
        local total, spent = call(GetPetTrainingPoints)
        if type(total) == "number" and type(spent) == "number" then
            local spare = total - spent
            row("Training points", spare >= SPARE_POINTS and 70 or 100, 0.5,
                spare > 0 and string.format("%d unspent", spare) or "all spent",
                string.format("Spend %d pet training points at a pet trainer.", spare))
        end
    end

    local total, weights = 0, 0
    for _, r in ipairs(rows) do total, weights = total + r.score * r.weight, weights + r.weight end
    res.score = math.floor(total / weights + 0.5)
    res.action = worst and worst.action
    res.actionHere = worst and worst.here
    res.reason = worst and (out and "Your pet needs attention." or "Your pet is falling behind.")
        or (out and "Your pet is keeping up." or "Your pet was keeping up when you last had it out.")
    return res
end

ns:RegisterPillar(Pet)
