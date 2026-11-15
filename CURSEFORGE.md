# CurseForge listing — Road to 60

**Name:** Road to 60
**Game version:** WoW Forever (Interface 16001)
**Version / release type:** 1.2.0 · Release
**Changelog for the file:** the 1.2.0 section of `RoadTo60/CHANGELOG.md`
**Category suggestion:** Quests & Leveling
**Optional dependencies to link:** LevelUpInfo, ForeverDungeonJournal
**Summary (one line):** At any level, see whether you're prepared for the road to 60, and what to fix next.

---

## Description (paste below this line)

**Am I ready for what's next?** Road to 60 answers that at a glance while you level in WoW Forever. It's about being prepared, not about rushing.

A row of colored pips sits at the top of your screen, one per pillar, in order of importance. Green means you're in good shape, yellow means something's slipping, and red means it needs attention. Hover a pip for the reason, or click it for a full breakdown. Under the pips, one line tells you the single most useful thing to do next.

### The pillars
- **Raid ready** (from level 55): a checklist for Forever's first raids (Barrow Deeps, Hyjal Summit and Onyxia's Lair): gear, spells and talents, supplies, and the Drakefire Amulet for Onyxia's attunement.
- **Gear**: slots that have fallen behind your level, empty slots, and small or missing bags. Weapons count most, and better quality lasts longer. Priests, Mages and Warlocks get their wand graded like a weapon. *"Your boots are 12 levels old."*
- **Spells**: ranks waiting at your trainer, unspent talent points, and weapon skills you could learn. *"Train 3 ranks — 1g 40s. You can afford it."*
- **Quests**: finished quests waiting to be turned in, gray quests, and enough quests at your level to work on.
- **Supplies**: food, water, healing potions, bandages, class supplies (Hunter ammo, Warlock soul shards, Rogue poisons), repairs, and a hearthstone still set in a zone you've left. *"Buy food."*
- **Pet** (Hunters, from level 10): your pet's level against yours, its happiness, and unspent training points. *"Your pet is 4 levels behind."*
- **Gold**: savings toward your riding goals, using Forever's prices (Paladin class mounts included) and your Honored discount.
- **Dungeons**: dungeons in your level range, the quest XP you'd leave behind, and quests to pick up in town before you go in. *"Before Ragefire Chasm: pick up Hidden Enemies (Thrall, Orgrimmar)."*
- **Professions**: skill for your level, tiers you can train, and a suggested second profession that pairs with your first.
- **Legacy**: appears once a character reaches level 25, when Forever's Legacy System unlocks.

### Prepared, not rushed
- **Next best step**: favors what you can do where you're standing, such as quest turn-ins nearby, the trainer you're next to, or a vendor in town. *"Here: Turn in 3 quests (Quests C to A)."*
- **Breakdowns**: click any pillar to see the grade of each part, e.g. Quests by zone and class quests, Gear by slot, Dungeons by dungeon.
- **Report cards** at levels 10, 20, 30, 40, 50 and 60: an A–F grade per pillar, saved so you can look back through your run.
- **Progress tab**: your best report card, your on-pace streak (levels in a row at B or better), and your no-stale-gear streak.
- **Ghost run**: your next character compares its preparation with your best earlier run. *"Oldpally (Paladin) was C at 30 — you're ahead on Gear, behind on Gold."*
- **`/r60 share`**: post your grades to your party or guild in one line.

### Learns as you go
Forever reworked the classes and most quests, so Road to 60 doesn't ship a fixed database. It learns your class's spells from your trainer visits, shares them with your other characters of that class, and remembers where trainers stand. If you have **LevelUpInfo** or **ForeverDungeonJournal** installed, it reads their data too: trainer spell lists, dungeon levels and dungeon quests.

### Stays out of your way
Nothing shows during combat, and alerts wait until you're out of it. Every alert can be muted, every threshold tuned in `/r60 settings`, and any pillar you don't care about hidden (right-click its pip) or weighted down.

Lay the pip bar out as a row or a column, put the next step on any side, scale it, add grade letters to the pips, or let it fade while everything is green. Prefer it elsewhere? Turn on the minimap button, or show your grade in Titan Panel, ChocolateBar or another LibDataBroker display.

### Good to know
- Made for the English client. Some checks read item and quest text (food vs. drink, healing potions, the Drakefire Amulet), so other languages may miss them.
- If something looks wrong, `/r60 debug` has tools that save what Road to 60 sees, which makes a bug report easy to act on.

### Commands
`/r60` opens the dashboard · `/r60 settings` · `/r60 progress` · `/r60 card` · `/r60 next` · `/r60 share` · `/r60 hide <pillar>` · `/r60 show <pillar>` · `/r60 bar row|column` · `/r60 bar next <side>` · `/r60 help`
