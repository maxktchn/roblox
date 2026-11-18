# Lobby screens (P2-8, #109): design

## Why
Today a run starts the moment you join, and the only way to reach the Gear screen is the run-over banner. maxktchn wants a lobby now (ahead of the DEV menu tabs, #140) to get a better feel for how gear works while testing: give yourself gear, open Gear, equip and level it, press Play, feel the difference, come back. It's also the frame every other Phase 2 screen plugs into (PRD §7.1): Talents and Shop (#108) and Chapters (#107) fill their own tabs when they're designed, without the lobby being redone.

## Decided (by maxktchn)
- **Joining puts you in the lobby, not a run.** No enemies and no clock until you press Play.
- **Tabs across the top** switch between screens: **HOME · GEAR · TALENTS · CHAPTERS · SHOP · COOKBOOK**. Battle Pass and Missions stay hidden until Phase 3.
- **Talents, Chapters and Shop are "coming soon" placeholders** until athatcher989's designs fill them. The lobby can be built before those exist.
- **Home shows the chapter** you're on (not an account level): "Chapter 1: Diner Kitchen" today.
- **Home is a flat panel over the kitchen, blurred** (option A).
- **Gear shows your chef in the kitchen with the gear panel beside them** (option B). Gear isn't drawn on the chef in Phase 2 (#105), so the chef looks the same whatever's equipped; the layout is ready for when it is.
- **After a run, back to the lobby.** The run-over banner shows the result, then **Continue** goes to Home. "Play again" leaves the banner. Run rewards (#106) will show their payout on the banner later.
- **Cookbook is a real tab now:** recipes you've made show in full; the rest show as a dark silhouette with a hint ("Pepper Shaker + ???"). The save remembers which recipes you've made.
- **Approach: the lobby is a run state** (option A below).

## Approaches considered
1. **The lobby is a run state (picked).** RunManager's `RunState` ("Playing", "Won", "Lost") gets a fourth value, "Lobby". One source of truth that every system already watches; the smallest change to run code.
2. **A separate lobby service with its own "in lobby" flag.** Touches less of RunManager, but two things then say whether you're in a run, and they can disagree.
3. **A separate lobby place with teleports.** Ruled out for now by PRD §8.1 (one place; teleports don't work in Studio playtests). The lobby's screens live in their own controller so they can move to a separate place when co-op comes.

## Flow
```
join ──► LOBBY ──Play──► PLAYING ──win/lose──► WON / LOST (banner) ──Continue──► LOBBY
```
- **Join:** `RunState = "Lobby"`. The chef spawns in the kitchen and can't move (anchored on the client, like the card screen). No enemies spawn, the clock doesn't run, weapons don't fire. The HUD (tip bar, timer, kills, item icons) is hidden; the lobby screens show.
- **Play:** starts a fresh run, the same way "Play again" does today (`RestartService.restart()`: everything reset, gear fixed for the run, the chef respawned at the SpawnLocation). `RunState = "Playing"`. Accepted only while in the lobby.
- **Run ends (Won or Lost):** the run-over banner shows the result as now (with the boss-power unlock line) and one button, **Continue**. The run-end save and lifetime stats happen at this moment as now.
- **Continue:** clears what the run left (enemies, pickups, puddles, the boss arena) and goes back to `RunState = "Lobby"` with the chef standing in the kitchen. Accepted only while the run is over (Won or Lost).
- **Save not loaded yet:** the lobby shows "Loading..." where currencies and the Cookbook go; Play still works (gear is fixed when the save arrives, as now).
- **Gear can change whenever no run is on:** in the lobby and on the run-over banner. Changes apply from the next run (as now).
- **Run gear is fixed when Play is pressed** (the restart path already does this). A save that finishes loading while you're still in the lobby doesn't start anything: an Epic Hat's free picks only come with a run.

## Screens
Phone first (PRD §7.4): the 6 tabs share the width; buttons at least 44 px. Simple shapes and rarity colours for icons until there's art.

**Tab bar** (every screen): the 6 tabs along the top, the current one highlighted, and gold at the top right. The lobby always opens on Home (on joining and after Continue).

**HOME** (flat panel over the blurred kitchen)
```
┌ HOME│GEAR│TALENTS│CHAPTERS│SHOP│COOKBOOK   Gold 1,250 ┐
│░░░░░░░░░░░░░░ blurred kitchen ░░░░░░░░░░░░░░░░░░░░░░░░│
│               Chapter 1: Diner Kitchen                 │
│               Chef's Knife (Common Lv 1)               │
│               Runs 12 · Wins 3 · Best 5:42             │
│                    [   PLAY   ]                        │
└────────────────────────────────────────────────────────┘
```
- The chapter's number and `Name` from `Chapters.luau`. Only Chapter 1 today; #107 makes it a choice.
- What's equipped in the Utensil slot, with its rarity colour and level. Until #107 lets the Utensil choose the run's starter, every run still starts with the Chef's Knife (only DEV tools can equip a Frying Pan or Rolling Pin today); making Play use the equipped utensil is #107's job.
- A small line from the save's lifetime stats (runs, wins, best win time; "no wins yet" when there are none).
- A big Play button.

**GEAR** (chef in the kitchen, panel beside)
```
┌ HOME│GEAR│...                                Gold 1,250 ┐
│                  │ Gold · Sharpener · Hat · Apron · ...│
│      🧑‍🍳          │ Slots     │ Inventory               │
│     (chef)        │ Utensil   │ ▢ ▢ ▢ ▢                 │
│                   │ Hat ...   │ ▢ ▢ ▢                   │
└────────────────────────────────────────────────────────┘
```
- The camera frames the chef from the front, on the left part of the screen; no blur.
- The right part is the Gear screen from #138 (slots, inventory, detail, pick-3 merge, salvage), without its own close button.

**TALENTS, CHAPTERS, SHOP:** a short panel over the blurred kitchen: the tab's name, one line on what it will hold ("Spend gold on permanent upgrades", "Pick which kitchen to cook in", "Chests and more"), and "Coming soon". Each one's own topic replaces it.

**COOKBOOK** (flat panel over the blurred kitchen)
```
┌ HOME│...│COOKBOOK                              Gold 1,250 ┐
│ ┌──────────────┐ ┌──────────────┐ ┌──────────────┐        │
│ │Sushi Master  │ │ ▓▓▓▓▓▓▓▓▓▓▓▓ │ │ ▓▓▓▓▓▓▓▓▓▓▓▓ │        │
│ │Blade         │ │ Pepper Shaker│ │ Toaster      │        │
│ │Chef's Knife  │ │ + ???        │ │ + ???        │        │
│ │+ Salt        │ └──────────────┘ └──────────────┘        │
│ └──────────────┘    Found 1 of 8                          │
└───────────────────────────────────────────────────────────┘
```
- One card per recipe in `Recipes.luau` that a run can reach (its weapon and ingredient are in the upgrade pool or are the starter), so recipes that can't be made yet don't show.
- **Found:** the recipe's name, its weapon + ingredient, and its description.
- **Not found:** a dark card with the weapon's name + "???" (the hint), no recipe name.
- "Found N of M" underneath.

## Recipe discovery (saved)
- A recipe is **found** the first time you take its card in a run (UpgradeService applies a Recipe card). The playtest bot's runs count too, like they count toward lifetime stats (saves are wiped before launch); a DEV "Give" doesn't, since it skips the card.
- Following the saving rule (#102), it's written to the save **when the run ends** (Won or Lost). Quitting mid-run doesn't record it.
- Save: a new section `Cookbook = {}`, `[recipeId] = true`, added to DataService's template (save version stays 1; saves are wiped freely before launch, and Reconcile fills it in for old test saves).
- The client gets the found set to draw the Cookbook (a remote or player attributes; builder's call).

## Order
Build on main **after the gear PR (#141) merges**: the Gear tab reuses its Gear screen and its run-gear rules.

## Things that change
- **RunManager:** the "Lobby" run state; starts in it on join; a way to go back to it (stops the clock, no spawns, treated as "run over" for the gear rule).
- **Restart / Play / Continue:** Play uses the existing restart path, now accepted only from the lobby; Continue is new. The playtest bot and the DEV "Restart" keep starting runs directly, as now.
- **Run-over banner (HUDController):** one Continue button instead of Play again and Gear; the HUD hides in the lobby.
- **Gear screen (GearController):** shows inside the lobby's Gear tab; its own close button and banner button go.
- **New:** a lobby controller (tab bar, Home, placeholders, Cookbook, camera and blur), a recipe-discovery save.
- **PRD §7.1, §2.1** updated (lobby flow, which tabs exist now).

## Non-goals
- Talents, Chapters and Shop contents (#107, #108).
- Battle Pass and Missions screens (Phase 3).
- Gear models on the chef (later).
- A separate lobby place and teleports (co-op, later).
- Run reward payout on the banner (#106).
- Real icons and art.

## Left to the builder
- How the client learns the found recipes (remote or attributes).
- Where Play and Continue go as remotes (reuse `RequestRestart` for Play, plus a new one for Continue, or two new ones).
- Exact camera angle for the Gear tab and the blur strength.
- Tab bar sizing on narrow phones (shrink text, or icons only).
