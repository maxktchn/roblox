# Kitchen Chaos: Product Requirements Document

**Status:** Draft v1 (source of truth)
**Platform:** Roblox
**Last updated:** 2026-11-13

> All numbers in this doc (damage, timers, costs, odds) are **starting values for tuning**, not final balance. Change them in the config modules, then update this doc.

---

## 1. Overview

### 1.1 Pitch
The restaurant's food has gone rotten and come alive. You're the chef, and you have to survive the dinner shift. Each run lasts about 10 minutes and ends in a boss fight. You start with only your signature tool, collect tips to level up, and pick 1 of 3 upgrades each time to build a combo of kitchen weapons that can clear the screen.

### 1.2 Genre and references
- **Genre:** Survivors-style roguelike with permanent progression between runs
- **References:** Vampire Survivors (run loop, evolutions), survivor.io (gear, merging, talents, chapters, monetization), archero (mobile-friendly controls and pacing)

### 1.3 Target players
- Roblox players who play on mobile and want short, replayable sessions
- Players who enjoy collecting and upgrading gear between runs

### 1.4 Core pillars
1. **Easy to learn, fun to master:** Players only move, and attacks fire on their own. The depth comes from choosing upgrades.
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
6. At **5:00**, a mini-boss appears
7. At **10:00**, the final boss appears in a closed arena
8. Beat the final boss to **clear the chapter**. If HP reaches 0, the player can revive once, or the run ends.
9. Results screen shows rewards earned

### 2.2 Controls and camera
- **Movement only.** All attacks fire automatically.
- **Mobile:** Roblox's default dynamic thumbstick
- **PC:** WASD or arrow keys
- **Camera:** Fixed, angled overhead view (3/4 view like survivor.io). Players cannot rotate or zoom it during a run. Starting values: looks down at 55°, 45 studs from the chef, 50° field of view.

### 2.3 Leveling up ("Order Up!")
- Each card shows: icon, name, new level, and a one-line description of what changes
- Cards are pulled from one shared pool, which includes:
  - The player's own starter weapon upgrades
  - Kitchen Gadgets (new or upgrades to owned ones)
  - Ingredients (new or upgrades to owned ones)
  - Recipe cards (when the conditions are met, see 2.5)
- Starter upgrades **do not** get a guaranteed slot. They compete in the same pool.
- **Rerolls:** Players get **2 rerolls per run**. A reroll replaces all 3 cards with a new draw. Talents can add more (see 4.5).
- Items already at max level are removed from the pool. Once all 6 shared slots are full, new gadgets and ingredients are removed too, and only upgrades to owned items can appear.
- If the pool runs out completely, show filler cards: **Pie** (heal 30% HP) or **Tip Jar** (bonus gold). Phase 1 has no gold, so it shows only Pie.
- **Tip bar:** 5 tips fill the first bar, and each bar after needs 3 more than the last (5, 8, 11, 14…). Leftover tips carry over. If several bars fill at once, the "Order Up!" screens come one after another.

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
| Ghost Pepper Blaster | Arc | 10 damage, 120° cone, 13 range, every 0.7 s, burns 12/s for 3 s |
| Fondue Ring | Orbit | 6 forks on a 9-stud circle, 260°/s, 14 damage, burns 6/s for 2 s |
| Smoothie Vortex | Aura | 9 damage every 0.35 s within 12 studs. The pull comes later, since it needs a way to move enemies. |

### 2.6 Pickups in the arena
| Pickup | Effect |
|---|---|
| Tips | XP (small, medium, large values). Dropped by every defeated enemy; tips within 8 studs (Fridge Magnet adds to this) fly to the chef at 45 studs/s. At most 250 lie on the floor; extra value is added to the oldest one. |
| Pie | Heals 30% max HP |
| Tip Jar | Pulls every tip on the map to the player |
| Fire Extinguisher | Clears all normal enemies on screen |
| Lunchbox | Dropped by elites and bosses. Gives 1 to 3 free upgrades. |

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
- **First-clear rewards:** Gems and a gear chest the first time a player reaches 5:00 and the first time they clear the chapter

---

## 3. Content

### 3.1 Signature Tools (starters)
- Starters are the **Utensil** gear slot. The Utensil you have equipped is your starter weapon.
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

**Chef's Knife starting values** (Lv 1 → Lv 5): damage 10 / 13 / 13 / 18 / 24, cooldown 0.8 / 0.8 / 0.65 / 0.65 / 0.55 s, range 10 / 10 / 11 / 12 / 12 studs, arc 90° / 90° / 100° / 100° / 120°.

