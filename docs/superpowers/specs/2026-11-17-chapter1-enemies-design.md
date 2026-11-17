# Chapter 1 enemies, elites and the dinner rush (P2-2, #103): design

## Why
Phase 2's MVP needs the full Chapter 1 (PRD §9: "5 enemies, elites, 2 bosses"). Phase 1 shipped three enemies that only move (Moldy Bread, Fruit Flies, Meatball). This topic adds the last two (Rotten Tomato, Sour Lemon), elites and their Lunchbox drop, the dinner rush at 4:30, and a small fix that makes the Meatball fairer. It all happens inside a run, so it doesn't depend on saving or gear.

## Decided (by athatcher989)
- **Rotten Tomato:** when it dies, it leaves a puddle that **slows only** (no damage). The Big Cheese's trail already covers "puddles that hurt"; the tomato's job is to limit where you can run.
- **Sour Lemon:** keeps its distance and lobs a **slow, telegraphed** juice blob at where you stood. It always has a tell and can always be dodged by moving.
- **Elites come on a fixed schedule**, not at random, so runs are predictable to tune and to test with the bot.
- **An elite's Lunchbox gives 1 free upgrade** through the normal "Order Up!" card screen. (Bosses can give 3 later.)
- **Dinner rush is a 20 s stretch** of much faster spawns from every side, with a warning first, not a single burst.
- **Meatball gets a wind-up** before each charge. Nothing else changes.
- **Sour Lemons start after The Big Cheese** is beaten, so the first ranged enemy never arrives mid mini-boss fight.

