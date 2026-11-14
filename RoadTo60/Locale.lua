-- Road to 60: words the addon looks for in item and spell text.
-- A few checks can't use item IDs (Forever reworked most items), so they read text:
-- food vs. drink, healing vs. mana potions, rogue poisons, the Drakefire Amulet.
-- To support another client language, copy the enUS block under that locale and
-- translate the values. Matches are lowercase plain substrings.
local _, ns = ...

local L = {
    -- Item spell text on food that restores mana ("Drink", "Refreshment")
    drink       = "drink",
    refreshment = "refreshment",
    -- Potion names
    healing     = "healing",
    mana        = "mana",
    -- Consumable names (Rogue poisons)
    poison      = "poison",
    -- Onyxia attunement item (matched by ID first; the name is a fallback)
    drakefireAmulet = "Drakefire Amulet",
}

local locale = GetLocale and GetLocale() or "enUS"

-- Example, to be filled in by a translator:
-- if locale == "deDE" then
--     L.drink = "trinken"
--     ...
-- end

ns.L = L
