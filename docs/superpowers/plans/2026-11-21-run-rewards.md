# Run Rewards Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every finished run pays gold, account XP and random materials by time survived; a clear pays a bonus; a chapter's first clear gives its set gear item once; the run-over banner shows it all.

**Architecture:** A pure shared module (`RewardMath`) works out the payout and rolls materials. The existing `RewardService` stub pays it on `RunManager.onRunEnded` (before RunState changes, so it's in the run-end save and the banner's attributes are set first) and gives the first-clear item. `HUDController` draws layout B from `Reward*` player attributes.

**Tech Stack:** Luau `--!strict`, Rojo, Roblox Studio (tests: pure modules via Client `execute_luau`; server behaviour via an injected server Script reporting to a `workspace` attribute; UI via Client `execute_luau` reads of the PlayerGui).

**Spec:** `docs/superpowers/specs/2026-11-21-run-rewards-design.md`

## Global Constraints
- Every file starts with `--!strict`; run `stylua src` then `check.sh` (stylua, selene, rojo build, luau-lsp): `RESULT: PASS`.
- Server decides every amount (PRD §8.4); the client only shows `Reward*` attributes.
- Starting values (config, Chapter 1 ×1): **Gold 60/min, XP 25/min, 4 material drops per whole minute; clear bonus +140 gold, +50 XP, +5 drops; at least 1 drop per run.** `t` is capped at `RunRules.RunLengthSeconds` (360). Amounts are worked out, multiplied by the chapter's `RewardScale`, then rounded down.
- Each drop is one of the 5 materials (`Gear.Slots[*].Material`), equally likely.
- Chapter 1 (`DinerKitchen`): `RewardScale = 1`, `FirstClearReward = { Item = "ChefsHat", Rarity = "Rare" }`. Given once ever, at Lv 1, marked `New`.
- No gear drops from runs. Quitting mid-run pays nothing. Saving Off: paid and shown, not saved.
- Banner copy: stats line `Survived m:ss · Reached Lv N · Defeated K` (real run time, not capped); rewards `🪙 +<gold>` and `⭐ +<xp> XP`; first-clear box `🏆 First clear! <Rarity> <Item name>`.

## Review Focus
1. **A run that ends before the save loads:** nothing paid, no `Reward*` attributes, banner hides the reward rows (no "+0"). Test in Task 2.
2. **A win whose clock is past 6:00 (boss fight):** paid as 6:00 + clear (500 gold), but the stats line shows the real time. Tests in Tasks 1 and 3.
3. **Second clear of the same chapter, and after DEV "Reset unlocks":** no second Chef's Hat. Test in Task 2.
4. **Starting the next run:** every `Reward*` attribute is cleared, so an old payout never shows on the next banner. Test in Task 2.
5. **Small phone (640×360 viewport):** the taller banner fits on screen with Continue reachable. Check in Task 3.

---

### Task 1: Config, `RewardMath` and ConfigCheck

**Files:**
- Create: `src/config/RunRewards.luau`, `src/shared/RewardMath.luau`
- Modify: `src/config/Chapters.luau` (type + 4 chapters), `src/shared/ConfigCheck.luau` (chapter loop ~line 421)

**Interfaces:**
- Produces `Config/RunRewards.luau`: `{ GoldPerMinute = 60, XpPerMinute = 25, MaterialDropsPerMinute = 4, MinMaterialDrops = 1, ClearBonus = { Gold = 140, Xp = 50, MaterialDrops = 5 } }`.
- Produces `Chapter` fields: `RewardScale: number` (required; Chapter 1 `1`, Chapters 2–4 `1` with a comment "set when designed (#106)"), `FirstClearReward: { Item: string, Rarity: string }?` (Chapter 1 only).
- Produces `RewardMath.payout(seconds: number, won: boolean, scale: number): { Gold: number, Xp: number, MaterialDrops: number }` — non-number/NaN/negative seconds count as 0; seconds capped at `RunRules.RunLengthSeconds`; drops use whole minutes (`seconds // 60`).
- Produces `RewardMath.rollMaterials(drops: number, rng: Random): { [string]: number }` — only materials actually rolled appear as keys.
- Produces `RewardMath.formatMaterials(materials: { [string]: number }): string` — `"HatPattern=3,Sharpener=4"`, keys sorted (the attribute format; `""` for none) and `RewardMath.parseMaterials(text: string): { [string]: number }` (its inverse; ignores malformed parts).

