# Aimed starter weapon — design

Date: 2026-11-14 · Status: draft for approval

## Intent and why

Playtesting showed the player has too little to do: they only move, and everything fires on its
own. To make runs more interactive, the player now **aims their starter weapon**. It still swings
automatically; the player only chooses the direction:

- **PC:** toward the mouse cursor.
- **Mobile:** with a new **aim joystick** on the right side of the screen.

Only the starter is aimed. Gadgets, ingredients and the rest of the card pool keep working as
they do now.

## Goals

- The Chef's Knife swings toward the player's aim instead of the way the chef is walking.
- PC aims with the mouse; mobile aims with a right-thumb joystick.
- A subtle floor indicator shows where the next swing will land.
- Feels responsive; no noticeable lag at any weapon level.

## Non-goals

- Manual attacking (the swing stays automatic, PRD pillar 1 keeps "attacks fire on their own").
- Aiming gadgets, recipes from gadgets, or boss powers.
- Turning the chef's body toward the aim.

## Anti-goals

- **The client deciding hits.** The server still decides timing, reach and what gets hit (§8.4).
- **Overwhelming phone players.** Letting go of the aim stick never breaks anything; the knife
  keeps working.
- **Lag that grows with upgrades.** Only one aim direction is ever sent, whatever the loadout.

## Decisions (from the conversation)

| Question | Decision |
|---|---|
| Which weapons | The starter only (Chef's Knife now; Rolling Pin and Meat Cleaver later) |
| Swing | Still automatic; the player controls direction |
| PC aim | Mouse cursor |
| Mobile aim | New aim joystick on the right side |
| Thumb off the aim stick | Keep the last aim direction |
| Chef's body | Keeps facing the way they walk; only the swing follows the aim |
| Indicator | A subtle wedge on the floor showing the next swing's direction and reach |
| Jump | Removed (does nothing in this game; frees the right thumb) |
| How the aim reaches the server | The client sends its aim direction; the server keeps the latest and uses it |

## Approaches considered (how the aim reaches the server)

1. **Client sends its aim direction (chosen).** Two numbers on an unreliable remote (Roblox's
   remote for frequent, throwaway updates), only when the aim changes, at most ~20 per second.
   The server validates it and keeps the latest. The server still times the swing and decides hits.
2. **Client decides when and where to swing.** Most responsive, but breaks server authority and
   invites cheating. Rejected.
3. **Encode the aim in the character's rotation.** Conflicts with "body faces movement" and is
   fragile. Rejected.

**Lag:** traffic is under 1 KB/s and doesn't grow with upgrades. The server uses the aim from
about one ping ago (~0.05–0.15 s); with a swing every 0.45–0.8 s that is barely noticeable. The
indicator uses the local aim, so aiming itself feels instant.

## Design

### Config

- Weapon configs get an optional **`Aimed: boolean`**. `Starters.ChefsKnife.Aimed = true`.
- **`Recipes.SushiMasterBlade.Aimed = true`** (see builder's calls: the starter's recipe replaces
  it in the same slot, so it stays aimed).
- `ConfigCheck`: `Aimed` is only allowed on shapes that use a direction (Arc for now), and only on
  starters and starter recipes.
- `RunRules.AimMessagesPerSecond = 20` (client send cap; the server ignores anything faster).

### Network (`Remotes.luau`)

- `Remotes.luau` learns to create **unreliable** remotes too (a second list).
- New unreliable remote **`AimDirection`** (client → server): `(x: number, z: number)`, a flat
  direction on the floor.

### Server

- **Aim storage** (in `WeaponService`, which is the only user): the latest valid aim per player.
  - Validation: both numbers, finite, not NaN, length > 0.01; normalised. Anything else is ignored.
  - Rate limit: more than `AimMessagesPerSecond` in a second → the extras are ignored.
  - Cleared by `WeaponService.reset()` (new run → back to facing until the player aims).
- **`attackArc`:** for a weapon with `Aimed`, the slash direction is the stored aim; with no aim
  yet, the chef's facing (today's behaviour). The `WeaponFx` message carries the direction used,
  so the drawn slash always matches what was hit.
- **No jump:** on each character spawn the server sets the Humanoid's jump height to 0.

### Client (new `AimController`)

- **PC:** each frame, cast a ray from the camera through the mouse onto the floor plane at the
  chef's height; aim = flat direction from the chef to that point.
- **Mobile:** a custom aim joystick (bottom-right, thumb-sized, PRD §7.4): a base circle and a
  knob. Dragging sets the aim from the knob's offset, converted from screen to floor using the
  fixed camera (screen up = away from the camera on the floor). Small dead zone in the middle.
  Releasing keeps the last aim. Only shown on touch devices.
- **Gamepad (bonus, my call):** the right thumbstick aims the same way.
- **Send:** on change only, at most `AimMessagesPerSecond`.
- **Jump button:** Roblox hides its touch jump button when jumping is disabled; if it doesn't,
  hide it here.
- **Indicator:** a faint flat wedge on the floor in front of the chef, in the aim direction, sized
  to the starter's current range and arc. Updates every frame from the local aim. Hidden while the
  "Order Up!" cards are open and when the run is over.

### PRD changes

- **§1.4 pillar 1:** "Players move and aim their signature tool; attacks fire on their own."
- **§2.2 Controls:** movement plus aiming the starter (mouse on PC, right aim stick on mobile,
  right stick on gamepad); no jump.
- **§3.1:** starters (and their recipes) are aimed; gadgets are not.
- **§7.4 Mobile:** the aim stick, bottom-right, thumb-sized.
- **§8.4 Security:** the client sends movement, card choices, and an aim direction (validated,
  rate-limited); the server still decides every hit.

## Builder's calls (decided while writing this; easy to change)

- **Sushi Master Blade stays aimed.** It's the Chef's Knife's recipe and takes its slot, so
  losing aim on evolving would feel like a downgrade. Gadget recipes are not aimed.
- **Before the first aim** in a run, the knife uses the chef's facing (today's behaviour).
- **Gamepad right stick** aims too (cheap, and keeps controllers working).
- **Indicator hidden** during the card screen and after the run ends.
- **Aim stick only on touch devices**; PC never sees it. On devices with both touch and a mouse,
  the input used last decides which one aims.
- **The aim stick sits in a fixed spot** (bottom-right), not wherever the thumb lands, so it
  doesn't fight Roblox's movement stick on the left half of the screen.

## Left to the builder

- Exact look of the joystick and the indicator, dead-zone size, and the send cap value.
- Where the aim code lives inside `WeaponService`, following existing patterns.
