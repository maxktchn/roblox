# DEV menu tabs (#140): design

Short design (small change). Approved by maxktchn on 2026-11-20.

## Why
The DEV panel (`DevPanelController`) is one long scrolling list: Run, Bot, Jump to time, Give, Account. Every topic adds more, and it's getting cluttered (maxktchn, in the gear brainstorm, #105). Tabs keep each kind of test one tap away.

## Goals
- Four tabs along the top of the panel: **RUN · GIVE · BOT · ACCOUNT**.
- Every existing DEV button works from its tab, at phone and PC sizes.
- The ACCOUNT tab gets the save tools the issue lists.
- In the lobby, run-only buttons say so instead of replying as if they worked.

## Non-goals
- Bot gear presets (later, with balance work).
- Run rewards, talents and chapters DEV buttons (#106, #107, #108 add to ACCOUNT later).
- Any change to the run report box or the status line.

## Approaches
1. **Tabs inside today's panel (chosen).** Same left-side panel, a tab row at the top, one scrolling page per tab. Small change; the run stays visible while testing (the issue asks for this).
2. A full-screen DEV menu. More room, but it covers the run, which defeats testing mid-run.
3. Separate small panels per topic. More buttons on screen at once and more clutter, the thing #140 is fixing.

## The design
- **Panel:** stays on the left with the red "DEV" toggle. Under the status line, a row of 4 tab buttons, then the selected tab's page (a ScrollingFrame, like today's list). The selected tab is highlighted.
- **RUN:** +1 Level, +5 Levels, Heal, God, Wipe enemies, Restart run. Then a "Jump to time" header: the 5 time buttons, CHEESE NOW, BOSS NOW.
- **GIVE:** the same buttons as today's Give section, under four headers: Gadgets, Ingredients, Recipes, Boss powers. Still read from config, so new items appear by themselves.
- **BOT:** the bot controls as today (-, count, +, Start bot, Stop bot).
- **ACCOUNT:**
  - Gear: the rarity button and one button per gear item (as today).
  - +1000 gold, +50 materials.
  - Unlock powers (moved from RUN), and **Lock powers** (new): relock every boss power.
  - Reset gear, Reset unlocks.
  - **Reload save** (new): `DataService.reload(player)`, as if the player rejoined.
  - **Simulate save failure** (new): `DataService.reload(player, true)`: the session plays without saving.
  - **Reset my save** (new): back to a new player's save. Needs a second tap to confirm (the button reads "Tap again to reset" for a few seconds).
- **In the lobby:** the run-only actions (LevelUp, SetTime, Boss, Cheese, Give, Heal, Wipe) reply "Not in a run. Press Play or Restart run." and do nothing. Restart run still starts a run from the lobby. God, Bot and the ACCOUNT actions work anywhere.
- **Remember the last tab:** for the rest of the session (a module variable); the panel opens on RUN the first time.

## Left to the builder
- How "Reset my save" swaps the data in (for example a DataService helper that copies the template, then a reload so every service picks it up).
- Exact tab and button sizes, within today's 290 px panel.
- How the lobby check is shared between the run-only actions.
