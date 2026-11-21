# Talents, account levels and Basic Chests (P2-7, #108): design

## Why
After gear (#105), the next layer of meta progression is the **talent path** (PRD §4.5) and **Basic Chests** (PRD §4.8):
- **Talents** give every run some permanent progress even when no gear drops. They also give a steady stream of small goals.
- **Chests** are where gear comes from, apart from DEV tools.

This topic sets:
- account XP and levels
- the 30-node talent path and what each node does
- what nodes cost
- the Basic Chest's price, odds and opening
- the Talents and Shop tabs that the lobby (#109) left as "Coming soon"

**Run rewards (#106, maxktchn) isn't designed yet.** That topic decides how much gold and account XP a run pays. So every curve here is set in **runs**: "Lv 10 after about 12 runs", "a chest costs about 2 runs of gold".

The config numbers below assume a **typical run pays about 250 gold and 100 account XP**. When #106 sets the real payouts, these numbers get rescaled to keep the same number of runs. Until then, gold and XP come only from DEV tools. There's no temporary payout to take out later.

## Decided (by athatcher989)
- **The talent path is 30 levels** at launch: one node per account level, so 24 standard nodes and 6 special nodes. It can be extended later.
- **Standard nodes are small, so gear stays the main source of power.** The cycle is Attack, Max HP, Armor, Pie healing, and each stat appears 6 times. By Lv 30:
  - Attack: +2% damage per node, **+12%** in total
  - Max HP: +3% per node, **+18%**
  - Armor: +0.5 per node, **+3**. This is smaller than first offered: hits are only 5-12 damage, so +6 would make early enemies harmless.
  - Pie healing: +5% per node, **+30%**. That's relative: a pie heals 20% of max HP today, so 26% at Lv 30.

  For scale, one Legendary item at max level gives +60%.
- **Special nodes every 5 levels give run perks**, in this order:

  | Level | Special node |
  |---|---|
  | Lv 5 | +1 reroll per run |
  | Lv 10 | Start each run with 1 Pie on the floor beside the chef |
  | Lv 15 | +1 free Order Up! pick at the start of each run |
  | Lv 20 | +10% tip pickup range |
  | Lv 25 | +1 reroll per run (another one) |
  | Lv 30 | +5% move speed |
- **The account XP curve starts fast, then slows:** about **Lv 5 after 4 runs, Lv 10 after 12, Lv 30 after about 80**.
- **Nodes cost gold, rising from about half a run to about 2 runs of gold.** A node is usually affordable when its level arrives, so XP is the real limit, not gold.
- **The Basic Chest costs about 2 runs of gold** and drops:
  - **Common 75%, Fine 22%, Rare 3%**
  - plus the PRD's **1% starter**
- **Opening is a short reveal (about 1.5 s) and there's an "Open x10" button.** The chest shakes, pops open, and the item card flips over in its rarity colour; Rare gets extra sparkle. Open x10 shows all 10 cards at once.
- **Chests drop any slot. Duplicates become merge copies**, as the PRD says.

## Account XP and levels
- The account starts at **Lv 1 with 0 XP**. XP to go from Lv L to L+1 = `Xp.Base + Xp.Step × (L − 1)`, starting at **Base 80, Step 13**. At 100 XP a run, Lv 1→2 takes under one run, and Lv 29→30 takes about 4.4.

| Account level | Total XP | Runs (at 100 XP) |
|---|---|---|
| 5 | 398 | ~4 |
| 10 | 1,188 | ~12 |
| 20 | 3,743 | ~37 |
| 30 | 7,598 | ~76 |

- **Max level is 30**, the end of the path. XP past the max is kept but does nothing until the path grows.
- **More than one level can come at once**, from a big XP grant or DEV +XP.
- **`TalentService.addXp(player, amount)`** is the one way XP is added. #106 calls it when a run ends, and DEV tools call it too.
- **Gaining levels is shown in two places.** The run-over banner gets a line in the same style as the unlock lines: "Account Lv 6! New talent ready". If a node can be bought, the **TALENTS tab gets a NEW badge**, the same way the GEAR tab does.
- **Home shows the account level** and an XP bar under the stats line: "Account Lv 6 · 140 / 145 XP".

## The talent path
- There are **30 nodes, one per account level.** Node N can be bought once the account is Lv N and the nodes before it are bought. There are no branches, so no choices and no respec.
- **A new player can buy node 1 right away** once they have the gold. Lv 1 opens node 1.
- **Order:** nodes 5, 10, 15, 20, 25 and 30 are the specials. The other 24 run through the cycle Attack, Max HP, Armor, Pie healing, so node 1 is Attack, 2 is Max HP, 3 is Armor, 4 is Pie healing, 6 is Attack again, and so on.
- **Cost:** node N costs `Cost.Base + Cost.Step × (N − 1)` gold, starting at **Base 125, Step 13**. Node 1 is 125 (half a run at 250 gold) and node 30 is 502 (2 runs). All 30 cost about 9,400 gold, about 38 runs. That's half the gold earned on the way to Lv 30, so the rest goes to gear and chests.
- **How the effects work** (they're on for every run):
  - **Attack and Max HP** add to the same totals as gear's Attack and HP (additive %), applied at run start the way gear is.
  - **Armor** adds to the run's Armor stat, which Beef Jerky also uses. `RunManager.damagePlayer` already does `max(hit − Armor, 1)`, and fractions are fine.
  - **Pie healing** multiplies `RunRules.PieHealFraction`.
  - **Extra rerolls** add to `RunRules.RerollsPerRun`.
  - **The free pick** adds to the Epic/Legendary Hat's `FreePicks` and uses the same opening.
  - **The starting Pie** drops beside the chef at 0:00. Pies stay on the floor while the chef is at full HP, so it waits for the first time it's needed.
  - **Pickup range and move speed** add to the run's `PickupRange` and `MoveSpeed` stats (the Fridge Magnet's stat and the speed stat).
- **Saved** in the save's reserved `Talents` section: `{ Level = 1, Xp = 0, Bought = 0 }`. `Xp` is XP into the current level. `Bought` is how many nodes are bought, which is enough because the path is in order.

## TALENTS tab
Replaces the lobby's "Coming soon" placeholder.
```
┌ HOME│GEAR│TALENTS│CHAPTERS│SHOP│COOKBOOK          Gold 1,250 ┐
│  Account Lv 6   ███████░░░  140 / 145 XP                     │
│  [ ✓ 1  +2% attack ]                                         │
│  [ ✓ 5  ★ +1 reroll per run ]                                │
│  [   6  +2% attack          BUY 190 gold ]  ← next node      │
│  [ 🔒 7  +3% max HP          Account Lv 7 ]                   │
│  ... (scrolls; opens scrolled to the next node)              │
│  Totals: +2% attack · +3% max HP · +0.5 armor · +5% pies     │
└─────────────────────────────────────────────────────────────┘
```
- One full-width card per node, at least 44 px tall. Each card shows the node's number and effect. Bought nodes have a ✓. Special nodes have a ★ and a gold border. The next node has a **BUY** button with its price, greyed out if there isn't enough gold. Later nodes show "🔒 Account Lv N".
- **The tab opens scrolled to the next node.** A totals line at the bottom adds up everything bought.
- **Buying is one remote call** (`TalentAction("Buy")`). The server checks the level and the gold, spends the gold through GearService's currency functions and saves `Bought`. The card flips to ✓ with a short pop.

## Basic Chests and the SHOP tab
- **Price:** **500 gold**, about 2 runs at 250 gold. Open x10 costs 5,000 (no bulk discount for now).
- **The server rolls each chest:**
  1. **1%: a chest starter.** It's Common Lv 1, from the MVP starters without an `UnlockRule`. Today that's only the **Frying Pan** (Whisk and Ladle are post-launch). This replaces "Frying Pan only from DEV tools" (#107).
  2. **Otherwise a gear item:** one of the 5 slots at random. Each slot has one item today, so this picks Chef's Hat, Apron, Oven Mitts, Shoes or the Chef's Knife (the Utensil). The rarity is rolled: **Common 75%, Fine 22%, Rare 3%**, at Lv 1.
- **Everything goes into the inventory, marked New.** The GEAR tab's NEW badge (#151) picks it up. Duplicates are just more copies for merging (3 → 1 of the next rarity, #105).
- **Odds on screen:** the SHOP tab shows them under the chest: "Common 75% · Fine 22% · Rare 3% · plus 1% for a starter". Roblox requires odds for paid random items, and Basic Chests are bought with free gold. We show them anyway so Premium Chests (Phase 3) only need the same line.
- **SHOP tab:**
  ```
  ┌ ...│SHOP│...                                Gold 1,250 ┐
  │        [ chest picture ]                               │
  │        BASIC CHEST                                     │
  │        Common 75% · Fine 22% · Rare 3% · 1% starter    │
  │   [ OPEN  500 gold ]     [ OPEN x10  5,000 gold ]      │
  │        Premium Chests: coming later                    │
  └────────────────────────────────────────────────────────┘
  ```
- **Opening:**
  1. The server takes the gold, rolls, gives the items, saves, and sends back the results.
  2. The client then plays the reveal: the chest shakes (0.6 s), pops open, and the item card flips (0.5 s) in its rarity colour. Rare and starters get a sparkle burst.
  3. Tap to close.
  4. **x10** shows the 10 cards in a grid that flip one after another (0.1 s apart), with the best at the end.
  5. The result screen has an "Open again" button.
- **Security:** the client only asks to open 1 or 10. The server checks the gold first and rolls on the server; the client never sends what it got. If the save isn't loaded, opening is refused.

## Config
- **`Config/Talents.luau`** (replaces today's stub):
  - `MaxLevel = 30`
  - `Xp = { Base = 80, Step = 13 }`
  - `Cost = { Base = 125, Step = 13 }`
  - `StandardCycle`: each entry's stat and amount, for example `{ Stat = "Attack", Amount = 0.02 }`
  - `Specials`: by node number (5 to 30), each with a kind (`Reroll`, `StartingPie`, `FreePick`, `PickupRange`, `MoveSpeed`), an amount and its card text
- **`Config/Gear.luau`:** `Chests.Basic` gets `Price = 500`, `BulkCount = 10` and `Rarities = { Common = 0.75, Fine = 0.22, Rare = 0.03 }`. `StarterDropChance = 0.01` stays.
- **ConfigCheck:**
  - rarity odds add up to 1
  - every special sits on a multiple of `SpecialEvery`, and every number from 1 to `MaxLevel` has a node
  - the amounts are positive

## DEV tools (ACCOUNT tab, #140)
- **+100 XP, +1,000 XP**
- **Reset talents** (level 1, 0 XP, nothing bought)
- **Give chest roll** (one roll without paying, to test the reveal)

## Playtest bot
- **The bot doesn't buy talents.** Bot runs compare balance on a fixed account.
- **A BOT-tab option sets a talent level** (0, 15 or 30 nodes bought) for the bot's runs, so #153-style comparisons can include talents. Without it, bot runs use whatever the save has.

## Build order (issues)
1. **P2-7a: account XP and levels.**
   - Save section, config, `TalentService.addXp` and level-ups.
   - Level and XP attributes, the run-over banner line, and the account level on Home.
   - DEV +XP and Reset talents.
2. **P2-7b: the talent path.**
   - Node config and ConfigCheck, buying (remote and checks), and the effects in runs: stats, pies, rerolls, the free pick, the starting Pie.
   - Bot talent-level option.
3. **P2-7c: TALENTS tab.** Node cards, BUY, totals, the NEW badge, opening scrolled to the next node.
4. **P2-7d: Basic Chests.**
   - Config and the server roll (starter, slot, rarity), open x1 and x10.
   - SHOP tab with odds, the reveal animation, and the DEV give-roll button.
5. **P2-7e: PRD and playtest.**
   - PRD §4.5, §4.7, §4.8 tables match the config.
   - A playthrough from a new save with DEV gold and XP at #106-sized amounts, checking the pacing in runs.
   - Once #106 lands, its build issue rescales the numbers above to the real payouts.

## Testing (each build issue)
- **XP:** an XP grant across several levels gives every level, and the banner and Home show the new level. Lv 30 stops levelling. Everything survives a rejoin.
- **Buying:**
  - a node can't be bought below its level, out of order, or without the gold
  - buying spends exactly its cost and the effect is on in the next run (DEV run report shows the stats)
  - all 30 bought gives +12% attack, +18% max HP, +3 armor, ×1.3 pie healing, 4 rerolls, 1 free pick, a starting Pie, +10% pickup range and +5% speed
- **Chests:**
  - 10,000 simulated rolls land within about 1 percentage point of 75/22/3 and 1% starters
  - x10 refuses with under 5,000 gold
  - every item arrives marked New
  - a Frying Pan from a chest works like the DEV one
- **Phone:** both tabs fit at phone size, and the BUY and OPEN buttons are at least 44 px.

## Not in this topic
- Gold and XP amounts per run, and first-clear rewards (#106).
- Premium Chests, gems and pity (Phase 3). The config keeps the Premium entry.
- Talent nodes past 30, branches and respecs.
- Chest-only starters other than the Frying Pan (the Whisk and Ladle are post-launch).