- [ ] **Step 1: Write the failing test** (Client `execute_luau`, requiring `ReplicatedStorage.Shared.RewardMath`; a pure module, so a separate instance is fine). Checks:
  - `payout(150,false,1)` → `{Gold=150, Xp=62, MaterialDrops=8}`
  - `payout(250,false,1)` → `{250, 104, 16}`
  - `payout(360,false,1)` → `{360, 150, 24}`
  - `payout(407,true,1)` → `{500, 200, 29}` (capped, plus bonus)
  - `payout(20,false,1)` → `{20, 8, 1}` (minimum drop)
  - `payout(250,false,1.5)` → `{375, 156, 24}`
  - `payout(0/0,false,1)` and `payout(-5,false,1)` → `{0, 0, 1}`
  - `rollMaterials(16, Random.new(1))`: values sum to 16, every key is one of the 5 materials.
  - `rollMaterials(10000, Random.new(2))`: each material between 1800 and 2200.
  - `parseMaterials(formatMaterials({Sharpener=4, HatPattern=2}))` equals the input; `formatMaterials({})` is `""`; `parseMaterials("x=,Sharpener=3")` → `{Sharpener=3}`.
- [ ] **Step 2: Run it** (Rojo synced, Studio Edit or Play): FAIL (`RewardMath` missing).
- [ ] **Step 3: Implement** the config, `Chapters` fields and `RewardMath`. Materials list: from `Gear.Slots`, sorted by name, so rolls are repeatable for a given `Random`. ConfigCheck (inside the chapter loop): `RewardScale` must be a number above 0; `FirstClearReward.Item` must be in `Gear.Items` and `.Rarity` in `Gear.Rarities`; and every `RunRewards` number must be 0 or more.
- [ ] **Step 4: Run it again:** all PASS. Start play once: no ConfigCheck error in Output. stylua + `check.sh`: `RESULT: PASS`.
- [ ] **Step 5: Commit** `Run rewards: config, RewardMath and checks (#106)`.

### Task 2: `RewardService`: pay at run end, first-clear item, DEV buttons

**Files:**
- Modify: `src/server/Services/RewardService.luau` (fill the stub), `src/server/Services/DataService.luau` (type + template), `src/server/Services/RestartService.luau` (`clearRun`, line ~49), `src/server/Services/DevCommandService.luau`, `src/client/Controllers/DevPanelController.luau` (ACCOUNT tab)

**Interfaces:**
- Consumes: Task 1's `RewardMath`, `RunRewards`, `Chapter.RewardScale`, `Chapter.FirstClearReward`; existing `RunManager.onRunEnded`, `RunManager.getRunSeconds()`, `RunManager.getChapter()`, `GearService.addCurrency`, `GearService.give`, `GearService.sendState`, `TalentService.addXp`, `DataService.get`.
- Produces save section `Rewards: { FirstClears: { [string]: boolean }? }` (template `Rewards = {}`; `Reconcile` fills old saves). `DataService.resetSave` already resets it via the template.
- Produces `RewardService.pay(player: Player, seconds: number, won: boolean): RewardMath.Payout?` — pays gold, XP and rolled materials for the current chapter's `RewardScale`; returns the payout plus `Materials` (the rolled table), or nil when the save isn't loaded. Never gives the first-clear item.
- Produces `RewardService.clearRewards()` — removes every `Reward*` attribute from the run player. Called from `RestartService.clearRun` next to `TalentService.clearJustLeveled()`.
- Produces player attributes (set in the `onRunEnded` callback, only when the save is loaded): `RewardGold: number`, `RewardXp: number`, `RewardMaterials: string` (the `formatMaterials` text), `RewardFirstClear: string?` (e.g. `"Rare Chef's Hat"`, only on the first clear).
- Produces DEV actions: `"RewardRun"` (arg: seconds, number 0–`RunLengthSeconds`, else reply `"Seconds must be 0 to 360"`) pays a loss at that time; `"RewardClear"` (no arg) pays a clear at 6:00. Both reply `Paid: +<gold> gold, +<xp> XP, <drops> materials` and work anywhere (not run-only). ACCOUNT tab, a "Run rewards" header with buttons "Reward: 3:00 loss" (`RewardRun`, 180) and "Reward: clear" (`RewardClear`).

