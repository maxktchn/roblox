# New gadgets, ingredients and recipes (P2-3, #104): design

## Why
Phase 2's MVP needs the full upgrade pool: 7 Kitchen Gadgets, 7 Ingredients and their recipes (PRD §3.2, §3.3, §2.5). Phase 1 shipped 3 gadgets (Pepper Shaker, Spinning Forks, Toaster) and 4 ingredients (Salt, Hot Sauce, Beef Jerky, Fridge Magnet). This topic adds the other 4 gadgets, the 3 missing ingredients, and the 5 recipes those unlock. It all happens inside a run, so it doesn't depend on saving or gear.

## Decided (by athatcher989)
- **The 7th gadget is the Ice Cube Tray.** It fires ice cubes that slide in a straight line, **pierce** every enemy in their path and slow them. Its recipe is **Deep Freeze** (+ Fridge Magnet), which freezes enemies solid. This finally gives Fridge Magnet a recipe.
- **Egg Grenade, Pizza Cutter and Squeeze Bottle keep their PRD behaviours** (lob + splash, a disc that bounces between enemies, a ketchup trail that slows).
- **Recipes keep their names and pairings, and each one adds a new trick**, not just bigger numbers (below).
- **New ingredients are cut by the same 40% as Hot Sauce** (+10% → +6%):
  - Butter +8% → **+5%** move speed
  - Coffee −8% → **−5%** weapon cooldowns
  - Bread +10% → **+6%** max HP

  Butter and Coffee would be exactly 4.8%; they're rounded to 5% so the cards read cleanly.
- **Sharing ingredients is fine:**
  - Salt feeds Sushi Master Blade and Condiment Flood.
  - Bread feeds Steamroller and Breakfast Bomb.
  - Butter feeds Flambé Pan and Buttered Barrage.
  - Coffee feeds Hurricane Whisk and Pizza Party.
- **Every gadget and ingredient has the same odds** of showing up, and boss powers stay rarer (35%, PRD §3.8). **The 6-slot limit stays.** With 7 recipes in the pool, a run can complete about 3, which is the point of the limit.

