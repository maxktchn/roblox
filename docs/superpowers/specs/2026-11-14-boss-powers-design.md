# Boss Powers — design

Date: 2026-11-14 · Status: draft for approval

## Intent and why

Beating a chapter's final boss should give the player something they keep: the boss's
**power**, which can then show up in future runs. The team wants each boss win to feel like
**earning a new tool** *and* **getting stronger**. It is an extra layer of between-run
progress, on top of the PRD's gear, talents and starter unlocks (none of those change).

The first one is the **Microwave Monster's** power, **Microwave Pulse**: a shockwave ring that
grows out from the chef, like the boss's own damage pulse, but aimed at enemies.

## Goals

- Beating the Microwave Monster unlocks Microwave Pulse.
- Once unlocked, Microwave Pulse can be offered as an "Order Up!" card in later runs.
- At Lv 1 it is about as strong as a normal gadget; at Lv 5 it is stronger than a maxed gadget.
- Its first ("NEW") card is rarer than a normal gadget card.
- Playtestable in Phase 1, before saving exists.
- Built as config + one new attack shape, so later bosses' powers are mostly config (PRD §8.5).

## Non-goals

- Saving unlocks between sessions (comes with Phase 2 saving; this design leaves a clean hook).
- Powers for Doughzilla, Kraken Roll and the Rat King (each final boss will get one later; not designed here).
- Recipes for boss powers (decided: none; the stronger Lv 5 is the payoff).
- An active ability button. Powers fire on their own like every other weapon (PRD pillar 1).

## Anti-goals (would be a failure even if it works)

- **A reskinned Blender.** The pulse must look and play differently from the Blender aura.
- **Locking existing content.** The Blender and Smoothie Vortex stay in the normal pool, so new
  players still see all 4 Phase 1 gadgets.
- **Pay to unlock.** Boss powers are never sold for Robux or gems (PRD §1.4 pillar 5).
- **A must-pick.** Taking the pulse should be a good option, not the only sane choice.

## Decisions (from the conversation)

| Question | Decision |
|---|---|
| What the power is | A new ability modeled on the boss's attack: Microwave Pulse |
| How it appears | As an "Order Up!" card, once unlocked |
| Fit with other progression | Added alongside gear, talents and starter unlocks |
| Slots and levels | Like a gadget: uses one of the 6 shared slots, levels 1–5 |
| Strength | Lv 1 ≈ a normal gadget; Lv 5 stronger than a maxed gadget |
| Rarity | Its card appears **less often** than a normal gadget card |
| Which bosses | Every chapter's final boss gives one (4 in the long run) |
| Recipes | None |
| Buying | Never; earn only |
| Phase 1 test | Build now; beating the boss unlocks it until the server closes; DEV panel can unlock it |
| How it attacks | A new **Pulse** shape: a ring expands from the chef and hits each enemy once as it passes, with knockback |

## Approaches considered (for how the pulse attacks)

1. **Reuse the Aura shape** with a ring visual: everything in range is hit at once every few
   seconds. Almost no code, but plays like a slow Blender. Rejected (anti-goal).
2. **New Pulse shape (chosen):** a ring grows outward over ~0.5 s, hitting each enemy once as it
   reaches them, and pushing them back. Looks and feels like the boss's pulse; one new shape,
   reusable by later bosses' powers.
3. **Charge then blast,** copying the boss's warning ring. Most faithful, but the wind-up feels
   slow and the warning is meant for a dodging player, not enemies. Rejected.

## Design

### Config

- **New `src/config/BossPowers.luau`**, shaped like `Gadgets.luau`: each power has `Name`,
  `Behavior`, `Shape`, `FxColor`, `Levels` (5), and `Boss` (the boss id that unlocks it).
- **`Bosses.luau`**: each final boss gets a `Power` id (Microwave Monster → `MicrowavePulse`).
- **`RunRules.UpgradePool.BossPowers = { "MicrowavePulse" }`** (which powers exist in the game).
- **`RunRules.BossPowerNewCardChance`**: chance that an unlocked-but-not-owned power's NEW card
  enters the pool for a given offer (starting value **0.35**). See Rarity.
- **`Shared/WeaponTypes`**: add `"Pulse"` to `Shape`, and an optional `Knockback` (studs) field.
  For Pulse: `Range` = how far the ring grows, `Speed` = how fast it grows (studs/s),
  `Cooldown` = seconds between pulses, `Damage` = per enemy per pulse.
- **`ConfigCheck`**: every `UpgradePool.BossPowers` id exists and is playable (5 levels, Pulse
  needs `Speed`); every boss `Power` points at a real power, and that power's `Boss` points back.

