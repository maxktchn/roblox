# Saving player data (P2-1, #102): design

## Why
Phase 2's goal (PRD §9) is that a new player can go from their first run to unlocking the Rolling Pin, and all their progress saves. Every other Phase 2 topic stores something: gear (#105), run rewards (#106), unlocks (#107), talents and chests (#108). This topic builds the loading and saving they all use, sets out the save file they add to, and makes the first real use: boss power unlocks (PRD §3.8) are kept between sessions instead of being lost when the server closes.

## Decided (by maxktchn)
- **Quitting mid-run loses that run.** Nothing a run earns is saved until the run ends (won or lost). A player who leaves or disconnects mid-run keeps nothing from it, including lifetime stats. A boss power unlocks at the moment the run is won, so it always counts.
- **Wipe freely before launch.** Until launch, when a change makes old saves wrong, everyone's data is reset by changing one config value. Upgrade steps for old saves only start on launch day. A small "Test build: progress may be reset" note is shown so testers know.
- **If a save can't load, let them play without saving.** ProfileStore retries for a few seconds first. If it still fails, the player plays normally with a clear "Progress isn't saving right now" banner. Their stored save is never written to in that session, so their real progress is safe.
- **Approach: ProfileStore, with `DataService` as the only door** (option 1 below).

## Approaches considered
1. **ProfileStore, with `DataService` as the only door (picked).** DataService loads the profile and hands each service its own section through a few functions. Only one file knows how saving works, which suits a beginner team. It's also how `UnlockService` was already written to expect saving.
2. **ProfileStore, with every service editing the save table directly.** Less code up front, but every service has to know the save layout. A bug in one service could break another's data, and a wipe or upgrade would touch many files.
3. **Plain DataStores with our own session locking.** Nothing to copy in, but we'd write the locking, retries and save-on-leave ourselves, which is where data-loss bugs come from. Not worth it for two people.

## Behaviour
- **Join:** DataService starts a ProfileStore session for the player (key `Player_<UserId>`) and fills in any missing fields from the template (ProfileStore `Reconcile`). When it's loaded, it tells every service that asked (`onLoaded`), and the services copy their section into their own state.
- **The run starts right away**, as it does now. It doesn't wait for the load, which normally takes about a second. Anything a service gains before the load finishes is merged in when the save arrives (unlocks are a set, so merging is a union).
- **Run ends (RunState becomes "Won" or "Lost"):** DataService adds the run to the lifetime stats and asks ProfileStore to save now. Later topics (run rewards, #106) add their payout at this same moment.
- **Leave:** DataService ends the session. ProfileStore saves the profile and frees it for the next server.
- **Autosave:** ProfileStore also saves on its own every few minutes. Since nothing from a run is written into the profile before the run ends, an autosave mid-run can't keep a quitter's rewards.
- **Load fails** (save servers down, or the session can't be taken over): the player gets a fresh copy of the template in memory, the player attribute `SaveStatus` is `"Off"`, and DataService never saves that session. The HUD shows the "Progress isn't saving right now" banner.
- **Session already open in another server:** ProfileStore takes it over once the other server lets go (it has a built-in timeout). With one player per server (§8.1) this mostly happens on a fast rejoin.

## Studio testing
- Studio playtests use a **separate store**: the store name gets a `_Studio` suffix, so test data never mixes with real players' saves.
- This needs "Enable Studio Access to API Services" on in the place's Game Settings. If it's off, ProfileStore falls back to its in-memory mock store: everything works, but nothing persists between playtests.

## Wiping before launch
- The store name comes from config: `RunRules.SaveSlot` (or a small new `Config/Saving.luau`, builder's call), e.g. `"PlayerData_v1"`. Changing it to `"PlayerData_v2"` starts everyone fresh. The old store just stops being read.
- After launch we stop changing the slot. Layout changes then go through the version number and an upgrade step instead.

## The save file (version 1)
```lua
{
	Version = 1, -- bump when the layout changes; after launch, each bump needs an upgrade step
	BossPowers = {}, -- [powerId] = true, e.g. { MicrowavePulse = true }
	Lifetime = {
		Kills = 0, -- every enemy killed in finished runs (the Meat Cleaver's 5,000 can use this later)
		RunsPlayed = 0, -- finished runs, won or lost
		RunsWon = 0,
		BestWinSeconds = 0, -- fastest win's run clock; 0 = no win yet
	},
	-- Reserved for later topics. Each fills in its own section in its own design:
	Currencies = {}, -- gold and materials (#106, #105)
	Gear = {}, -- inventory and equipped items (#105)
	Talents = {}, -- account level, XP and talent nodes (#108)
	Unlocks = {}, -- chapters and starters (#107)
}
```
- ProfileStore can't store `nil`, so "none yet" is written as 0 or an empty table.
- Only DataService touches this table. Services read and change their section through DataService.

## DataService functions (for the builder)
- `DataService.onLoaded(callback: (player, data) -> ())`: called once the player's save is ready (or the fresh copy, when saving is off).
- `DataService.get(player): Data?`: the player's save table, nil until loaded. Services change only their own section.
- `DataService.isSaving(player): boolean`: false when the load failed.
- `DataService.saveNow(player)`: asks ProfileStore to save soon (run end). Does nothing when saving is off.
- Player attribute `SaveStatus`: `"Loading"`, `"On"` or `"Off"`, for the HUD.

## Boss power unlocks
- On load, `UnlockService` adds the saved `BossPowers` to its in-memory set and shows them as attributes, as it does now.
- When a power unlocks, `UnlockService` also sets `data.BossPowers[id] = true`. The run is ending at that moment (the boss died), and the run-end save writes it.
- DEV tools (UnlockPowers, and the playtest bot's lock and unlock) change the save too. That only affects devs, and saves are wiped before launch anyway.

## Notes on screen
- Until the lobby exists (#109), both notes sit on the HUD in small text:
  - "Test build: progress may be reset", always shown until launch.
  - "Progress isn't saving right now", shown while `SaveStatus` is `"Off"`.
- When the lobby is built, the test-build note moves there.

## Code shape (for the builder)
- **ProfileStore** is copied into the repo as one file (`src/server/ProfileStore.luau`, or a `Packages` folder), with its MIT licence header and the version noted. It's third-party code, so it's left out of our `--!strict`, stylua and selene rules (add it to their ignore lists) instead of being rewritten.
- **`DataService`** owns ProfileStore and everything above.
- **`UnlockService`** gets load-and-save through DataService.
- **Lifetime stats** are updated by DataService at run end from the `Kills` attribute, `RunState` and `RunSeconds`.
- **HUD** reads `SaveStatus` for the banner.
- **`ConfigCheck`**: the save slot must be a non-empty string.
- **PRD §8.2** is updated with the decisions above.

## Non-goals
- Gold, materials, gear, talents and chapter or starter unlocks. Each later topic designs its own section.
- Leaderboards (ordered DataStores, Phase 3).
- Upgrade steps for old saves (only from launch day).
- Moving data between places (one place for now, §8.1).

## Left to the builder
- Whether the save slot lives in `RunRules` or a new `Config/Saving.luau`.
- Where the ProfileStore file sits in `src/server`.
- Whether bot runs count toward lifetime stats (counting them is fine, since saves are wiped before launch).
