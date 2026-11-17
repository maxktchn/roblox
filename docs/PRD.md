# Kitchen Chaos: Product Requirements Document

**Status:** Draft v1 (source of truth)
**Platform:** Roblox
**Last updated:** 2026-11-13

> All numbers in this doc (damage, timers, costs, odds) are **starting values for tuning**, not final balance. Change them in the config modules, then update this doc.

---

## 1. Overview

### 1.1 Pitch
The restaurant's food has gone rotten and come alive. You're the chef, and you have to survive the dinner shift. Each run lasts about 6 minutes and ends in a boss fight. You start with only your signature tool, collect tips to level up, and pick 1 of 3 upgrades each time to build a combo of kitchen weapons that can clear the screen.

### 1.2 Genre and references
- **Genre:** Survivors-style roguelike with permanent progression between runs
- **References:** Vampire Survivors (run loop, evolutions), survivor.io (gear, merging, talents, chapters, monetization), archero (mobile-friendly controls and pacing)

### 1.3 Target players
- Roblox players who play on mobile and want short, replayable sessions
- Players who enjoy collecting and upgrading gear between runs

### 1.4 Core pillars
1. **Easy to learn, fun to master:** Players move and aim their signature tool; attacks fire on their own. The depth comes from choosing upgrades.
2. **Every run moves you forward:** Even a lost run earns gold, account XP, and materials.
3. **Funny kitchen theme:** Every weapon, enemy, and upgrade should make sense as kitchen gear or food.
4. **Mobile first:** If it doesn't play well on a phone, it doesn't ship.
5. **Fair monetization:** Paying only speeds things up. Everything can be earned for free.

### 1.5 Team and constraints
- **Team:** 2 people, beginner Luau
- **What this means for the plan:** Keep the scope small, store all content as data (config tables) instead of writing separate code for each item, and get a playable prototype working before building any progression systems.

### 1.6 Art and audio
- **Art style:** Low-poly cartoon. Bright colors and simple shapes that are quick to build and run well on phones.
- **Audio:** Music and sound effects from the Roblox Creator Store (free and licensed for Roblox games)

### 1.7 Goals for MVP
- A new player understands the game within their first run without needing a tutorial
- A run plays smoothly on a mid-range phone during the heaviest waves
- Playtesters want to start another run right after finishing one
- No way to get currency or gear without playing or paying (all checked on the server)

---

## 2. Core Run Loop

### 2.1 Run flow
1. Player picks a chapter and their equipped Utensil (starter) in the lobby
2. Run starts with only the starter weapon at Lv 1
3. Enemies spawn in waves and get harder over time
4. Defeated enemies drop **tips** (XP)
5. When the tip bar fills: **"Order Up!"** The game pauses and shows 3 upgrade cards. The player picks 1.
6. At **3:00**, a mini-boss appears (Chapter 1: The Big Cheese). Normal spawns stop and the run clock holds at 3:00 until every piece of it is defeated; enemies already in the kitchen stay
7. At **6:00**, the final boss appears in a closed arena
8. Beat the final boss to **clear the chapter**. If HP reaches 0, the player can revive once, or the run ends.
9. Results screen shows rewards earned

### 2.2 Controls and camera
- **Move and aim.** All attacks fire automatically. The signature tool (starter) swings toward where the player aims; gadgets don't aim.
- **Mobile:** Roblox's default dynamic thumbstick on the left to move; an **aim stick** fixed bottom-right to aim. Letting go keeps the last aim.
- **PC:** WASD or arrow keys to move; the **mouse cursor** aims
- **Gamepad:** left stick moves, right stick aims
- **No jump.** It does nothing in this game, and on phones the right thumb aims.
- **Aim indicator:** a thin orange arc (like a "U" opening toward the player), 4 studs from the chef and 50° wide, centred on the aim, at about the height of the starter's slash so the two line up. It doesn't depend on the weapon, so it works for any aimed weapon. Until the player aims, the starter swings the way the chef faces (and the arc sits there).
- **Camera:** Fixed, angled overhead view (3/4 view like survivor.io). Players cannot rotate or zoom it during a run. Starting values: looks down at 55°, 45 studs from the chef, 50° field of view.

### 2.3 Leveling up ("Order Up!")
- Each card shows: icon, name, new level, and a one-line description of what changes
- Cards are pulled from one shared pool, which includes:
  - The player's own starter weapon upgrades
  - Kitchen Gadgets (new or upgrades to owned ones)
  - Ingredients (new or upgrades to owned ones)
  - Recipe cards (when the conditions are met, see 2.5)
  - Boss power cards, once their boss has been beaten (rarer when new, see 3.8)
- Starter upgrades **do not** get a guaranteed slot. They compete in the same pool.
- **Rerolls:** Players get **2 rerolls per run**. A reroll replaces all 3 cards with a new draw. Talents can add more (see 4.5).
- Items already at max level are removed from the pool. Once all 6 shared slots are full, new gadgets and ingredients are removed too, and only upgrades to owned items can appear.
- If the pool runs out completely, show a filler card: **Tip Jar** (bonus gold). Phase 1 has no gold, so once everything is maxed, level-ups show no cards. There is no healing card: healing comes only from pies on the floor (2.6).
- **Tip bar:** 5 tips fill the first bar, and each bar after needs 5 more than the last (5, 10, 15, 20…), so a run reaches about Lv 20 by the boss. Leftover tips carry over. If several bars fill at once, the "Order Up!" screens come one after another.

