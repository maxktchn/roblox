# Unlocks: chapters, Rolling Pin and Frying Pan (P2-6, #107): design

## Why
Phase 2 ends when a new player can go from their first run to unlocking the Rolling Pin, with all progress saved (PRD §9). This topic adds the two MVP starters that are still config stubs (Rolling Pin, Frying Pan) and their recipes (Steamroller, Flambé Pan). It also adds the rules that unlock them, lets the equipped Utensil choose the run's starter, and adds the Chapters tab. Saving (#102), gear (#105) and the lobby design (#109) are done, so this topic only fills the slots they left for it: the save's `Unlocks` section, the Utensil slot and the Chapters tab.

## Decided (by athatcher989)
- **Rolling Pin:** rolls toward where you aim, hitting each enemy in its path once. Medium roll: **20 studs long, 4 wide, 14 damage, every 1.4 s** at Lv 1.
- **Frying Pan:** a **180° swing toward where you aim**, 9 studs, **12 damage every 1.1 s**, knocking enemies **6 studs** back. Elites are pushed half as far and bosses not at all, so the Pan doesn't push them out of your other weapons' reach.
- **Steamroller** (Rolling Pin + Bread): one wide pin that **flattens** every enemy it rolls over. Flattened enemies can't move for 1 s and take **+20% damage** meanwhile.
- **Flambé Pan** (Frying Pan + Butter): each swing leaves a **burning arc on the ground** where it hit. It lasts 2.5 s and burns enemies that walk into it.
- **Chapters tab:** all 4 chapters show. Chapter 1 is playable; Chapters 2-4 are greyed out with a lock and **"Coming soon"**.
- **Unlock moment:** the run-over banner gets a line like the boss-power one ("New starter unlocked: Rolling Pin"), and the **Gear tab shows a NEW badge** until you open it.
- **The Frying Pan is built now but only DEV tools give it** until chests exist (P2-7, #108). There's no temporary unlock rule to take out later.

Already settled by earlier designs:
- **The Utensil slot picks the run's starter** (gear #105, lobby #109). This topic makes Play use it.
- **Lifetime kills are already saved** (`Lifetime.Kills`, saving #102), so the Meat Cleaver's 5,000 (post-launch) will have progress waiting.
- **The Epic and Legendary effects** of the Pan (stun) and Pin (slow, then +20% damage) are set in `Gear.luau`; they're built here with their starters.

All numbers are **starting values**, sized against the Chef's Knife. They get tuned in the playtest after each build issue.

## How strong each starter should be (the yardstick)
| Starter | Lv 1 damage per second | Good at |
|---|---|---|
| Chef's Knife | 10 / 0.8 s = **12.5**, 90° cone, 10 studs | close single targets, fast |
| Rolling Pin | 14 / 1.4 s = **10**, a 20 × 4 stud line | lines of enemies, reach |
| Frying Pan | 12 / 1.1 s = **11**, 180°, 9 studs, push 6 | crowds close by, breathing room |

The Pin and the Pan have a little less damage per second than the Knife because they hit more enemies per swing (the Pin) or buy space (the Pan).

## Approaches considered
1. **Reuse existing shapes with a few new fields (picked).** The Rolling Pin is a `Projectile` that is aimed, pierces everything and has a `Width`. The Frying Pan is an aimed `Arc` with `Knockback`. Flambé's fire reuses the splat code the Squeeze Bottle added. No new shape and no new client drawing code beyond a pin and a fire arc.
2. **A new `Roll` shape.** Cleaner names, but it would copy most of `updateShots`.
3. **Starters as hand-written special cases.** Ruled out by PRD §8.5 (weapons are config).

## Rolling Pin (`Projectile` + `Aimed` + `Width`)
- **Aimed** (like the Knife): one pin rolls toward the player's aim; without an aim, the way the chef faces.
- **`Pierce = 99`:** it hits every enemy in its path, each once.
- **New `Width` on Projectile:** how wide the hit area is (side to side). Shots without `Width` keep `RunRules.ProjectileHitRadius`. The pin looks like a rolling pin lying across its path (`ShotSize`).
- **Speed** 32 studs/s, so a 20-stud roll takes about 0.6 s.

| Lv | Damage | Cooldown | Range (roll length) | Width |
|---|---|---|---|---|
| 1 | 14 | 1.4 | 20 | 4 |
| 2 | 17 | 1.4 | 20 | 4 |
| 3 | 17 | 1.2 | 22 | 4.5 |
| 4 | 20 | 1.2 | 24 | 4.5 |
| 5 | 24 | 1.0 | 26 | 5 |

**Steamroller** (Rolling Pin Lv 5 + Bread): a pin **6 wide**, **40 damage every 1.1 s**, 28 studs.
- **New `Flatten = { Seconds = 1, DamageBonus = 0.2 }`:** every enemy it rolls over is flattened. It uses `EnemyService.freeze` (the Deep Freeze rules), so the Big Cheese is only slowed 50% and the Microwave Monster is unaffected.
- **A flattened enemy looks squashed** (its part is squashed to half height for the second) instead of icy. `freeze` gets an optional look: "Ice" (Deep Freeze, the default), "Flat" or "Stun".

## Frying Pan (`Arc` + `Aimed` + `Knockback`)
- **Aimed** 180° swing.
- **`Knockback` now works on Arc too** (it was Pulse only): each enemy hit is pushed straight away from the chef.
- **`EnemyService.push` gets the elite rule:** elites move half the distance. Bosses already don't move.

| Lv | Damage | Cooldown | Arc | Range | Knockback |
|---|---|---|---|---|---|
| 1 | 12 | 1.1 | 180° | 9 | 6 |
| 2 | 15 | 1.1 | 180° | 9 | 6 |
| 3 | 15 | 0.95 | 190° | 9.5 | 7 |
| 4 | 18 | 0.95 | 190° | 10 | 7 |
| 5 | 20 | 0.85 | 200° | 10 | 8 |

**Flambé Pan** (Frying Pan Lv 5 + Butter): **30 damage every 0.8 s**, 200°, 10 studs, push 6.
- **New `FireArc = { Splats = 5, Width = 4, Seconds = 2.5, Damage = 3 }`:** after each swing, 5 fire splats drop along the arc, 70% of the way out. Each lasts 2.5 s and ticks 3 damage every 0.5 s to enemies on it (6 a second). They reuse the splat list from the Squeeze Bottle (`dropSplat`), capped at `RunRules.MaxFireSplats` (20).
- The client draws the splats orange and flickering (the splat drawing gets a colour from `FxColor`, as the Squeeze Bottle's does).

**Recipe strength:** Steamroller (about 36 per second along a 28-stud line) and Flambé (about 37 per second plus fire) are both well under the Knife's Sushi Master Blade (30 / 0.45 s = 67 per second). They make up for it by hitting many enemies and controlling them. The playtest decides whether they need more.

## Gear effects for the two starters (from `Gear.luau`)
- **Frying Pan Epic:** hits stun for 0.5 s. **Legendary:** 1 s, and the stun spreads to enemies within 4 studs of the one hit. A stun is `freeze` with no damage bonus and the "Stun" look (the enemy wobbles in place). Bosses follow the freeze rules.
- **Rolling Pin Epic:** enemies it rolls over are 30% slower for 2 s. **Legendary:** 50% slower, and they take +20% damage while slowed. `EnemyService.slow` gets an optional damage bonus that lasts as long as the slow.
- **The recipes keep their starter's gear effect** (Steamroller still slows; Flambé still stuns), as the Chef's Knife's extra knife already does for Sushi Master Blade.

## Starting a run with the equipped Utensil
- **Play** (and the restart path) gives the run the **equipped Utensil's starter** at Lv 1 instead of always the Chef's Knife. `WeaponService.reset` takes the starter id; `RunManager` reads it from the gear fixed for the run.
- **The upgrade cards** offer that starter's levels, and its recipe when its ingredient is owned (the recipe check already reads the starter line).
- **Salvage:** the gear design keeps your last Chef's Knife. This widens it: **your last copy of any starter can't be salvaged**, so a player can't lose the Rolling Pin they earned. *(For review: the gear design only protects the Knife.)*
- **The Cookbook** shows Steamroller and Flambé Pan once you own that starter (the lobby design's "can a run reach it" rule).

## Unlocks (save and rules)
**Save** (`Data.Unlocks`, reserved by #102):
```lua
Unlocks = {
	Cleared = { DinerKitchen = true }, -- chapters won at least once
	Starters = { RollingPin = true }, -- starters already given by an unlock rule (never given twice)
}
```
- **Chapters unlock in order:** a chapter can be played if it's Chapter 1 or the chapter before it is in `Cleared`, **and** it has a `Timeline` (Chapters 2-4 have none yet, so they stay "Coming soon" even after you clear Chapter 1).
- **Unlock rules are config:** `Starters.luau` replaces the free-text `Achievement` with `UnlockRule`:
  - `{ Kind = "ClearChapter", Chapter = "DinerKitchen" }` for the Rolling Pin
  - `{ Kind = "Kills", Count = 5000 }` for the Meat Cleaver (post-launch, `Mvp = false`, so never given yet)
  - `Unlock = "Chest"` starters have no rule
  - `ConfigCheck` checks every rule.
- **At run end** (`RunState` becomes "Won"), before the run-end save:
  1. The chapter goes into `Cleared`.
  2. Every MVP starter whose rule is now met and isn't in `Starters` is given: a **Common Lv 1** item of it goes into the gear inventory (unequipped), its id goes into `Starters`, and it's marked **new**.
  3. Lost runs can meet a `Kills` rule too, once one exists.
- **Already cleared Chapter 1 before this ships?** Saves are wiped before launch, so there's no catch-up rule. Devs can use the DEV tools.

**On screen:**
- **The run-over banner** adds "New starter unlocked: Rolling Pin" under the boss-power line (same style).
- **The Gear tab gets a NEW badge** while any item is marked new. Opening Gear clears the marks (one remote call; the marks are saved, so the badge survives a rejoin).
- **DEV tools:** give any starter (that's how the Frying Pan is got until #108), and clear `Unlocks` to replay the Rolling Pin moment.

## Chapters tab
Replaces the lobby's "Coming soon" placeholder.
```
┌ HOME│GEAR│TALENTS│CHAPTERS│SHOP│COOKBOOK          Gold 1,250 ┐
│  [ 1  Diner Kitchen     ✓ Cleared     (selected) ]          │
│  [ 2  Bakery            🔒 Coming soon ]                     │
│  [ 3  Sushi Bar         🔒 Coming soon ]                     │
│  [ 4  Walk-in Freezer   🔒 Coming soon ]                     │
└─────────────────────────────────────────────────────────────┘
```
- One card per chapter in `Chapters.luau`, by `Order`: number, `Name`, and a state (playable, Cleared, Locked "Clear Chapter N first", or "Coming soon").
- **Tapping a playable chapter selects it.** Home shows the selected chapter, and Play starts it. With one chapter it's always Chapter 1; the selection lives for the session (it isn't saved).
- Phone first: cards full width, at least 44 px tall.

## Playtest bot
- The bot plays whatever starter is equipped. Its aiming already serves the Knife; the Pin and Pan use the same aim (toward the nearest enemy).
- A DEV option equips a Rolling Pin or Frying Pan for bot runs, so each starter can get a few runs.

## Testing (each build issue)
- **Rolling Pin, Lv 1 and Lv 5:** an enemy line along the aim is hit once each, and an enemy beside the path (outside `Width`) isn't. Steamroller flattens (enemy speed 0 for 1 s, +20% damage), the Big Cheese is only slowed and the Microwave Monster is untouched.
- **Frying Pan, Lv 1 and Lv 5:** enemies inside 180° are hit and pushed 6 studs, elites 3, bosses 0. Flambé leaves 5 fire splats that tick 3 per 0.5 s and fade after 2.5 s.
- **Gear effects:** the Pan stun holds enemies (and spreads at Legendary); the Pin slow is 30% / 50% with +20% at Legendary.
- **Starting starter:** equip each starter, press Play, and the run starts with it; its recipe card appears at Lv 5 with the ingredient owned.
- **Unlocks:** winning Chapter 1 gives exactly one Rolling Pin, the banner line and the NEW badge; winning again gives nothing new; it all survives a rejoin. The last copy of a starter can't be salvaged.
- **Chapters tab:** 4 cards, Chapter 1 playable, 2-4 "Coming soon".
- **Bot:** 2 runs each with the Pin and the Pan, to compare with the Knife.

## Build issues (after this doc is merged)
1. **Rolling Pin + Steamroller:** `Width` and `Flatten` on Projectile, aimed shots, the "Flat" look, pin drawing.
2. **Frying Pan + Flambé Pan:** `Knockback` on Arc, the elite push rule, `FireArc` splats.
3. **Gear effects for the Pan and the Pin:** stun (with spread), slow with a damage bonus. It needs 1 and 2.
4. **Play uses the equipped Utensil:** `WeaponService.reset(starter)`, the salvage rule, and the bot and DEV options. It needs the lobby's Play (#143).
5. **Unlocks:** `Data.Unlocks`, `UnlockRule` in config, giving the Rolling Pin, the banner line and the NEW badge. It needs 4.
6. **Chapters tab:** it needs the lobby screens (#144).
7. **PRD and playtest:** §2.5, §3.1 and §3.7 tables, and bot runs with each starter. It needs 1-6.

1, 2 and 3 can start straight away (they only need the DEV tools to equip a starter); 4-6 wait for the lobby build.

## Coordination
- **Lobby (#143, #144, #145, maxktchn):** Play and the Chapters tab plug in here. The Cookbook (#145) already hides recipes a run can't reach, so Steamroller and Flambé appear once you own their starter.
- **Chests (#108):** chests drop the Frying Pan (and duplicates of any starter) as gear items; this topic only gives starters through `UnlockRule`.
- **Run rewards (#106):** no overlap. The banner's unlock lines sit above the reward payout.
