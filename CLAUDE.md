# Kitchen Chaos — notes for Claude

Roblox survivors-style roguelike. **`docs/PRD.md` is the source of truth** for design and numbers. Team: 2 beginners in Luau — keep code simple, commented where non-obvious, and avoid clever abstractions.

## Layout (Rojo, `default.project.json`)
- `src/config/` → `ReplicatedStorage.Config`: content as data. Adding a weapon/enemy/gear item should only need a config entry plus its visuals — no new systems (PRD §8.5).
- `src/shared/` → `ReplicatedStorage.Shared`: server+client code. `Remotes.luau` is the only place remotes are declared.
- `src/server/` → `ServerScriptService.Server`: `Main.server.luau` boots every module in `Services/` (`init` then `start`; never yield in `init`).
- `src/client/` → `StarterPlayerScripts.Client`: `Main.client.luau` boots every module in `Controllers/` the same way.
- Workspace / maps / models are Studio-owned and not in the repo.
- Rojo naming: `.server.luau` Script, `.client.luau` LocalScript (legacy `emitLegacyScripts` default).

## Rules
- Config ids are PascalCase keys (`ChefsKnife`, `HotSauce`). Cross-references are checked by `src/shared/ConfigCheck.luau` at server boot — extend it when adding new references.
- When a config number changes, update the matching PRD value too.
- Server authority (PRD §8.4): server decides damage, drops, XP, rewards, currency. Client sends only card choices (movement is Roblox's). Validate every remote argument.
- Enemies: no Humanoids, pooled parts, `workspace:BulkMoveTo`, distance checks, alive cap `RunRules.MaxAliveEnemies` (PRD §8.3).
- Every file starts with `--!strict`. Keep `stylua --check src`, `selene src`, `rojo build`, and `luau-lsp analyze` (see CI) clean.
- Our `RunService`-equivalent is `RunManager`; `RunService` always means Roblox's.

## Phase 1 scope (current)
One map, Chef's Knife, 4 gadgets, 4 ingredients, 3 enemy types, 1 boss; tips, "Order Up!" cards, recipes. No saving, lobby or progression. Only one place (the run place) exists for now; the lobby place comes in Phase 2.
