# DEV Menu Tabs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split the DEV panel into RUN · GIVE · BOT · ACCOUNT tabs, add the ACCOUNT save tools, and make run-only DEV actions refuse in the lobby.

**Architecture:** Server first: `DevCommandService` gets 4 new actions (LockPowers, ReloadSave, FailSave, ResetSave) and a lobby guard on run-only actions; `DataService` gets `resetSave`. Then `DevPanelController` builds a tab row and one ScrollingFrame page per tab, moving today's sections onto them.

**Tech Stack:** Luau `--!strict`, Rojo, Roblox Studio (tests are injected server Scripts and Client `execute_luau` checks, as in the lobby build).

**Spec:** `docs/superpowers/specs/2026-11-20-dev-menu-tabs-design.md`

## Global Constraints
- Every file starts with `--!strict`; `stylua`, `selene`, `rojo build`, `luau-lsp` clean (run `check.sh`: `RESULT: PASS`).
- Server validates every DevAction argument; only `DevAccess.isAllowed` players.
- Lobby reply text, exactly: `Not in a run. Press Play or Restart run.`
- Tabs, in order: `RUN`, `GIVE`, `BOT`, `ACCOUNT`. Panel stays 290 px wide on the left; the panel opens on RUN the first time, then on the last tab used (session only, no save).
- Reset my save confirm label, exactly: `Tap again to reset` (reverts after 3 s).

## Review Focus
1. Reset my save while saving is Off (after Simulate save failure): must reset the in-memory save and resync, not try to load.
2. Reload / Reset tapped mid-run: the run keeps going; the next run uses the reloaded gear (GearService already handles a mid-run reload).
3. Restart run from the lobby must still start a run (not hit the lobby guard).
4. GIVE in the lobby must not give anything (WeaponService state would leak into the next run otherwise; Play resets it, but the reply must not lie).
5. Many GIVE buttons on a phone: the GIVE page must scroll; tab row must stay visible.

---

### Task 1: Server: new ACCOUNT actions and the lobby guard

**Files:**
- Modify: `src/server/Services/DataService.luau` (add `resetSave` next to `reload`)
- Modify: `src/server/Services/DevCommandService.luau` (actions list comment, guard, 4 actions)

**Interfaces:**
- Produces: `DataService.resetSave(player: Player)` (yields). Clears the save table in place and copies the template in; when saving is On, then `DataService.reload(player)` so it's saved and every service resyncs; when Off, `announceLoaded(player, data)` instead.
- Produces DevAction names: `"LockPowers"`, `"ReloadSave"`, `"FailSave"`, `"ResetSave"` (no args). Replies: `"All boss powers locked"`, `"Save reloaded"`, `"Save failure simulated: not saving"`, `"Save reset to a new player's"`.
- Lobby guard: in the `DevAction` handler, if `RunManager.isInLobby()` and the action is one of `LevelUp, SetTime, Boss, Cheese, Give, Heal, Wipe`, reply the lobby text and return.

- [ ] **Step 1: Write the failing test** (injected server Script, reports to `workspace` attribute `T1`). Fire actions through the handler by calling the same function the remote uses; expose it as `DevCommandService.handle(player, action, arg)` (the OnServerEvent connects to it). Checks:
  - `lobby refuses give`: in the lobby, `handle(p,"Give","Toaster")` → `WeaponService.getWeaponLevel("Toaster") == nil`.
  - `restart works from lobby`: `handle(p,"Restart")` → RunState `"Playing"`.
  - `lock powers`: `handle(p,"UnlockPowers")` then `handle(p,"LockPowers")` → `#UnlockService.getUnlocked() == 0`.
  - `reload save`: `GearService.addCurrency(p,"Gold",5)`, `handle(p,"ReloadSave")` → `GearService.getCurrency(p,"Gold")` still includes the +5, `SaveStatus == "On"`.
  - `fail save`: `handle(p,"FailSave")` → `SaveStatus == "Off"`.
  - `reset while off`: `GearService.addCurrency(p,"Gold",999)`, `handle(p,"ResetSave")` → `getCurrency(p,"Gold") == 0`, `SaveStatus == "Off"`, `LifetimeRuns == 0`.
  - `reset while on`: `handle(p,"ReloadSave")` (back On), add gold, `handle(p,"ResetSave")` → `getCurrency(p,"Gold") == 0`, `SaveStatus == "On"`, `DS.get(p).Cookbook` empty.