### 2.4 Loadout limits
| Slot type | Max | Max level each |
|---|---|---|
| Signature Tool (starter) | 1 | 5 |
| Kitchen Gadgets + Ingredients (combined) | 6 total, any mix | 5 |

- The 6 shared slots can hold any mix, such as 3 gadgets + 3 ingredients or 2 gadgets + 4 ingredients.
- **Why:** Every recipe needs a weapon and its matching ingredient, so players can't take everything. They have to plan which recipes they're going for.
- Example: A Frying Pan player going for Flambé Pan needs Butter, which uses 1 of their 6 slots. A player who wants 3 gadget recipes needs 3 gadgets + 3 matching ingredients, which fills all 6.

### 2.5 Recipes (evolutions)
- **Condition:** A weapon at max level (Lv 5) + its matching ingredient owned (any level)
- When the condition is met, the weapon's **Recipe card** is guaranteed to show up at the next "Order Up!"
- Taking the recipe replaces the weapon with its upgraded version (same slot)
- Recipes are shown in an in-game **Cookbook** once discovered
- The recipe card keeps showing up in every "Order Up!" until it is taken. If several are ready, they fill the 3 card slots first.
- A recipe is a weapon with one level: it can't be upgraded further, and its old weapon never comes back.

**Phase 1 recipe starting values** (tune in `Recipes.luau`):
| Recipe | Shape | Numbers |
|---|---|---|
| Sushi Master Blade | Arc | 30 damage, 150° slash, 13 range, every 0.45 s, +25% crit chance on this weapon |
| Ghost Pepper Blaster | Arc | 7 damage, 120° cone, 13 range, every 0.7 s, burns 8/s for 3 s |
| Fondue Ring | Orbit | 6 forks on a 9-stud circle, 260°/s, 9 damage, burns 4/s for 2 s |

