# Boss Powers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Beating the Microwave Monster unlocks **Microwave Pulse**, a boss power that can then appear as a rarer "Order Up!" card and attacks with a new **Pulse** shape (an expanding ring that hits and knocks back each enemy once).

**Architecture:** Boss powers are config (`BossPowers.luau`) using the existing weapon pipeline (`WeaponService`, card pool, HUD, FX) plus one new shape. A new `UnlockService` holds unlocks in memory for Phase 1 (per server; survives "Play again") and is the only place Phase 2 saving will need to hook into. Unlocking listens to `EnemyService.onEnemyKilled` for a boss with a `Power`, so `BossService` is untouched.

**Tech Stack:** Roblox Luau (`--!strict`), Rojo 7.7.1, StyLua, Selene, luau-lsp. No unit-test framework: "tests" are `ConfigCheck` rules plus Studio playtest scripts (Studio MCP `execute_luau`; server code injected as a Script into ServerScriptService so it shares the real module cache, results read from attributes).

**Spec:** `docs/superpowers/specs/2026-11-14-boss-powers-design.md`

## Global Constraints

- Every file starts with `--!strict`; `check.sh` (stylua, selene, rojo build, luau-lsp) prints `RESULT: PASS`.
- Server authority: unlocks and cards are decided on the server; the client only draws.
- Boss powers are never sold; only a defeated boss unlocks its power.
- The Blender and Smoothie Vortex stay in the normal pool (nothing existing gets locked).
- A boss power uses a shared slot and levels 1–5 like a gadget. No recipes.
- `RunRules.BossPowerNewCardChance = 0.35`; rarity applies only to the NEW card.
- Microwave Pulse numbers (Damage / Cooldown s / Range / Speed studs/s / Knockback):
  Lv1 12/3.0/14/30/4 · Lv2 15/2.8/15/32/5 · Lv3 19/2.6/17/34/6 · Lv4 24/2.4/19/36/7 · Lv5 30/2.2/22/40/8.