- [ ] **Step 1: Write the failing test** (injected server Script → `workspace` attribute `T2`, polled). `p` = the player, wait for `SaveStatus == "On"`, `DataService.resetSave(p)`, then start a run with `RestartService.restart(p)` (or `Dev.handle(p,"Restart")`). Helper `gold()` = `GearService.getCurrency(p,"Gold")`, `mats()` = sum of the 5 materials. Checks:
  - `loss pays by time`: `RunManager.setRunSeconds(250)`, `RunManager.damagePlayer(1e6)` (after `setHitBlocker(nil)`), wait 0.3 s → gold +250, `mats()` +16, `RewardGold == 250`, `RewardXp == 104`, `parseMaterials(RewardMaterials)` sums to 16, `RewardFirstClear == nil`.
  - `next run clears attributes`: restart → `RewardGold`, `RewardXp`, `RewardMaterials`, `RewardFirstClear` all nil.
  - `first clear`: `setRunSeconds(407)`, `RunManager.winRun()` → gold +500, `mats()` +29, exactly one `ChefsHat` item at `Rare`, Lv 1, `New == true`; `RewardFirstClear == "Rare Chef's Hat"`; `DataService.get(p).Rewards.FirstClears.DinerKitchen == true`.
  - `second clear gives no hat`: restart, `UnlockService.resetUnlocks(p)`, `winRun()` → still one `ChefsHat`; `RewardFirstClear == nil`; gold +500.
  - `account XP paid`: `AccountLevel`/`AccountXp` attributes reflect the XP added (after the two wins + loss from a reset save: total 504 XP → `AccountLevel == 5`).
  - `dev reward`: `Dev.handle(p,"RewardRun",180)` → gold +180; `Dev.handle(p,"RewardRun",-1)` and `Dev.handle(p,"RewardRun","x")` → gold unchanged; `Dev.handle(p,"RewardClear")` → gold +500 and still one `ChefsHat`.
  - `save not loaded`: `DataService.reload(p)` without waiting; immediately `RewardService.pay(p, 250, false)` returns nil if `DataService.get(p)` is nil (skip the check with a note if the reload finished first).
- [ ] **Step 2: Run it:** FAIL (no payout).
- [ ] **Step 3: Implement.** In `RewardService:start()`, `RunManager.onRunEnded(function(result) ... end)`: run player = `Players:GetPlayers()[1]`; if no save, `clearRewards()` and return; `pay(player, RunManager.getRunSeconds(), result == "Won")`; then if won and the chapter has a `FirstClearReward` not in `data.Rewards.FirstClears`: `GearService.give(player, item, rarity, 1)`, set `.New = true`, record it, `GearService.sendState(player)`, set `RewardFirstClear` to `` `{rarity} {Gear.Items[item].Name}` ``. Set the other attributes from `pay`'s result. Rolls use one module-level `Random.new()`. Add the DEV actions, the header comment's action list, and the two buttons.
- [ ] **Step 4: Run it again:** all PASS; no new errors in Output. stylua + `check.sh`: PASS.
- [ ] **Step 5: Commit** `Run rewards: pay gold, XP and materials at run end, first-clear item, DEV buttons (#106)`.

### Task 3: The run-over banner (layout B)

**Files:**
- Modify: `src/client/Controllers/HUDController.luau` (run-over panel ~line 269, `updateRunState` ~line 309, header attribute list)