All numbers below are **starting values**. The two new enemies have never been played, so they get tuned in the playtest after the build, and again in the full rebalance at M5 (#94).

## Approaches considered
1. **Each mechanic in its own small service, enemies stay data records (picked).** Puddles, juice blobs and elites are each a service like `TrailService` / `PopcornService`, hooked up with `EnemyService.onEnemyKilled` and RunManager callbacks. Fits how the boss and the Big Cheese were built, and keeps every hit a flat distance check (PRD §8.3).
2. **Give enemies scripts or Humanoids.** Easier to reason about one enemy, but breaks the pooled-parts design that keeps 150 enemies fast on phones. Rejected.
3. **Put it all into `EnemyService`.** Fewer files, but EnemyService is already the biggest file and each mechanic would be harder to find and test. Rejected.

## Rotten Tomato (area denial)
- **Stats unchanged:** 35 HP, speed 7, contact damage 6, 3 tips, 3-stud ball (already in `Enemies.luau`). Chases the chef like Moldy Bread.
- **Death puddle:** whenever a tomato dies (to any weapon), a flat red puddle appears where it died.
  - **6 studs** across, lasts **4 s**, fades out over its last second (same look as the cheese trail, red-brown `(150, 40, 35)`).
  - The chef standing in any puddle moves **40% slower**. Puddles don't stack: one or five, it's 40%. Leaving the puddle gives full speed back straight away.
  - No damage, and enemies aren't affected.
  - At most **10** puddles on the floor; an 11th removes the oldest, so a big tomato wave can't cover the arena.
- **Code:** a new `PuddleService` (or `TrailService` grown to handle still puddles; builder's call) listens to `onEnemyKilled` for enemies with a new `Enemies.luau` field, e.g. `DeathPuddle = { Width = 6, Seconds = 4, Slow = 0.4 }`.
- **Slowing the chef:** the server sets the chef's `Humanoid.WalkSpeed`. This should go through one function in `StatsService` that works out the chef's speed (base 16 × Butter bonus × slow), because Butter (+8% move speed, P2-3 #104) changes the same number. Coordinate with #104 so there's only one place that sets WalkSpeed.

## Sour Lemon (ranged)
- **Stats unchanged:** 30 HP, speed 9, contact damage 6, 3 tips, 2.8-stud ball.
- **Movement (new `Movement = "KeepAway"`):**
  - Further than 25 studs from the chef: walks toward the chef.
  - Closer than 18 studs: backs away. It's slower than the chef (9 vs 16), so you can always catch it.
  - In between: stands still and shoots.
  - Pushed apart from other enemies like everything else; walls stop it backing away, so it can be cornered.
- **Juice shot:**
  - Every **3 s** while it's within 30 studs of the chef (first shot 1.5 s after it gets in range, so a fresh lemon doesn't fire instantly).
  - **Tell:** the lemon swells to 1.3× its size for **0.5 s**, then shoots.
  - The blob is a bright yellow ball (1.2 studs) that flies flat at **20 studs/s** toward where the chef was when it fired, and disappears when it gets there (it doesn't keep flying). At 18-25 studs that's about a second in the air: walking sideways dodges it.
  - **8 damage** (before armor) if the chef is touched on the way (flat distance: blob radius + `ChefRadius`). It uses the normal 0.5 s hit cooldown like contact damage. Damage source `"LemonJuice"` ("Lemon juice" in the run report).
  - At most **30** blobs in the air; past that, lemons skip a shot.
  - Shot damage gets the same per-minute damage scaling as contact damage.
- **Code:** a new `JuiceService` handles the shot timer per lemon, the swell, the blobs and the hits. New `Enemies.luau` fields, e.g. `Shot = { Every = 3, Windup = 0.5, Speed = 20, Damage = 8, Range = 30 }` and `KeepAway = { Min = 18, Max = 25 }`.

## Meatball wind-up
- Before every charge (when it spawns, and each time it turns to aim again after overshooting or hitting a wall) the Meatball **stops and shakes for 0.4 s**, then rolls at where the chef is at the end of the wind-up.
- The shake is a small side-to-side wobble of its part, so you can see a charge is coming.
- New `RunRules.ChargeWindupSeconds = 0.4` (next to `ChargeOvershootDistance`).

## Elites
- **Schedule (run clock):** **1:50, 2:40, 3:40, 4:15, 5:00, 5:40.** Six per run. The clock holds at 3:00 during the Big Cheese, so 3:40 always comes after the cheese is beaten. Times live in the chapter config, e.g. `Chapters.DinerKitchen.Elites = { 110, 160, 220, 255, 300, 340 }`, so later chapters can have their own.
- **Which enemy:** a random one from the current phase's enemy list that's allowed to be elite. **Moldy Bread, Rotten Tomato, Meatball and Sour Lemon** can be (new `Enemies.luau` field `CanBeElite = true`). Fruit Flies never are: too small to read as elite.
- **Spawns** like a normal enemy (off to the side of the chef, inside the walls). It ignores the alive cap, so a busy screen can't swallow it.
- **Stronger:** **1.5× size, ×8 HP, ×1.5 contact damage, ×5 tips**, on top of the normal per-minute scaling. Speed is unchanged. An elite tomato's puddle is 1.5× wider, and an elite lemon's shot does ×1.5 damage.
- **For scale:** an elite Moldy Bread at 1:50 has about 280 HP (25 × 8 × 1.4 scaling), 3.5× a Big Cheese Cube.
- **Look:** a gold outline (`Highlight`, gold `(255, 200, 50)`) plus a soft gold `PointLight`. Both stand apart from the red damage flash and read on a phone. Roblox only shows 31 Highlights at once; with six elites a run that's never a problem.
- **Health bar:** elites always show their health bar (EnemyHealthBarController), so you can see the extra HP.
- **Drops a Lunchbox** when it dies (always), plus its normal tips and pie chance.
- **Code:** a new `EliteService` watches the clock and spawns elites; EnemyService gets a way to spawn one enemy with multipliers (size, HP, damage, tips) and an `IsElite` attribute on its part. New `RunRules` (or chapter) values: `EliteSizeScale = 1.5`, `EliteHpScale = 8`, `EliteDamageScale = 1.5`, `EliteTipScale = 5`.

## Lunchbox
- Dropped where an elite dies. A small lunchbox-shaped part (red box, white handle) with a slow bob and spin, so it reads as a reward, not a tip.
- **Walk over it** (2.5 studs, like a pie) to open it: **1 free upgrade**, which opens the normal "Order Up!" card screen. If a level-up is already waiting, the Lunchbox's upgrade waits in line after it.
- It stays on the floor until picked up (no timeout), and a new run clears it. At most 6 on the floor (one per elite).
- Bosses don't drop one yet; that can come later with 3 upgrades.
- **Code:** `PickupService` already handles pies, so the Lunchbox goes there. `UpgradeService` gets `grantLevelUps(count)`, which adds to `pendingLevelUps` and shows the next offer, the same path a full tip bar uses. `RunRules.LunchboxUpgradesMin/Max` (1 and 3 today, unused) become one value per source: `EliteLunchboxUpgrades = 1`.

## Dinner rush
- At **4:30** (run clock), for **20 s**, normal spawns run at **3×** the current phase's rate (1.4 → 4.2 spawn groups a second) from every side of the chef. Still capped at `MaxAliveEnemies` (150), so phones stay safe.
- **Warning:** 2 s before it starts, a big "DINNER RUSH!" banner on the HUD and a bell sound. The banner stays (smaller) until the rush ends.
- Uses the current phase's enemy list; nothing special spawns.
- Paused time doesn't count. If the clock is held (it can't be at 4:30 in Chapter 1, but a later chapter might), the rush waits too.
- **Code:** a new optional `Rushes` list in the chapter config, e.g. `Rushes = { { At = 270, Seconds = 20, SpawnScale = 3, Warning = 2 } }`. RunManager already tells listeners the spawn rate when the phase changes; it announces the rush rate the same way, and sets a workspace attribute (e.g. `DinnerRush = true`) for the HUD.

## Timeline
| Time | What happens |
|---|---|
| 0:00 to 0:40 | Moldy Bread only |
| 0:40 to 1:15 | Add Fruit Flies |
| 1:15 to 3:00 | Add **Rotten Tomatoes** and Meatballs. **First elite at 1:50**, second at 2:40. |
| 3:00 | The Big Cheese (clock holds until it's beaten) |
| 3:00 to 5:25 | Add **Sour Lemons** (only after the cheese, since the clock is held until then). Elites at 3:40, 4:15, 5:00. **Dinner rush at 4:30.** |
| 5:25 to 6:00 | Final heavy wave. Elite at 5:40. |
| 6:00 | Microwave Monster |

- `Chapters.luau` already lists Tomatoes from 1:15 and Lemons from 3:00. Because the clock and spawns hold during the Big Cheese, "Lemons from 3:00" already means "after the cheese". The builder just needs to check that the 3:00 phase doesn't spawn anything in the moment before the fight starts.
- `RunRules.EnemyPool` gets `"RottenTomato"` and `"SourLemon"` added.

## Playtest bot
The bot is how we compare balance changes (#94), so it needs to cope with the new threats:
- **Juice blobs:** step sideways from a blob heading at it (like it dodges popcorn pops).
- **Tomato puddles:** avoid walking through puddles when there's another way.
- **Lunchboxes:** walk to them like pies.
- **Elites:** treat them like a slow mini-boss (keep away while weapons work).

## Run report
- Elites: how many killed out of how many spawned, and when each died.
- Lunchboxes opened.
- Damage from Lemon juice (as a named source).
- Seconds spent slowed by tomato puddles.

## Testing (scripted Studio playtest, as usual)
- **Tomato:** kill one, check a puddle appears for 4 s; stand in it and check WalkSpeed is 60% of normal, and back to normal right after leaving; 11 puddles leaves 10.
- **Lemon:** it holds 18-25 studs; it swells before each shot; standing still gets hit for 8, moving sideways doesn't; shots stop at the target point.
- **Meatball:** it stands still for 0.4 s before every charge.
- **Elites:** at each scheduled time, one appears with ×8 HP, 1.5× size and a gold outline; Fruit Flies are never picked; it drops a Lunchbox; the Lunchbox gives exactly one card screen.
- **Dinner rush:** the banner shows at 4:28; the spawn rate is 3× from 4:30 to 4:50; alive enemies never go over 150.
- **Bot:** a few full runs before and after, to see how much harder 1:15-6:00 got. Numbers are tuned from that and the human playtest.
- **Phone:** the puddles, the lemon's swell and the elite glow are easy to see on a small screen (#53's phone test later).

## Build issues (opened when this design is merged)
1. **P2-2a Rotten Tomato and slowing puddles** (with the chef speed function, coordinated with Butter, #104).
2. **P2-2b Sour Lemon: keep-away movement and juice shots.**
3. **P2-2c Meatball wind-up.**
4. **P2-2d Elites and the Lunchbox.**
5. **P2-2e Dinner rush.**
6. **P2-2f Turn them on:** add Tomato and Lemon to `EnemyPool`, the bot changes, run report lines, PRD §2.6, §3.4 and §3.6, then a bot run and a playtest to tune.

PRD: §2.6, §3.4, §3.6