- When a config number changes, update `docs/PRD.md` to match.
- Coordinate with the aiming work (#59–#62): both edit `WeaponService`. Start after aiming merges, or rebase onto it.
- Commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **Beating the boss when the power is already unlocked:** no second "New power unlocked" line, no error. Test in Task 2.
2. **Dying in the boss fight:** nothing unlocks. Test in Task 2.
3. **Play again:** unlocks stay (same server), the "New power unlocked" line clears. Test in Task 2.
4. **All 6 slots full:** the power's NEW card is never offered; an owned power's upgrade still is. Test in Task 4.
5. **Knockback pushes an enemy outward into the still-growing ring:** it's hit only once by that pulse. Test in Task 3.

---

### Task 1: Config — `BossPowers.luau`, Pulse shape fields, boss `Power`, checks, PRD

**Files:**
- Create: `src/config/BossPowers.luau` (type `BossPower = { Name, Behavior, Boss: string, Shape: WeaponTypes.Shape, FxColor: Color3, Levels: { WeaponLevel } }`; entry `MicrowavePulse`, `Boss = "MicrowaveMonster"`, `Shape = "Pulse"`, numbers from Global Constraints, `FxColor = Color3.fromRGB(255, 190, 70)`, `Behavior = "A shockwave ring blasts enemies back"`)
- Modify: `src/shared/WeaponTypes.luau` (`Shape` gains `"Pulse"`; `WeaponLevel` gains `Knockback: number?`; comments for Pulse meanings of Range/Speed/Cooldown)
- Modify: `src/config/Bosses.luau` (type `Boss` gains `Power: string?`; `MicrowaveMonster.Power = "MicrowavePulse"`)
- Modify: `src/config/RunRules.luau` (`UpgradePool.BossPowers = { "MicrowavePulse" }`, `BossPowerNewCardChance = 0.35`)
- Modify: `src/shared/ConfigCheck.luau`
- Modify: `docs/PRD.md` (new §3.8 Boss Powers; Power column in §3.5; §9 roadmap; §8.1 and §7.1 lobby-as-menu; all wording from the spec's "PRD and roadmap changes")

**Interfaces:**
- Produces: `BossPowers[id]`, `RunRules.UpgradePool.BossPowers: { string }`, `RunRules.BossPowerNewCardChance: number`, `Bosses[id].Power: string?`, Shape `"Pulse"`, `WeaponLevel.Knockback`.

- [ ] **Step 1: Write the failing check (Studio Edit)**

```lua
local problems = require(game.ReplicatedStorage.Shared.ConfigCheck).run()
assert(#problems == 0, table.concat(problems, "\n"))          -- real config is clean
local Bosses = require(game.ReplicatedStorage.Config.Bosses) :: any
Bosses.MicrowaveMonster.Power = "Nope"
local bad = require(game.ReplicatedStorage.Shared.ConfigCheck).run()
local found = false
for _, p in bad do if string.find(p, "Nope") then found = true end end
assert(found, "unknown boss Power must be reported")
```

- [ ] **Step 2: Run it** — Expected: fails (no `BossPowers` / no rule).

- [ ] **Step 3: Implement the config and rules**
  - Every `UpgradePool.BossPowers` id exists and passes `checkWeapon(id, power, SharedItemMaxLevel)`; Pulse requires `Speed` and `Range` > 0.
  - Every boss `Power` exists in `BossPowers`, and that power's `Boss` equals the boss id.
  - `BossPowerNewCardChance` is between 0 and 1.

- [ ] **Step 4: Verify** — Step 1 passes; `check.sh` → `RESULT: PASS`.

- [ ] **Step 5: Commit** — `git commit -m "Add boss power config and Microwave Pulse numbers"`

---

### Task 2: `UnlockService`, unlock on boss defeat, banner line, DEV unlock

**Files:**
- Create: `src/server/Services/UnlockService.luau`
- Modify: `src/server/Services/RestartService.luau` (call `UnlockService.clearJustUnlocked()`)
- Modify: `src/server/Services/DevCommandService.luau` (action `"UnlockPowers"` → unlock every `UpgradePool.BossPowers` id)
- Modify: `src/client/Controllers/DevPanelController.luau` (RUN section button **"Unlock powers"**)
- Modify: `src/client/Controllers/HUDController.luau` (banner line when `JustUnlocked` is set)
- Modify: `docs/PRD.md` (§2.8 first boss defeat unlocks its power; §5 boss powers are never sold)

**Interfaces:**
- Consumes: Task 1's `Bosses[id].Power`, `BossPowers`.
- Produces:
  - `UnlockService.unlock(id: string): boolean` — true if newly unlocked.
  - `UnlockService.isUnlocked(id: string): boolean`
  - `UnlockService.getUnlocked(): { string }`
  - `UnlockService.clearJustUnlocked()`
  - Player attributes `Unlocked_<id> = true`; `JustUnlocked = "<power name>"` (set only on a new unlock; cleared by `clearJustUnlocked`).

- [ ] **Step 1: Write the failing playtest (Studio Play)**

```lua
-- Boss defeated → unlocked, banner line shown.
-- (server) DevAction Boss, then EnemyService.damage(bossId, 1e9)
assert(UnlockService.isUnlocked("MicrowavePulse"))
assert(player:GetAttribute("Unlocked_MicrowavePulse") == true)
assert(player:GetAttribute("JustUnlocked") == "Microwave Pulse")
-- (client) HUD RunOver banner contains a label whose Text == "New power unlocked: Microwave Pulse"
-- Review Focus 3: RestartService.restart() → still unlocked; JustUnlocked == nil
-- Review Focus 1: beat the boss again → unlock returns false; JustUnlocked stays nil; no errors
-- Review Focus 2: fresh server; start boss fight, kill the chef → isUnlocked("MicrowavePulse") == false
-- DEV: DevAction("UnlockPowers") → isUnlocked true
```

- [ ] **Step 2: Run it** — Expected: fails (no `UnlockService`).

- [ ] **Step 3: Implement**
  - `UnlockService` keeps a set in memory. In `start()`: `EnemyService.onEnemyKilled(function(_, enemyType) local power = Bosses[enemyType] and Bosses[enemyType].Power; if power then UnlockService.unlock(power) end end)`.
  - Header comment: Phase 2 saving loads/saves this set via `DataService`; nothing else changes.
  - HUD: a new label under the stats on the run-over panel, visible only when `JustUnlocked` is set.

- [ ] **Step 4: Verify** — assertions pass; `check.sh` → `RESULT: PASS`.

- [ ] **Step 5: Commit** — `git commit -m "Unlock a boss's power when it's defeated"`

---

### Task 3: Pulse shape — server attack, knockback, client effect

**Files:**
- Modify: `src/server/Services/EnemyService.luau` (new `push`; athatcher989's file — flag in the PR)
- Modify: `src/server/Services/WeaponService.luau` (config lookup includes `BossPowers`; `attackPulse`; per-frame `updatePulses`; `ATTACKS.Pulse`; reset clears pulses)
- Modify: `src/client/Controllers/WeaponFxController.luau` (config lookup includes `BossPowers`; `drawPulse`)

**Interfaces:**
- Consumes: Task 1 shape fields.
- Produces:
  - `EnemyService.push(enemyId: EnemyId, from: Vector3, studs: number)` — moves an enemy `studs` directly away from `from` (flat), clamped to the arena; bosses unaffected; `studs <= 0` does nothing.
  - `WeaponFx` for a Pulse weapon: `(weaponId, origin: Vector3, range: number, speed: number)`, sent once per pulse.

- [ ] **Step 1: Write the failing playtest (Studio Play; knife removed, chef kept alive)**

```lua
-- Microwave Pulse Lv 1 (Range 14, Damage 12, Knockback 4). Meatballs (25 HP) at 5, 10 and 20 studs.
-- After the first pulse finishes (~0.5 s):
assert(hp(at5) == 13 and hp(at10) == 13)        -- hit once each
assert(hp(at20) == 25)                           -- out of range
assert(dist(at5) >= 5 + 4 - 0.5)                 -- pushed back ~4 studs (minus their own walking)
-- Review Focus 5: the 10-stud meatball, pushed to ~14, isn't hit a second time by the same pulse
-- Boss: MicrowaveMonster at 8 studs takes 12 damage and is NOT pushed (only its walk moves it)
-- Client: a part named "MicrowavePulse" in workspace.WeaponFx grows from ~0 to 14 studs radius and fades
```

- [ ] **Step 2: Run it** — Expected: fails (no Pulse shape).

- [ ] **Step 3: Implement**
  - `attackPulse(weaponId, stats, root)`: add `{ weaponId, origin = root.Position, radius = 0, stats, hit = {} }` to `pulses`; `sendFx(weaponId, origin, stats.Range, stats.Speed)`.
  - `updatePulses(deltaTime)` (called from `update`, paused with everything else): grow `radius` by `Speed × deltaTime` (cap `Range`); for each enemy in `getEnemiesInReach(origin, radius)` not in `hit`: mark, `hit(...)` through the normal damage path (Hot Sauce, crits, hit numbers, run report), then `EnemyService.push(enemyId, origin, stats.Knockback or 0)`. Remove the pulse at full `Range`.
  - `drawPulse`: a flat ring/disc in `FxColor` growing from the chef's origin to `range` at `speed`, fading as it grows.

- [ ] **Step 4: Verify** — assertions pass; looks like a ring in Studio; `check.sh` → `RESULT: PASS`.

- [ ] **Step 5: Commit** — `git commit -m "Add the Pulse attack shape with knockback"`

---

### Task 4: Boss power cards — pool, rarity, slots, card look, HUD, DEV give, run report

**Files:**
- Modify: `src/shared/Card.luau` (`Kind` gains `"BossPower"`)
- Modify: `src/server/Services/UpgradeService.luau` (`slotsUsed`, `buildPool`, `applyCard`)
- Modify: `src/client/Controllers/UpgradeUIController.luau` (badge "BOSS POWER", its own border colour `Color3.fromRGB(255, 190, 70)`, thickness like recipes)
- Modify: `src/client/Controllers/HUDController.luau` (owned-icon lookup includes `BossPowers`, kind colour)
- Modify: `src/server/Services/DevCommandService.luau`, `src/client/Controllers/DevPanelController.luau` (Give includes boss powers, even if not unlocked)
- Modify: `src/server/Services/RunReportService.luau` (`nameOf` includes `BossPowers`)
- Modify: `docs/PRD.md` (§2.3/§7.3 card types mention the boss power card)

**Interfaces:**
- Consumes: `UnlockService.isUnlocked`, Task 1 config, Task 3 shape.
- Produces: card `{ Kind = "BossPower", Id, Name, FromLevel, ToLevel, Description }` (NEW shows `Behavior`, upgrades show `describeChange`).

- [ ] **Step 1: Write the failing playtest (Studio Play)**

```lua
-- Helper: draw 200 offers (UpgradeService internals via addTips + getCurrentOffer + chooseCard on a non-power card)
-- Not unlocked: MicrowavePulse never appears in 200 offers.
-- Unlocked, chance set to 1 for the test: NEW card appears in every offer where a slot is free.
-- Unlocked, chance 0.35: it appears in roughly 20–50% of offers (wide band; random).
-- Taking it: Weapon_MicrowavePulse == 1, counts as a slot (slotsUsed +1), HUD shows its icon.
-- Owned at Lv 2: its upgrade card is offered like any owned gadget (no chance roll).
-- Review Focus 4: fill 6 slots without it → its NEW card never appears; own it at Lv 1 with 6 slots
-- full → its upgrade still appears.
-- Client: its card shows badge "BOSS POWER" and the boss-power border colour.
-- DEV Give MicrowavePulse → Lv 1 even when locked; run report lists "Microwave Pulse" damage.
```

- [ ] **Step 2: Run it** — Expected: fails (no `BossPower` kind).

- [ ] **Step 3: Implement**
  - `buildPool`: for each `UpgradePool.BossPowers` id — owned and below max → upgrade card; not owned, unlocked, slot free, and `random:NextNumber() < BossPowerNewCardChance` (rolled once per `buildPool` call) → NEW card.
  - `slotsUsed` counts owned boss powers. `applyCard` handles `"BossPower"` like `"Gadget"`.

- [ ] **Step 4: Verify** — assertions pass; `check.sh` → `RESULT: PASS`; full run in Studio: beat the boss (DEV BOSS NOW + god mode), Play again, get offered and take Microwave Pulse, see it fire.

- [ ] **Step 5: Commit, push, PR** — `git commit -m "Offer unlocked boss powers as Order Up! cards"`, push, open the PR (flag `EnemyService.push` for athatcher989).