### 3.2 Kitchen Gadgets (shared pool)
| Gadget | Behavior | Recipe |
|---|---|---|
| Pepper Shaker | Cone spray that burns | + Hot Sauce = **Ghost Pepper Blaster** |
| Egg Grenade | Lobbed, splash damage | + Bread = **Breakfast Bomb** (cluster splash) |
| Pizza Cutter | Disc that bounces between enemies | + Coffee = **Pizza Party** (multiple discs) |
| Blender | Damage zone around you | + Fridge Magnet = **Smoothie Vortex** (pulls enemies in) |
| Spinning Forks | Forks orbit you | + Beef Jerky = **Fondue Ring** (burning orbit) |
| Toaster | Launches toast at the nearest enemies | + Butter = **Buttered Barrage** |
| Squeeze Bottle | Drops a ketchup trail that slows enemies | + Salt = **Condiment Flood** |

All 7 gadgets are in the MVP.

**Phase 1 gadget starting values** (Lv 1 → Lv 5, tune in `Gadgets.luau`):
| Gadget | Shape | Lv 1 | Changes by Lv 5 |
|---|---|---|---|
| Pepper Shaker | Arc | 4 damage, 60° cone, 9 range, every 1.2 s, burns 3/s for 2 s | 7 damage, 90° cone, 10 range, every 0.9 s, burns 6/s for 3 s |
| Blender | Aura | 3 damage every 0.5 s within 6 studs | 6 damage every 0.4 s within 9 studs |
| Spinning Forks | Orbit | 2 forks on a 7-stud circle, 180°/s, 6 damage, each enemy hit at most every 0.6 s | 4 forks, 8 studs, 240°/s, 11 damage |
| Toaster | Projectile | 1 toast every 1.4 s at the nearest enemy within 40 studs, 9 damage, 45 studs/s | 4 toasts every 1.2 s, 16 damage |

Burns tick every 0.5 s and get the Hot Sauce bonus but can't crit. A fork hits enemies within 2.5 studs of it; a toast hits the first enemy within 2 studs.

### 3.3 Ingredients (passives)
| Ingredient | Effect per level |
|---|---|
| Hot Sauce | +10% damage |
| Butter | +8% move speed |
| Coffee | -8% weapon cooldowns |
| Salt | +5% crit chance |
| Bread | +10% max HP |
| Beef Jerky | +1 armor (flat damage reduction) |
| Fridge Magnet | +20% tip pickup range |

Percent bonuses add up per level and multiply the base value (Hot Sauce Lv 3 = base damage × 1.3). Base crit chance is 0%, and a crit deals **2×** damage.

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

**Elites:** Larger, glowing versions of normal enemies with more HP. They always drop a Lunchbox.

**Starting stats** (tune in `Enemies.luau`). Speed is in studs per second; the chef walks at 16. Damage is contact damage before armor. Tips is the tip (XP) value it drops.

| Enemy | HP | Speed | Damage | Tips |
|---|---|---|---|---|
| Moldy Bread | 10 | 8 | 5 | 2 |
| Fruit Flies | 3 | 17 | 2 | 1 |
| Rotten Tomato | 15 | 7 | 6 | 3 |
| Meatball | 25 | 20 | 10 | 4 |
| Sour Lemon | 12 | 9 | 6 | 3 |
| Spaghetti Monster | 30 | 6 | 4 | 4 |
| Burnt Toast | 80 | 4 | 12 | 8 |

**Movement (Phase 1):** Fruit Flies spawn in groups of 6. Meatballs roll straight at where the chef was, and turn to aim again after overshooting by 25 studs or hitting a wall. Everything else walks straight at the chef. Enemies push each other apart so the swarm spreads into a crowd instead of stacking on one spot.

### 3.5 Bosses
| Boss | When | Mechanics | MVP |
|---|---|---|---|
| The Big Cheese | 5:00 mini-boss (Chapter 1) | Splits into smaller cheeses when damaged | Yes |
| Microwave Monster | 10:00 final boss (Chapter 1) | Summons minions and sends out damage pulses | Yes |
| Doughzilla | Final boss (Chapter 2, Bakery) | Giant dough that grows bigger by absorbing flour clouds | No |
| Kraken Roll | Final boss (Chapter 3, Sushi Bar) | Sushi kraken that grabs the player from the conveyor belts | No |
| Pantry Rat King | Final boss (Chapter 4, Walk-in Freezer) | TBD | No |

**Boss arena:** When a final boss spawns, a ring of counters closes around the player and boss. Normal enemies stop spawning until the boss is defeated.

### 3.6 Run timeline (Chapter 1, starting values)
| Time | What happens |
|---|---|
| 0:00 to 2:00 | Moldy Bread and Fruit Flies only |
| 2:00 to 5:00 | Add Rotten Tomatoes and Meatballs. First elite at 3:00. |
| 5:00 | The Big Cheese (mini-boss) |
| 5:00 to 9:00 | Add Sour Lemons. Larger waves and a "dinner rush" swarm event at 7:30. |
| 9:00 to 10:00 | Final heavy wave |
| 10:00 | Microwave Monster in the closed arena |