- [ ] **Step 2: Run it** in Studio play (Rojo synced): expect FAIL / ERROR (`handle` is nil).
- [ ] **Step 3: Implement** `DataService.resetSave`, `DevCommandService.handle`, the guard and the 4 actions. Move "UnlockPowers" in the header comment next to "LockPowers".
- [ ] **Step 4: Run it again:** all PASS. Run stylua + `check.sh`: `RESULT: PASS`.
- [ ] **Step 5: Commit** `DEV tools: save tools, lock powers, run-only actions refuse in the lobby (#140)`.

### Task 2: Client: the tabbed panel

**Files:**
- Modify: `src/client/Controllers/DevPanelController.luau`

**Interfaces:**
- Consumes: the Task 1 action names.
- Produces (for tests): panel children `Tabs` (Frame) with `Tab_RUN`, `Tab_GIVE`, `Tab_BOT`, `Tab_ACCOUNT`; pages `Page_RUN` … `Page_ACCOUNT` (ScrollingFrames, one Visible at a time); the gui attribute `"Tab"` = the shown tab's name.
- `makeHeader(page, text)` / `makeGrid(page)` take the page to add to (today they use the single `list`).

- [ ] **Step 1: Write the failing client check** (Client `execute_luau`, after `user_mouse_input` clicks by `instance_path`, e.g. `LocalPlayer.PlayerGui.DevPanel.Tab`, then `…Panel.Tabs.Tab_GIVE`):
  - `four tabs in order`: `Tab_RUN, Tab_GIVE, Tab_BOT, Tab_ACCOUNT` exist with LayoutOrder 1–4.
  - `opens on RUN`: gui attribute `Tab == "RUN"`, only `Page_RUN` visible.
  - `run page`: `Page_RUN` has buttons "+1 Level", "Restart run", "BOSS NOW", and no "Unlock powers".
  - `give headers`: `Page_GIVE` has header labels "Gadgets", "Ingredients", "Recipes", "Boss powers", and a "Toaster" button.
  - `account page`: buttons "Lock powers", "Reload save", "Simulate save failure", "Reset my save", "+1000 gold".
  - `remembers tab`: click Tab_ACCOUNT, close and reopen via `Tab` → `Tab == "ACCOUNT"`.
  - `reset needs two taps`: one click on "Reset my save" → its text `Tap again to reset` and the save is untouched (server gold unchanged).
- [ ] **Step 2: Run it:** FAIL (no `Tabs`).
- [ ] **Step 3: Implement.** Tab row under the status line (y 34, height 32), pages fill the rest (y 72). Selected tab uses `COLORS.danger`, others `COLORS.button`. RUN, GIVE, BOT, ACCOUNT content as in the spec; the GIVE headers replace today's colour-only grouping. Reset my save: first tap sets text and a 3 s `task.delay` revert; a second tap within that sends `"ResetSave"`. Update the file's header comment.
- [ ] **Step 4: Run it again:** all PASS. Check at a phone size (Studio Device emulation or a 640×360 viewport check that `Page_GIVE.AbsoluteCanvasSize.Y > Page_GIVE.AbsoluteSize.Y` and the tab row is inside the panel). Every action button from today still sends: click "+1 Level" in a run → Level rises. stylua + `check.sh` PASS.
- [ ] **Step 5: Commit** `DEV menu: RUN, GIVE, BOT and ACCOUNT tabs (#140)`.
