# The Big Cheese Mini-Boss Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** At 3:00, the run clock freezes, normal spawns stop, and The Big Cheese appears. It splits on death (1 → 3 Wedges → 6 Cubes), and the clock and spawns resume when the last piece dies.

**Architecture:**
- RunManager gets a mini-boss trigger and a "clock held" switch. It still doesn't require EnemyService.
- A new `MiniBossService` owns the fight: it spawns the cheese, splits pieces on kill, counts the pieces still alive, and releases the clock.
- Splitting is config data (`SplitInto` / `SplitCount` on an enemy).
- The boss HP bar is pulled out of BossService into a small shared module, so both bosses use it.

**Tech Stack:** Luau `--!strict`, Rojo, Roblox Studio (tests are `execute_luau` scripts run in a Studio play session, as in earlier issues).

**Spec:** `docs/superpowers/specs/2026-11-15-big-cheese-design.md`

## Global Constraints
- Every file starts with `--!strict`. `stylua`, `selene`, `rojo build` and `luau-lsp analyze` stay clean: run `stylua src`, then the check script, and expect `RESULT: PASS`.
- RunManager must not require EnemyService, WeaponService or UpgradeService.
- Enemies are pooled parts with no Humanoids. Splits ignore `RunRules.MaxAliveEnemies`.
- Cheese pieces are **not** HP-scaled.
- Numbers (from the spec):
  - Big Cheese: HP 600, Speed 6, Damage 12, Tips 20, Ball 6×6×6, colour (255, 200, 60), `PieDropChance = 1`.
  - Wedge: 120 / 10 / 8 / 6, Block 3.5×3×3.5, colour (255, 215, 100).
  - Cube: 40 / 15 / 5 / 3, Block 2×2×2, colour (255, 230, 150).
  - All use `Movement = "Chase"`.
- HUD copy: `Defeat The Big Cheese!`
- Every config number change gets a matching PRD update.

## Review Focus
1. **Restart or death mid-fight:** a new run must start with the clock free, no fight active, and no leftover HP bar. (Task 4, restart test)
2. **A dev clock jump during or past the fight:** the BOSS NOW button at 2:00 must not start the cheese at 6:00. SetTime while the clock is held must release it, or the final boss could never start. (Task 2 tests)
3. **A full alive cap (150) at split time:** every child piece must still appear, or the clock stays frozen forever. (Task 3 test)
4. **"Order Up!" during the fight:** the clock must stay at 3:00 after the cards close, and spawns must stay off. (Task 4 test)
5. **A piece dying against a wall:** its children must spawn inside the arena. This comes from `clampToArena` in the spawn path (Task 3).

---

### Task 1: Cheese config and checks

**Files:**
- Modify: `src/config/Enemies.luau` (type + 2 entries + header comment)
- Modify: `src/config/Bosses.luau` (`BigCheese.Body`)
- Modify: `src/shared/ConfigCheck.luau` (enemy loop ~L192, chapter loop ~L208)
- Modify: `docs/PRD.md` §3.4 table, §3.5 Big Cheese row

**Interfaces:**
- Produces:
  - Two new optional fields on `Enemies.Enemy`: `SplitInto: string?` and `SplitCount: number?`.
  - Enemy ids `CheeseWedge` and `CheeseCube`.
  - `Bosses.BigCheese.Body`: Name "The Big Cheese", Role "Mini-boss", `SplitInto = "CheeseWedge"`, `SplitCount = 3`.
  - `CheeseWedge` has `SplitInto = "CheeseCube"`, `SplitCount = 2`. `CheeseCube` has no split.
  - None of the three goes in `RunRules.EnemyPool`.

- [ ] **Step 1: Add the config**
  - Add the fields, entries and Body with the Global Constraints numbers.
  - The header comment explains `SplitInto` and `SplitCount`: "when it dies, SplitCount of SplitInto appear where it died (MiniBossService)".
- [ ] **Step 2: Add the ConfigCheck rules**
  - Check every enemy config, including boss Bodies: `SplitInto` must be a key of `Enemies`, and `SplitCount` must be a whole number ≥ 1 whenever `SplitInto` is set.
  - A chapter's `MiniBoss` must have a `Body`. Failure message: `Chapter {id}: mini-boss "{x}" has no Body`.
- [ ] **Step 3: Verify**
  - Run `stylua src` and the check script; expect `RESULT: PASS`.
  - In Studio, play and expect no `ConfigCheck` failure in Output.
  - Temporarily set `SplitInto = "Nope"` on the Wedge, play, and expect a ConfigCheck failure naming `CheeseWedge`. Revert it.
- [ ] **Step 4: Update the PRD**
  - Add the 3 cheese rows to the §3.4 table, marked mini-boss pieces with no scaling.
  - Set the §3.5 Big Cheese mechanics to "Splits on death: 1 → 3 Wedges → 6 Cubes".
- [ ] **Step 5: Commit** `Big Cheese config: cheese pieces and SplitInto (#84)`