### 2.6 Pickups in the arena
| Pickup | Effect |
|---|---|
| Tips | XP (small, medium, large values). Dropped by every defeated enemy; tips within 8 studs (Fridge Magnet adds to this) fly to the chef at 45 studs/s. At most 250 lie on the floor; extra value is added to the oldest one. |
| Pie | Heals 20% max HP. Moldy Bread, Meatballs and other bigger enemies have a 4.5% chance to drop one (Fruit Flies never do), about 13 a run. Walk over it to eat it (2.5 studs); it stays on the floor while you're at full HP. At most 15 on the floor. |
| Tip Jar | Pulls every tip on the map to the player |
| Fire Extinguisher | Clears all normal enemies on screen |
| Lunchbox | Every elite drops one (#120). Walk over it (2.5 studs) for **1 free upgrade**: the normal "Order Up!" card screen, without changing your level (`RunRules.EliteLunchboxUpgrades`). It stays on the floor until picked up; at most 6. Bosses may drop one with 3 upgrades later. |

### 2.7 Revive
- One revive per run
- Costs gems (starting price: 30 gems)
- Revives with full HP and briefly pushes back nearby enemies

### 2.8 Run rewards
Rewards scale with how long the player survived and how far they got:
- **Gold**
- **Account XP**
- **Gear materials** (see 4.4)
- **Chance at a gear drop** (higher on chapter clear)
- **First-clear rewards:** Gems and a gear chest the first time a player reaches 3:00 and the first time they clear the chapter
- **Boss power:** defeating a chapter's final boss for the first time unlocks its power (see 3.8)

---

## 3. Content

### 3.1 Signature Tools (starters)
- Starters are the **Utensil** gear slot. The Utensil you have equipped is your starter weapon.
- Starters (and their recipes) are **aimed**: they swing on their own toward where the player aims (see 2.2). Gadgets and boss powers are not aimed.
- A starter can only be used in a run if you started with it. It **never** appears as a random upgrade.
- There are three ways to unlock a starter:
  - **Free:** Chef's Knife, so every player has a starter
  - **Achievement:** Rolling Pin and Meat Cleaver
  - **Chest drop:** Every other starter. It drops at random from chests (see 4.8).
- Every unlock gives the player the **Common** version. Higher tiers come from merging (see 4.2). Extra copies of any starter, including achievement starters, come from chests.

| Starter | Attack | Unlock | Recipe | MVP |
|---|---|---|---|---|
| Chef's Knife | Quick slashes in the direction you face | Free (default) | + Salt = **Sushi Master Blade** (crit combos) | Yes |
| Frying Pan | Wide swing with heavy knockback | Chest drop | + Butter = **Flambé Pan** (leaves a fire trail) | Yes |
| Rolling Pin | Rolls forward, hits everything in its path | Achievement: Clear Chapter 1 | + Bread = **Steamroller** | Yes |
| Meat Cleaver | Thrown, comes back like a boomerang | Achievement: Defeat 5,000 enemies total | + Hot Sauce = **Butcher's Fury** | No |
| Whisk | Spinning flurry at close range | Chest drop | + Coffee = **Hurricane Whisk** | No |
| Ladle | Lobs soup that leaves damaging puddles | Chest drop | + Beef Jerky = **Stew Cauldron** | No |

**Chef's Knife starting values** (Lv 1 → Lv 5): damage 10 / 13 / 13 / 16 / 20, cooldown 0.8 / 0.8 / 0.65 / 0.65 / 0.55 s, range 10 / 10 / 11 / 12 / 12 studs, arc 90° / 90° / 100° / 100° / 120°.

### 3.2 Kitchen Gadgets (shared pool)
| Gadget | Behavior | Recipe |
|---|---|---|
| Pepper Shaker | Sprays a burning cone at the nearest enemy | + Hot Sauce = **Ghost Pepper Blaster** |
| Egg Grenade | Lobbed, splash damage | + Bread = **Breakfast Bomb** (cluster splash) |
| Pizza Cutter | Disc that bounces between enemies | + Coffee = **Pizza Party** (multiple discs) |
| Spinning Forks | Forks orbit you | + Beef Jerky = **Fondue Ring** (burning orbit) |
| Toaster | Launches toast at the nearest enemies | + Butter = **Buttered Barrage** |
| Squeeze Bottle | Drops a ketchup trail that slows enemies | + Salt = **Condiment Flood** |

All 6 gadgets are in the MVP, plus a 7th that takes the removed Blender's place (designed in Phase 2, #83). Fridge Magnet has no recipe until then; the new gadget's recipe can use it.

**Phase 1 gadget starting values** (Lv 1 → Lv 5, tune in `Gadgets.luau`):
| Gadget | Shape | Lv 1 | Changes by Lv 5 |
|---|---|---|---|
| Pepper Shaker | Arc | 4 damage, 75° cone, 9 range, every 1.2 s, burns 3/s for 2 s | 7 damage, 105° cone, 10 range, every 0.9 s, burns 6/s for 3 s |
| Spinning Forks | Orbit | 2 forks on a 7-stud circle, 180°/s, 4 damage, each enemy hit at most every 0.6 s | 4 forks, 8 studs, 240°/s, 8 damage |
| Toaster | Projectile | 1 toast every 1.4 s at the nearest enemy within 40 studs, 8 damage, 45 studs/s | 4 toasts every 1.2 s, 14 damage |

The Pepper Shaker (and Ghost Pepper Blaster) sprays toward the nearest enemy within its range plus 4 studs, or the way the chef faces if nothing is that close. Burns tick every 0.5 s and get the Hot Sauce bonus but can't crit. A fork hits enemies within 2.5 studs of it; a toast hits the first enemy within 2 studs.

### 3.3 Ingredients (passives)
| Ingredient | Effect per level |
|---|---|
| Hot Sauce | +6% damage |
| Butter | +8% move speed |
| Coffee | -8% weapon cooldowns |
| Salt | +5% crit chance |
| Bread | +10% max HP |
| Beef Jerky | +1 armor (flat damage reduction) |
| Fridge Magnet | +20% tip pickup range |

Percent bonuses add up per level and multiply the base value (Hot Sauce Lv 3 = base damage × 1.18). Base crit chance is 0%, and a crit deals **2×** damage.

Weapon ranges (and orbit and shot hit radii) are measured to the enemy's edge, not its center, so big enemies like bosses can be hit from outside touching distance. Enemies are measured by their real shape: their **thickness** toward the chef for distances (flat ones like Moldy Bread are thin) and their **width** for side-to-side checks, so a slash that crosses any part of an enemy's body hits it. A slash stays live while its blade is drawn sweeping across (0.15 s, `RunRules.SlashSeconds`): an enemy that runs into it during the sweep is hit too, once per slash.

All 7 ingredients are in the MVP. Ingredients share the 6 combined slots with gadgets (see 2.4).

### 3.4 Enemies
| Enemy | Role | Behavior | MVP |
|---|---|---|---|
| Moldy Bread | Basic swarm | Walks straight at the player | Yes |
| Fruit Flies | Fast swarm | Fast, low HP, spawn in large groups | Yes |
| Rotten Tomato | Area denial | Bursts on death, leaves a slowing puddle | Yes |
| Meatball | Charger | Rolls toward the player in a straight line | Yes |
| Sour Lemon | Ranged | Keeps distance and squirts juice | Yes |
| Spaghetti Monster | Disabler | Slows the player when touching | No |
| Burnt Toast | Tank | Slow, high HP | No |

**Elites** (#120, tune the `Elite...` values in `RunRules.luau` and the schedule in `Chapters.luau`): larger, glowing versions of normal enemies. One arrives at each scheduled time (Chapter 1: **1:50, 2:40, 3:40, 4:15, 5:00, 5:40**), picked at random from the current phase's enemies that can be elite (Moldy Bread, Rotten Tomato, Meatball, Sour Lemon; never Fruit Flies). An elite is **1.5x the size** with **x6 HP, x1.5 contact damage and x5 tips**, on top of the run-time scaling below; speed is unchanged. An elite tomato's puddle is 1.5x wider and an elite lemon's shot does x1.5 damage. It has a gold outline and glow, always shows its health bar, ignores the alive cap, and always drops a Lunchbox. The clock holds during The Big Cheese, so held time doesn't move the schedule.

**Rotten Tomato puddle** (#117, tune `DeathPuddle` in `Enemies.luau`): whenever a tomato dies, a red puddle **6 studs** across appears where it died for **4 s** (fading over the last second). The chef standing in any puddle walks **40% slower** (doesn't stack; full speed straight away after leaving). It never hurts, and enemies aren't slowed. At most 10 on the floor (`RunRules.MaxPuddles`); a new one removes the oldest.

**Sour Lemon** (#118, tune `KeepAway` and `Shot` in `Enemies.luau`): keeps **18-25 studs** from the chef, backing away when you get closer (it's slower than you, so it can be caught). Within **45 studs** it shoots every **3 s** (the first 1.5 s after getting in range). **After its first shot it plants itself and never moves again** (`Shot.Plant`); it keeps shooting whenever the chef is within 45 studs, so walking out of range stops it. Tell: it swells to 1.3x for **0.5 s**, then a yellow blob flies flat at **20 studs/s** to where the chef was and stops there. Walking sideways dodges it. A hit does **8 damage** (before armor; grows over the run like contact damage). At most 30 blobs in the air (`RunRules.MaxJuiceShots`).

**Contact damage:** the chef starts with **100 HP** (Bread adds %). An enemy hurts the chef when it touches them (distance check: within 0.75 studs of touching, using the chef's body (1 stud from its centre, `RunRules.ChefRadius`) and the enemy's real thickness toward the chef). After a hit, the chef can't be hurt again for **0.5 s**, and only the strongest touching enemy's damage counts. Armor (Beef Jerky) is subtracted from each hit, minimum 1. At 0 HP the run is lost.

**Starting stats** (tune in `Enemies.luau`). Speed is in studs per second; the chef walks at 16. Damage is contact damage before armor. Tips is the tip (XP) value it drops.

| Enemy | HP | Speed | Damage | Tips |
|---|---|---|---|---|
| Moldy Bread | 25 | 8 | 5 | 2 |
| Fruit Flies | 6 | 17 | 2 | 1 |
| Rotten Tomato | 35 | 7 | 6 | 3 |
| Meatball | 40 | 24 | 6 | 4 |
| Sour Lemon | 30 | 9 | 6 | 3 |
| Spaghetti Monster | 30 | 6 | 4 | 4 |
| Burnt Toast | 80 | 4 | 12 | 8 |

**The Big Cheese's pieces** (mini-boss, see 3.5; tune in `Bosses.luau` and `Enemies.luau`). They never spawn in the normal waves and don't get the run-time scaling below. The Big Cheese always drops a pie when it splits.

**Melted cheese trail** (#99, tune `Trail` in `Bosses.luau`): The Big Cheese drops a cheese-yellow puddle every 1.5 studs it walks. Each puddle is 3 studs wide and lasts 4 s (fading over the last second). Stepping in one does **20 damage**, at most once a second. Only the big one leaves a trail, not its Wedges or Cubes; puddles already down fade normally after it splits.

| Piece | Count | HP | Speed | Damage | Tips |
|---|---|---|---|---|---|
| The Big Cheese | 1 | 1200 | 6 | 12 | 20 |
| Cheese Wedge | 3 | 240 | 10 | 8 | 6 |
| Cheese Cube | 6 | 80 | 15 | 5 | 3 |

**Movement:** Fruit Flies spawn in groups of 6. Meatballs roll straight at where the chef was, and turn to aim again after overshooting by 25 studs or hitting a wall. Before every charge (when it spawns and each time it re-aims) a Meatball stops and wobbles for **0.4 s** (#119, `RunRules.ChargeWindupSeconds`), so a charge can be seen coming and dodged. Sour Lemons keep their distance (above). Everything else walks straight at the chef. Enemies push each other apart so the swarm spreads into a crowd instead of stacking on one spot.

**Scaling over the run:** enemies get tougher the longer the run goes, so a strong build still meets resistance late. Every minute of run time (paused time doesn't count), new enemies get **+20% HP** and **+8.5% contact damage**, compounding. That's x1.7 HP at 3:00 and x3.0 at 6:00, and x1.6 damage at 6:00. This is well below the player's growth (about 10-20x damage from Lv 1 knife to a maxed build), so the player still pulls ahead. Speed and tips don't scale. The boss doesn't scale either (its numbers are in 3.5), but its minions do. Tune in `RunRules.luau` (`EnemyHpGrowthPerMinute`, `EnemyDamageGrowthPerMinute`).

### 3.5 Bosses
| Boss | When | Mechanics | Power (see 3.8) | MVP |
|---|---|---|---|---|
| The Big Cheese | 3:00 mini-boss (Chapter 1) | Leaves a melted cheese trail that hurts (20). Splits on death: 1 → 3 Cheese Wedges → 6 Cheese Cubes. Normal spawns stop and the run clock holds at 3:00 until every piece is defeated | None (mini-boss) | Yes |
| Microwave Monster | 6:00 final boss (Chapter 1) | Two HP phases. Phase 1: walks at the chef, summons minions, sends out damage pulses, fires homing popcorn. Below half HP: takes turns between spinning lasers in the middle of the arena and a walking turn (phase 1 again) | **Microwave Pulse** | Yes |
| Doughzilla | Final boss (Chapter 2, Bakery) | Giant dough that grows bigger by absorbing flour clouds | TBD | No |
| Kraken Roll | Final boss (Chapter 3, Sushi Bar) | Sushi kraken that grabs the player from the conveyor belts | TBD | No |
| Pantry Rat King | Final boss (Chapter 4, Walk-in Freezer) | TBD | TBD | No |

**Boss arena:** When a final boss spawns, a ring of counters closes around the player and boss. Normal enemies stop spawning until the boss is defeated.

**Microwave Monster starting values** (tune in `Bosses.luau`): when it arrives, the normal enemies on the map are cleared (no tips). The arena ring is 38 studs wide in radius.

| HP | Speed | Contact damage | Tips | Summons | Pulse |
|---|---|---|---|---|---|
| 5000 | 5 | 25, at most once a second | 50 | 4 Moldy Bread every 7 s | every 6 s, 1.2 s warning ring, 16 stud radius, 20 damage |

**Two HP phases** (aiming for a fight of about 60 s; tune in the `Fight` table in `Bosses.luau`):
- **Phase 1 (100% to 50% HP):** the summons and pulses above, plus homing popcorn (below).
- **Phase change (at 50%):** the boss stops for 1 s and flashes white, its HP bar turns from red to orange, and its screen changes from DING to HOT!
- **Phase 2 (below 50%):** it takes turns, over and over until it dies:
  - **Laser turn:** runs to the middle of the arena (speed 15, just slower than the chef) and stands there for 8 s, firing spinning lasers (below). No pulses and no new minions (minions already alive stay). It can still be hurt, so standing close and dodging is the reward. If the chef stands on the middle, it waits at their edge and walks in when they move.
  - **Walking turn (8 s):** phase 1 again. Summon, pulse and popcorn countdowns wait during laser turns and carry on in the next walking turn.

**Spinning lasers** (#93; during each laser turn, from the boss out to the ring of counters):
- **6 beams**, 60° apart. For the first **1.5 s** they are thin, see-through and still (the warning), starting with the chef halfway between two beams.
- Then they go live: 2 studs wide and solid, sweeping round at **25° per second** (clockwise or anticlockwise, at random each turn). At the arena's edge that's about 15 studs/s, just under the chef's 16, so you can run around with them at any distance.
- **Halfway through** the live time they switch direction. For 0.6 s before the switch they slow to a stop and go a little paler: a hint for players who are watching, meant to be easy to miss. Then straight back to full speed the other way.
- A live beam hits the chef for **35 damage**, at most once per second.

**Homing popcorn** (#92; in phase 1 and the walking turns):
- Every 10 s the microwave's window lights up and its screen says POP! for 0.6 s (the warning), then a **Popcorn Kernel** flies out of the door and follows the chef.
- It's an enemy, so every weapon can shoot it down: **400 HP** (not scaled, so it lives long enough to get out of the door), **speed 13** (the chef runs at 16, so you can outrun it but not lose it). It does no contact damage.
- Whenever it dies it **pops**: shot down (drops 5 tips), touching the chef, or after 8 s (no tips). An orange disc shows the whole blast area while a solid disc grows inside it for 0.5 s, then the blast hits the chef for **20 damage** if they're within **8 studs**. Only the chef is hurt.

### 3.6 Run timeline (Chapter 1, starting values)
| Time | What happens |
|---|---|
| 0:00 to 0:40 | Moldy Bread only (warm-up: time to level up before the fast Fruit Flies) |
| 0:40 to 1:15 | Add Fruit Flies |
| 1:15 to 3:00 | Add Rotten Tomatoes and Meatballs. Elites at 1:50 and 2:40. |
| 3:00 | The Big Cheese (mini-boss) |
| 3:00 to 5:25 | Add Sour Lemons (only after The Big Cheese is beaten: the clock holds until then). Larger waves and the dinner rush at 4:30. Elites at 3:40, 4:15, 5:00. |
| 5:25 to 6:00 | Final heavy wave |
| 6:00 | Microwave Monster in the closed arena |

**Spawn rate per phase** (spawn groups per second, tune in `Chapters.luau`; most enemies spawn alone, Fruit Flies in groups of 6): 0.6 until 1:15 (Moldy Bread only until 0:40), 1 until 3:00, 1.4 until 5:25, 2 until 6:00. Normal spawns stop at 6:00.

**Dinner rush** (#121, tune `Rushes` in `Chapters.luau`): from **4:30 to 4:50**, normal spawns run **3x** faster (1.4 to 4.2 spawn groups a second) from every side of the chef, still capped at `RunRules.MaxAliveEnemies`. A big "DINNER RUSH!" banner shows 2 s before it starts and stays (smaller) until it ends. A bell sound can be added later (`SoundId`).

**Enemies in the timeline:** all five Chapter 1 enemies spawn (`RunRules.EnemyPool`, since P2-2 #122). The Big Cheese mini-boss arrives at 3:00 (#84): spawns stop and the clock holds at 3:00 until all its pieces are defeated, then the timeline carries on. At 6:00 the Microwave Monster arrives; defeating it wins the run.

### 3.7 Chapters (maps)
- Chapters unlock in order. Beat a chapter's final boss to unlock the next one.
- Each run is about 6 minutes plus the boss fight (about 7 minutes of real time, since card picks pause the clock).

| # | Map | Notes | MVP |
|---|---|---|---|
| 1 | Diner Kitchen | Starter map | Yes |
| 2 | Bakery | Flour clouds that block vision | No |
| 3 | Sushi Bar | Conveyor belts that move the player | No |
| 4 | Walk-in Freezer | Ice floor where players slide | No |

### 3.8 Boss Powers
Beating a chapter's final boss takes its **power**: an ability the player keeps and can use in later runs. Every final boss has one. It's an extra layer of progress on top of gear, talents and starter unlocks.

- **Unlock:** defeating the boss unlocks its power for good (the first time only; dying in the fight unlocks nothing). The win screen says "New power unlocked: <name>".
- **In a run:** once unlocked, the power can show up as an "Order Up!" card, marked **BOSS POWER**. It works like a gadget: it uses one of the 6 shared slots and levels 1 to 5.
- **Rarity:** its NEW card is rarer than a gadget's. For each "Order Up!" it has a **35%** chance to join the cards being drawn from (while you don't own it and have a free slot), so it shows up about a third as often as a gadget's NEW card (roughly 1 offer in 8 with a 4-gadget pool, a bit more often with Phase 1's 3). Once owned, its upgrade cards appear like any gadget's.
- **Strength:** at Lv 1 about as strong as a normal gadget; at Lv 5 stronger than a maxed gadget.
- **No recipes.** Boss powers never evolve.
- **Never sold.** Only beating the boss unlocks a power (see 5.1).
- Nothing existing gets locked by boss powers. (The Blender was later removed because Microwave Pulse made it redundant, #83.)
- **Phase 1:** unlocks last until the server closes (no saving yet); Phase 2 saves them.

**Microwave Pulse** (Microwave Monster's power, tune in `BossPowers.luau`): every few seconds a shockwave ring grows out from where the chef stands, hitting each enemy once as it passes and knocking it back. Bosses aren't knocked back.

| Lv | Damage | Every | Ring reaches | Ring speed | Knockback |
|---|---|---|---|---|---|
| 1 | 12 | 3.0 s | 14 studs | 30 studs/s | 4 studs |
| 2 | 15 | 2.8 s | 15 | 32 | 5 |
| 3 | 19 | 2.6 s | 17 | 34 | 6 |
| 4 | 24 | 2.4 s | 19 | 36 | 7 |
| 5 | 30 | 2.2 s | 22 | 40 | 8 |

---

## 4. Meta Progression (survivor.io model)

### 4.1 Gear slots
| Slot | Main stat | Notes |
|---|---|---|
| Utensil | Attack | Sets your starter weapon |
| Hat | Attack | |
| Apron | HP | |
| Mitts | Attack | |
| Shoes | HP | |

### 4.2 Rarity and merging
| Tier | Color | Max gear level |
|---|---|---|
| Common | Gray | 10 |
| Fine | Green | 20 |
| Rare | Blue | 30 |
| Epic | Purple | 40 |
| Legendary | Gold | 50 |

- **Merge rule:** 3 copies of the **same item** at the **same tier** become 1 copy at the next tier
- The merged item keeps the highest gear level of the three
- **Tier bonuses:** Every tier raises the base stat. **Epic** and **Legendary** each add a bonus effect (for example, an Epic Frying Pan also stuns briefly on hit). Bonus effects are defined per item in config.

### 4.3 Gear leveling
- Leveling up gear costs **gold** and the slot's **material**
- Cost goes up with each level
- Max level depends on rarity (see 4.2)
- **Salvage:** Players can salvage a gear item. This **destroys the item** and refunds **80%** of the gold and materials spent leveling it (starting value, tune later).
  - Equipped gear can't be salvaged
  - The free Chef's Knife can't be salvaged, so players always have a starter
  - Show a confirmation popup before salvaging Epic or Legendary items

### 4.4 Materials
| Material | Used for |
|---|---|
| Sharpener | Utensil |
| Hat Pattern | Hat |
| Apron Pattern | Apron |
| Mitt Pattern | Mitts |
| Shoe Pattern | Shoes |

Materials come from runs, chests, daily missions, and the battle pass.

### 4.5 Talents
- Players earn **account XP** from every run
- Each account level unlocks the next talent node, which the player buys with gold
- **Standard nodes** repeat in a cycle: Attack, Max HP, Armor, Pie healing
- **Special nodes** every 5 levels give bigger effects (for example, start each run with 1 extra Pie, or +1 reroll per run)

### 4.6 No energy system
Players can start as many runs as they want. There is no energy or stamina cost.

### 4.7 Currencies
| Currency | Type | Earned from | Spent on |
|---|---|---|---|
| Gold | Free | Runs, missions, chests, battle pass | Gear leveling, talents, basic chests |
| Gems | Premium (also earnable) | First clears, missions, battle pass, purchase | Premium chests, revives |
| Materials | Free | Runs, chests, missions, battle pass | Gear leveling |

### 4.8 Chests
| Chest | Cost | Contents |
|---|---|---|
| Basic Chest | Gold | Common to Rare gear, small chance at a starter |
| Premium Chest | Gems | Fine to Epic gear, small chance at Legendary, higher chance at a starter |

- **Starter drops:** Chest-drop starters (Frying Pan, Whisk, Ladle) come from both chest types, so every starter can be earned for free with gold. Premium Chests give better odds, which is the paid way to speed things up.
- Starters drop as the Common version. If the player already owns it, the copy goes to their inventory for merging.

- **Starter drop odds:** 1% per Basic Chest, 5% per Premium Chest
- **Epic pity:** Guaranteed Epic gear within 30 Premium Chest opens
- **Starter pity:** Guaranteed chest-drop starter within 40 Premium Chest opens. It gives a starter the player doesn't own yet, if there is one.
- Each pity counter resets when its reward drops, whether it came from pity or normal luck
- Drop odds must be shown in game. Roblox requires odds to be shown for paid random items, so check the current policy before launch.

---

## 5. Monetization

### 5.1 Principle
**Paying only speeds things up.** Every item and power level can be earned for free. Nothing that adds power is paid-only.

**Boss powers are never sold.** Only defeating the boss unlocks its power (see 3.8): no Robux, gems or chest shortcut.

**Starters are a main monetization driver.** Most starters drop from chests, and Premium Chests (gems) have the best starter odds. Players can still get every starter with gold from Basic Chests, just more slowly.

### 5.2 Gems (developer products)
- Several gem bundles at different Robux prices (prices TBD)
- Gems are spent on Premium Chests and revives
- All purchases are processed on the server through `ProcessReceipt`

### 5.3 Battle pass
- Seasons last about 4 to 6 weeks
- **Free track** and **paid track**
- Players earn battle pass XP from daily missions and runs
- Rewards: gold, gems, materials, chests, gear
- No exclusive power on the paid track. Its gear can also be found in chests.

### 5.4 Gamepasses
Gamepasses must only save time. Starting list:
| Gamepass | Effect |
|---|---|
| 2x Gold | Double gold from runs |
| Auto Merge | One button to merge every possible gear trio |
| Daily Chest | 1 free Basic Chest every day |

---

## 6. Live Features at Launch

### 6.1 Daily missions
- 4 missions per day, reset at a fixed time (UTC)
- Examples: defeat 500 enemies, survive 5 minutes, take 3 recipes, level up gear once
- Rewards: gold, gems, materials, battle pass XP
- Bonus reward for completing all 4

### 6.2 Leaderboards
- **Highest chapter cleared**
- **Most enemies defeated in one run**
- **Fastest Chapter 1 boss kill**
- Stored with ordered DataStores and shown on a lobby board and in the UI

---

## 7. UI/UX

### 7.1 Lobby screens
For now the lobby is a set of **menu screens inside the run place** (see 8.1), shown before and between runs.

| Screen | Contents |
|---|---|
| Home | Play button, selected chapter, equipped starter, currencies |
| Gear | 5 gear slots, inventory, level up, merge, reset |
| Talents | Talent path, account level, unlock button |
| Chapters | Chapter list, lock state, first-clear rewards |
| Shop | Chests, gem bundles, gamepasses, odds info |
| Battle Pass | Free and paid tracks, season timer |
| Missions | Daily missions and progress |
| Cookbook | Discovered recipes and how to unlock the rest |

### 7.2 In-run HUD
- HP bar (above the chef)
- Enemy HP bars: a small bar over an enemy once it has been damaged, none at full HP (so a big swarm doesn't draw a bar each). At most 60 at once. Bosses have their own big bar.
- Tip (XP) bar and current level (top of screen)
- Run timer and kill count
- Owned weapons and ingredients (small icons)
- Pause button

### 7.3 "Order Up!" screen
- 3 large ticket-style cards, easy to tap on a phone
- Shows "NEW" or "Lv X → Lv Y" on each card
- Recipe cards have a special gold border
- Boss power cards have an orange border and a "BOSS POWER" badge when new
- Reroll button under the cards, showing how many rerolls are left

### 7.4 Mobile requirements
- All buttons must be large enough for thumbs
- The aim stick sits in a fixed spot in the bottom-right corner, thumb-sized (140 px), only on touch devices
- Nothing important near the screen edges where phones cut off content
- Test on a small phone screen before each milestone

---

## 8. Technical Notes for Roblox

### 8.1 Places and servers
- **One place for now.** The lobby is a set of menu screens inside the run place; each server holds **one player**, so run code only handles one player. No teleporting.
- **Why:** much easier to build and test (teleports don't work in Studio playtests), simpler saving (no save and load handoff between servers), one place to keep in sync, and an instant "Play again".
- **Cost accepted:** no shared social lobby where players see each other.
- **Revisit when co-op is designed:** co-op needs players matched into a shared run, which is when a separate Lobby place and teleports (`TeleportService`, reserved servers) come back. Build the lobby as its own screen code so it can move to a separate place later.

### 8.2 Saving player data
- Use a session-locked data library such as **ProfileStore** instead of writing DataStore code from scratch. It prevents lost or duplicated data when players switch servers.
- Save: currencies, gear inventory, equipped gear, talents, account level, unlocks, chapter progress, missions, battle pass progress, stats for leaderboards
- Run rewards are given by the run server and saved before teleporting the player back
- **Decided in #102** (design: `docs/superpowers/specs/2026-11-17-saving-design.md`):
  - **ProfileStore**, used only through `DataService`. Other services read and change their own section of the save.
  - **Quitting mid-run loses that run.** Nothing a run earns is saved until the run ends (won or lost).
  - **Load fails:** after `Saving.LoadTimeoutSeconds` (45 s, longer than ProfileStore's 40 s take-over of a save held by a crashed server) the player plays without saving, with a "Progress isn't saving right now" banner. Their real save is never written that session.
  - **Wipes before launch:** change `Saving.SaveSlot` (`PlayerData_v1`). A "Test build: progress may be reset" note is shown until launch. Studio uses its own store (`_Studio`).

### 8.3 Performance (enemy swarms on mobile)
This is the biggest technical risk. Rules:
- **Do not use Humanoids for enemies.** Use simple models or single parts.
- Track enemies as data in a Lua table and move them in bulk (for example, `workspace:BulkMoveTo`)
- **Object pooling:** Reuse enemy, projectile, and tip objects instead of creating and destroying them
- Use simple distance checks for hits instead of Roblox physics touches
- Limit how many enemies can be alive at once (starting cap: 150, tune after testing)
- Spawn enemies on a ring just outside the camera view (starting radius: 90 studs), at a rate set per timeline phase (see 3.6)
- **Phase 1 checked the cap on a flagship phone** (iPhone 15 Pro Max: 150 enemies, 60 fps average, 1% low 57). The mid-range phone check is deferred to before launch (#53), since we don't have one to test on.

### 8.4 Security (server authority)
- The server decides all damage, drops, XP, rewards, and purchases
- The client only sends movement, level-up card choices, and an aim direction for the starter (validated and rate-limited, at most 20 a second). The server still decides every hit.
- The server checks that every card choice was actually one of the 3 offered
- All currency changes happen on the server only

### 8.5 Code structure (beginner-friendly)
```
ReplicatedStorage/
  Config/            -- all content as data tables
    Starters.lua
    Gadgets.lua
    Ingredients.lua
    Recipes.lua
    Enemies.lua
    Bosses.lua
    Chapters.lua
    Gear.lua
    Talents.lua
  Shared/            -- code used by both server and client
ServerScriptService/
  Services/
    DataService.lua
    RunService.lua      -- name it RunManager to avoid confusion with Roblox's RunService
    EnemyService.lua
    WeaponService.lua
    UpgradeService.lua
    RewardService.lua
    ShopService.lua
StarterPlayerScripts/
  Controllers/
    InputController.lua
    CameraController.lua
    HUDController.lua
    UpgradeUIController.lua
```
- **Rule:** Adding a new weapon, enemy, or gear item should only need a new entry in `Config` plus its visual effect. No new systems.

---

## 9. Roadmap

### Phase 1: Playable run prototype
- One map, Chef's Knife, 3 gadgets, 4 ingredients, 3 enemy types, a mini-boss and a boss
  - **Map:** Diner Kitchen
  - **Gadgets:** Pepper Shaker (cone), Spinning Forks (orbit), Toaster (projectile). Three different attack shapes that the other gadgets reuse later. (The Blender was removed in #83: Microwave Pulse covers the damage-zone role.)
  - **Ingredients:** Salt, Hot Sauce, Beef Jerky, Fridge Magnet. Together these make 3 recipes testable: Sushi Master Blade, Ghost Pepper Blaster, Fondue Ring. Fridge Magnet has no recipe in Phase 1. (Toaster has no recipe in Phase 1, since Buttered Barrage needs Butter.)
  - **Enemies:** Moldy Bread, Fruit Flies, Meatball (movement only, no puddles or ranged attacks)
  - **Bosses:** The Big Cheese mini-boss at 3:00 (#84) and the Microwave Monster at 6:00.
- Tips, "Order Up!" cards, and recipes working
- No saving, no lobby, no progression
- **Boss powers prototype:** Microwave Pulse, unlocked by beating the Microwave Monster until the server closes (no saving yet)
- **Done when:** A full 6-minute run is fun and runs smoothly on a phone. (The mid-range phone check moved to Phase 3, #53.)

### Phase 2: MVP
- **Build order:**
  1. Saving player data
  2. Boss powers saving properly (unlocks kept between sessions)
  3. Chapter and starter unlocks
  4. Full Chapter 1 content: 3 starters, 7 gadgets, 7 ingredients, 5 enemies, elites, 2 bosses (The Big Cheese is already in from Phase 1)
  5. Gear (5 slots, rarity, merging, leveling), talents, Basic Chests
- Lobby as menu screens in the run place (see 8.1)
- **Done when:** A new player can go from first run to unlocking the Rolling Pin, and all progress saves correctly

### Phase 3: Monetization and live features
- Gems, Premium Chests with odds shown, pity system, revives
- Battle pass (first season)
- Gamepasses
- Daily missions and leaderboards
- Mid-range phone performance check with every Phase 2 enemy and effect in (#53)
- **Done when:** All purchases work and are checked on the server, and the game is ready to publish

### Post-launch
- Chapters 2 to 4 and their bosses
- Meat Cleaver, Whisk, Ladle starters
- Spaghetti Monster, Burnt Toast enemies
- Co-op
- Chef skins

---

## 10. Open Questions and Out of Scope

### 10.1 Open questions
1. Robux prices for gem bundles, gamepasses, and the battle pass (decide in Phase 3)
2. What enemy cap can a mid-range phone actually handle? (150 passes on a flagship; mid-range still to test before launch, #53)

### 10.2 Out of scope for launch
- Co-op
- Chef skins and cosmetics
- PvP
- Chapters 2 to 4
- Energy or stamina system (not planned)
