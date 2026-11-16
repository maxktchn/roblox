# The Big Cheese mini-boss (#84): design

## Why
PRD §2.1 step 6 and §3.5: a mini-boss arrives at 3:00 in Chapter 1. It's a mid-run "boss moment" that tests the build before the 6:00 final boss. It gives no boss power.

## Decided (by maxktchn)
- **Duel, not a swarm add.** When the fight starts, normal spawns stop. Enemies already alive stay alive and keep fighting; nothing despawns.
- **It splits when it dies.** The Big Cheese breaks into 3 Cheese Wedges, and each wedge breaks into 2 Cheese Cubes (1 → 3 → 6). The fight ends when the last piece dies.
- **The run clock freezes at 3:00** while any cheese piece is alive. When the last piece dies, the clock and normal spawns start again. You can't reach 6:00 without killing the cheese.

## Approaches considered
1. **Splits on death (picked).** One clear end to the fight, each split feels like progress, and it reads well on a phone. It's the least code: when a piece dies, it spawns its children.
2. **Sheds pieces at 75/50/25% HP.** A single long bar, and leftover wedges join the crowd. It has more state to track, and there's no clear point for spawns to resume.

## Behaviour
- **Trigger:** the first time the run clock reaches `RunRules.MiniBossAtSeconds` (180), and only if the chapter has a `MiniBoss`. If a dev jumps the clock past 3:00, the fight is skipped.
- **Start:**
  - The clock holds at 3:00 (the HUD timer shows 3:00).
  - Normal spawns stop.
  - The Big Cheese spawns where normal enemies spawn (off to the side of the chef, inside the walls).
- **Pieces:**
  - They are normal enemies (pooled parts, every weapon hits them, touching hurts).
  - When one dies, its children appear around where it died. Splits ignore the alive cap, so a busy screen can't swallow a piece and soft-lock the clock.
- **End:** when no cheese pieces are left, the clock runs again and the current phase's spawns start again.
- **Pauses:** "Order Up!" pauses everything, the same as now.
- **Restart:** a new run clears the fight state.
- **Run report:** adds one line saying how long the cheese fight took. The report's "at m:ss" uses the run clock, which leaves out the fight.

## Numbers (my proposal; tune after playtests)
Pieces are **not** HP-scaled. The clock is frozen at 3:00 anyway, so the numbers below are what you fight.

| Piece | Count | HP | Speed | Damage | Tips | Size | Look |
|---|---|---|---|---|---|---|---|
| The Big Cheese | 1 | 600 | 6 | 12 | 20 | 6 ball | yellow (255, 200, 60) |
| Cheese Wedge | 3 | 120 | 10 | 8 | 6 | 3.5 block | lighter yellow |
| Cheese Cube | 6 | 40 | 15 | 5 | 3 | 2 block | pale yellow |

- Total HP is 1,320, and the whole fight drops 56 tips.
- For scale: a 3:00 Meatball has 68 HP, and the Microwave Monster has 3,500.
- All pieces chase the chef. The Cubes (15) are just slower than the chef (16), so they can only barely be outrun.
- **Reward:** the Big Cheese always drops a Pie when it splits (my call: it's a breather for weak builds). Beyond that, just the tips.

## Visuals
- The Big Cheese gets a name plus a big HP bar over it, like the Microwave Monster. The bar logic moves into a shared helper in BossService, so it isn't copied.
- Wedges and Cubes get the normal small enemy health bars (#81).
- HUD: while the fight is on, a line under the timer reads "Defeat The Big Cheese!".

## Code shape (for the builder)
- **Config, `Enemies.luau`:**
  - Add the `CheeseWedge` and `CheeseCube` enemies, with `Mvp = true`. They're kept out of `RunRules.EnemyPool`, so the waves never spawn them.
  - Add two optional fields, `SplitInto: string?` and `SplitCount: number?`.
- **Config, `Bosses.luau`:** give `BigCheese` a `Body` with `SplitInto = "CheeseWedge"`, `SplitCount = 3`. The wedge has `SplitInto = "CheeseCube"`, `SplitCount = 2`.
- **`ConfigCheck`:** `SplitInto` must name a real enemy, and `SplitCount` must be ≥ 1.
- **RunManager** (still must not require EnemyService):
  - `onMiniBoss(callback)` fires once when the clock reaches 180.
  - `holdClock(on)`: while on, the clock doesn't advance and phase listeners are told "spawn nothing". When it's turned off, the current phase is announced again.
  - Reset on restart.
- **New `MiniBossService`:**
  - Listens to `onMiniBoss`, holds the clock and spawns the Big Cheese.
  - On every enemy kill whose config has `SplitInto`, spawns the children, unscaled and past the cap. It needs a small `EnemyService.spawnPiece(type, position)`, or an option on `spawn`.
  - Counts the cheese pieces alive. At 0, it releases the clock.
  - Sets the player attribute `MiniBoss` (the name while the fight is on, otherwise nil) for the HUD line.
- **PlaytestBotController:** the Big Cheese counts as "big" (dodge from 14 studs), because `Bosses[name]` already covers it. The pieces are small.
- **DEV panel:** a "Big Cheese" button that jumps the clock to 2:55, so the fight is quick to test.
- **PRD:** add the 3 rows to §3.5/§3.4, describe the clock freeze in §2.1 step 6, and give the Phase 1 timeline note.

## Non-goals
- No boss power, no arena ring, no cheese-specific attacks (no pulses, no summons).
- No new art beyond coloured parts.
