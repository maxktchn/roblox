# Run rewards (P2-5, #106): design

## Why
Runs pay nothing today. Gold, account XP and materials come only from DEV tools, so gear levelling (#105), talents and Basic Chests (#108) have nothing to spend.

maxktchn wants the loop to feel like this:
1. **Losing early should send you back to upgrade.** A new player who loses should feel they need to make some upgrades before trying the chapter again.
2. **Grinding is expected.** Replaying a chapter several times to earn gold for those upgrades is part of the design, not a failure of it.
3. **Beating a chapter gives a nice piece of gear.** The first clear gives an item that gets the player ready for the next chapter.

So a lost run is the normal way to earn early on, and has to pay real gold. A clear pays more, plus a one-time gear item.

## Goals
- Every run that ends (won or lost) pays **gold, account XP and random materials**, based on how long the player survived.
- A clear pays a **bonus**.
- The **first clear of each chapter** gives that chapter's set gear item, **once ever**.
- The run-over banner shows the payout.
- The amounts match what gear (#105) and talents/chests (#108) were sized for, so their prices don't need rescaling.

## Non-goals
- **Gear drops from runs.** Gear comes only from Basic Chests in the lobby and from first clears (plus the free knife and starter unlocks). This changes PRD §2.8, which listed "chance at a gear drop".
- **Gems and the "first time reaching 3:00" reward.** Gems arrive in Phase 3; this reward is dropped and the first-clear item takes its place.
- **Gold from kills or tips.** Tips stay XP inside the run.
- **Balance tuning.** The numbers below are starting values; balancing comes with playtests (#153, #165).
- 2x Gold and other monetization (PRD §5).

## Anti-goals
- **A loss that pays a token amount.** If a 3-minute loss feels worthless, the grind loop breaks.
- **Replaying an easy, already-cleared chapter as the best farm.** Clear rewards must not outweigh pushing forward.
- **A reward the player can lose or earn twice.** The first-clear item is given once, and a run's payout is added once, at the run-end save.

## Decided (maxktchn)
- **Pay by time survived.** Losses pay in proportion to time; there's no flat "consolation" amount.
- **Gold: 60 per minute survived.** A loss at 2:30 pays 150; at 4:10, 250 (the "typical run" #108 assumed); lasting to 6:00, 360.
- **Clear bonus: medium.** +140 gold, so a clear pays **500 gold** (one Basic Chest). May be adjusted when balancing.
- **Materials are random drops from the pool of all five.** Each minute survived earns more drops, and each drop is a random material. (maxktchn changed this from "some of every material".)
- **No gear drops from runs.** Gear is bought from chests in the lobby.
- **First clear: a set item per chapter**, kept in that chapter's config. **Rare** for the early chapters and **Epic** for the later ones. Given **only once**.
- **Banner: layout B** (big gold and XP numbers that count up, plus a chip for each material received). See the sketch below.
- **Later chapters pay more**: each chapter has a pay multiplier in its config, so pushing forward always beats farming an easier chapter.

## The payout
All amounts are from the time survived, `t` = the run's seconds, capped at `RunRules.RunLengthSeconds` (6:00). Every amount is worked out, multiplied by the chapter's pay multiplier (below), then rounded down. The table is for Chapter 1 (×1).

| | Formula (starting values) | Lost at 2:30 | Lost at 4:10 | Lost at 6:00 (boss) | Cleared |
|---|---|---|---|---|---|
| Gold | `60 × t / 60` | 150 | 250 | 360 | 360 + **140** = 500 |
| Account XP | `25 × t / 60` | 62 | 104 | 150 | 150 + **50** = 200 |
| Material drops (each one random) | `4 × whole minutes`, at least 1 | 8 | 16 | 24 | 24 + **5** = 29 |

- **Account XP's rate (25 a minute) and clear bonus (+50), and the material numbers, are Claude's proposal**, accepted by maxktchn. They give about 100 XP for a typical run, the amount #108's account XP curve assumed.
- **Material drops:** **4 for each whole minute survived**, plus **5 for a clear**, and **at least 1** for any run (so a very short loss still gives something). A typical 4:10 run gives 16, about 3 of each; a full clear gives 29. (maxktchn picked 4 a minute so materials keep pace with gold.)
- **Each drop is one of the five materials, equally likely** (Sharpener, Hat Pattern, Apron Pattern, Mitt Pattern, Shoe Pattern). So a player saving for one item may get little of its material on one run; it evens out over a few. That luck is wanted.
- **What this buys**, in runs at about 250 gold: one item from Lv 1 to 10 costs about 1,250 gold and 17 of its material, about 5 runs of gold (the gear design's target). Its material comes at about 3.2 a run on average (16 drops ÷ 5), so the 17 take about 5 runs too: gold and material keep pace, with luck moving it a run either way.
- **Pay multiplier per chapter** (maxktchn picked this): each chapter in `Chapters.luau` gets `RewardScale` (Chapter 1: **1.0**). Gold, XP and the number of material drops (and the clear bonuses) are multiplied by it, so a 4:10 loss in a ×1.5 chapter pays 375 gold. Later chapters' multipliers are set when they're designed; ConfigCheck requires a number above 0. The first-clear item isn't scaled.
- **Salvage gold stays as it is** (`Gear.SalvageGold`: Common 20 up to Legendary 1,620; Claude's call). The gear design left it to #106; at about 250 gold a run, salvaging a Common gives a small extra and a Rare (180) most of a run's worth, which fits.
- **The numbers live in config** (a new `Config/RunRewards.luau`, builder's call on the exact name): gold and XP per minute, material drops per minute, the clear bonuses and the minimum of 1 drop.

## First-clear items
- Each chapter in `Chapters.luau` also gets an optional **`FirstClearReward = { Item = <gear item id>, Rarity = <rarity id> }`**.
- **Chapter 1 (Diner Kitchen): a Rare Chef's Hat** (Claude's example, maxktchn can change it in config).
- **Rare for Chapters 1–2, Epic for Chapters 3–4** (Claude's reading of "lower" and "later"). Chapters 2–4 get their item when they're designed (they have no timeline yet).
- **It arrives at Lv 1 and marked NEW**, so the lobby's GEAR badge shows it, the same as a chest item.
- **Given once ever.** The save records each chapter whose reward was given, in its own list (for example `Rewards.FirstClears = { [chapterId] = true }`), separate from `Unlocks.Cleared`. So DEV "Reset unlocks" doesn't give it again, and the order in which UnlockService and the reward code run doesn't matter. DEV "Reset my save" clears it, like everything else.
- **ConfigCheck** checks that the item and rarity exist.
- This is on top of any starter unlocked by the same clear (Chapter 1's first clear also unlocks the Rolling Pin, #151).

## The run-over banner (layout B)
```
┌──────────────────────────────────┐
│        SHIFT SURVIVED!           │
│ New starter unlocked: Rolling Pin · Account Lv 4! │
│ Survived 6:00 · Reached Lv 22 · Defeated 1,140 │
│      🪙 +500     ⭐ +200 XP        │
│   🔪+4  🎩+2  🥼+3  🧤+5  👟+1     │
│ ┌──────────────────────────────┐ │
│ │ 🏆 First clear! Rare Chef's Hat │ │
│ └──────────────────────────────┘ │
│          [ Continue ]            │
└──────────────────────────────────┘
```
- **Top to bottom:**
  1. The title, as today.
  2. The unlock and account level line, as today, shown only when something happened.
  3. The stats line. **"Survived m:ss"** is new, because time is what pays. It shows the real run time, so a win can read "Survived 6:47" (the clock keeps going during the boss fight) while the pay stops counting at 6:00 (Claude's call).
  4. **Gold and XP**, big, **counting up from 0** when the banner appears (about 1 s; a tick sound is the builder's call).
  5. **Material chips**, one for each material received with its count (materials not received aren't shown).
  6. **The "First clear!" box**, only on a chapter's first clear, naming the item with its rarity colour.
  7. **Continue**, as today.
- **It must fit a phone screen**: the banner grows taller than today's 420×250, and the builder checks it at phone size.
- **When the save hasn't loaded**, nothing is paid (DataService already skips runs that end before the save loads), and the reward lines are hidden.

## Rules
- **Paid when the run ends** (Won or Lost), at the same moment UnlockService unlocks things: `RunManager.onRunEnded`, before RunState changes. That way the banner's attributes are set before it appears, and the payout is in the run-end save.
- **Quitting mid-run pays nothing**, as with every other run-end reward (the saving rule, #102).
- **When saving is off** (the red "not saving" banner), the payout is still added and shown for this session, but isn't saved, the same as everything else.
- **Playtest bot runs pay like normal runs.** The bot is DEV-only, and this keeps the payout testable.
- **The server decides every amount.** The client only shows what the server published.
- **Account levels from the payout** already show on the banner: `TalentService.addXp` sets `JustLeveledAccount` because the run isn't in the lobby yet.

## How it's built (approach 1, chosen by maxktchn)
- **`RewardService` (server).** The empty stub `src/server/Services/RewardService.luau` already exists for exactly this; it gets filled in. On `RunManager.onRunEnded(result)`:
  1. Reads the run's seconds, the result and the chapter, and works out gold, XP and materials from the config and the chapter's `RewardScale`.
  2. Pays them with `GearService.addCurrency` (gold and each material) and `TalentService.addXp`.
  3. If won, and the chapter has a `FirstClearReward` not given yet, gives it with `GearService.give`, marks it NEW, records it in the save and sends the gear state.
  4. Publishes the payout as player attributes for the banner, for example `RewardGold`, `RewardXp`, `RewardMaterials` (what was received, for example a string like `"Sharpener=4,HatPattern=2"` or one attribute per material) and `RewardFirstClear` (the item's display name and rarity). They're cleared when the next run starts, like `JustUnlocked`.
- **`HUDController`:** draws the new banner rows and the count-up.
- **`DevPanelController` and `DevCommandService`:** an ACCOUNT button that pays a run reward without playing, for example "Reward: 3:00 loss" and "Reward: clear". It replies with what was paid. Neither gives the first-clear item; a real clear (or BOSS NOW) tests that.
- **PRD:** §2.8 (the payout, no gear drops, no 3:00 reward), §4.4 (materials come from runs this way), §4.7 and §7 (the banner) are updated with the numbers.

### Approaches considered
1. **Its own service, `RewardService` (chosen).** It keeps the economy in one place, easy to find and rebalance. It hooks the same run-end moment as UnlockService.
2. **Add it to `UnlockService`.** One less file, and it already knows when a chapter is first cleared. But it mixes the economy into unlocks, a file already doing a lot, and rebalancing payouts would mean editing unlock code.
3. *Dropped:* **the client works out the payout from the run time.** The numbers could disagree with the server's, which must decide every reward (PRD §8.4).

## Left to the builder
- Config and attribute names, and how the banner grows to fit.
- The count-up's exact timing and sound.
- Which DEV reward buttons exist, within "pay a run without playing it".
- The save's exact place for the given first-clear rewards, and its default for old saves.

## Build issues after this is merged
- **P2-5a:** `RewardService`, its config and the first-clear item (server, with DEV buttons).
- **P2-5b:** the run-over banner (layout B).
- **P2-5c:** PRD updates and a check of the pacing (a few runs from a new save).