All numbers below are **starting values**, sized against the 3 existing gadgets. None of these has been played yet, so they get tuned in the playtest after each build issue, and again in the full rebalance at M5 (#94).

## How strong each gadget should be (the yardstick)
These are the existing gadgets' rough damage per second, before Hot Sauce and crits. Single target is one enemy; "crowd" counts every enemy a hit can reach.
| Gadget | Lv 1 | Lv 5 |
|---|---|---|
| Toaster (single target) | 8 / 1.4 s ≈ 6 | 4 × 14 / 1.2 s ≈ 47 |
| Pepper Shaker (crowd, each enemy) | 4 / 1.2 s + 3/s burn ≈ 6 | 7 / 0.9 s + 6/s burn ≈ 14 |
| Spinning Forks (crowd, each fork) | 4 / 0.6 s ≈ 7 | 8 / 0.6 s ≈ 13 |

New gadgets aim for the same band. Crowd gadgets do less per hit than single-target ones, and gadgets that also slow do a bit less again.

## Approaches considered
1. **One new shape per new behaviour, plus optional fields on Projectile (picked).**
   - New shapes: `Lob` (Egg Grenade), `Bounce` (Pizza Cutter) and `Trail` (Squeeze Bottle).
   - The Ice Cube Tray and Buttered Barrage are still "fire shots at enemies", so `Projectile` gets optional `Pierce`, `Slow`, `Freeze` and `Slick` fields instead of a new shape.
   - This fits PRD §8.5 (one function per shape in WeaponService, weapons are config only), and every hit stays a flat distance check (§8.3).
2. **A new shape for every gadget and recipe.** Clearer per weapon, but Ice Cube Tray, Toaster and Buttered Barrage would be three near-copies of the projectile code. Rejected.
3. **Scripted, per-weapon code (a module per gadget).** Most freedom, but it breaks the "weapons are just config" rule that lets either of us add or tune a weapon without touching code. Rejected.

## Shared: slowing and freezing enemies
Squeeze Bottle, Ice Cube Tray, Buttered Barrage and Deep Freeze all slow enemies, and nothing in the game can slow an enemy yet.
- **`EnemyService.slow(id, fraction, seconds)`:** the enemy moves at `(1 − fraction)` speed until the time runs out. Slows **don't stack**: the strongest one wins. A longer slow of the same strength extends the time.
- **`EnemyService.freeze(id, seconds)`:** the enemy can't move at all; it's a slow of 1.0. A frozen enemy still hurts on contact; freezing stops it chasing you, not hurting you.
- **Bosses** (The Big Cheese pieces and the Microwave Monster) take **half the slow** and are **never frozen** (a freeze slows them 50% instead). Same idea as bosses ignoring knockback.
- **Elites** are slowed and frozen like normal enemies.
- **Look:** a slowed enemy gets a light blue tint and a frozen one a stronger tint. This is done by changing the pooled part's colour, so there are no new parts, and the colour goes back when the slow ends or the part is reused.
- **Meatball charges** are slowed too: a slowed Meatball rolls slower but still goes straight.

## Ingredients
| Ingredient | Effect per level | Lv 5 | Notes |
|---|---|---|---|
| Butter | +5% move speed | +25% (16 → 20 walk speed) | Already wired: `StatsService.getWalkSpeed` (from #117). A tomato puddle still slows 40% on top. |
| Coffee | −5% weapon cooldowns | −25% (every weapon fires 1.33× as often) | **New wiring:** WeaponService multiplies every weapon's `Cooldown` by `(1 − Coffee)`. This covers starters, gadgets, recipes and boss powers. For Spinning Forks it's the per-enemy re-hit time. Burns and slows aren't shortened. |
| Bread | +6% max HP | +30% (100 → 130) | Already wired: RunManager's max HP. Taking a level adds the gained max HP to current HP too, as today. |

`Ingredients.luau` and the PRD §3.3 table change to these values. All three join `RunRules.UpgradePool.Ingredients`.

## Egg Grenade (new shape: `Lob`)
**Behaviour:** every `Cooldown`, lobs `Count` eggs at enemies within `Range`. The first egg goes at the nearest enemy, and each extra egg at the next-nearest different enemy, like the Toaster.
- An egg flies in an arc for **0.6 s**: it's visible and lands where the enemy was when thrown, so it can miss fast enemies.
- On landing it **splashes**, hitting every enemy within `Radius` (measured to their edge, like other weapons). That makes it a slow crowd hitter.

| Lv | Damage | Every | Eggs | Splash radius | Range |
|---|---|---|---|---|---|
| 1 | 12 | 2.0 s | 1 | 5 | 30 |
| 2 | 14 | 2.0 s | 1 | 5.5 | 30 |
| 3 | 14 | 1.8 s | 2 | 5.5 | 30 |
| 4 | 17 | 1.8 s | 2 | 6.5 | 30 |
| 5 | 20 | 1.6 s | 2 | 7 | 30 |

**Breakfast Bomb** (Egg Grenade + Bread), the trick being a **cluster**:
- Each egg splashes (26 damage, 7 radius), then **4 mini-eggs** pop out in a cross and land 6 studs away 0.3 s later.
- Each mini-egg splashes again (12 damage, 4 radius).
- It throws 3 eggs every 1.4 s.

**New fields:**
- `Radius`: the splash radius.
- `Cluster = { Count, Distance, Damage, Radius }`: the recipe only.

## Pizza Cutter (new shape: `Bounce`)
**Behaviour:** every `Cooldown`, throws a disc at the nearest enemy within `Range`.
- After each hit, the disc flies on to the **nearest enemy it hasn't hit yet** within `BounceRange` of where it is. It does this up to `Bounces` times, then vanishes.
- It flies at 40 studs/s, so you can watch it chain.
- It hits each enemy once per throw.

| Lv | Damage | Every | Bounces | Bounce range | Range |
|---|---|---|---|---|---|
| 1 | 9 | 1.5 s | 3 | 12 | 30 |
| 2 | 11 | 1.5 s | 4 | 12 | 30 |
| 3 | 11 | 1.3 s | 5 | 13 | 30 |
| 4 | 14 | 1.3 s | 6 | 13 | 30 |
| 5 | 16 | 1.1 s | 7 | 14 | 30 |

**Pizza Party** (Pizza Cutter + Coffee), the trick being **3 discs at once**:
- Each disc is thrown at a different enemy, does 18 damage and bounces 8 times, every 1.0 s.
- The 3 discs share one "already hit" list per throw, so they spread across the crowd instead of piling on the same enemies.

**New fields:**
- `Bounces`, `BounceRange`.
- `Count`, used here as discs per throw (as for Projectile).

## Squeeze Bottle (new shape: `Trail`)
**Behaviour:** while the chef **walks**, it drops a ketchup splat behind them every 0.3 s. Standing still drops nothing, so it rewards kiting.
- A splat is a flat red disc `Width` studs across that lasts `Seconds`.
- An enemy standing on any splat is slowed by `Slow` and takes `Damage` every 0.5 s. Splats don't stack: one splat or five, the enemy is hit once per tick.
- At most **40 splats** on the floor (the oldest goes first) for phone performance.

| Lv | Damage per 0.5 s | Width | Lasts | Slow |
|---|---|---|---|---|
| 1 | 2 | 3 | 2.0 s | 30% |
| 2 | 3 | 3 | 2.5 s | 30% |
| 3 | 3 | 3.5 | 2.5 s | 35% |
| 4 | 4 | 3.5 | 3.0 s | 35% |
| 5 | 5 | 4 | 3.5 s | 40% |

**Condiment Flood** (Squeeze Bottle + Salt), the trick being a **flood that crits**:
- The trail is **6 studs** wide, lasts 4 s, slows 50% and does 8 every 0.5 s.
- Its ticks **can crit**, unlike burns, so Salt pays off twice.
- While the chef stands still, it **keeps pooling**: a splat every 0.6 s at their feet.

**New fields:** `Width`, `Seconds`, `Slow`, plus `Cooldown` = the drop interval and `Damage` = per tick.

## Ice Cube Tray, the 7th gadget (`Projectile` + `Pierce`)
**Behaviour:** every `Cooldown`, slides `Count` ice cubes toward the nearest enemy within `Range`. Extra cubes fan out 15° apart.
- A cube travels flat at 35 studs/s up to `Range` studs, **passing through** every enemy it touches (2-stud hit radius).
- It hits each enemy once, and every enemy it hits is slowed by `Slow` for 1.5 s.
- It's best lined up down a corridor of enemies, where the Toaster is best on singles.

| Lv | Damage | Every | Cubes | Slow (1.5 s) | Range |
|---|---|---|---|---|---|
| 1 | 9 | 1.6 s | 1 | 25% | 30 |
| 2 | 11 | 1.6 s | 1 | 25% | 32 |
| 3 | 11 | 1.4 s | 2 | 30% | 32 |
| 4 | 13 | 1.4 s | 2 | 30% | 35 |
| 5 | 15 | 1.2 s | 3 | 35% | 35 |

**Deep Freeze** (Ice Cube Tray + Fridge Magnet), the trick being a **freeze**:
- It fires 5 cubes in a fan every 1.0 s; each does 20 damage, pierces, and reaches 40 studs.
- Every enemy hit is **frozen solid for 1.5 s**: it can't move (bosses are slowed 50% instead).
- A frozen enemy takes **+25% damage** from everything, so it pairs with any build.

**New fields on any `Projectile`:**
- `Pierce`: how many enemies a shot passes through; nil means it stops at the first, as today.
- `Spread`: the degrees between extra shots; nil means aimed at different enemies, like the Toaster.
- `Slow`, `SlowSeconds`, `Freeze`.
- `FrozenBonus`: Deep Freeze only.

## Toaster recipe: Buttered Barrage (`Projectile` + `Pierce` + `Slick`)
**Buttered Barrage** (Toaster + Butter), the trick being **butter slicks**:
- It fires 6 toasts every 1.0 s; each does 16 damage and **pierces up to 3** enemies.
- Wherever a toast hits, it leaves a **butter slick** 4 studs across for 3 s. Enemies on a slick are slowed 30%; it's the same splat code as the Squeeze Bottle, with no damage.
- At most 20 slicks on the floor.

**New field:** `Slick = { Width, Seconds, Slow }`.

## Card text (the "Order Up!" one-liners)
Each card says what changes at its level, as today (UpgradeService already lists changed stats). New stat names to add to its table:
- **Splash** (radius)
- **Bounces**
- **Width**
- **Lasts** (seconds)
- **Slow** (%)
- **Pierce**

## Playtest bot
- The bot already picks cards by kind (Gadget, Ingredient). New gadgets and ingredients just join, so no strategy change is needed.
- `INGREDIENT_LIKES` gets Butter 1, Coffee 3 and Bread 2 (Hot Sauce stays the favourite).
- The bot's client half needs nothing new: these weapons fire on their own.

## Testing (each build issue)
- **Each gadget at Lv 1 and Lv 5**, scripted in Studio:
  - spawn a known group, fire, and check damage, count, splash/bounce/pierce counts and slow strength
  - check the hit list really is once per enemy per throw
- **Each recipe:** the recipe card appears once the gadget is Lv 5 and its ingredient is owned, it replaces the gadget in the same slot, and the trick works (cluster eggs land, 3 discs share a hit list, the flood crits, freezes hold enemies still, slicks slow).
- **Coffee:** a weapon's real time between attacks is `Cooldown × (1 − 0.05 × level)` (measure the Toaster at Coffee Lv 5: 1.2 s → 0.9 s).
- **Slows:** the strongest slow wins, bosses take half and never freeze, and the colour goes back afterwards and on pooled reuse.
- **Phone performance:** 150 enemies plus a Lv 5 Squeeze Bottle trail, Pizza Party and Deep Freeze, without frame drops (the `StressTest` setup).
- **Bot comparison:** 6 bot runs before and after the full pool, like #122, to see the new pool doesn't make runs much easier or harder.

## Build issues (after this doc is merged)
1. **Butter, Coffee, Bread:** the new values, Coffee's cooldown wiring in WeaponService, all three in the pool, bot likes, and PRD §3.3.
2. **Slowing and freezing enemies:** `EnemyService.slow` / `freeze`, boss rules, tint. Needed by 4, 5 and 6.
3. **Egg Grenade + Breakfast Bomb:** the `Lob` shape.
4. **Pizza Cutter + Pizza Party:** the `Bounce` shape.
5. **Squeeze Bottle + Condiment Flood:** the `Trail` shape and the splat pool. It needs 2.
6. **Ice Cube Tray + Deep Freeze, and Buttered Barrage:** `Projectile` gets `Pierce`, `Spread`, `Slow`, `Freeze` and `Slick`. It needs 2 and 5 (the slicks reuse the splat code).
7. **Full pool bot comparison and PRD §3.2 tables:** after 1-6.

1 and 2 can start at once; 3 and 4 don't depend on anything else.

## Coordination
- **P2-6 (#107, Frying Pan / Rolling Pin):** the ingredient list is final here. Butter (+5% speed) feeds Flambé Pan and Bread (+6% max HP) feeds Steamroller, alongside Buttered Barrage and Breakfast Bomb.
- **Butter and slows:** the chef's walk speed still has one owner (`StatsService.getWalkSpeed`), and enemy slows have one owner (`EnemyService.slow`).