**Starting numbers** (first guesses, tuned in #22):

| Lv | Damage | Cooldown | Range | Ring speed | Knockback |
|---|---|---|---|---|---|
| 1 | 12 | 3.0 s | 14 | 30 studs/s | 4 |
| 2 | 15 | 2.8 s | 15 | 32 | 5 |
| 3 | 19 | 2.6 s | 17 | 34 | 6 |
| 4 | 24 | 2.4 s | 19 | 36 | 7 |
| 5 | 30 | 2.2 s | 22 | 40 | 8 |

For comparison: Blender Lv 1 does ~6 damage/s within 6 studs; the pulse Lv 1 does 4/s but over a
14-stud circle (similar overall). Blender Lv 5 does 15/s within 9 studs; pulse Lv 5 does ~14/s
over a 22-stud circle with knockback (clearly stronger).

### Unlocking (new `UnlockService`)

- Holds which boss powers the run's player has unlocked. **Phase 1: in memory**, so it lasts
  until the server closes and survives "Play again".
- `UnlockService.unlock(id)`, `isUnlocked(id)`, `getUnlocked()`. Sets player attribute
  `Unlocked_<id> = true` for the client.
- **When:** the moment the boss dies (the same event that wins the run), unlock that boss's
  `Power`. Only a defeated boss unlocks it; dying in the fight does not.
- **Phase 2 hook:** `UnlockService` is the only place that knows unlocks, so saving only needs
  `DataService` to load the list into it on join and save it on change. Nothing else changes.

### In a run

- **Card pool (`UpgradeService.buildPool`):** a new `"BossPower"` card kind.
  - Owned and below Lv 5: its upgrade card is in the pool like any owned gadget.
  - Unlocked, not owned, a slot free: its NEW card enters the pool only if a roll under
    `BossPowerNewCardChance` succeeds for this offer.
  - Not unlocked: never offered.
- **Attack (`WeaponService`):** a new `attackPulse` for the Pulse shape. On each cooldown it
  starts a pulse at the chef's position (the ring stays where it was fired). Every frame the
  ring's radius grows by `Speed × deltaTime` up to `Range`; each enemy whose edge the ring has
  reached is hit once per pulse (normal damage path: Hot Sauce, crits, hit numbers, run report)
  and pushed `Knockback` studs away from the pulse's center.
- **Knockback (`EnemyService`, athatcher989's file):** a new `EnemyService.push(enemyId, from,
  studs)`, the mirror of `pull`: moves an enemy away, stays inside the arena, bosses not pushed.
- **Visual (`WeaponFxController`):** a "Pulse" effect: a flat ring that grows from the chef to
  `Range` at the ring speed and fades, in the power's `FxColor` (microwave orange-yellow).
  Sent once per pulse with the existing `WeaponFx` remote.
- **Card look (`UpgradeUIController`):** boss power cards get their own badge, **"BOSS POWER"**,
  and a distinct border colour, like the gold RECIPE cards.
- **HUD:** owned-item icons include boss powers (same as gadgets).
- **Run report:** works automatically (damage dealt per weapon includes the pulse).

### DEV panel

- New button **"Unlock powers"**: unlocks every boss power (for testing without beating the boss).
- The Give section includes **Microwave Pulse** (gives it even if not unlocked).

## PRD and roadmap changes (in the same work)

- **New §3.8 Boss Powers:** what they are, the rules above, Microwave Pulse's numbers, and a
  Power column in §3.5's boss table (other bosses' powers: TBD).
- **§2.8 Run rewards:** defeating a chapter's final boss for the first time unlocks its power.
- **§5 Monetization:** boss powers are never sold.
- **§8.1 / §7.1:** the lobby is a **menu screen in the run place** (no separate Lobby place or
  teleports for now). Servers hold 1 player, so run code keeps handling one player.
  - **Why:** much easier to build and test (teleports don't work in Studio playtests), simpler
    saving (no save/load handoff between servers), one place to keep in sync, instant "Play again".
  - **Cost accepted:** no shared social lobby for now.
  - **Revisit when co-op is designed** (post-launch): co-op needs players matched into a shared
    run, which is when a separate Lobby place and teleports come back. Build the lobby as its own
    screen code so it can move to a separate place later.
- **§9 Roadmap:**
  - Phase 1 gains Microwave Pulse (unlocked per server) as a prototype of boss powers.
  - Phase 2 order: **saving first, then boss powers saving properly, then chapter and starter
    unlocks**; content (gadgets, enemies, The Big Cheese), gear, talents and chests after.
  - Phase 2 bullet "Lobby and Run places with teleporting" → "Lobby menu in the run place".

## Builder's calls (decided while writing this; easy to change)

- **Rarity only applies to the NEW card.** Once you own the power, its upgrades appear like any
  owned gadget's, otherwise reaching the stronger Lv 5 would be very unlikely.
- **The ring stays where it was fired** rather than following the chef (it only lasts ~0.5 s).
- **Each enemy is hit at most once per pulse**, and pulses can overlap at high levels.
- **Unlock is per run-player** in Phase 1 (the game is single-player); co-op is out of scope.
- **The unlock is announced:** the "SHIFT SURVIVED!" banner shows a line like
  "New power unlocked: Microwave Pulse" the first time, so the player knows what they earned.
  Beating the boss again when it's already unlocked shows nothing extra.
- **A boss power uses a shared slot** in every rule that counts slots (`slotsUsed`), exactly like
  a gadget, and shows in the HUD's owned icons.
- Starting numbers and the 0.35 chance are first guesses for #22.

## Left to the builder

- Exact visuals of the ring (thickness, fade), the card's border colour, and the knockback feel.
- File-level structure inside the services, following existing patterns.
