# Road to 60

Tells you, at any level, whether you're prepared. Pips, in order of importance: **Raid ready**
(from level 55), **Gear**, **Spells**, **Quests**, **Supplies**, **Gold**, **Dungeons**,
**Professions** and **Legacy** (once a character reaches level 25).

Works best alongside two optional addons it reads data from (if installed):
**LevelUpInfo** (trainer spell lists) and **ForeverDungeonJournal** (dungeon levels and quests).

## Install

1. Install with the CurseForge app, or copy the `RoadTo60` folder into
   `World of Warcraft\_forever_\Interface\AddOns\`.
2. Made for WoW Forever (Interface `16001`) and the English client.

## Commands

| Command | What it does |
| --- | --- |
| `/r60` | Toggle the dashboard (or click the pip bar) |
| `/r60 settings` | Thresholds, alerts, pillars, gold goals |
| `/r60 progress` | Checkpoint cards, records and your ghost run |
| `/r60 card [level]` | A saved checkpoint card, or a preview of today's |
| `/r60 next` | Every next-step option, ranked |
| `/r60 goal 40 100 Riding + mount` | Add/change a gold goal (level, gold, label) |
| `/r60 goals`, `/r60 delgoal 40` | List / remove gold goals |
| `/r60 share [party\|raid\|guild\|say]` | Post your grades in one line |
| `/r60 bar show\|hide\|reset` | Pip bar |
| `/r60 mute pillarRed\|trainable\|checkpoint\|record` | Toggle an alert type |
| `/r60 debug` | Troubleshooting tools (probe, info, spells, supplies, …) |

## How grading works

- **Gear**: each slot's "level" is its required level (or item level − 5 if none), plus
  3/6/9 levels for green/blue/epic quality. Each slot scores 100 within 4 levels, 75 at 8
  (stale), then −6 a level. Slots are weighted by impact (weapon ×2, big armor ×1, small
  pieces ×0.6, jewelry ×0.4; Hunters' ranged weapon ×2). Empty armor/weapon slots count;
  neck/rings/trinkets count from level 25. One stale chest ≈ B, a stale weapon ≈ C. From level 8, empty bag slots and bags well
  below the size your level can easily get (6 → 14 slots by level 50) cost up to 20 points.
- **Gold**: graded from level 20; projects your gold at the next goal's level from your
  savings so far. Score = projected ÷ goal cost. Default goals are riding + mount: 100g at
  40 and 1200g at 60 (Paladins 1350g for the Charger chain), 10% off riding at Honored.
- **Spells**: each class-trainer visit records every rank it offers (by spell ID) into an
  account-wide table, so alts of the same class benefit. Ranks you could train but haven't
  are "waiting"; more than 4 levels late is "overdue". Ranks of spells on your action bars
  count fully, others half. Skipped lower ranks don't count.
  `/r60 spells` lists them. From level 10, unspent talent points cost up to 40 points
  and are always offered as a next step.
- **Professions**: primary professions are expected to be around 5 skill per level
  (capped by the tier your level unlocks). Secondary ones only count when a tier is waiting.
  An empty primary slot scores 70 and comes with a suggestion.
  Tier unlocks use Classic's rules (Journeyman 10/50, Expert 20/125, Artisan 35/200).
- **Quests**: log health — each gray quest costs 6, each finished quest beyond 2 costs 8,
  a nearly full log costs up to 20, and fewer than 3 quests you can work on at your level
  costs 6 each (an empty log is a D). `/r60 quests` lists the log.
- **Supplies**: food, drink (mana users), healing potions, bandages (with First Aid), class
  supplies (Hunter ammo, Warlock soul shards, Rogue poisons), repairs under 50%, and a
  hearthstone set in a zone you left 5+ levels ago.
- **Raid ready** (from 55): gear, spells and talents, supplies, and the Drakefire Amulet for
  Onyxia's Lair; the December 9 raids are Barrow Deeps (10), Hyjal Summit (20) and Onyxia's
  Lair (40). It summarises other pillars, so it isn't counted in the overall grade.
- **Dungeons**: XP you're about to leave behind in dungeon quests (faction- and
  class-filtered, checked live with `IsQuestFlaggedCompleted`), compared with your current
  level's XP. Quests in your log count fully, ones you haven't picked up count half. Urgency
  rises from the middle of a dungeon's range to its top level; out-levelled dungeons count
  for 5 levels, then stop. Missing a whole level's worth costs 60 points. Runs and
  final-boss clears are recorded. `/r60 dungeons` lists them all.
- Grades: A ≥ 90, B ≥ 75, C ≥ 60, D ≥ 40, F below. Pips: green ≥ 75, yellow ≥ 50, red below.

## Fun layer (M4)

- **Checkpoint cards** at 10, 20, 30, 40, 50, 60: an A–F grade per pillar plus overall,
  and gold on hand. Saved per character; flip through
  them on the dashboard's Checkpoints tab or with `/r60 card 20`. `/r60 card` previews today's.
- **Next best step**: one line under the pip bar with the single action that would raise
  your grades most, e.g. "Here: Turn in 3 quests here (Quests C to A)". Things you can do
  where you stand win: quest turn-ins near you (the game's own turn-in locations) and
  trainers you've used near you (remembered from each visit). Hover for the next few
  options; `/r60 next` lists them all.
- **Progress** tab (checkpoint tiles, then records): best checkpoint grade (yours, and the account's with the character's
  name), on-pace streak (levels in a row at B or better), no-stale-gear streak, quests
  turned in, dungeon runs/clears and time played. Records are about being ready, not fast.

## History (M5)

- **Ghost run**: every character's checkpoint grades are saved account-wide. On a later
  character, each checkpoint card compares you with your best-prepared earlier run at that
  level (same class first): "Oldpally (Paladin) was C at 30 — you're ahead on Gear, behind
  on Gold". The Records tab shows how the ghost looked at your next checkpoint.
- **Share**: `/r60 share` posts one line to raid, party or guild (whichever you're in),
  or `/r60 share say`. Example: "[Road to 60] Lv 30 checkpoint: B (Gear A, Spells A, …)".
- **Legacy**: no addon API for Forever's Legacy System is documented yet.
  `/r60 legacy` scans the client for anything Legacy-related and saves it, so the
  pillar can be wired to the real data.

## Layout

```
Core.lua            events, SavedVariables, pillar registry, grading
Probe.lua           M0 API check + /r60 info
Pillars/Gear.lua    stale/empty slots, item history
Pillars/Gold.lua    goal projection, gold per level/hour
Pillars/Planned.lua gray placeholders for M2–M5 pillars
UI/Alerts.lua       toast + chat line, queued during combat
UI/PipBar.lua       compact pip bar
UI/Dashboard.lua    /r60 window
Commands.lua        slash commands
```

New pillars plug in with `ns:RegisterPillar{ key, name, order, events, Evaluate }`,
where `Evaluate` returns `{ score = 0–100, reason = "...", action = "..." }`.