### 3.7 Chapters (maps)
- Chapters unlock in order. Beat a chapter's final boss to unlock the next one.
- Each run is about 10 minutes plus the boss fight.

| # | Map | Notes | MVP |
|---|---|---|---|
| 1 | Diner Kitchen | Starter map | Yes |
| 2 | Bakery | Flour clouds that block vision | No |
| 3 | Sushi Bar | Conveyor belts that move the player | No |
| 4 | Walk-in Freezer | Ice floor where players slide | No |

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
- Tip (XP) bar and current level (top of screen)
- Run timer and kill count
- Owned weapons and ingredients (small icons)
- Pause button

### 7.3 "Order Up!" screen
- 3 large ticket-style cards, easy to tap on a phone
- Shows "NEW" or "Lv X → Lv Y" on each card
- Recipe cards have a special gold border
- Reroll button under the cards, showing how many rerolls are left

### 7.4 Mobile requirements
- All buttons must be large enough for thumbs
- Nothing important near the screen edges where phones cut off content
- Test on a small phone screen before each milestone

---

## 8. Technical Notes for Roblox

### 8.1 Places and servers
- **Lobby place:** Players manage gear, talents, shop, and start runs
- **Run place:** Each run happens in its own reserved server (one player per server), using `TeleportService`
- **Why:** Keeps run code simple (only one player to handle) and keeps heavy enemy simulation off the lobby server
- **Downside:** A loading screen between lobby and run. Make it short and on theme.

### 8.2 Saving player data
- Use a session-locked data library such as **ProfileStore** instead of writing DataStore code from scratch. It prevents lost or duplicated data when players switch servers.
- Save: currencies, gear inventory, equipped gear, talents, account level, unlocks, chapter progress, missions, battle pass progress, stats for leaderboards
- Run rewards are given by the run server and saved before teleporting the player back

### 8.3 Performance (enemy swarms on mobile)
This is the biggest technical risk. Rules:
- **Do not use Humanoids for enemies.** Use simple models or single parts.
- Track enemies as data in a Lua table and move them in bulk (for example, `workspace:BulkMoveTo`)
- **Object pooling:** Reuse enemy, projectile, and tip objects instead of creating and destroying them
- Use simple distance checks for hits instead of Roblox physics touches
- Limit how many enemies can be alive at once (starting cap: 150, tune after testing)
- Spawn enemies on a ring just outside the camera view (starting radius: 90 studs), at a base rate of 2 per second that the timeline raises
- **Phase 1 must prove** the cap runs smoothly on a mid-range phone

### 8.4 Security (server authority)
- The server decides all damage, drops, XP, rewards, and purchases
- The client only sends movement and level-up card choices
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
- One map, Chef's Knife, 4 gadgets, 4 ingredients, 3 enemy types, 1 boss
  - **Map:** Diner Kitchen
  - **Gadgets:** Pepper Shaker (cone), Blender (aura), Spinning Forks (orbit), Toaster (projectile). Four different attack shapes that the other gadgets reuse later.
  - **Ingredients:** Salt, Hot Sauce, Beef Jerky, Fridge Magnet. Together these make 4 recipes testable: Sushi Master Blade, Ghost Pepper Blaster, Fondue Ring, Smoothie Vortex. (Toaster has no recipe in Phase 1, since Buttered Barrage needs Butter.)
  - **Enemies:** Moldy Bread, Fruit Flies, Meatball (movement only, no puddles or ranged attacks)
  - **Boss:** Microwave Monster at 10:00. The Big Cheese mini-boss waits for Phase 2.
- Tips, "Order Up!" cards, and recipes working
- No saving, no lobby, no progression
- **Done when:** A full 10-minute run is fun and runs smoothly on a mid-range phone

### Phase 2: MVP
- Full Chapter 1 content: 3 starters, 7 gadgets, 7 ingredients, 5 enemies, elites, 2 bosses
- Lobby and Run places with teleporting
- Saving player data
- Gear (5 slots, rarity, merging, leveling), talents, Basic Chests, chapter unlocks
- **Done when:** A new player can go from first run to unlocking the Rolling Pin, and all progress saves correctly

### Phase 3: Monetization and live features
- Gems, Premium Chests with odds shown, pity system, revives
- Battle pass (first season)
- Gamepasses
- Daily missions and leaderboards
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
2. What enemy cap can a mid-range phone actually handle? (answered by testing in Phase 1)

### 10.2 Out of scope for launch
- Co-op
- Chef skins and cosmetics
- PvP
- Chapters 2 to 4
- Energy or stamina system (not planned)