**Interfaces:**
- Consumes: Task 2's `RewardGold`, `RewardXp`, `RewardMaterials`, `RewardFirstClear` attributes and `RewardMath.parseMaterials`.
- Produces (for tests): inside `HUD.RunOver`: `Stats` (TextLabel), `Rewards` (Frame) with `Gold` and `Xp` TextLabels, `Materials` (Frame, one TextLabel per received material named `Chip_<materialId>`), `FirstClear` (Frame with a TextLabel `Text`), `Continue`.

- [ ] **Step 1: Write the failing client check** (Client `execute_luau`, after the server test script ends a run — reuse Task 2's setup: reset save, run, `setRunSeconds(250)`, lose; then a second injected run that wins at 407 for the first-clear case). Checks:
  - `stats line`: `RunOver.Stats.Text` starts with `Survived 4:10 · Reached Lv`.
  - `count-up ends on the total`: after 1.5 s, `Rewards.Gold.Text == "🪙 +250"`, `Rewards.Xp.Text == "⭐ +104 XP"`.
  - `chips match`: one `Chip_<id>` per key of `parseMaterials(RewardMaterials)`, each text ending in `+<count>`; no chips for materials not received.
  - `no first clear on a loss`: `FirstClear.Visible == false`.
  - `first clear box`: after the winning run, `FirstClear.Visible == true` and its text `🏆 First clear! Rare Chef's Hat`; stats line starts `Survived 6:47` (the real time).
  - `hidden without rewards`: while the banner is up, the server calls `RewardService.clearRewards()` → `Rewards.Visible == false`, `Materials.Visible == false`, `FirstClear.Visible == false` (the banner redraws when a `Reward*` attribute changes).
- [ ] **Step 2: Run it:** FAIL (no `Rewards`).
- [ ] **Step 3: Implement.** Panel grows to about 420×360; rows top to bottom: Title, Unlock (as today), Stats, Rewards (gold and XP side by side, gold `COLORS.tips`), Materials (horizontal `UIListLayout`, centred), FirstClear (blue box with a gold "First clear!" line, only when set), Continue. Material chip text is an icon plus count; icons by material id: Sharpener 🔪, HatPattern 🎩, ApronPattern 🥼, MittPattern 🧤, ShoePattern 👟. Count-up: when the banner appears, gold and XP go from 0 to their totals over 1 s (a cancellable loop; a new banner cancels the old one). The banner also redraws when any `Reward*` attribute changes; the count-up restarts only when the gold or XP value itself changes. Phone fit: a `UIScale` on the panel = `min(1, (viewport height − 20) / panel height)`, updated when the viewport changes.
- [ ] **Step 4: Run it again:** all PASS. Phone check: set the Studio viewport to 640×360 (Device emulation) or check that `RunOver.AbsoluteSize.Y <= camera.ViewportSize.Y - 10` with `RunOver.Continue` fully inside the screen. Screenshot the loss and first-clear banners. stylua + `check.sh`: PASS.
- [ ] **Step 5: Commit** `Run rewards: the run-over banner shows the payout (#106)`.

### Task 4: PRD and a pacing check

**Files:**
- Modify: `docs/PRD.md` §2.8 (payout numbers, no gear drops, no 3:00 reward, first-clear item, pay multiplier), §4.4 (materials: random run drops), §4.7 (gold and XP from runs), §7.1 or the run-over banner text wherever it's described (layout B), and §3.7 Chapters (`RewardScale`, first-clear item, Chapter 1: Rare Chef's Hat).

- [ ] **Step 1: Update the PRD** with the spec's numbers (Global Constraints above). Point to `Config/RunRewards.luau` and `Chapters.luau` for tuning, the same way other sections name their config.
- [ ] **Step 2: Pacing check** in Studio from a reset save: 3 runs with the playtest bot (DEV BOT tab, 3 runs). Record each run's time, result, gold, XP and materials from the banners (or the `Reward*` attributes), and the account level after. Expected: payouts match the formulas; account Lv 3–4 after 3 runs. Put the numbers in the PR description.
- [ ] **Step 3: Run** stylua + `check.sh`: PASS.
- [ ] **Step 4: Commit** `PRD: run rewards (#106)`.
