# Changelog

## 1.2.0
Class checks. Each can be switched off: the Pet pillar in Settings > Pillars, the others
under Settings > General > Class checks.

- **Hunter pet pillar** (from level 10): your pet's level against yours, its happiness, and
  unspent training points. A dismissed or stabled pet still counts at the level you last
  saw it. No pet by level 12 suggests the taming quest.
- **Wands for Priests, Mages and Warlocks:** the ranged slot is now graded as "Wand", nearly
  as heavily as a weapon, and an empty one counts from level 12.
- **Mages conjure their food and water:** Supplies now says "Conjure water" instead of
  sending you to a vendor.
- **Fairer empty-slot grading:** empty head and shoulder slots now count from level 25
  (was 20; helmets rarely drop sooner), set under Settings > General. Every empty slot that
  starts counting at a level phases in over 5 levels instead of hitting all at once, so
  reaching 20 no longer drops Gear from an A to a D overnight.
- Report cards have room for all ten pillars.

## 1.1.0
Polish round: everything new can be switched off in `/r60 settings`, which now has
General, Pillars and Display tabs.

**Pillars**
- Turning a pillar off now hides it completely: no pip, no dashboard row, no report-card
  line, and it's left out of `/r60 share` and ghost-run comparisons. (Before, it only left
  the overall grade and kept a gray pip.)
- Right-click a pip to hide that pillar, or use `/r60 hide <pillar>` / `/r60 show <pillar>`.
- Pillar weights: set how much each pillar counts in your overall grade, from 0% to 200%.

**Pip bar**
- Lay it out as a row or a column (`/r60 bar row|column`).
- Choose where the next best step sits: below, above, left or right of the bar
  (`/r60 bar next <side>`). It stays on screen wherever the bar is.
- The next best step sits in a box like the bar's (optional) and wraps at a width you set.
- The overall grade at the end of the bar is colored green, yellow or red like the pips.
- Scale and pip size settings.
- Optional grade letter on each pip, for players who find the colors hard to tell apart.
- Optional fade while every pillar is green; it comes back when anything slips or you hover.
- Pip tooltips open on the side away from the next-step line.

**Elsewhere**
- Minimap button: click for the dashboard, right-click for settings.
- Titan Panel / ChocolateBar / other LibDataBroker displays can show your overall grade.
- Level-up recap: one chat line at each ding with the grades that changed and gold gained.
- Share button on report cards.
- Words the addon reads in item text (food vs. drink, potions, poisons, the Drakefire Amulet)
  now live in `Locale.lua`, ready for translations. The Drakefire Amulet is also matched by
  item ID.

## 1.0.0
First release.
- Pip bar with a grade for each pillar: Gear, Spells, Quests, Supplies, Gold, Dungeons,
  Professions, plus Legacy (from level 25) and Raid ready (from level 55).
- One line under the pips with the most useful next step, favoring what you can do nearby.
- Dashboard with a breakdown for every pillar, report cards at every 10 levels, and a
  Progress tab with records and a ghost run of your best earlier character.
- Learns your trainers' spells as you visit them; reads LevelUpInfo and ForeverDungeonJournal
  data if you have them installed.
