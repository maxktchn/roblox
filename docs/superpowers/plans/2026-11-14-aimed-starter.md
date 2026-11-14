# Aimed Starter Weapon Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The starter weapon (Chef's Knife, and its recipe Sushi Master Blade) swings automatically toward the player's aim (mouse on PC, right aim stick on mobile, right stick on gamepad), with a floor indicator; jumping is removed.

**Architecture:** The client works out a flat aim direction and sends it on a new unreliable remote, only on change and at most `RunRules.AimMessagesPerSecond` times a second. `WeaponService` validates and stores the latest aim, and `attackArc` uses it for weapons whose config has `Aimed = true` (falling back to the chef's facing until the first aim). A new client `AimController` owns input, the mobile stick and the indicator.

**Tech Stack:** Roblox Luau (`--!strict`), Rojo 7.7.1, StyLua, Selene, luau-lsp. No unit-test framework: "tests" are `ConfigCheck` rules plus Studio playtest scripts run through Studio MCP `execute_luau`, with the exact assertions below.

**Spec:** `docs/superpowers/specs/2026-11-14-aimed-starter-design.md`

## Global Constraints

- Every file starts with `--!strict`; `stylua --check src`, `selene src`, `rojo build`, `luau-lsp analyze` must pass (run the scratchpad `check.sh`; expect `RESULT: PASS`).
- Server authority (PRD §8.4): the client sends only a direction; the server decides swing timing, reach and hits.
- Only weapons with `Aimed = true` aim: `Starters.ChefsKnife` and `Recipes.SushiMasterBlade`. Gadgets, gadget recipes and boss powers never aim.
- Chef's body keeps facing movement (do not change `Humanoid.AutoRotate`).
- Mobile: thumb off the aim stick keeps the last aim. Aim stick only on touch devices, fixed bottom-right, thumb-sized (PRD §7.4).
- Before the first aim in a run, aimed weapons use the chef's facing.
- `RunRules.AimMessagesPerSecond = 20`.
- When a config number changes, update `docs/PRD.md` to match (CLAUDE.md).
- Commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **Junk aim from a modified client** (NaN, infinity, strings, zero-length, missing args): ignored, no server error, previous aim kept. Test in Task 2.
2. **Aim flood** (hundreds of messages a second): extras past the cap ignored, server keeps running. Test in Task 2.
3. **Play again / DEV Restart:** aim cleared, the knife uses facing until the player aims again. Test in Task 2.
4. **Knife evolves into Sushi Master Blade:** still aimed with the same stored direction. Test in Task 2.
5. **Mouse over UI, outside the window, or a ray that misses the floor plane:** aim keeps its last value, never NaN. Test in Task 3.

---

### Task 1: Config — `Aimed` flag, send cap, ConfigCheck rules

**Files:**
- Modify: `src/config/Starters.luau` (type `Starter`: add `Aimed: boolean?`; `ChefsKnife.Aimed = true`; Attack text → `"Quick slashes toward where you aim"`)
- Modify: `src/config/Recipes.luau` (recipe type: add `Aimed: boolean?`; `SushiMasterBlade.Aimed = true`)
- Modify: `src/config/RunRules.luau` (add `AimMessagesPerSecond = 20` under a `-- Aiming (PRD §2.2)` comment)
- Modify: `src/shared/ConfigCheck.luau` (new rules below)

**Interfaces:**
- Produces: `Starters[id].Aimed: boolean?`, `Recipes[id].Aimed: boolean?`, `RunRules.AimMessagesPerSecond: number`.

- [ ] **Step 1: Write the failing check (Studio, Edit datamodel)**

```lua
-- Mark a gadget as aimed, which must be rejected.
local Gadgets = require(game.ReplicatedStorage.Config.Gadgets) :: any
Gadgets.Blender.Aimed = true
local problems = require(game.ReplicatedStorage.Shared.ConfigCheck).run()
local found = false
for _, p in problems do if string.find(p, "Blender") and string.find(p, "Aimed") then found = true end end
assert(found, "expected an Aimed problem for Blender")
```

- [ ] **Step 2: Run it** — Expected: assertion fails (no such rule yet).

- [ ] **Step 3: Implement the rules in `ConfigCheck.run()`**
  - Any gadget (`Gadgets[id].Aimed`) → fail `Weapon {id}: Aimed is only for starters and their recipes`.
  - A recipe with `Aimed` whose `Weapon` is not a starter → same message.
  - An aimed weapon whose `Shape` is not `"Arc"` → fail `Weapon {id}: Aimed needs a shape with a direction (Arc)`.
  - `RunRules.AimMessagesPerSecond` must be > 0.

- [ ] **Step 4: Verify** — Step 1 script passes; then in a fresh Studio session `ConfigCheck.run()` returns `{}`; `check.sh` prints `RESULT: PASS`.

- [ ] **Step 5: Commit** — `git commit -m "Add the Aimed weapon flag and aim send cap"`

---

### Task 2: Server — aim remote, validation, aimed `attackArc`, no jump

**Files:**
- Modify: `src/shared/Remotes.luau` (second list `UNRELIABLE_NAMES = { "AimDirection" }` created as `UnreliableRemoteEvent`; `Remotes.getUnreliable(name: string): UnreliableRemoteEvent`)
- Modify: `src/server/Services/WeaponService.luau`
- Modify: `docs/PRD.md` (§1.4 pillar 1, §3.1, §8.4 — wording from the spec's "PRD changes")

**Interfaces:**
- Consumes: Task 1 config.
- Produces:
  - Remote `AimDirection` (client → server, unreliable): `(x: number, z: number)`.
  - `WeaponService.getAim(): Vector3?` — the stored flat unit aim for the run's player, or nil (for tests).
  - `WeaponFx` for an Arc weapon keeps its signature `(weaponId, facing: Vector3, range, arcDegrees)`; `facing` is now the direction actually used.

- [ ] **Step 1: Write the failing playtest (Studio Play; server script injected into ServerScriptService, results read from attributes)**

```lua
-- Chef faces -Z (default). Aim +X. One bread at +X 5 studs, one at -X 5 studs.
-- After 1 s: the +X bread is dead, the -X bread is alive.
assert(WeaponService.getAim() == nil)          -- before any aim
-- (client) Remotes.getUnreliable("AimDirection"):FireServer(1, 0)
assert(WeaponService.getAim():FuzzyEq(Vector3.new(1, 0, 0)))
-- Review Focus 1: junk keeps the last aim
for _, junk in { {0/0, 1}, {math.huge, 0}, {"a", "b"}, {0, 0}, {} } do fire(table.unpack(junk)) end
assert(WeaponService.getAim():FuzzyEq(Vector3.new(1, 0, 0)))
-- Review Focus 2: 500 messages in one frame alternating (0,1)/(0,-1); afterwards getAim() is one of
-- them and no errors appear in Output; the server's frame keeps running (Heartbeat still fires).
-- Review Focus 4: WeaponService.replaceWeapon("ChefsKnife", "SushiMasterBlade"); with aim (-1, 0)
-- a bread at -X 5 studs dies, one at +X 5 studs survives.
-- Review Focus 3: RestartService.restart() → getAim() == nil.
-- Jump: after spawn, character Humanoid.JumpHeight == 0 and JumpPower == 0.
```

- [ ] **Step 2: Run it** — Expected: fails at `getAim` (doesn't exist).

- [ ] **Step 3: Implement in `WeaponService`**
  - Local `aim: Vector3?` plus a per-second counter. `OnServerEvent(player, x, z)`: only the run's player; drop if this second's count ≥ `AimMessagesPerSecond`; require `type(x) == "number" and type(z) == "number"`, both finite and not NaN, flat length > 0.01; store `Vector3.new(x, 0, z).Unit`.
  - Helper `getAttackDirection(weaponId: string, root: BasePart): Vector3` — the stored aim if the weapon's config has `Aimed` and an aim exists, else today's flattened `root.CFrame.LookVector`. `attackArc` uses it for `facing`.
  - `WeaponService.reset()` sets `aim = nil`.
  - `WeaponService.getAim()` returns `aim`.
  - On each `CharacterAdded`: `humanoid.UseJumpPower = false; humanoid.JumpHeight = 0` (and `JumpPower = 0` for safety).
  - Update PRD §1.4 pillar 1, §3.1 (starters and their recipes are aimed; gadgets are not), §8.4 (the client sends movement, card choices and a validated, rate-limited aim direction; the server decides every hit).

- [ ] **Step 4: Verify** — every assertion above passes; `check.sh` → `RESULT: PASS`; no errors in Output.

- [ ] **Step 5: Commit** — `git commit -m "Aim the starter weapon from a validated client aim direction"`

---

### Task 3: Client — `AimController` for mouse and gamepad, sending

**Files:**
- Create: `src/client/Controllers/AimController.luau`

**Interfaces:**
- Consumes: `Remotes.getUnreliable("AimDirection")`, `RunRules.AimMessagesPerSecond`.
- Produces: `AimController.getAim(): Vector3?` (latest local flat unit aim, for Task 4's indicator); `AimController.setAimFromStick(screenOffset: Vector2)` (used by Task 4's mobile stick; screen offset in pixels, +X right, +Y down).

- [ ] **Step 1: Write the failing playtest (Studio Play, client)**

```lua
local Aim = require(game.Players.LocalPlayer.PlayerScripts.Client.Controllers.AimController)
-- Stick input maps through the fixed camera: screen right = world +X, screen down = world +Z.
Aim.setAimFromStick(Vector2.new(50, 0));  assert(Aim.getAim():FuzzyEq(Vector3.new(1, 0, 0)))
Aim.setAimFromStick(Vector2.new(0, -50)); assert(Aim.getAim():FuzzyEq(Vector3.new(0, 0, -1)))
-- Dead zone: small offsets don't change the aim
Aim.setAimFromStick(Vector2.new(2, 2));   assert(Aim.getAim():FuzzyEq(Vector3.new(0, 0, -1)))
-- Review Focus 5: a mouse position whose ray misses the floor plane (e.g. above the horizon, or
-- the chef missing) leaves getAim() unchanged and never NaN.
-- Sending: moving the mouse continuously for 1 s sends ≤ 20 AimDirection messages; holding still sends 0.
```

- [ ] **Step 2: Run it** — Expected: fails (module doesn't exist).

- [ ] **Step 3: Implement `AimController`**
  - `RenderStepped`: if the last input type was mouse/keyboard, cast `camera:ViewportPointToRay(mouse.X, mouse.Y)` onto the plane `y = root.Position.Y`; ignore if the ray is parallel, points away, or there's no chef; aim = flat unit direction chef → hit point. Gamepad: right thumbstick (`Thumbstick2`) past a 0.3 dead zone sets aim as `Vector3.new(stick.X, 0, -stick.Y)`.
  - `setAimFromStick(offset)`: ignore if `offset.Magnitude < 10`; aim = `Vector3.new(offset.X, 0, offset.Y).Unit` (camera is fixed looking toward −Z, so screen axes map directly).
  - Send when the aim changed by more than 2° since the last send and at least `1 / AimMessagesPerSecond` s have passed.
  - Before the first aim, `getAim()` returns nil.

- [ ] **Step 4: Verify** — assertions pass; in Studio with the mouse, the knife's slash follows the cursor; `check.sh` → `RESULT: PASS`.

- [ ] **Step 5: Commit** — `git commit -m "Aim with the mouse and gamepad"`

---

### Task 4: Client — mobile aim stick, hidden jump button, floor indicator

**Files:**
- Modify: `src/client/Controllers/AimController.luau`
- Modify: `docs/PRD.md` (§2.2 controls, §7.4 mobile — wording from the spec)

**Interfaces:**
- Consumes: Task 3's `setAimFromStick`, `getAim`; `Starters`/`Recipes` config for the current aimed weapon's `Range` and `ArcDegrees` at the player's level (read `Weapon_<id>` attributes).

- [ ] **Step 1: Write the failing playtest (Studio Play, client; device emulator for touch)**

```lua
-- Indicator: a part named "AimIndicator" exists, faces the aim, length = current Range
-- (Knife Lv 1: 10 studs), and is hidden while PlayerGui.OrderUp.Enabled or RunState ~= "Playing".
-- Touch device (emulator): ScreenGui "AimStick" visible, bottom-right, base ≥ 120 px;
-- PC: AimStick not visible. Jump button not visible on touch.
-- Releasing the stick keeps getAim() unchanged.
```

- [ ] **Step 2: Run it** — Expected: fails (no indicator or stick).

- [ ] **Step 3: Implement**
  - **Stick:** ScreenGui `AimStick` (`ScreenInsets = CoreUISafeInsets`), a 140 px base circle anchored bottom-right with a 24 px margin and a 60 px knob. Track one touch that starts inside the base; knob follows within the base radius; each move calls `setAimFromStick(knobOffset)`; on release the knob recentres and the aim stays. Visible only when `UserInputService.TouchEnabled` and the last input was touch.
  - **Jump button:** if `PlayerGui.TouchGui.TouchControlFrame.JumpButton` still shows after spawn, set `Visible = false`.
  - **Indicator:** one anchored, non-colliding, non-queryable wedge part (`AimIndicator`, transparency ~0.85, the weapon's `FxColor`) lying on the floor in front of the chef, pointing along `getAim()` (or facing before the first aim), sized to the aimed weapon's current `Range` and `ArcDegrees`; updated each `RenderStepped`; hidden while the cards are open or the run is over.
  - Update PRD §2.2 and §7.4.

- [ ] **Step 4: Verify** — assertions pass; on the emulator the stick aims the slash and the indicator; `check.sh` → `RESULT: PASS`.

- [ ] **Step 5: Commit, push, PR** — `git commit -m "Add the mobile aim stick and aim indicator"`, then push the branch and open a PR referencing both spec and plan.
