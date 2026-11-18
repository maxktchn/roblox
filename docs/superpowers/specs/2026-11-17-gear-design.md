# Gear (P2-4, #105): design

## Why
Gear is the main progression between runs (PRD §4). Runs pay out gold and materials (#106), chests hand out items (#108), and gear turns them into a stronger chef. This topic sets which items exist, how strong they get, and how levelling, merging and salvage work. It also sets the format for items and currencies in the save, which run rewards, unlocks and chests all use.

## Decided (by maxktchn)
- **One item per slot.** One Hat, one Apron, one pair of Mitts and one pair of Shoes. The Utensil slot holds your starter weapon (Chef's Knife now; Rolling Pin and Frying Pan arrive with #107).
- **Gear starts weak and rarity is where the power is.** Levelling gives small steps inside a rarity; every merge to the next rarity is a jump bigger than all the levelling before it. Upgrading gear should feel rewarding, not like something people put off. This needs a lot of balancing, so every number is a starting value in config.
- **Epic adds a bonus effect, Legendary makes it stronger** (7 effects, below). They are a rough outline, tuned once built.
- **Levelling pace "front-loaded":** cheap first levels, each level a bit dearer than the last. Rough targets: about 5 runs to Lv 10, 15 runs to Lv 20, 40 runs to Lv 30; Epic and Legendary levels are long-term goals.
- **Levels are capped by rarity** (Common 10, Fine 20, Rare 30, Epic 40, Legendary 50). At the cap, the only way up is merging.
- **Merging resets to Lv 1**, with a **"pick 3" screen** so collectors can keep their levelled copies. **80% of the gold and materials spent levelling the 3 copies comes back.**
- **Salvage works on any item, new ones too.** It gives 1 of the slot's material plus some gold (amount set later), plus 80% of what was spent levelling it.
- **No gear on the chef in Phase 2** (stats only; models are art work for later).
- **No inventory limit.**
- **One material per slot** (Sharpener, Hat Pattern, Apron Pattern, Mitt Pattern, Shoe Pattern).
- **You always own a Chef's Knife.** Your last one can't be salvaged.

## Approaches considered
1. **One item per slot (picked).** The fun is growing each item Common to Legendary. Only a few items to design and draw, every chest drop is useful, and merges come quicker because copies aren't spread out.
2. **Several items per slot to collect.** More variety and chest excitement, but every item needs its own numbers, effect and art, and merges get slower. Can be added later: the config format below already allows more items per slot.

## Items
| Id | Name | Slot | Main stat | Material |
|---|---|---|---|---|
| `ChefsKnife`, `FryingPan`, `RollingPin` (starters) | from `Starters.luau` | Utensil | Attack | Sharpener |
| `ChefsHat` | Chef's Hat | Hat | Attack | Hat Pattern |
| `Apron` | Apron | Apron | HP | Apron Pattern |
| `OvenMitts` | Oven Mitts | Mitts | Attack | Mitt Pattern |
| `Shoes` | Shoes | Shoes | HP | Shoe Pattern |

Names are placeholders and can change freely (ids stay).

A new player owns one **Common Lv 1 Chef's Knife**, equipped, and nothing else.

## Stats
- **Attack** = a % bonus to **all** the chef's damage (starter weapon, gadgets, recipes, burns).
- **HP** = a % bonus to max HP.
- Each item's bonus goes in a straight line from its rarity's Lv 1 value to its max-level value:

| Rarity | Attack item, Lv 1 → max | HP item, Lv 1 → max |
|---|---|---|
| Common (max Lv 10) | +2% → +5% | +3% → +7% |
| Fine (Lv 20) | +8% → +14% | +10% → +18% |
| Rare (Lv 30) | +16% → +26% | +20% → +33% |
| Epic (Lv 40) | +30% → +42% | +38% → +52% |
| Legendary (Lv 50) | +48% → +60% | +60% → +75% |

- **Every rarity's Lv 1 beats the rarity below at max**, so merging (which resets to Lv 1) is never a downgrade. `ConfigCheck` enforces this.
- The equipped items' bonuses are added together: 3 Attack items, 2 HP items. A full maxed Legendary set is +180% damage (**x2.8**) and +150% HP (**x2.5**). Chapter 1 stays beatable with no gear.
- **Gear is its own multiplier, on top of ingredients:** `damage = base × (1 + gear Attack) × (1 + Hot Sauce …)`, and max HP `= 100 × (1 + gear HP) × (1 + Bread)`. Adding gear and ingredients together would make each worth less and gear upgrades feel smaller.
- **Gear is locked in when a run starts.** Changing gear during a run changes nothing until the next run.

## Bonus effects (Epic and Legendary)
Epic adds the effect; Legendary makes it stronger. Numbers are starting values in each item's config entry.

| Item | Epic | Legendary |
|---|---|---|
| Chef's Knife | Every 5th attack throws a second knife | Every 3rd attack |
| Frying Pan | Hits stun for 0.5 s | 1 s, and the stun spreads to enemies next to it |
| Rolling Pin | Enemies it rolls over are flattened: 30% slower for 2 s | 50% slower, and flattened enemies take +20% damage |
| Chef's Hat | Start every run with 1 free "Order Up!" pick | 2 free picks |
| Apron | Blocks the first hit every 12 s (a splash shield shows when it's ready) | Every 7 s |
| Oven Mitts | 10% of hits set enemies on fire (damage over 3 s) | 20%, and fire spreads when a burning enemy dies |
| Shoes | After you're hit, run 30% faster for 2 s | And can't be hurt for 1 s |

- Slows and stuns follow P2-3's rules (#104): the mini-boss takes half and is never stunned; the final boss is immune.
- The Frying Pan and Rolling Pin effects are built with those starters (#107).

## Levelling
- One level costs **gold + the slot's material**. Cost depends only on the level, not the rarity:
  - gold for Lv L → L+1 = `LevelCost.Gold × LevelCost.Growth^(L-1)`, rounded
  - material = `LevelCost.Material × LevelCost.Growth^(L-1)`, rounded up
  - starting `Growth = 1.08`. That spacing hits the targets above (Lv 10 : Lv 20 : Lv 30 ≈ 1 : 3 : 8 in total cost).
- The base costs are placeholders until run rewards (#106) set how much a run pays. #106 sizes its payouts so Lv 1 → 10 takes about 5 runs.
- Can't level past the rarity's max level.
- Each item remembers the gold and materials spent levelling it, so refunds stay right even after costs are tuned.

## Merging
- **3 copies of the same item at the same rarity → 1 copy at the next rarity, at Lv 1.** Legendary can't merge.
- **Pick-3 screen:** choose which 3 copies go in. The 3 lowest-level copies are picked by default, so a quick merge never eats a levelled copy.
- Before confirming, the screen shows the result and the refund: e.g. "Rare Lv 14 +18% → Epic Lv 1 +30%, unlocks: 1 free Order Up! pick. Refund: 340 gold, 6 Hat Patterns".
- **Refund: 80%** (`Gear.SalvageRefund`) of everything spent levelling the 3 copies.
- If the equipped copy is one of the 3, the new item is equipped in its place.
- Auto Merge (merge everything at once) is a paid gamepass in Phase 3, not part of this.

## Salvage
- Destroys the item and gives back:
  - **1 of the slot's material**
  - **some gold**, by rarity (`Gear.SalvageGold`, placeholder values until #106)
  - **80% of what was spent levelling it**
- Works on any item, including one just received.
- Not allowed: the equipped item, or your **last Chef's Knife** (any rarity).
- Epic and Legendary items ask for confirmation first.

## The Gear screen
- **For now a plain screen opened by a "Gear" button on the run-end screen** (the lobby doesn't exist yet). #109 restyles it and moves it into the lobby, as the saving notes did.
- Shows the 5 slots with what's equipped, the inventory (each item with its rarity colour and level), gold and the 5 materials.
- Tapping an item: equip, level up (shows the cost), merge (opens pick-3, only when 3 copies exist), salvage.
- Only usable between runs. A run in progress uses the gear it started with.

## Save layout
Fills the sections reserved in the saving design (`DataService`, version stays 1: saves are wiped freely before launch).
```lua
Gear = {
	NextId = 2, -- the next item id to hand out
	-- Keys are strings: DataStores can't hold gappy number keys.
	Items = {
		["1"] = { Item = "ChefsKnife", Rarity = "Common", Level = 1, SpentGold = 0, SpentMaterial = 0 },
	},
	Equipped = { Utensil = "1" }, -- [slot] = item id; a missing slot is empty
},
Currencies = {
	Gold = 0,
	Sharpener = 0, HatPattern = 0, ApronPattern = 0, MittPattern = 0, ShoePattern = 0,
	-- Gems join here in Phase 3.
},
```
- Only `GearService` changes `Gear`. `Currencies` is shared: run rewards and chests add to it through a small function on `GearService` (or a `CurrencyService`, builder's call), never by editing the table directly.
- On load, a player with no Chef's Knife gets one (new players, and saves made before this topic).

## Code shape (for the builder)
- **`Config/Gear.luau`:** the items above (slot, name, bonus effect numbers), the two stat tables, `LevelCost`, `SalvageGold`. Starters stay in `Starters.luau`; a Utensil item is any starter id.
- **`ConfigCheck`:** every item's slot exists; Utensil items are starter ids; each rarity's Lv 1 value is above the previous rarity's max; costs and growth are positive.
- **`GearService`** (server): owns `Data.Gear`, gives the free knife, and handles equip, level up, merge and salvage. One remote (e.g. `GearAction(action, args)`); every argument is checked (the item ids belong to the player, same item and rarity for a merge, enough gold and materials, not equipped or last knife for salvage). The client gets the gear and currencies to draw the screen (a remote or attributes, builder's call).
- **`StatsService`:** at run start, read the equipped items' Attack and HP bonuses and apply them as the separate multiplier above. Weapon and max HP code keeps calling `StatsService`, so nothing else needs to know about gear.
- **Bonus effects:** one place on the server reads which equipped items are Epic or Legendary at run start and turns their effects on. Each effect is a little code plus numbers in config.
- **DEV tools** (the DEV panel's new ACCOUNT tab, see below): give any item at any rarity and level, +gold, +materials, and reset my save. Until #106 and #108 exist, these are the only way to get gear.
- **PRD §4.1 to §4.4** are updated with this design.

## DEV menu
The DEV panel becomes a tabbed menu (separate issue): **RUN** (level up, heal, god, wipe, restart, jump to time, Cheese and Boss now), **GIVE** (in-run upgrades, with headers), **BOT** (playtest bot; gear presets later), **ACCOUNT** (gear, gold, materials, boss power unlocks, reload save, simulate a save failure, reset my save). It stays on the left so the run can still be seen. Built after the gear issues; until then gear's DEV buttons go in a new "ACCOUNT" section of today's panel.

## Non-goals
- Where gear, gold and materials come from, and gold amounts (#106 run rewards, #108 chests).
- Whether chests drop extra knives and other starters (#108).
- Gear shown on the chef, item art and icons beyond rarity colours.
- Auto Merge (Phase 3 gamepass), gems.
- More than one item per slot.

## Left to the builder
- How the client gets the gear and currency data (a remote snapshot or attributes).
- Whether currencies get their own small service.
- Exact layout of the Gear screen, within the description above.