### Task 2: RunManager mini-boss trigger and clock hold

**Files:**
- Modify: `src/server/Services/RunManager.luau`

**Interfaces:**
- Produces:
  - `RunManager.onMiniBoss(callback: () -> ())` fires once per run, on the frame the clock **crosses** `RunRules.MiniBossAtSeconds` by counting up: the value before the frame's `+= deltaTime` is < 180 and the value after is ≥ 180. On that frame the clock is set to exactly 180 before the callbacks run.
  - `RunManager.setClockHeld(held: boolean)`:
    - While held, `update` doesn't advance `runSeconds` or the phase.
    - Holding tells every phase listener `({}, 0)`.
    - Releasing re-announces `setPhase(findPhase(runSeconds))`.
  - `RunManager.isClockHeld(): boolean`
  - `RunManager.reset()` clears the hold and re-arms the trigger.
  - `RunManager.setRunSeconds(s)`:
    - Releases a hold (dev override).
    - Re-arms the trigger when `s < MiniBossAtSeconds`.
    - Never fires the trigger itself (a jump isn't a crossing).

- [ ] **Step 1: Write the Studio test** as a server Script that writes results to workspace attributes:
  - `setRunSeconds(178)`, wait about 3 s: the callback fired exactly once and `getRunSeconds() == 180` while held. (The test's callback calls `setClockHeld(true)`.)
  - Wait 2 s: still `180`.
  - `setClockHeld(false)`, wait 1 s: `> 180`.
  - `setRunSeconds(100)`, then `setRunSeconds(300)`: the callback count doesn't change (a jump isn't a crossing).
  - `setRunSeconds(178)` and wait again: it fires a second time (re-armed by the jump below 180).
  - Hold, then `setRunSeconds(200)`: `isClockHeld() == false`.
- [ ] **Step 2: Run it** on the current code. Expect a failure: `onMiniBoss` is nil.
- [ ] **Step 3: Implement** the interfaces above. Keep the new state next to `finalBossStarted`, and update the header comment.
- [ ] **Step 4: Run the test** and expect every check to pass. Run the check script and expect `RESULT: PASS`.
- [ ] **Step 5: Commit** `RunManager: mini-boss trigger at 3:00 and a clock hold (#84)`

### Task 3: Unscaled spawns and the shared boss HP bar

**Files:**
- Modify: `src/server/Services/EnemyService.luau` (next to `spawnBoss`)
- Create: `src/server/BossHpBar.luau` (a plain module, **not** in `Services/`, so `Main` doesn't boot it)
- Modify: `src/server/Services/BossService.luau` (`decorateBoss` uses it)

**Interfaces:**
- Produces:
  - `EnemyService.spawnUnscaled(enemyType: string, position: Vector3): EnemyId?`
    - Works for any enemy or boss type (via `getConfigForType`).
    - No HP or damage scaling, ignores the alive cap, and clamps to the arena.
    - Returns nil and warns only for an unknown type.
  - `BossHpBar.attach(part: BasePart, title: string): Frame`
    - Builds the name plus bar BillboardGui exactly as `decorateBoss` does today: 12×2.2 scale, offset Y half + 2.5, the same colours and font.
    - It first removes any old `BossHp` BillboardGui from the part (pooled parts).
    - Returns the fill Frame. Callers set `fill.Size = UDim2.fromScale(hp / maxHp, 1)`.

- [ ] **Step 1: Write the Studio test**
  - Fill the alive count to `MaxAliveEnemies` with `spawn("MoldyBread", …)`.
  - `spawnUnscaled("CheeseCube", pos)` returns a number.
  - `getEnemyHp(id)` returns `40, 40`, even with the clock at 5:00 (no scaling).
  - `spawnUnscaled("Nope", pos)` returns nil.
- [ ] **Step 2: Run it** and expect a failure: `spawnUnscaled` is nil.
- [ ] **Step 3: Implement** `spawnUnscaled`. `spawnBoss` becomes a thin check that calls it. Then add `BossHpBar` and switch BossService over to it (`decorateBoss` keeps the microwave face).
- [ ] **Step 4: Verify**
  - The test passes.
  - BOSS NOW: the Microwave Monster still shows its name and bar, and the bar drops when it's hit (read the `Fill` size through a script).
  - The check script prints `RESULT: PASS`.
- [ ] **Step 5: Commit** `EnemyService.spawnUnscaled and a shared boss HP bar (#84)`

### Task 4: MiniBossService, HUD line, run report and restart

**Files:**
- Create: `src/server/Services/MiniBossService.luau`
- Modify: `src/server/Services/RestartService.luau` (`MiniBossService.reset()` after `BossService.reset()`)
- Modify: `src/server/Services/RunReportService.luau` (one line in `buildReport`)
- Modify: `src/client/Controllers/HUDController.luau` (a label under the timer)

**Interfaces:**
- Consumes:
  - `RunManager.onMiniBoss`, `setClockHeld` (Task 2)
  - `EnemyService.spawnBoss`, `spawnUnscaled` (Task 3), `getConfigForType`, `onEnemyKilled`, `getEnemyHp`, `getEnemyPart`
  - `BossHpBar.attach` (Task 3)
- Produces:
  - `MiniBossService.reset()`: forget the fight, release nothing (RunManager.reset does that), clear the attribute.
  - `MiniBossService.getFightSeconds(): (number?, boolean)`: the fight's length so far in unpaused seconds (nil if no fight this run), and whether it's finished.
  - Player attribute `MiniBoss`: the boss's `Name` while the fight is on, otherwise nil.

Behaviour (from the spec):
- On `onMiniBoss`:
  - Read the chapter's `MiniBoss` (`Chapters[RunManager.getChapter()]`). If it's missing or has no Body, do nothing.
  - Hold the clock.
  - Spawn the cheese with `spawnBoss`, 30 studs from the chef in a random flat direction.
  - Attach its HP bar and add its id to a `pieces` set.
- On a kill of an id in `pieces`:
  - Remove the id from the set.
  - If its config has `SplitInto`, spawn `SplitCount` children with `spawnUnscaled`, 2–4 studs from the death spot at random angles, and add their ids.
  - If the set is now empty, release the clock, clear the attribute, and mark the fight finished.
- A Heartbeat loop:
  - Updates the bar while the cheese is alive.
  - Adds `deltaTime` to the fight time when the fight is on and the run isn't paused or over.
- Report line, placed after `Progress`:
  - `Big Cheese: beaten in m:ss`
  - `Big Cheese: still alive after m:ss` (the run ended mid-fight)
  - `Big Cheese: not reached`

- [ ] **Step 1: Write the Studio test** (a play session, God mode on):
  - Set the clock to 2:58 and wait 3 s:
    - one `BigCheese` part is under `workspace.Enemies` above y −50
    - `RunSeconds == 180`
    - the attribute `MiniBoss == "The Big Cheese"`
    - the live non-cheese enemy count doesn't rise over the next 3 s (spawns are off)
    - the non-cheese enemies alive before 2:58 are still there.
  - Damage the cheese by 600 through `EnemyService.damage`: 3 `CheeseWedge` appear and a Pie appears in `workspace.Tips`.
  - Kill the wedges: 6 cubes appear.
  - Open "Order Up!" (+1 level) mid-fight, pick a card, and the clock is still 180.
  - Kill the cubes: `MiniBoss` is nil and the clock is > 180 within 2 s.
  - The report from `RunReportService` (after `RunManager.winRun()`) contains `Big Cheese: beaten in`.
  - Restart test: start the fight again (set the clock to 2:58), then call `RestartService.restart()`:
    - `isClockHeld() == false`
    - `MiniBoss` is nil
    - the clock counts up from 0
    - no `BossHp` gui is left on any live part.
- [ ] **Step 2: Run it** and expect a failure: no BigCheese appears.
- [ ] **Step 3: Implement** MiniBossService, the restart call, the report line, and the HUD label.
  - The HUD label sits under the timer: FredokaOne, yellow (255, 200, 60), `Defeat The Big Cheese!`.
  - It's visible only while the `MiniBoss` attribute is set.
- [ ] **Step 4: Run the test** and expect every check to pass. Screenshot the HUD line. Run the check script and expect `RESULT: PASS`.
- [ ] **Step 5: Commit** `The Big Cheese mini-boss: clock holds at 3:00 until every piece is gone (#84)`

### Task 5: DEV button, PRD flow text, full playthrough

**Files:**
- Modify: `src/server/Services/DevCommandService.luau` (`ACTIONS.Cheese`)
- Modify: `src/client/Controllers/DevPanelController.luau` (a button next to BOSS NOW)
- Modify: `docs/PRD.md` §2.1 step 6, the Phase 1 timeline note (~L255)
- Modify: `CLAUDE.md` only if its scope line changes (it shouldn't)

**Interfaces:**
- Produces: dev action `"Cheese"`, which calls `RunManager.setRunSeconds(RunRules.MiniBossAtSeconds - 5)` and replies `The Big Cheese arrives in 5 s`. Button label: `CHEESE NOW`.

- [ ] **Step 1: Implement** the action, the button, and the PRD text.
  - §2.1 step 6: "At 3:00, The Big Cheese appears: normal spawns stop and the run clock holds at 3:00 until every cheese piece is defeated".
  - Timeline note: the same, in one sentence.
- [ ] **Step 2: Full playthrough in dev.rbxl**
  - One normal run with the playtest bot (1 run). Expect the report line `Big Cheese: beaten in …` or `still alive after …`, and no errors in Output.
  - CHEESE NOW works twice in one run, because a jump below 3:00 re-arms the trigger.
- [ ] **Step 3: Run the check script** and expect `RESULT: PASS`.
- [ ] **Step 4: Commit** `DEV: CHEESE NOW button; PRD run flow for the Big Cheese (#84)`. Also commit the spec and plan docs.
